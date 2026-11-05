param(
    [Parameter(Mandatory)]
    [string] $AdaProbe
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$original = Get-Location
try {
    Set-Location $root
    & alr exec -- gprbuild -P experiments/libraries/host_layout.gpr
    if ($LASTEXITCODE -ne 0) { throw 'C layout probe build failed' }
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    $expected = @(& "./build/libraries/host_layout$suffix")
    if ($LASTEXITCODE -ne 0) { throw 'C layout probe failed' }
    $actual = @(& $AdaProbe)
    if ($LASTEXITCODE -ne 0) { throw 'Ada layout probe failed' }
    # Compare every measured native width and alignment, including C99's
    # long-double contribution. Equal format output alone could conceal an
    # incorrect host assumption until a different ABI reaches the same code.
    if (($expected -join "`n") -cne ($actual -join "`n")) {
        throw "Native layout mismatch:`nC:`n$($expected -join "`n")`nAda:`n$($actual -join "`n")"
    }
    [IO.Directory]::CreateDirectory((Join-Path $root 'reports')) | Out-Null
    [IO.File]::WriteAllLines((Join-Path $root 'reports/native-layout.txt'),
        [string[]]$actual, [Text.UTF8Encoding]::new($false))
    Write-Output ($actual -join "`n")
    Write-Output 'PASS: Ada native packing layout matches the C99 oracle'
}
finally { Set-Location $original }
exit 0
