param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'PEUnwind.psm1') -Force
$temporary = Join-Path $root ('reports/pe-unwind-selftest/' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($temporary)
$script:Cases = 0

function New-Image {
    # Minimal synthetic headers are never executable fixtures. Three mapped
    # sections supply two adjacent code intervals and real unwind bytes.
    [byte[]] $image = [byte[]]::new(0x600)
    function U16([int] $Offset, [uint16] $Value) {
        [BitConverter]::GetBytes($Value).CopyTo($image, $Offset)
    }
    function U32([int] $Offset, [uint32] $Value) {
        [BitConverter]::GetBytes($Value).CopyTo($image, $Offset)
    }
    U16 0 0x5A4D; U32 0x3C 0x80; U32 0x80 0x4550
    U16 0x84 0x8664; U16 0x86 3; U16 0x94 0xF0
    U16 0x98 0x20B; U32 0xD0 0x4000; U32 0xD4 0x200
    U32 0x104 16; U32 0x120 0x2000; U32 0x124 24
    $section = 0x188
    foreach ($mapping in @(@(0x1000, 0x200), @(0x2000, 0x300), @(0x3000, 0x400))) {
        U32 ($section + 12) $mapping[0]
        U32 ($section + 16) 0x100
        U32 ($section + 20) $mapping[1]
        $section += 40
    }
    U32 0x300 0x1000; U32 0x304 0x1020; U32 0x308 0x3000
    U32 0x30C 0x1020; U32 0x310 0x1040; U32 0x314 0x3004
    return ,$image
}

function Set-U32([byte[]] $Image, [int] $Offset, [uint32] $Value) {
    [BitConverter]::GetBytes($Value).CopyTo($Image, $Offset)
}
function Case([string] $Name, [scriptblock] $Action) {
    & $Action
    $script:Cases++
    Write-Output "PE UNWIND TEST PASS: $Name"
}
function Reject([byte[]] $Image, [string] $Expected) {
    $path = Join-Path $temporary "$($script:Cases).exe"
    [IO.File]::WriteAllBytes($path, $Image)
    $message = ''
    try { $null = Test-PEUnwindTable $path }
    catch { $message = $_.Exception.Message }
    if ($message -notmatch $Expected) {
        throw "Expected rejection '$Expected', observed '$message'"
    }
}

Case 'adjacent intervals are valid' {
    $path = Join-Path $temporary 'valid.exe'
    [IO.File]::WriteAllBytes($path, (New-Image))
    $result = Test-PEUnwindTable $path
    if ($result.Entries -ne 2) { throw 'Valid fixture lost a real unwind row' }
}
Case 'overlapping ranges are rejected' {
    $image = New-Image; Set-U32 $image 0x30C 0x1010
    Reject $image 'Overlapping'
}
Case 'duplicate starts are rejected' {
    $image = New-Image; Set-U32 $image 0x30C 0x1000
    Reject $image 'Overlapping'
}
Case 'unsorted ranges are rejected' {
    $image = New-Image; Set-U32 $image 0x30C 0x0FF0
    Reject $image 'Unsorted'
}
Case 'empty code range is rejected' {
    $image = New-Image; Set-U32 $image 0x304 0x1000
    Reject $image 'Invalid PE unwind interval'
}
Case 'partial table row is rejected' {
    $image = New-Image; Set-U32 $image 0x124 25
    Reject $image 'RUNTIME_FUNCTION'
}
Case 'unmapped table bytes are rejected' {
    $image = New-Image; Set-U32 $image 0x120 0x20F8
    Reject $image 'no initialized section'
}
Case 'unmapped unwind information is rejected' {
    $image = New-Image; Set-U32 $image 0x308 0x3100
    Reject $image 'no initialized section'
}
Case 'missing exception directory is rejected' {
    $image = New-Image; Set-U32 $image 0x124 0
    Reject $image 'Missing PE exception'
}
Case 'wrong machine is rejected' {
    $image = New-Image
    [BitConverter]::GetBytes([uint16]0xAA64).CopyTo($image, 0x84)
    Reject $image 'x86-64'
}
Case 'truncated header is rejected' { Reject ([byte[]]::new(16)) 'Truncated' }
Write-Output "PASS: $script:Cases focused PE unwind validator cases"
