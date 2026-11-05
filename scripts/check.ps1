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
    & (Join-Path $PSScriptRoot 'check-documentation.ps1')
    Invoke-Alire -Arguments @('-n', 'build', $profileArgument, '--', $scenario)
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
    $env:DYLD_LIBRARY_PATH = $runtimePath + [IO.Path]::PathSeparator + $savedDyldPath

    Set-Location (Join-Path $projectRoot 'tests')
    Invoke-Alire -Arguments @('exec', '--', "bin/$LibraryType/test_runner$suffix")

    Set-Location (Join-Path $projectRoot 'cli')
    $cliExecutable = "bin/$LibraryType/lua_ada$suffix"
    $absoluteCli = Join-Path (Get-Location).Path $cliExecutable
    Invoke-Alire -Arguments @('exec', '--', 'pwsh', '-NoProfile', '-File',
        (Join-Path $PSScriptRoot 'check-cli.ps1'), '-Interpreter', $absoluteCli)
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
}

# The expected negative CLI test leaves the last native exit status nonzero.
exit 0
