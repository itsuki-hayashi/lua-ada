param(
    [string] $Interpreter = '',
    [switch] $OracleOnly,
    [string] $ConfiguredWitnessReport = '',
    [string] $ConfiguredInterpreter = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$suffix = if ($IsWindows) { '.exe' } else { '' }
Import-Module (Join-Path $PSScriptRoot 'ConfiguredFixtureEvidence.psm1')
if(-not $OracleOnly){
    if($ConfiguredWitnessReport -eq '' -or $ConfiguredInterpreter -eq ''){
        throw 'Default differential fixtures require the actual configured fixture pair report and its Ada interpreter'
    }
    $configured=Get-Content -LiteralPath $ConfiguredWitnessReport -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $null=Assert-ConfiguredFixtureReport -Root $projectRoot -Report $configured -Configuration default -Interpreter $ConfiguredInterpreter
}

function Invoke-Program {
    param([string] $Executable, [string] $Script,[string[]]$PreludeArguments=@())
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    foreach($argument in $PreludeArguments){$start.ArgumentList.Add($argument)}
    $start.ArgumentList.Add($Script)
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $outBuffer = [IO.MemoryStream]::new()
    $errBuffer = [IO.MemoryStream]::new()
    try {
        [void]$process.Start()
        # Lua strings are arbitrary bytes. TextReader decoding could replace
        # distinct invalid UTF-8 sequences with the same replacement character.
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync($outBuffer)
        $stderr = $process.StandardError.BaseStream.CopyToAsync($errBuffer)
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "Interpreter timed out: $Script"
        }
        $stdout.GetAwaiter().GetResult()
        $stderr.GetAwaiter().GetResult()
        return @{
            Code = $process.ExitCode
            Out = [Convert]::ToBase64String($outBuffer.ToArray())
            Err = [Convert]::ToBase64String($errBuffer.ToArray())
        }
    }
    finally {
        $process.Dispose()
        $outBuffer.Dispose()
        $errBuffer.Dispose()
    }
}

function Show-FirstDifference {
    param([string] $Expected, [string] $Actual)
    $left = [Convert]::FromBase64String($Expected)
    $right = [Convert]::FromBase64String($Actual)
    $offset = 0
    while ($offset -lt [Math]::Min($left.Length, $right.Length) -and
           $left[$offset] -eq $right[$offset]) { $offset++ }
    Write-Output "First differing byte: $offset; sizes C=$($left.Length), Ada=$($right.Length)"
    # Decode context only for diagnostic readability. Equality above always
    # uses the complete raw bytes, including invalid UTF-8 and line endings.
    foreach ($entry in @(@{ Name='C'; Bytes=$left }, @{ Name='Ada'; Bytes=$right })) {
        $start = [Math]::Max(0, [Math]::Min($offset, $entry.Bytes.Length) - 80)
        $count = [Math]::Min(160, $entry.Bytes.Length - $start)
        Write-Output "$($entry.Name): $([Text.Encoding]::UTF8.GetString($entry.Bytes, $start, $count))"
    }
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
    $mismatches = @()
    foreach ($script in Get-ChildItem tests/lua -Filter *.lua | Sort-Object Name) {
        # These are configured witnesses, not default T-absent successes.
        # The default portal pair has already run with measured matching stack
        # limits. The real-T file is mandatory in check-instrumented.ps1.
        if($script.Name -ceq 'stack_inspection.lua'){
            Write-Output 'CONFIGURED T REQUIRED: stack_inspection.lua (mandatory instrumented campaign; no default observation)'
            continue
        }
        if($script.Name -ceq 'coroutine_result_portal.lua' -and -not $OracleOnly){
            Write-Output 'CONFIGURED PARITY: coroutine_result_portal.lua (verified dedicated native/Ada report)'
            continue
        }
        $prelude=@()
        if($script.Name -ceq 'coroutine_result_portal.lua'){
            # Oracle-only diagnostics still execute the actual default portal
            # with the pinned stack limit; they never claim Ada parity.
            $prelude=@('-e',@(Get-ConfiguredFixtureDefinitions default)[0].setup)
        }
        $expected = Invoke-Program -Executable $oracle -Script $script.FullName -PreludeArguments $prelude
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
                Write-Output "DIFFERENTIAL MISMATCH: $($script.Name)"
                Write-Output "Exit status C=$($expected.Code), Ada=$($actual.Code)"
                Show-FirstDifference -Expected $expected.Out -Actual $actual.Out
                if ($expected.Err -cne $actual.Err) {
                    Show-FirstDifference -Expected $expected.Err -Actual $actual.Err
                }
                $mismatches += $script.Name
                continue
            }
            Write-Output "PARITY: $($script.Name)"
        }
    }
    if ($mismatches.Count -gt 0) { throw "Differential mismatches: $($mismatches -join ', ')" }
}
finally { Set-Location $originalLocation }
exit 0
