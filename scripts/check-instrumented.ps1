param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('','remaining-upstream-compatibility')][string] $TargetPolicy = '',
    [string] $TargetWitnessPolicy = '',
    [switch] $TargetDevelopmentObservation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1') -Force
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
$targetWitnesses = $null; $previousTargetReports = @()
if ($TargetPolicy -ne '') {
    if ($TargetWitnessPolicy -eq '') { throw 'Target build mode requires its explicit successor witness policy' }
    Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
    $targetWitnesses = Read-TargetWitnessPolicy -Root $root -Path $TargetWitnessPolicy -RequireReview:(-not $TargetDevelopmentObservation)
    $previousTargetReports = @(Get-ChildItem (Join-Path $root 'reports/core-image') -Filter result.json -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
} elseif ($TargetWitnessPolicy -ne '' -or $TargetDevelopmentObservation) { throw 'Target witness/development flags require TargetPolicy' }

function Invoke-CheckedAlire([string[]] $Arguments) {
    & alr @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Alire failed: $Arguments" }
}

& (Join-Path $PSScriptRoot 'test-aunit-launch.ps1')
& (Join-Path $PSScriptRoot 'test-aunit-evidence.ps1')
& (Join-Path $PSScriptRoot 'test-foreign-contract-evidence.ps1')
& (Join-Path $PSScriptRoot 'test-configured-fixture-selection.ps1')

function Invoke-ObservedProcess {
    param([string] $Name, [string] $Executable, [string[]] $Arguments,
        [string] $Directory, [string] $Witness, [switch] $Shutdown,
        [string] $ExpectedError = '', [switch] $Telemetry)
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $Directory
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $runId = [Guid]::NewGuid().ToString('N')
    $telemetryPrefix = Join-Path $reportDirectory "$Name-$runId"
    if ($Telemetry) {
        $start.Environment['LUA_ADA_CONFORMANCE_TELEMETRY'] = $telemetryPrefix
        $start.Environment['LUA_ADA_CONFORMANCE_RUN_ID'] = $runId
    }
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
        if ($Telemetry) {
            $measured = Get-Content -LiteralPath "$telemetryPrefix.$($process.Id).json" -Raw |
                ConvertFrom-Json -AsHashtable
            Assert-ManagedTelemetry -Telemetry $measured -RunId $runId `
                -ProcessId $process.Id -Configuration upstream-test -RequireShutdown
            $observations.Add([ordered]@{ name="$Name-allocator"; telemetry=$measured;
                allocator_telemetry_verified=$true })
        }
        Write-Host "PASS: instrumented regression $Name"
        return $stdout
    } finally { $process.Dispose() }
}

try {
    Set-Location $root
    $env:LUA_ADA_CONFIGURATION = 'upstream-test'
    $runtimePrefix = ''
    if (-not $IsWindows) {
        Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1') -Force
        $runtime = Get-SelectedAdaRuntime
        if ($IsMacOS) {
            $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $runtime.CoreArchive
            $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $runtime.TaskingArchive
            $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $runtime.Directory
        }
        $runtimePrefix = $runtime.Directory + [IO.Path]::PathSeparator
    }
    # Build serially with the same strict project switches as ordinary jobs.
    Invoke-CheckedAlire @('-n', '-C', 'tests', 'build', '--validation',
        '--profiles=lua_ada=validation', '--', "-XLUA_ADA_LIBRARY_TYPE=$LibraryType", '-XLUA_ADA_PREBUILT=false')
    Invoke-CheckedAlire @('-n','-C','cli','build','--validation',
        '--profiles=lua_ada=validation','--',"-XLUA_ADA_LIBRARY_TYPE=$LibraryType",'-XLUA_ADA_PREBUILT=false')
    # Shared executables need the selected compiler's support DLLs as well as
    # liblua. Obtain that search path from Alire instead of the ambient shell.
    $selectedPath = & alr exec -- pwsh -NoProfile -Command '$env:PATH'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot obtain selected runtime search path' }
    $selectedPath = ($selectedPath -join '').Trim()
    $library = Join-Path $root "lib/upstream-test/validation/$LibraryType"
    $env:PATH = $library + [IO.Path]::PathSeparator + $selectedPath
    $env:LD_LIBRARY_PATH = $library + [IO.Path]::PathSeparator + $runtimePrefix + $saved.LD_LIBRARY_PATH
    $env:DYLD_LIBRARY_PATH = $library + [IO.Path]::PathSeparator + $runtimePrefix + $saved.DYLD_LIBRARY_PATH
    $libraryName = if ($LibraryType -ne 'relocatable') { 'liblua.a' }
        elseif ($IsWindows) { 'liblua.dll' }
        elseif ($IsMacOS) { 'liblua.dylib' } else { 'liblua.so' }
    $observations.Add([ordered]@{ name='library-artifact';
        path=(Join-Path $library $libraryName);
        sha256=(Get-FileHash -LiteralPath (Join-Path $library $libraryName) -Algorithm SHA256).Hash })
    $bin = Join-Path $root "tests/bin/upstream-test/$LibraryType"
    & "$PSScriptRoot/check-aunit-evidence.ps1" -Executable "$bin/test_runner$suffix" `
        -Configuration upstream-test -Profile validation -LibraryType $LibraryType
    $null = Invoke-ObservedProcess -Name configuration `
        -Executable "$bin/lua-configuration_probe$suffix" -Arguments @() `
        -Directory $root -Witness '"configuration":"upstream-test"'
    $runner = "$bin/conformance_runner$suffix"
    & "$PSScriptRoot/check-conformance-adapter.ps1" -Interpreter $runner
    $null = Invoke-ObservedProcess -Name continuation-api -Executable $runner `
        -Arguments @((Join-Path $root 'tests/instrumented/t_coroutine_api.lua')) `
        -Directory $root -Witness 'T COROUTINE API OK' -Telemetry
    & "$PSScriptRoot/check-conformance-telemetry.ps1" -Interpreter $runner -Configuration upstream-test
    if ($TargetPolicy -eq '') {
        & "$PSScriptRoot/check-conformance-equivalents.ps1"
        & "$PSScriptRoot/check-conformance-scope.ps1"
        & "$PSScriptRoot/test-conformance-scope.ps1"
        & "$PSScriptRoot/test-conformance-matrix.ps1"
    } else {
        # The accepted scopes remain bound to their original source tree.
        # Target builds exercise the successor validators and frozen-input
        # reconstruction tests; those tests report stale production bindings
        # explicitly and never grant runtime or target acceptance.
        & "$PSScriptRoot/test-code-v3-installation.ps1"
        if ($LASTEXITCODE -ne 0) { throw 'Installed Code source guards failed' }
        & "$PSScriptRoot/test-t-transform-output.ps1"
        if ($LASTEXITCODE -ne 0) { throw 'Disposable T source guards failed' }
        & "$PSScriptRoot/test-conformance-transforms.ps1"
        & "$PSScriptRoot/test-target-development-observer.ps1"
        & "$PSScriptRoot/test-conformance-target-matrix.ps1"
    }

    Invoke-CheckedAlire @('exec', '--', 'gprbuild', '-P',
        'experiments/conformance/oracle.gpr', '-XLUA_CONFORMANCE_CONFIGURATION=upstream-test')
    Invoke-CheckedAlire @('exec', '--', 'gprbuild', '-P',
        'experiments/conformance/oracle.gpr', '-XLUA_CONFORMANCE_CONFIGURATION=default')
    $consoleDirectory=Join-Path $root ('reports/core-image/'+[guid]::NewGuid().ToString('N'))
    & "$PSScriptRoot/check-debug-console.ps1" -Interpreter "$root/cli/bin/upstream-test/$LibraryType/lua_ada$suffix" `
        -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua$suffix" `
        -ReferenceLibraryDirectory "$root/build/conformance/upstream-test/lib" `
        -RuntimeDirectory $library -Configuration upstream-test -OutputDirectory (Join-Path $consoleDirectory 'lua')
    $cliPairReport=Join-Path $root ('reports/core-image/cli-'+[guid]::NewGuid().ToString('N')+'/pair.json')
    & "$PSScriptRoot/check-configured-cli.ps1" -Interpreter "$root/cli/bin/upstream-test/$LibraryType/lua_ada$suffix" `
        -RuntimeDirectory $library `
        -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua$suffix" `
        -ReferenceLibraryDirectory "$root/build/conformance/upstream-test/lib" `
        -Configuration upstream-test -LibraryType $LibraryType -Report $cliPairReport `
        -DevelopmentObservation:$TargetDevelopmentObservation
    & "$PSScriptRoot/test-cli-fixtures.ps1" -Report $cliPairReport
    & "$PSScriptRoot/test-cli-fixture-transport.ps1" -Interpreter "$root/build/conformance/default/bin/lua$suffix" `
        -RuntimeDirectory "$root/build/conformance/default/lib"
    # These files need actual selected stack constants and a real T table.
    # Running their source through the default glob without setup would either
    # fail before the operation or silently miss the instrumented obligation.
    $configuredReport=Join-Path $root ('reports/core-image/configured-'+[guid]::NewGuid().ToString('N')+'/result.json')
    & "$PSScriptRoot/check-configured-fixtures.ps1" -Interpreter $runner `
        -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua$suffix" `
        -Configuration upstream-test -RuntimeDirectory $library `
        -ReferenceLibraryDirectory "$root/build/conformance/upstream-test/lib" -LibraryType $LibraryType -Report $configuredReport
    if ($IsWindows) {
        & "$PSScriptRoot/check-windows-buffered-failure.ps1" -Interpreter $runner `
            -Configuration upstream-test -LibraryType $LibraryType `
            -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua.exe" `
            -ReferenceLibraryDirectory "$root/build/conformance/upstream-test/lib"
    } elseif (-not $IsMacOS) {
        # The scoped macOS runner below executes its native flush counterpart
        # before the equivalent, while retaining upstream T.nonblock tests.
        & "$PSScriptRoot/check-posix-files.ps1" -Interpreter $runner `
            -Configuration upstream-test -LibraryType $LibraryType `
            -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua" `
            -ReferenceLibraryDirectory "$root/build/conformance/upstream-test/lib"
    }
    if ($TargetPolicy -eq '') {
    & "$PSScriptRoot/check-expanded-conformance.ps1" -Interpreter $runner `
        -Configuration upstream-test -LibraryType $LibraryType -RuntimeDirectory $library `
        -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua$suffix"
    }
    & "$PSScriptRoot/test-conformance-launcher.ps1" -Interpreter $runner `
        -Configuration upstream-test `
        -ReferenceInterpreter "$root/build/conformance/upstream-test/bin/lua$suffix" `
        -ReferenceLibraryDirectory "$root/build/conformance/upstream-test/lib"
    # Exercise the real public C consumers exactly once after deliberately
    # selecting a different remembered root profile. The regression selects
    # configuration only, preserves the existing SAL and owns no second build.
    # Keep Alire invocations serialized with the test and oracle builds above.
    & "$PSScriptRoot/test-prebuilt-runtime-profile.ps1" -Profile validation `
        -LibraryType $LibraryType -Configuration upstream-test -TargetPolicy $TargetPolicy
    if ($LASTEXITCODE -ne 0) { throw 'Instrumented C consumer checks failed' }
    # The four console modes are separate invocations of the actual newly
    # linked consumer. They cannot borrow its no-argument case count or its
    # custom allocator counts: these modes use their public state constructor.
    $consoleCompilerOutput=& alr exec -- pwsh -NoProfile -Command '(Get-Command gcc -ErrorAction Stop).Source'
    if($LASTEXITCODE -ne 0){throw 'Cannot identify selected instrumented console C compiler'}
    $consoleCompiler=($consoleCompilerOutput -join '').Trim()
    & "$PSScriptRoot/check-debug-console-c.ps1" -Interpreter "$root/build/conformance/upstream-test/bin/lua$suffix" `
        -AdaConsumer "$root/build/c-api/bin/upstream-test/validation/$LibraryType/builtin_api_contract$suffix" `
        -Compiler $consoleCompiler -ReferenceLibrary "$root/build/conformance/upstream-test/lib" `
        -AdaRuntimeDirectory $library -Configuration upstream-test -OutputDirectory (Join-Path $consoleDirectory 'c')
    if ($TargetPolicy -ne '') {
        $platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        $link = if ($LibraryType -ceq 'relocatable') { 'shared' } else { $LibraryType }
        $null = Write-TargetBuildWitnesses -Root $root -Policy $targetWitnesses `
            -Context "upstream-test/$platform/validation/$link" -PreviousReports $previousTargetReports -ConfiguredReport $configuredReport -CliReport $cliPairReport
        Write-Output 'Target build phase completed; File/Aggregate/Heavy executions belong to immutable-image partition jobs; target acceptance=False'
    }
    Write-Output "PASS: instrumented validation/$LibraryType regressions; scope acceptance remains pending"
} finally {
    [ordered]@{ schema_version=1; configuration='upstream-test'; library=$LibraryType;
        diagnostic_only=$true; scope_accepted=$false; observations=@($observations.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportDirectory 'report.json')
    Set-Location $savedLocation
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}
