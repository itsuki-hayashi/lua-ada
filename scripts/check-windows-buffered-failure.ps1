param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $ReferenceLibraryDirectory,
    [ValidateSet('default', 'upstream-test')][string] $Configuration = 'default',
    [ValidateSet('development','validation','release')][string] $Profile = 'validation',
    [ValidateSet('static','static-pic','relocatable')][string] $LibraryType = 'static'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This counterpart requires Windows native pipes' }
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1') -Force
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
$hostName = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$link = if ($LibraryType -eq 'relocatable') { 'shared' } else { $LibraryType }
$context = "$Configuration/$hostName/$Profile/$link"
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
    $runId = [Guid]::NewGuid().ToString('N')
    $telemetryPrefix = Join-Path $working 'allocator'
    $start.Environment['LUA_ADA_CONFORMANCE_TELEMETRY'] = $telemetryPrefix
    $start.Environment['LUA_ADA_CONFORMANCE_RUN_ID'] = $runId
    $setup = if ($Configuration -eq 'upstream-test') { "assert(type(T)=='table' and type(T.checkmemory)=='function'); " }
        else { 'assert(T==nil); ' }
    $setup += 'assert(_soft==nil and _port==nil); '
    if ($implementation -eq 'c') {
        $start.Environment['PATH'] = $working + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $executionPath
        $setup += "local p=assert(package.loadlib('conformance_platform.dll','luaopen_conformance_platform'))(); _test_failing_stream=p.failing_stream; _test_nonblocking_pair=p.nonblocking_pair"
    }
    if ((Get-FileHash -LiteralPath $executable).Hash -cne (Get-FileHash -LiteralPath $child).Hash) {
        throw 'Disposable Windows launcher differs from selected executable'
    }
    $target = if ($implementation -eq 'c') { 'ReferenceC' } else { 'Ada' }
    $probeEnvironment = @{}
    foreach ($entry in $start.Environment.GetEnumerator()) { $probeEnvironment[$entry.Key] = $entry.Value }
    $launcher = Test-ScopedLauncher -Executable $child -Directory $working `
        -OutputPrefix (Join-Path $directory "$implementation-$($fixtureCase.File)-configuration") `
        -Environment $probeEnvironment -Configuration $Configuration -Target $target
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
        $measured = Get-Content -LiteralPath "$telemetryPrefix.$($process.Id).json" -Raw |
            ConvertFrom-Json -AsHashtable
        Assert-ManagedTelemetry -Telemetry $measured -RunId $runId -ProcessId $process.Id `
            -Configuration $Configuration -RequireShutdown:($implementation -eq 'ada')
        $childTelemetry = @()
        foreach ($sidecar in Get-ChildItem -LiteralPath $working -Filter 'allocator.*.json') {
            $child = Get-Content -LiteralPath $sidecar.FullName -Raw | ConvertFrom-Json -AsHashtable
            $childId = [int]($sidecar.BaseName.Split('.')[-1])
            Assert-ManagedTelemetry -Telemetry $child -RunId $runId -ProcessId $childId `
                -Configuration $Configuration -RequireShutdown:($implementation -eq 'ada')
            if ($childId -ne $process.Id) { $childTelemetry += $child }
        }
        # The pinned C os.exit children bypass its CLI telemetry writer. The
        # Ada launcher disposes and records all eight Lua children, including
        # typed exits. Normal C children still supply their four sidecars.
        $expectedChildren = if ($fixtureCase.File -in @('windows-files-contract.lua', 'files-windows-equivalent.lua')) {
            if ($implementation -eq 'ada') { 8 } else { 4 }
        } else { 0 }
        if ($childTelemetry.Count -ne $expectedChildren) {
            throw "Missing or unexpected child allocator telemetry: $implementation/$($fixtureCase.File)"
        }
        $records += [ordered]@{ implementation=$implementation; exit_code=$process.ExitCode;
            launcher=$launcher;
            allocator_telemetry=$measured; child_allocator_telemetry=$childTelemetry;
            fixture=$fixtureCase.File;
            fixture_sha256=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash;
            executable_sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash }
    } finally { $process.Dispose() }
}
}
[ordered]@{ counterpart='Windows file platform obligations'; review_status='pending';
    configuration=$Configuration; context=$context; diagnostic_only=$true; scope_accepted=$false;
    driver_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;
    module_sha256=(Get-FileHash -LiteralPath $module -Algorithm SHA256).Hash;
    terminator_sha256=(Get-FileHash -LiteralPath $terminator -Algorithm SHA256).Hash;
    executions=$records } | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath (Join-Path $directory 'report.json')
Write-Output 'PASS: matching C/Ada Windows file equivalents and counterparts; mapping review pending'
