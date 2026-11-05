param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$savedArchive = $env:LUA_ADA_ABI_RUNTIME_ARCHIVE
try {
    Set-Location $projectRoot
    if ($IsMacOS) {
        # macOS GPRbuild lacks encapsulated SAL support and does not infer
        # Ada runtime linkage for this C-only main. Ask the selected native
        # compiler for its archive; never commit a machine-specific path.
        $archive = & alr exec -- gcc '-print-file-name=adalib/libgnat.a'
        if ($LASTEXITCODE -ne 0 -or
            -not (Test-Path -LiteralPath ($archive -join '') -PathType Leaf)) {
            throw 'Cannot locate selected GNAT runtime archive'
        }
        $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = ($archive -join '').Trim()
    }
    & alr exec -- gprbuild -P experiments/abi/abi_probe.gpr
    if ($LASTEXITCODE -ne 0) { throw 'ABI fixture build failed' }
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    & alr exec -- "build/abi/bin/abi_probe$suffix"
    if ($LASTEXITCODE -ne 0) { throw 'ABI feasibility probe failed' }
}
finally {
    Set-Location $originalLocation
    $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $savedArchive
}
exit 0
