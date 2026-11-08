param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('development', 'validation', 'release')]
    [string] $Profile = 'validation',
    [ValidateSet('','remaining-upstream-compatibility')][string] $TargetPolicy = '',
    [string] $TargetWitnessPolicy = '',
    [switch] $TargetDevelopmentObservation
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$savedPath = $env:PATH
$savedLdPath = $env:LD_LIBRARY_PATH
$savedDyldPath = $env:DYLD_LIBRARY_PATH
$savedArchive = $env:LUA_ADA_ABI_RUNTIME_ARCHIVE
$savedTaskingArchive = $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE
$savedRuntimeDirectory = $env:LUA_ADA_RUNTIME_LIBRARY_DIR
$savedConfiguration = $env:LUA_ADA_CONFIGURATION
Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1') -Force
$scenario = '-XLUA_ADA_LIBRARY_TYPE=' + $LibraryType
$profileArgument = '--' + $Profile
$suffix = if ($IsWindows) { '.exe' } else { '' }
$targetWitnesses = $null; $previousTargetReports = @()
if ($TargetPolicy -ne '') {
    if ($TargetWitnessPolicy -eq '') { throw 'Target build mode requires its explicit successor witness policy' }
    Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
    $targetWitnesses = Read-TargetWitnessPolicy -Root $projectRoot -Path $TargetWitnessPolicy -RequireReview:(-not $TargetDevelopmentObservation)
    $previousTargetReports = @(Get-ChildItem (Join-Path $projectRoot 'reports/core-image') -Filter result.json -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
} elseif ($TargetWitnessPolicy -ne '' -or $TargetDevelopmentObservation) { throw 'Target witness/development flags require TargetPolicy' }

function Invoke-Alire {
    param([string[]] $Arguments)
    & alr @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Alire failed with exit status $LASTEXITCODE"
    }
}

try {
    Set-Location $projectRoot
    $env:LUA_ADA_CONFIGURATION = 'default'
    $adaRuntimeDirectory = ''
    if (-not $IsWindows) {
        $runtime = Get-SelectedAdaRuntime
        if ($IsMacOS) {
            $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $runtime.CoreArchive
            $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $runtime.TaskingArchive
            $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $runtime.Directory
        }
        $adaRuntimeDirectory = $runtime.Directory + [IO.Path]::PathSeparator
    }
    & (Join-Path $PSScriptRoot 'check-documentation.ps1')
    & (Join-Path $PSScriptRoot 'test-pe-unwind.ps1')
    & (Join-Path $PSScriptRoot 'test-aunit-launch.ps1')
    & (Join-Path $PSScriptRoot 'test-aunit-evidence.ps1')
    & (Join-Path $PSScriptRoot 'test-foreign-contract-evidence.ps1')
    Invoke-Alire -Arguments @('-n', 'build', $profileArgument, '--', $scenario, '-XLUA_ADA_PREBUILT=false')
    $coreArguments=@('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-core-image.ps1'),
        '-LibraryType', $LibraryType, '-Profile', $Profile, '-UseExistingRuntime')
    if($TargetPolicy -ne ''){$coreArguments+=@('-TargetPolicy',$TargetPolicy)}
    Invoke-Alire -Arguments $coreArguments
    foreach ($crateName in @('cli', 'tests')) {
        Set-Location (Join-Path $projectRoot $crateName)
        Invoke-Alire -Arguments @('-n', 'build', $profileArgument,
            "--profiles=lua_ada=$Profile", '--', $scenario, '-XLUA_ADA_PREBUILT=true')
    }

    # Pin runtime lookup to the exact library that this job compiled. Searching
    # other profiles first could accidentally load a stale, incompatible DLL.
    $runtimePath = Join-Path $projectRoot "lib/$Profile/$LibraryType"
    $env:PATH = $runtimePath + [IO.Path]::PathSeparator + $savedPath
    # Disposable launchers lose any executable-relative compiler runtime path.
    # Keep the selected compiler's real adalib directory for their children.
    $env:LD_LIBRARY_PATH = $runtimePath + [IO.Path]::PathSeparator + $adaRuntimeDirectory + $savedLdPath
    $env:DYLD_LIBRARY_PATH = $runtimePath + [IO.Path]::PathSeparator + $adaRuntimeDirectory + $savedDyldPath

    Set-Location (Join-Path $projectRoot 'tests')
    & (Join-Path $PSScriptRoot 'check-aunit-evidence.ps1') `
        -Executable (Join-Path $projectRoot "tests/bin/$LibraryType/test_runner$suffix") `
        -Profile $Profile -LibraryType $LibraryType
    Invoke-Alire -Arguments @('exec', '--', "bin/$LibraryType/syntax_consumer$suffix")
    $upstreamRunner = Join-Path (Get-Location).Path "bin/$LibraryType/upstream_runner$suffix"
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-upstream.ps1'),
        '-Interpreter', $upstreamRunner)

    Set-Location (Join-Path $projectRoot 'cli')
    $cliExecutable = "bin/$LibraryType/lua_ada$suffix"
    $absoluteCli = Join-Path (Get-Location).Path $cliExecutable
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-output-policy.ps1'),
        '-Consumer', (Join-Path $projectRoot "tests/bin/$LibraryType/output_consumer$suffix"),
        '-Interpreter', $absoluteCli)
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-cli.ps1'), '-Interpreter', $absoluteCli)
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-lifecycle.ps1'),
        '-Interpreter', $absoluteCli)
    Set-Location $projectRoot
    Invoke-Alire -Arguments @('exec', '--', 'gprbuild', '-P',
        'experiments/conformance/oracle.gpr',
        '-XLUA_CONFORMANCE_CONFIGURATION=default')
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-binary-cli.ps1'),
        '-Interpreter', $absoluteCli,
        '-ReferenceInterpreter',
        (Join-Path $projectRoot "build/conformance/default/bin/lua$suffix"),
        '-RuntimeDirectory', $runtimePath)
    Set-Location (Join-Path $projectRoot 'cli')
    $versionOutput = & alr exec -- $cliExecutable --version
    if ($LASTEXITCODE -ne 0 -or
        ($versionOutput -join "`n") -ne 'Lua Ada 0.1.0-dev (target 5.5.1)') {
        throw 'CLI version contract failed'
    }
    $helpOutput = & alr exec -- $cliExecutable --help
    if ($LASTEXITCODE -ne 0 -or ($helpOutput -join "`n") -notmatch 'Usage:') {
        throw 'CLI help contract failed'
    }
    & alr exec -- $cliExecutable --invalid-option
    if ($LASTEXITCODE -eq 0) {
        throw 'CLI must fail for unsupported execution requests'
    }
    Set-Location $projectRoot
    $configuredRunner=Join-Path $projectRoot "tests/bin/$LibraryType/conformance_runner$suffix"
    $configuredReport=Join-Path $projectRoot ('reports/configured-fixtures/'+[guid]::NewGuid().ToString('N')+'/report.json')
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-configured-fixtures.ps1'),
        '-Interpreter',$configuredRunner,'-ReferenceInterpreter',
        (Join-Path $projectRoot "build/conformance/default/bin/lua$suffix"),
        '-Configuration','default','-RuntimeDirectory',$runtimePath,
        '-ReferenceLibraryDirectory',(Join-Path $projectRoot 'build/conformance/default/lib'),
        '-Report',$configuredReport)
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'compare.ps1'), '-Interpreter', $absoluteCli,
        '-ConfiguredWitnessReport',$configuredReport,'-ConfiguredInterpreter',$configuredRunner)
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-conformance-telemetry.ps1'),
        '-Interpreter', (Join-Path $projectRoot "tests/bin/$LibraryType/conformance_runner$suffix"),
        '-Configuration', 'default')
    if ($IsWindows) {
        Set-Location $projectRoot
        & (Join-Path $PSScriptRoot 'check-windows-buffered-failure.ps1') `
            -Interpreter (Join-Path $projectRoot "tests/bin/$LibraryType/conformance_runner$suffix") `
            -ReferenceInterpreter (Join-Path $projectRoot "build/conformance/default/bin/lua$suffix") `
            -ReferenceLibraryDirectory (Join-Path $projectRoot 'build/conformance/default/lib') `
            -Profile $Profile -LibraryType $LibraryType
    } elseif (-not $IsMacOS) {
        # macOS executes its named native counterpart in the scoped runner;
        # unchanged files.lua requires Linux's /dev/full device.
        & (Join-Path $PSScriptRoot 'check-posix-files.ps1') `
            -Interpreter (Join-Path $projectRoot "tests/bin/$LibraryType/conformance_runner$suffix") `
            -ReferenceInterpreter (Join-Path $projectRoot "build/conformance/default/bin/lua$suffix") `
            -ReferenceLibraryDirectory (Join-Path $projectRoot 'build/conformance/default/lib') `
            -Profile $Profile -LibraryType $LibraryType
    }
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'test-conformance-launcher.ps1'),
        '-Interpreter', (Join-Path $projectRoot "tests/bin/$LibraryType/conformance_runner$suffix"),
        '-ReferenceInterpreter', (Join-Path $projectRoot "build/conformance/default/bin/lua$suffix"),
        '-ReferenceLibraryDirectory', (Join-Path $projectRoot 'build/conformance/default/lib'))
    if ($TargetPolicy -eq '') {
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-expanded-conformance.ps1'),
        '-Interpreter', (Join-Path $projectRoot "tests/bin/$LibraryType/conformance_runner$suffix"),
        '-ReferenceInterpreter', (Join-Path $projectRoot "build/conformance/default/bin/lua$suffix"),
        '-RuntimeDirectory', $runtimePath, '-Configuration', 'default',
        '-Profile', $Profile, '-LibraryType', $LibraryType)
    } else {
        $platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        $link = if ($LibraryType -ceq 'relocatable') { 'shared' } else { $LibraryType }
        $null = Write-TargetBuildWitnesses -Root $projectRoot -Policy $targetWitnesses `
            -Context "default/$platform/$Profile/$link" -PreviousReports $previousTargetReports
        Write-Output 'Target build phase completed; File/Aggregate/Heavy executions belong to immutable-image partition jobs; target acceptance=False'
    }

    Write-Output "PASS: $Profile / $LibraryType (AUnit and CLI contracts)"
}
finally {
    Set-Location $originalLocation
    $env:PATH = $savedPath
    $env:LD_LIBRARY_PATH = $savedLdPath
    $env:DYLD_LIBRARY_PATH = $savedDyldPath
    $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $savedArchive
    $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $savedTaskingArchive
    $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $savedRuntimeDirectory
    $env:LUA_ADA_CONFIGURATION = $savedConfiguration
}

# The expected negative CLI test leaves the last native exit status nonzero.
exit 0
