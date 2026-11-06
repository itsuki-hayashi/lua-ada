param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $ReferenceLibraryDirectory,
    [ValidateSet('default', 'upstream-test')][string] $Configuration = 'default'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($IsWindows) { throw 'Use the named Windows platform equivalent on Windows' }
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'references/lua/testes/files.lua'
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$ada = (Resolve-Path -LiteralPath $Interpreter).Path
$oracle = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
$referenceLibrary = (Resolve-Path -LiteralPath $ReferenceLibraryDirectory).Path
$directory = Join-Path $root ('reports/posix-files/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$records = @()
$failures = @()
$outputs = @{}
foreach ($implementation in @('c', 'ada')) {
    $working = Join-Path $directory $implementation
    [void][IO.Directory]::CreateDirectory($working)
    $original = if ($implementation -eq 'c') { $oracle } else { $ada }
    $executable = Join-Path $working 'lua'
    $fixture = Join-Path $working 'files.lua'
    Copy-Item -LiteralPath $original -Destination $executable
    Copy-Item -LiteralPath $source -Destination $fixture
    $environment = @{ PATH=$working + [IO.Path]::PathSeparator + $env:PATH }
    $runId = [Guid]::NewGuid().ToString('N')
    $telemetryPrefix = Join-Path $working 'allocator'
    $environment.LUA_ADA_CONFORMANCE_TELEMETRY = $telemetryPrefix
    $environment.LUA_ADA_CONFORMANCE_RUN_ID = $runId
    if ($implementation -eq 'c') {
        $environment.LD_LIBRARY_PATH = $referenceLibrary + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $environment.DYLD_LIBRARY_PATH = $referenceLibrary + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
    }
    $setup = if ($Configuration -eq 'upstream-test') {
        "assert(T and T.checkmemory and T.nonblock); "
    } else { 'assert(T==nil); ' }
    $setup += 'assert(_soft==nil and _port==nil); '
    $childCheck = if ($Configuration -eq 'upstream-test') { 'assert(T and T.checkmemory and T.nonblock)' } else { 'assert(T==nil)' }
    $setup += "local check=[[$childCheck]]; assert(os.execute('lua -e '..string.format('%q',check))); "
    $setup += "local i=0; while arg[i] do i=i-1 end; assert(os.execute(string.format('%q',arg[i+1])..' -e '..string.format('%q',check)))"
    $process = Invoke-ConformanceProcess -Executable $executable `
        -Arguments @('-e', $setup, $fixture) -Directory $working `
        -OutputPrefix (Join-Path $directory $implementation) -TimeoutSeconds 900 `
        -Environment $environment
    $records += [ordered]@{ implementation=$implementation; process=$process;
        executable_sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash;
        executed_source_sha256=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash }
    $stdout = [IO.File]::ReadAllText($process.stdout_path)
    $stderr = [IO.File]::ReadAllText($process.stderr_path)
    $outputs[$implementation] = @{ stdout=$stdout; stderr=$stderr }
    $complete = $process.exit_code -eq 0 -and -not $process.timed_out -and
        -not $process.capture_exceeded -and -not $process.pipe_drain_failed -and
        -not $process.process_tree_kill_error
    foreach ($marker in @('testing i/o', 'testing flush', 'testing large files',
        'testing popen/pclose and execute', 'testing date/time')) {
        $complete = $complete -and $stdout.Contains($marker)
    }
    if ($Configuration -eq 'upstream-test') {
        $complete = $complete -and $stdout.Contains('testing failed write')
    }
    $complete = $complete -and $stdout -notmatch 'skipping|omitted|not implemented' -and
        $stdout -match '(?m)^test done on \d{2}/\d{2}/\d+, at \d{2}:\d{2}:\d{2}\nLua 5\.5\n\z'
    if (-not $complete) { $failures += "$implementation did not complete files.lua" }
    try {
        $measured = Get-Content -LiteralPath "$telemetryPrefix.$($process.process_id).json" -Raw |
            ConvertFrom-Json -AsHashtable
        Assert-ManagedTelemetry -Telemetry $measured -RunId $runId `
            -ProcessId $process.process_id -Configuration $Configuration `
            -RequireShutdown:($implementation -eq 'ada')
        $records[-1].allocator_telemetry = $measured
    } catch { $failures += "$implementation allocator telemetry: $($_.Exception.Message)" }
    foreach ($line in $stderr.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($line -notmatch '^(?:.*not-to-be-found-command.*|Hangup.*|Killed.*)$') {
            $failures += "$implementation unexpected stderr: $line"
        }
    }
}
if ($outputs.c.stderr -cne $outputs.ada.stderr) { $failures += 'C/Ada stderr differs' }
$dateLine = '(?m)^test done on .*\n'
if (($outputs.c.stdout -replace $dateLine, ('[date witness]' + "`n")) -cne
    ($outputs.ada.stdout -replace $dateLine, ('[date witness]' + "`n"))) {
    $failures += 'C/Ada output differs outside final date witness'
}
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $sourceHash) {
    $failures += 'Upstream source changed'
}
[ordered]@{ configuration=$Configuration; disposition='unchanged';
    diagnostic_only=$true; scope_accepted=$false; source_sha256=$sourceHash;
    executions=$records; failures=$failures } | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $directory 'report.json')
if ($failures.Count -ne 0) { throw ($failures -join '; ') }
Write-Output 'PASS: matching unchanged POSIX files.lua observations; scope acceptance pending'
