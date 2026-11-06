param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $ReferenceLibraryDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This counterpart requires Windows native pipes' }
$root = Split-Path -Parent $PSScriptRoot
$ada = (Resolve-Path -LiteralPath $Interpreter).Path
$oracle = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
$referenceLibrary = (Resolve-Path -LiteralPath $ReferenceLibraryDirectory).Path
$directory = Join-Path $root ('reports/windows-buffered-failure/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$module = Join-Path $directory 'conformance_platform.dll'
$source = Join-Path $root 'tests/c/conformance_platform.c'
& alr exec -- gcc -std=c99 -Wall -Wextra -Werror -pedantic -shared `
    -DLUA_ADA_PLATFORM_MODULE -I "$root/c_api/include/api" -o $module $source `
    -L $referenceLibrary -lconformance_lua
if ($LASTEXITCODE -ne 0) { throw 'Native counterpart module build failed' }
$fixture = Join-Path $root 'tests/conformance/platform/windows-buffered-failure.lua'
$records = @()
foreach ($implementation in @('c', 'ada')) {
    $executable = if ($implementation -eq 'c') { $oracle } else { $ada }
    $start = [Diagnostics.ProcessStartInfo]::new($executable)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $directory
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($implementation -eq 'c') {
        $start.Environment['PATH'] = $referenceLibrary + [IO.Path]::PathSeparator + $env:PATH
        $start.ArgumentList.Add('-e')
        $start.ArgumentList.Add("_test_failing_stream=assert(package.loadlib('conformance_platform.dll','luaopen_conformance_platform'))().failing_stream")
    }
    $start.ArgumentList.Add($fixture)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "Native counterpart timeout: $implementation"
        }
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $directory "$implementation.stdout"), $stdout)
        [IO.File]::WriteAllText((Join-Path $directory "$implementation.stderr"), $stderr)
        if ($process.ExitCode -ne 0 -or $stderr -ne '' -or
            $stdout.TrimEnd("`r", "`n") -cne 'native Windows buffered failure counterpart OK') {
            throw "Native counterpart failed: $implementation (see $directory)"
        }
        $records += [ordered]@{ implementation=$implementation; exit_code=$process.ExitCode;
            executable_sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash }
    } finally { $process.Dispose() }
}
[ordered]@{ counterpart='Windows buffered flush failure'; review_status='pending';
    fixture_sha256=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash;
    driver_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;
    module_sha256=(Get-FileHash -LiteralPath $module -Algorithm SHA256).Hash;
    executions=$records } | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $directory 'report.json')
Write-Output 'PASS: matching C/Ada native buffered failure counterpart; mapping review pending'
