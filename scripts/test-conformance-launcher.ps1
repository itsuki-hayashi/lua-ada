param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $ReferenceLibraryDirectory,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/launcher-selftest/' + [Guid]::NewGuid().ToString('N'))
$selected = Join-Path $directory 'selected'
$ambient = Join-Path $directory 'ambient'
[void][IO.Directory]::CreateDirectory($selected)
[void][IO.Directory]::CreateDirectory($ambient)
$suffix = if ($IsWindows) { '.exe' } else { '' }
$ada = Join-Path $selected "lua$suffix"
$c = Join-Path $ambient "lua$suffix"
Copy-Item -LiteralPath (Resolve-Path -LiteralPath $Interpreter).Path -Destination $ada
Copy-Item -LiteralPath (Resolve-Path -LiteralPath $ReferenceInterpreter).Path -Destination $c
$referenceLibrary = (Resolve-Path -LiteralPath $ReferenceLibraryDirectory).Path
$environment = @{
    PATH=$selected + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:PATH
    LD_LIBRARY_PATH=$referenceLibrary + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    DYLD_LIBRARY_PATH=$referenceLibrary + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
$wrongConfiguration = if ($Configuration -eq 'default') { 'upstream-test' } else { 'default' }
$failure = $null
try {
    Test-ScopedLauncher -Executable $ada -Directory $selected -OutputPrefix (Join-Path $directory 'wrong-parent') `
        -Environment $environment -Configuration $wrongConfiguration -Target Ada | Out-Null
} catch { $failure = $_.Exception.Message }
if ($failure -cne 'Observed configuration does not match the requested numeric/allocator baseline') {
    throw "Wrong parent configuration was not rejected: $failure"
}
Write-Output 'LAUNCHER TEST PASS: wrong parent configuration rejected'

# The selected parent remains the real Ada executable. PATH deliberately
# resolves bare lua to the separately built C oracle, whose measured report
# is valid but identifies a different implementation. Never accept it merely
# because both processes provide T or both have the same numeric widths.
$environment.PATH = $ambient + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:PATH
$failure = $null
try {
    Test-ScopedLauncher -Executable $ada -Directory $ambient -OutputPrefix (Join-Path $directory 'wrong-child') `
        -Environment $environment -Configuration $Configuration -Target Ada | Out-Null
} catch { $failure = $_.Exception.Message }
if ($failure -cne 'Scoped launcher bare child configuration differs') {
    throw "Wrong bare-lua implementation was not rejected: $failure"
}
Write-Output 'LAUNCHER TEST PASS: real ambient C child rejected for Ada parent'
Write-Output 'PASS: 2 actual launcher isolation regressions'
