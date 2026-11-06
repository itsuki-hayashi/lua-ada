param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $ReferenceLibraryDirectory,
    [ValidateSet('default', 'upstream-test')][string] $Configuration = 'default'
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
$terminator = Join-Path $directory 'native-terminate.exe'
& alr exec -- gcc -std=c99 -Wall -Wextra -Werror -pedantic -o $terminator `
    "$root/tests/conformance/platform/windows_process.c"
if ($LASTEXITCODE -ne 0) { throw 'Native process fixture build failed' }
$selectedPath = & alr exec -- pwsh -NoProfile -Command '$env:PATH'
if ($LASTEXITCODE -ne 0) { throw 'Cannot obtain GNAT support DLL search path' }
# Keep the caller's exact liblua directory first, then add compiler support
# DLLs. Direct child execution does not inherit Alire's temporary environment.
$executionPath = $env:PATH + [IO.Path]::PathSeparator + ($selectedPath -join '').Trim()
$candidate = Join-Path $directory 'files-windows-equivalent.lua'
& "$PSScriptRoot/New-ConformanceEquivalent.ps1" `
    -Manifest "$root/tests/conformance/equivalents/files-windows-platform.json" `
    -Output $candidate -AllowUnreviewedDiagnostics |
    Set-Content -LiteralPath (Join-Path $directory 'equivalent.json')
$expectedShellError = "'not-to-be-found-command' is not recognized as an internal or external command,`r`noperable program or batch file.`r`n" * 2
$fixtures = @(
    @{ File='windows-buffered-failure.lua'; Witness='native Windows buffered failure counterpart OK' },
    @{ File='windows-partial-write.lua'; Witness='native Windows partial write counterpart OK' }
    @{ File='windows-files-contract.lua'; Witness='native Windows file contracts OK' }
    @{ File='files-windows-equivalent.lua'; Path=$candidate; MatchOutput=$true;
       Witness='(?m)^test done on \d{2}/\d{2}/\d+, at \d{2}:\d{2}:\d{2}\r?\nLua 5\.5\r?\n\z';
       ExpectedError=$expectedShellError }
)
$records = @()
foreach ($fixtureCase in $fixtures) {
$fixture = if ($fixtureCase.ContainsKey('Path')) { $fixtureCase.Path }
    else { Join-Path $root "tests/conformance/platform/$($fixtureCase.File)" }
foreach ($implementation in @('c', 'ada')) {
    $executable = if ($implementation -eq 'c') { $oracle } else { $ada }
    $working = Join-Path $directory ($implementation + '-' + $fixtureCase.File)
    [void][IO.Directory]::CreateDirectory($working)
    $child = Join-Path $working 'lua.exe'
    Copy-Item -LiteralPath $executable -Destination $child
    Copy-Item -LiteralPath $module -Destination $working
    Copy-Item -LiteralPath $terminator -Destination $working
    $start = [Diagnostics.ProcessStartInfo]::new($child)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $working
    $start.Environment['PATH'] = $working + [IO.Path]::PathSeparator + $executionPath
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $setup = if ($Configuration -eq 'upstream-test') { "assert(type(T)=='table' and type(T.checkmemory)=='function'); " }
        else { 'assert(T==nil); ' }
    $setup += 'assert(_soft==nil and _port==nil); '
    if ($implementation -eq 'c') {
        $start.Environment['PATH'] = $working + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $executionPath
        $setup += "local p=assert(package.loadlib('conformance_platform.dll','luaopen_conformance_platform'))(); _test_failing_stream=p.failing_stream; _test_nonblocking_pair=p.nonblocking_pair"
    }
    $start.ArgumentList.Add('-e')
    $start.ArgumentList.Add($setup)
    $start.ArgumentList.Add($fixture)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(900000)) {
            $process.Kill($true)
            throw "Native counterpart timeout: $implementation"
        }
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        $prefix = "$implementation-$($fixtureCase.File)"
        [IO.File]::WriteAllText((Join-Path $directory "$prefix.stdout"), $stdout)
        [IO.File]::WriteAllText((Join-Path $directory "$prefix.stderr"), $stderr)
        $expectedError = if ($fixtureCase.ContainsKey('ExpectedError')) { $fixtureCase.ExpectedError } else { '' }
        $matched = if ($fixtureCase.ContainsKey('MatchOutput')) { $stdout -match $fixtureCase.Witness }
            else { $stdout.TrimEnd("`r", "`n") -ceq $fixtureCase.Witness }
        if ($fixtureCase.ContainsKey('MatchOutput')) {
            foreach ($marker in @('testing i/o', 'testing flush', 'testing large files',
                'testing popen/pclose and execute', 'testing date/time')) {
                $matched = $matched -and $stdout.Contains($marker)
            }
            if ($Configuration -eq 'upstream-test') {
                $matched = $matched -and $stdout.Contains('testing failed write')
            }
            $matched = $matched -and $stdout -notmatch 'skipping|omitted|not implemented'
        }
        if ($process.ExitCode -ne 0 -or $stderr -cne $expectedError -or -not $matched) {
            throw "Native counterpart failed: $implementation (see $directory)"
        }
        $records += [ordered]@{ implementation=$implementation; exit_code=$process.ExitCode;
            fixture=$fixtureCase.File;
            fixture_sha256=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash;
            executable_sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash }
    } finally { $process.Dispose() }
}
}
[ordered]@{ counterpart='Windows file platform obligations'; review_status='pending';
    configuration=$Configuration; diagnostic_only=$true; scope_accepted=$false;
    driver_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;
    module_sha256=(Get-FileHash -LiteralPath $module -Algorithm SHA256).Hash;
    terminator_sha256=(Get-FileHash -LiteralPath $terminator -Algorithm SHA256).Hash;
    executions=$records } | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $directory 'report.json')
Write-Output 'PASS: matching C/Ada Windows file equivalents and counterparts; mapping review pending'
