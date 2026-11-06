param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('development', 'validation', 'release')]
    [string] $Profile = 'validation'
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
Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1') -Force
$scenario = '-XLUA_ADA_LIBRARY_TYPE=' + $LibraryType
$profileArgument = '--' + $Profile
$suffix = if ($IsWindows) { '.exe' } else { '' }

function Invoke-Alire {
    param([string[]] $Arguments)
    & alr @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Alire failed with exit status $LASTEXITCODE"
    }
}

try {
    Set-Location $projectRoot
    $adaRuntimeDirectory = ''
    if ($IsMacOS) {
        $runtime = Get-SelectedAdaRuntime
        $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $runtime.CoreArchive
        $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $runtime.TaskingArchive
        $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $runtime.Directory
        $adaRuntimeDirectory = $runtime.Directory + [IO.Path]::PathSeparator
    }
    & (Join-Path $PSScriptRoot 'check-documentation.ps1')
    & (Join-Path $PSScriptRoot 'test-pe-unwind.ps1')
    Invoke-Alire -Arguments @('-n', 'build', $profileArgument, '--', $scenario)
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-core-image.ps1'),
        '-LibraryType', $LibraryType, '-Profile', $Profile)
    foreach ($crateName in @('cli', 'tests')) {
        Set-Location (Join-Path $projectRoot $crateName)
        Invoke-Alire -Arguments @('-n', 'build', $profileArgument,
            "--profiles=lua_ada=$Profile", '--', $scenario)
    }

    # Pin runtime lookup to the exact library that this job compiled. Searching
    # other profiles first could accidentally load a stale, incompatible DLL.
    $runtimePath = Join-Path $projectRoot "lib/$Profile/$LibraryType"
    $env:PATH = $runtimePath + [IO.Path]::PathSeparator + $savedPath
    $env:LD_LIBRARY_PATH = $runtimePath + [IO.Path]::PathSeparator + $savedLdPath
    $env:DYLD_LIBRARY_PATH = $runtimePath + [IO.Path]::PathSeparator + $adaRuntimeDirectory + $savedDyldPath

    Set-Location (Join-Path $projectRoot 'tests')
    Invoke-Alire -Arguments @('exec', '--', "bin/$LibraryType/test_runner$suffix")
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
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'compare.ps1'), '-Interpreter', $absoluteCli)
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
}

# The expected negative CLI test leaves the last native exit status nonzero.
exit 0
