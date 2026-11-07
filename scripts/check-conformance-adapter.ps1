param([Parameter(Mandatory)][string] $Interpreter)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$executable = (Resolve-Path -LiteralPath $Interpreter).Path

# These are adapter process regressions, not upstream coverage records.
# Fatal warning violations must survive pcall and must fail at state close.
$cases = @(
    @{ Name='fragmented store'; Code="warn('@store'); warn('a','b'); assert(_WARN=='ab'); _WARN=false"; Success=$true },
    @{ Name='off normal'; Code="warn('@off'); warn('ignored')"; Success=$true },
    @{ Name='unexpected warning'; Code="warn('@on'); pcall(warn,'unexpected')"; Success=$false },
    @{ Name='invalid control'; Code="warn('@invalid')"; Success=$false },
    @{ Name='unconsumed store'; Code="warn('@store'); warn('first'); warn('second')"; Success=$false },
    @{ Name='buffer overflow'; Code="warn('@store'); warn(string.rep('x',200))"; Success=$false },
    @{ Name='shutdown warning'; Code="warn('@on'); keep=setmetatable({}, {__gc=function() error('unexpected shutdown') end})"; Success=$false }
)
foreach ($case in $cases) {
    $start = [Diagnostics.ProcessStartInfo]::new($executable)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add('-e')
    $start.ArgumentList.Add("assert(type(T)=='table'); " + $case.Code)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorOutput = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "Adapter timeout: $($case.Name)"
        }
        $stdout = $output.GetAwaiter().GetResult()
        $stderr = $errorOutput.GetAwaiter().GetResult()
        if ($case.Success) {
            if ($process.ExitCode -ne 0 -or $stdout -ne '' -or $stderr -ne '') {
                throw "Adapter case failed: $($case.Name): $stdout $stderr"
            }
        } elseif ($process.ExitCode -eq 0 -or $stderr -notmatch 'T warning failure:') {
            throw "Missing fatal warning evidence: $($case.Name): $stdout $stderr"
        }
        Write-Output "PASS: adapter $($case.Name)"
    } finally { $process.Dispose() }
}
