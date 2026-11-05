param(
    [string] $Interpreter = '',
    [switch] $OracleOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$suffix = if ($IsWindows) { '.exe' } else { '' }

function Invoke-Program {
    param([string] $Executable, [string] $Script)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.ArgumentList.Add($Script)
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "Interpreter timed out: $Script"
        }
        return @{
            Code = $process.ExitCode
            Out = $stdout.GetAwaiter().GetResult()
            Err = $stderr.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

try {
    Set-Location $projectRoot
    & alr exec -- gprbuild -P experiments/abi/oracle.gpr
    if ($LASTEXITCODE -ne 0) { throw 'Reference interpreter build failed' }
    $oracle = Join-Path $projectRoot "build/oracle/bin/lua$suffix"
    if (-not $OracleOnly -and -not (Test-Path -LiteralPath $Interpreter -PathType Leaf)) {
        throw 'Supply -Interpreter with the Ada executable to compare'
    }
    if (-not $OracleOnly) { $Interpreter = (Resolve-Path -LiteralPath $Interpreter).Path }
    foreach ($script in Get-ChildItem tests/lua -Filter *.lua | Sort-Object Name) {
        $expected = Invoke-Program -Executable $oracle -Script $script.FullName
        if ($expected.Code -ne 0 -or $expected.Err -ne '') {
            throw "Reference fixture failed: $($script.Name): $($expected.Err)"
        }
        if ($OracleOnly) {
            Write-Output "ORACLE ONLY: $($script.Name) (Ada parity not tested)"
        }
        else {
            $actual = Invoke-Program -Executable $Interpreter -Script $script.FullName
            if ($actual.Code -ne $expected.Code -or
                $actual.Out -cne $expected.Out -or $actual.Err -cne $expected.Err) {
                throw "Differential mismatch: $($script.Name)"
            }
            Write-Output "PARITY: $($script.Name)"
        }
    }
}
finally { Set-Location $originalLocation }
exit 0
