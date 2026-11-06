param(
    [Parameter(Mandatory = $true)]
    [string] $Interpreter,
    [string] $Oracle = '',
    [string] $Report = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$suffix = if ($IsWindows) { '.exe' } else { '' }
if ($Oracle -eq '') {
    $Oracle = Join-Path $projectRoot "build/oracle/bin/lua$suffix"
}
if ($Report -eq '') {
    $Report = Join-Path $projectRoot 'reports/m3-lifecycle-campaign.json'
}
$script = Join-Path $projectRoot 'tests/lua/lifecycle_campaign.lua'
$baseline = '7579fc9d7ed90240487251dfb69168f8e64e9294'
$marker = "M3 lifecycle campaign OK`t1024`tseed`t872641"

function Invoke-Campaign {
    param([string] $Executable)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.ArgumentList.Add($script)
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    foreach ($name in @('LUA_INIT', 'LUA_INIT_5_5', 'LUA_PATH',
                       'LUA_PATH_5_5', 'LUA_CPATH', 'LUA_CPATH_5_5')) {
        [void] $start.Environment.Remove($name)
    }
    $process.StartInfo = $start
    $output = [IO.MemoryStream]::new()
    $errors = [IO.MemoryStream]::new()
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        [void] $process.Start()
        # Capture bytes concurrently: neither invalid UTF-8 replacement nor a
        # full stderr pipe can hide a mismatch or deadlock the test process.
        $readOutput = $process.StandardOutput.BaseStream.CopyToAsync($output)
        $readErrors = $process.StandardError.BaseStream.CopyToAsync($errors)
        $timedOut = -not $process.WaitForExit(900000)
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        [void] $readOutput.GetAwaiter().GetResult()
        [void] $readErrors.GetAwaiter().GetResult()
        $watch.Stop()
        return @{
            Code = $process.ExitCode
            TimedOut = $timedOut
            Milliseconds = $watch.ElapsedMilliseconds
            Out = $output.ToArray()
            Err = $errors.ToArray()
        }
    }
    finally {
        $watch.Stop()
        $process.Dispose()
        $output.Dispose()
        $errors.Dispose()
    }
}

foreach ($program in @($Interpreter, $Oracle)) {
    if (-not (Test-Path -LiteralPath $program -PathType Leaf)) {
        throw "Build the interpreter and pinned C oracle first: $program"
    }
}
$Interpreter = (Resolve-Path -LiteralPath $Interpreter).Path
$Oracle = (Resolve-Path -LiteralPath $Oracle).Path
$revision = & git -c core.fsmonitor=false -C (Join-Path $projectRoot 'references/lua') rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or "$revision" -ne $baseline) {
    throw "Unexpected Lua oracle revision: $revision"
}

$reference = Invoke-Campaign -Executable $Oracle
$actual = Invoke-Campaign -Executable $Interpreter
$equal = [Convert]::ToBase64String($reference.Out) -ceq
         [Convert]::ToBase64String($actual.Out)
$success = $equal -and $reference.Code -eq 0 -and $actual.Code -eq 0 -and
           -not $reference.TimedOut -and -not $actual.TimedOut -and
           $reference.Err.Length -eq 0 -and $actual.Err.Length -eq 0 -and
           [Text.Encoding]::ASCII.GetString($reference.Out).Contains($marker) -and
           [Text.Encoding]::ASCII.GetString($actual.Out).Contains($marker)

# Keep exact outputs alongside a small machine-readable report. On a failure
# the fixed seed and unchanged first-party source reproduce the same input;
# resource exhaustion, crashes, and timeouts never become syntax-test skips.
$Report = [IO.Path]::GetFullPath($Report)
[void] [IO.Directory]::CreateDirectory((Split-Path -Parent $Report))
$prefix = [IO.Path]::Combine((Split-Path -Parent $Report),
                            [IO.Path]::GetFileNameWithoutExtension($Report))
[IO.File]::WriteAllBytes("$prefix-c.stdout", $reference.Out)
[IO.File]::WriteAllBytes("$prefix-c.stderr", $reference.Err)
[IO.File]::WriteAllBytes("$prefix-ada.stdout", $actual.Out)
[IO.File]::WriteAllBytes("$prefix-ada.stderr", $actual.Err)
$evidence = [ordered]@{
    Baseline = $baseline
    Seed = '872641'
    Cases = 1024
    Families = 4
    ExecutionPolicy = 'Lua_Compatible'
    TimeoutSeconds = 900
    RawStdoutEqual = $equal
    Passed = $success
    C = @{ Exit = $reference.Code; Timeout = $reference.TimedOut;
           Milliseconds = $reference.Milliseconds;
           StdoutBytes = $reference.Out.Length; StderrBytes = $reference.Err.Length }
    Ada = @{ Exit = $actual.Code; Timeout = $actual.TimedOut;
             Milliseconds = $actual.Milliseconds;
             StdoutBytes = $actual.Out.Length; StderrBytes = $actual.Err.Length }
}
[IO.File]::WriteAllText($Report, ($evidence | ConvertTo-Json -Depth 4),
                       [Text.UTF8Encoding]::new($false))
if (-not $success) {
    foreach ($entry in @(@{Name='c'; Result=$reference},
                         @{Name='ada'; Result=$actual})) {
        $text = [Text.Encoding]::UTF8.GetString($entry.Result.Out)
        $match = [regex]::Match($text, 'MISMATCH_SOURCE_HEX\s+([0-9a-f]+)')
        if ($match.Success) {
            [IO.File]::WriteAllBytes(
                "$prefix-$($entry.Name)-mismatch.lua",
                [Convert]::FromHexString($match.Groups[1].Value))
        }
    }
    $offset = 0
    while ($offset -lt [Math]::Min($reference.Out.Length, $actual.Out.Length) -and
           $reference.Out[$offset] -eq $actual.Out[$offset]) { $offset++ }
    Write-Output "First differing stdout byte: $offset"
    foreach ($result in @($reference, $actual)) {
        Write-Output "Exit=$($result.Code), timeout=$($result.TimedOut), stderr=$([Text.Encoding]::UTF8.GetString($result.Err))"
    }
    throw "M3 lifecycle library campaign failed; evidence: $Report"
}
Write-Output "PARITY: 1024 M3 lifecycle cases, seed 872641; evidence: $Report"
