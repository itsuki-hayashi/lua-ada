param(
    [Parameter(Mandatory)]
    [string] $Consumer,
    [Parameter(Mandatory)]
    [string] $Interpreter
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$newline = [Text.Encoding]::ASCII.GetBytes([Environment]::NewLine)

function Invoke-OutputCase {
    param([string] $Title, [string] $Executable, [string[]] $Arguments,
          [byte[]] $Expected)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Resolve-Path -LiteralPath $Executable).Path
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $bytes = [IO.MemoryStream]::new()
    try {
        [void]$process.Start()
        # Read the actual byte stream: UTF-8 decoding would replace 0xff and
        # could hide the encoding regression this consumer protects.
        $copy = $process.StandardOutput.BaseStream.CopyToAsync($bytes)
        $errorRead = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "Output policy timeout: $Title"
        }
        [void]$copy.GetAwaiter().GetResult()
        $stderr = $errorRead.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $stderr.Length -ne 0) {
            throw "Output policy failure: ${Title}: $stderr"
        }
        $actual = $bytes.ToArray()
        if ([Convert]::ToHexString($actual) -cne
            [Convert]::ToHexString($Expected)) {
            throw ("Output policy byte mismatch: ${Title}: " +
                [Convert]::ToHexString($actual))
        }
        Write-Output "OUTPUT PASS: $Title"
    }
    finally { $bytes.Dispose(); $process.Dispose() }
}

Invoke-OutputCase 'Ada defaults to captured bytes' $Consumer @('captured') @()
Invoke-OutputCase 'Ada process streams preserve byte strings' $Consumer @('bytes') `
    ([byte[]](97,0,255,9,55) + $newline)
Invoke-OutputCase 'callbacks publish in process order' $Consumer @('callback-order') `
    ($utf8.GetBytes('inner') + $newline + $utf8.GetBytes("first`tsecond") + $newline)
Invoke-OutputCase 'process error and recovery do not duplicate capture' `
    $Consumer @('recovery') `
    ($utf8.GetBytes('before') + $newline + $utf8.GetBytes('recovered') + $newline)
Invoke-OutputCase 'host can restore capture after process delivery' `
    $Consumer @('switch') ($utf8.GetBytes('process') + $newline)
Invoke-OutputCase 'reset restores capture after process delivery' `
    $Consumer @('reset') ($utf8.GetBytes('process') + $newline)
Invoke-OutputCase 'process quotas survive capture-free delivery' `
    $Consumer @('quota') ($utf8.GetBytes('abR') + $newline)
Invoke-OutputCase 'CLI publishes high bytes without Ada text encoding' `
    $Interpreter @('-e', "print('a'..string.char(0,255),7)") `
    ([byte[]](97,0,255,9,55) + $newline)
Invoke-OutputCase 'CLI version is flushed before runtime stdout' `
    $Interpreter @('-v', '-e', "print('after version')") `
    ($utf8.GetBytes('Lua Ada 0.1.0-dev (target 5.5.1)') + $newline +
     $utf8.GetBytes('after version') + $newline)
