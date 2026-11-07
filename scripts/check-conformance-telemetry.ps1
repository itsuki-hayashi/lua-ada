param(
    [Parameter(Mandatory)][string] $Interpreter,
    [ValidateSet('default', 'upstream-test')][string] $Configuration = 'default'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$executable = (Resolve-Path -LiteralPath $Interpreter).Path
$directory = Join-Path $root ('reports/managed-telemetry/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$cases = @(
    @{ Name='normal close'; Code="keep=setmetatable({}, {__gc=function() print('finalized') end})"; Exit=0; Out="finalized`n"; Error='' },
    @{ Name='exit without Lua close'; Code="keep=setmetatable({}, {__gc=function() print('finalized') end}); local x <close> = setmetatable({}, {__close=function() print('closed') end}); os.exit(42,false)"; Exit=42; Out=''; Error='' },
    @{ Name='exit with Lua close'; Code="keep=setmetatable({}, {__gc=function() print('finalized') end}); local x <close> = setmetatable({}, {__close=function() print('closed') end}); os.exit(43,true)"; Exit=43; Out="closed`nfinalized`n"; Error='' },
    @{ Name='runtime error cleanup'; Code="error('expected telemetry failure')"; Exit=1; Out=''; Error='expected telemetry failure' }
)
if ($Configuration -eq 'upstream-test') {
    $cases += @{ Name='real refusal recovery'; Code="T.allocfailnext(); local x={}; assert(type(x)=='table')"; Exit=0; Out=''; Error=''; Refusal=$true }
}
$baseline = $null
foreach ($case in $cases) {
    $runId = [Guid]::NewGuid().ToString('N')
    $prefix = Join-Path $directory $runId
    $start = [Diagnostics.ProcessStartInfo]::new($executable)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['LUA_ADA_CONFORMANCE_TELEMETRY'] = $prefix
    $start.Environment['LUA_ADA_CONFORMANCE_RUN_ID'] = $runId
    $start.ArgumentList.Add('-e')
    $start.ArgumentList.Add($case.Code)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "Telemetry process timeout: $($case.Name)"
        }
        $stdout = $outTask.GetAwaiter().GetResult().Replace("`r`n", "`n")
        $stderr = $errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText("$prefix.stdout", $stdout)
        [IO.File]::WriteAllText("$prefix.stderr", $stderr)
        if ($process.ExitCode -ne $case.Exit -or $stdout -cne $case.Out -or
            ($case.Error -eq '' -and $stderr -ne '') -or
            ($case.Error -ne '' -and $stderr -notmatch $case.Error)) {
            throw "Telemetry process behavior differs: $($case.Name): $stdout $stderr"
        }
        $telemetry = Get-Content -LiteralPath "$prefix.$($process.Id).json" -Raw |
            ConvertFrom-Json -AsHashtable
        Assert-ManagedTelemetry -Telemetry $telemetry -RunId $runId -ProcessId $process.Id `
            -Configuration $Configuration -RequireShutdown
        if ($telemetry.peak_managed_bytes -le 0) { throw 'No actual allocation measurement' }
        if ($case.ContainsKey('Refusal') -and $telemetry.managed_refusals -lt 1) {
            throw 'Real managed refusal was not measured'
        }
        $baseline = $telemetry
        Write-Output "PASS: telemetry $($case.Name)"
    } finally { $process.Dispose() }
}

# Mutate actual process evidence, not a handcrafted all-zero success report.
# Every identity, balance and shutdown condition must independently reject it.
$negative = @(
    @{ Name='leaked bytes'; Change={param($t) $t.outstanding_bytes=1} },
    @{ Name='leaked blocks'; Change={param($t) $t.outstanding_blocks=1} },
    @{ Name='wrong process'; Change={param($t) $t.process_id++} },
    @{ Name='wrong run'; Change={param($t) $t.run_id='bad'} },
    @{ Name='wrong configuration'; Change={param($t) $t.configuration='wrong'} },
    @{ Name='wrong ceiling'; Change={param($t) $t.allocator_limit_bytes=1} },
    @{ Name='missing shutdown'; Change={param($t) $t.shutdown_complete=$false} },
    @{ Name='accounting fault'; Change={param($t) $t.accounting_fault=$true} },
    @{ Name='invalid counter'; Change={param($t) $t.managed_refusals=-1} },
    @{ Name='missing counter'; Change={param($t) $t.Remove('outstanding_blocks')} }
)
foreach ($case in $negative) {
    $invalid = $baseline | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    $null = & $case.Change $invalid
    $rejected = $false
    try {
        Assert-ManagedTelemetry -Telemetry $invalid -RunId $baseline.run_id `
            -ProcessId $baseline.process_id -Configuration $Configuration -RequireShutdown
    } catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid telemetry: $($case.Name)" }
    Write-Output "PASS: telemetry rejects $($case.Name)"
}
