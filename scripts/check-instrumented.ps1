param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$savedLocation = Get-Location
$variables = @('LUA_ADA_CONFIGURATION', 'PATH', 'LD_LIBRARY_PATH',
    'DYLD_LIBRARY_PATH', 'LUA_ADA_ABI_RUNTIME_ARCHIVE',
    'LUA_ADA_TASKING_RUNTIME_ARCHIVE', 'LUA_ADA_RUNTIME_LIBRARY_DIR')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$suffix = if ($IsWindows) { '.exe' } else { '' }
$reportDirectory = Join-Path $root "reports/instrumented/$LibraryType"
[void][IO.Directory]::CreateDirectory($reportDirectory)
$observations = [Collections.Generic.List[object]]::new()

function Invoke-CheckedAlire([string[]] $Arguments) {
    & alr @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Alire failed: $Arguments" }
}

function Invoke-ObservedProcess {
    param([string] $Name, [string] $Executable, [string[]] $Arguments,
        [string] $Directory, [string] $Witness, [switch] $Shutdown,
        [string] $ExpectedError = '')
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $Directory
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit(900000)
        if (-not $finished) { $process.Kill($true); $process.WaitForExit() }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $reportDirectory "$Name.stdout"), $stdout)
        [IO.File]::WriteAllText((Join-Path $reportDirectory "$Name.stderr"), $stderr)
        $passed = $finished -and $process.ExitCode -eq 0 -and
            ($stderr.Replace("`r`n", "`n") -ceq $ExpectedError) -and
            $stdout -match $Witness
        if ($Shutdown) {
            $passed = $passed -and $stdout -match '(?s)\bOK\r?\n.*>>> closing state <<<'
        }
        $observations.Add([ordered]@{ name=$Name; exit_code=$process.ExitCode;
            completed=$finished; passed=$passed; shutdown_witness_required=[bool]$Shutdown })
        if (-not $passed) { throw "Instrumented regression failed: $Name (see $reportDirectory)" }
        Write-Host "PASS: instrumented regression $Name"
        return $stdout
    } finally { $process.Dispose() }
}

try {
    Set-Location $root
    $env:LUA_ADA_CONFIGURATION = 'upstream-test'
    $runtimePrefix = ''
    if ($IsMacOS) {
        Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1') -Force
        $runtime = Get-SelectedAdaRuntime
        $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $runtime.CoreArchive
        $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $runtime.TaskingArchive
        $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $runtime.Directory
        $runtimePrefix = $runtime.Directory + [IO.Path]::PathSeparator
    }
    # Build serially with the same strict project switches as ordinary jobs.
    Invoke-CheckedAlire @('-n', '-C', 'tests', 'build', '--validation',
        '--profiles=lua_ada=validation', '--', "-XLUA_ADA_LIBRARY_TYPE=$LibraryType")
    # Shared executables need the selected compiler's support DLLs as well as
    # liblua. Obtain that search path from Alire instead of the ambient shell.
    $selectedPath = & alr exec -- pwsh -NoProfile -Command '$env:PATH'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot obtain selected runtime search path' }
    $selectedPath = ($selectedPath -join '').Trim()
    $library = Join-Path $root "lib/upstream-test/validation/$LibraryType"
    $env:PATH = $library + [IO.Path]::PathSeparator + $selectedPath
    $env:LD_LIBRARY_PATH = $library + [IO.Path]::PathSeparator + $saved.LD_LIBRARY_PATH
    $env:DYLD_LIBRARY_PATH = $library + [IO.Path]::PathSeparator + $runtimePrefix + $saved.DYLD_LIBRARY_PATH
    $libraryName = if ($LibraryType -ne 'relocatable') { 'liblua.a' }
        elseif ($IsWindows) { 'liblua.dll' }
        elseif ($IsMacOS) { 'liblua.dylib' } else { 'liblua.so' }
    $observations.Add([ordered]@{ name='library-artifact';
        path=(Join-Path $library $libraryName);
        sha256=(Get-FileHash -LiteralPath (Join-Path $library $libraryName) -Algorithm SHA256).Hash })
    $bin = Join-Path $root "tests/bin/upstream-test/$LibraryType"
    $unitOutput = Invoke-ObservedProcess -Name aunit -Executable "$bin/test_runner$suffix" `
        -Arguments @() -Directory $root -Witness 'Failed Assertions:\s+0\s+Unexpected Errors:\s+0' `
        -ExpectedError "Lua warning: error in __gc ((native):1: ordinary failure)`n"
    if ($unitOutput -notmatch 'Total Tests Run:\s+([1-9][0-9]*)') { throw 'Missing AUnit case count' }
    Write-Host "AUnit cases: $($Matches[1])"
    $null = Invoke-ObservedProcess -Name configuration `
        -Executable "$bin/lua-configuration_probe$suffix" -Arguments @() `
        -Directory $root -Witness '"configuration":"upstream-test"'
    $runner = "$bin/conformance_runner$suffix"
    & "$PSScriptRoot/check-conformance-adapter.ps1" -Interpreter $runner
    & "$PSScriptRoot/check-conformance-equivalents.ps1"

    # Keep diagnostic equivalent execution visibly separate from acceptance.
    # Each file gets a fresh disposable working directory and a byte-identical
    # executable called lua, so subprocess lookup cannot select a C oracle.
    foreach ($file in @('events', 'gengc', 'gc')) {
        $directory = Join-Path $reportDirectory ($file + '-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        $child = Join-Path $directory "lua$suffix"
        Copy-Item -LiteralPath $runner -Destination $child
        $env:PATH = $directory + [IO.Path]::PathSeparator + $library + [IO.Path]::PathSeparator + $selectedPath
        $source = Join-Path $root "references/lua/testes/$file.lua"
        $target = Join-Path $directory "$file.lua"
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($file -eq 'gc') {
            & "$PSScriptRoot/New-ConformanceEquivalent.ps1" `
                -Manifest "$root/tests/conformance/equivalents/gc-ada-instrumented.json" `
                -Output $target -AllowUnreviewedDiagnostics |
                Set-Content -LiteralPath (Join-Path $reportDirectory 'gc-equivalent.json')
        } else { Copy-Item -LiteralPath $source -Destination $target }
        $code = "assert(T and T.checkmemory and T.alloccount); assert(_soft==nil and _port==nil)"
        $null = Invoke-ObservedProcess -Name $file -Executable $child `
            -Arguments @('-e', $code, $target) -Directory $directory `
            -Witness '(?m)^OK\r?$' -Shutdown:($file -eq 'gc')
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $sourceHash) {
            throw "Upstream source changed: $file"
        }
        $observations.Add([ordered]@{ name="$file-artifacts"; source_sha256=$sourceHash;
            executed_sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;
            executable_sha256=(Get-FileHash -LiteralPath $child -Algorithm SHA256).Hash;
            disposition=$(if ($file -eq 'gc') { 'unreviewed-equivalent' } else { 'unchanged' }) })
    }
    Write-Output "PASS: instrumented validation/$LibraryType regressions; scope acceptance remains pending"
} finally {
    [ordered]@{ schema_version=1; configuration='upstream-test'; library=$LibraryType;
        diagnostic_only=$true; scope_accepted=$false; observations=@($observations.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportDirectory 'report.json')
    Set-Location $savedLocation
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}
