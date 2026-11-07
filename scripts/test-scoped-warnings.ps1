param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $RuntimeDirectory,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [Parameter(Mandatory)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$directory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$reference = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
$RuntimeDirectory = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$referenceLibrary = Join-Path (Split-Path -Parent (Split-Path -Parent $reference)) 'lib'
$sourceRecords = @('scripts/test-scoped-warnings.ps1','scripts/check-gc-events.ps1',
    'scripts/run-conformance.ps1','scripts/ConformanceRunner.psm1',
    'tests/c/conformance_adapter.c','references/lua/ltests.c') | ForEach-Object {
    [ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$libraryRecords = @()
foreach ($pair in @(@{target='Ada';directory=$RuntimeDirectory},@{target='ReferenceC';directory=$referenceLibrary})) {
    $libraries = @(Get-ChildItem -LiteralPath $pair.directory -File | Where-Object {
        $_.Extension -in @('.a','.dll','.so','.dylib') })
    if ($libraries.Count -eq 0) { throw "No measured warning-test libraries: $($pair.target)" }
    foreach ($library in $libraries) {
        $libraryRecords += [ordered]@{target=$pair.target;path=$library.FullName;
            sha256=(Get-FileHash -LiteralPath $library.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
}
$revision = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify warning-test revision' }
$repositoryStatus = @(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify warning-test checkout state' }
$environment = @{
    PATH=$RuntimeDirectory + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:PATH
    LD_LIBRARY_PATH=$RuntimeDirectory + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    DYLD_LIBRARY_PATH=$RuntimeDirectory + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
$setup = if ($Configuration -eq 'upstream-test') { "assert(type(T)=='table'); " } else { 'assert(T==nil); ' }
# The normal and close-time cases must be rejected by the same zero-status /
# empty-stderr criterion used by the scoped GC driver. Default Lua reports a
# warning without failing execution; the real T handler aborts unexpected
# warnings. Require the diagnostic too, so a missing DLL or crash is not a pass.
$cases = @(
    @{name='normal-warning'; reject=$true; diagnostic='scoped unexpected warning';
      source="warn('@on'); warn('scoped unexpected warning'); print('OK')"},
    @{name='shutdown-warning'; reject=$true; diagnostic='scoped shutdown assertion';
      source="warn('@on'); _retained=setmetatable({}, {__gc=function() assert(false,'scoped shutdown assertion') end}); print('OK')"},
    @{name='explicit-warning-off'; reject=$false;
      source="warn('@on'); warn('@off'); warn('explicitly suppressed'); print('OK')"}
)
if ($Configuration -eq 'upstream-test') {
    $cases += @{name='stored-warning-consumed'; reject=$false;
        source="warn('@on'); warn('@store'); warn('expected',' fragments'); assert(_WARN=='expected fragments'); _WARN=false; warn('@normal'); print('OK')"}
}
$records = @()
foreach ($target in @('ReferenceC','Ada')) {
    $executable = if ($target -eq 'Ada') { (Resolve-Path -LiteralPath $Interpreter).Path } else { $reference }
    foreach ($case in $cases) {
        $process = Invoke-ConformanceProcess -Executable $executable -Arguments @('-e',($setup + $case.source)) `
            -Directory $directory -OutputPrefix (Join-Path $directory "$target-$($case.name)") `
            -TimeoutSeconds 30 -Environment $environment
        if ($process.timed_out -or $process.capture_exceeded -or $process.pipe_drain_failed -or $process.process_tree_kill_error) {
            throw "Warning regression process did not finish: $target/$($case.name)"
        }
        $stdout = [IO.File]::ReadAllText($process.stdout_path)
        $stderr = [IO.File]::ReadAllText($process.stderr_path)
        $accepted = $process.exit_code -eq 0 -and $process.stderr_bytes -eq 0
        if ($case.reject) {
            if ($accepted -or $stderr -notmatch [regex]::Escape($case.diagnostic)) {
                throw "Unexpected warning escaped scoped rejection: $target/$($case.name)"
            }
            # ltests.c badexit uses EXIT_FAILURE (1). The Ada test handler
            # calls abort: the Windows CRT returns 3; POSIX SIGABRT is 6 and
            # Process.ExitCode reports 128+signal. Other crashes are failures.
            $expectedExit = if ($Configuration -eq 'default') { 0 }
                elseif ($target -eq 'ReferenceC') { 1 }
                elseif ($IsWindows) { 3 } else { 134 }
            if ($process.exit_code -ne $expectedExit) {
                throw "Unexpected warning termination status: $target/$($case.name): $($process.exit_code), expected $expectedExit"
            }
            if ($Configuration -eq 'default' -and $stdout -notmatch '(?m)^OK\r?$') {
                throw "Default warning interrupted normal completion: $target/$($case.name)"
            }
            if ($case.name -eq 'shutdown-warning' -and $stdout -notmatch '(?m)^OK\r?$') {
                throw "Shutdown warning did not run after top-level completion: $target"
            }
        } elseif (-not $accepted -or $stdout -notmatch '(?m)^OK\r?$') {
            throw "Expected warning control failed: $target/$($case.name)"
        }
        $records += [ordered]@{name=$case.name;target=$target;expected_rejection=$case.reject;process=$process}
        Write-Output "WARNING TEST PASS: $target/$($case.name)"
    }
}
[ordered]@{schema_version=1;configuration=$Configuration;repository_revision=$revision;
    repository_dirty=($repositoryStatus.Count -ne 0);repository_status=$repositoryStatus;
    source_records=@($sourceRecords);library_records=$libraryRecords;cases=$records} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'index.json') -Encoding utf8
Write-Output "PASS: $($records.Count) actual scoped warning regressions"
