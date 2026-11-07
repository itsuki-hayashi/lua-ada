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
# GNAT's POSIX signal handler may convert abort to Program_Error. Exit 1
# qualifies only with both specific diagnostics, never an arbitrary error.
function Test-WarningTermination {
    param([string] $Mode, [string] $Target, [bool] $Windows,
        [int] $Code, [string] $Diagnostic,
        [string] $CaseName = 'normal-warning', [string] $Output = '')
    if ($Mode -eq 'default') { return $Code -eq 0 }
    if ($Target -eq 'ReferenceC') { return $Code -eq 1 }
    if ($Windows) { return $Code -eq 3 }
    $expectedText = if ($CaseName -eq 'shutdown-warning') { 'scoped shutdown assertion' }
        else { 'scoped unexpected warning' }
    if ($Diagnostic -notmatch ('(?m)^T warning failure: unexpected warning: [^\r\n]*' +
            [regex]::Escape($expectedText) + '[^\r\n]*\r?$')) { return $false }
    if ($CaseName -eq 'shutdown-warning' -and $Output -notmatch '(?m)^OK\r?$') { return $false }
    if ($Code -eq 134) { return $true }
    # Close runs outside Execute's error conversion and reaches Lua_CLI's
    # outer handler. This source-derived expectation still needs CI evidence.
    if ($CaseName -eq 'shutdown-warning') {
        return $Code -eq 1 -and $Diagnostic -match '(?m)^lua_ada: unhandled signal\r?$'
    }
    return $Code -eq 1 -and $Diagnostic -match `
        '(?m)^\(command line\):1: internal Ada check: unhandled signal\r?$'
}
# Fixtures validate the verifier; they do not claim foreign-platform runtime
# passes. The actual process tests below separately exercise this host.
$gnatWarning = "T warning failure: unexpected warning: scoped unexpected warning`n(command line):1: internal Ada check: unhandled signal`n"
$verifierCases = @(
    @{code=1;diagnostic=$gnatWarning;expected=$true},
    @{code=134;diagnostic='T warning failure: unexpected warning: scoped unexpected warning';expected=$true},
    @{code=2;diagnostic=$gnatWarning;expected=$false},
    @{code=139;diagnostic=$gnatWarning;expected=$false},
    @{code=1;diagnostic='T warning failure: unexpected warning: scoped unexpected warning';expected=$false},
    @{code=1;diagnostic='(command line):1: internal Ada check: unhandled signal';expected=$false},
    @{code=1;diagnostic="T warning failure: unexpected warning: scoped unexpected warning`n(command line):1: internal Ada check: unrelated error";expected=$false},
    @{code=134;diagnostic='unrelated abort';expected=$false}
)
foreach ($fixture in $verifierCases) {
    $actual = Test-WarningTermination -Mode upstream-test -Target Ada -Windows $false `
        -Code $fixture.code -Diagnostic $fixture.diagnostic
    if ($actual -ne $fixture.expected) { throw 'Warning termination verifier regression' }
}
$shutdownWarning = "T warning failure: unexpected warning: error in __gc (scoped shutdown assertion)`nlua_ada: unhandled signal`n"
$shutdownFixtures = @(
    @{name='shutdown-warning';output='OK';diagnostic=$shutdownWarning;expected=$true},
    @{name='normal-warning';output='OK';diagnostic=$shutdownWarning;expected=$false},
    @{name='normal-warning';output='OK';diagnostic=$shutdownWarning.Replace('scoped shutdown assertion','scoped unexpected warning');expected=$false},
    @{name='shutdown-warning';output='';diagnostic=$shutdownWarning;expected=$false},
    @{name='shutdown-warning';output='OK';diagnostic=$shutdownWarning.Replace('unhandled signal','unrelated error');expected=$false},
    @{name='shutdown-warning';output='OK';diagnostic=$gnatWarning.Replace('scoped unexpected warning','scoped shutdown assertion');expected=$false}
)
foreach ($fixture in $shutdownFixtures) {
    $actual = Test-WarningTermination -Mode upstream-test -Target Ada -Windows $false `
        -Code 1 -Diagnostic $fixture.diagnostic -CaseName $fixture.name -Output $fixture.output
    if ($actual -ne $fixture.expected) { throw 'Shutdown warning verifier regression' }
}
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
            # Keep C exit 1 and Windows abort 3, while recognizing the
            # specifically diagnosed GNAT POSIX signal conversion.
            if (-not (Test-WarningTermination -Mode $Configuration -Target $target `
                    -Windows $IsWindows -Code $process.exit_code -Diagnostic $stderr `
                    -CaseName $case.name -Output $stdout)) {
                throw "Unexpected warning termination status: $target/$($case.name): $($process.exit_code)"
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
    source_records=@($sourceRecords);library_records=$libraryRecords;
    verifier_fixture_count=($verifierCases.Count + $shutdownFixtures.Count);cases=$records} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'index.json') -Encoding utf8
Write-Output "PASS: $($records.Count) actual scoped warning regressions"
