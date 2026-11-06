Set-StrictMode -Version Latest

function Test-PEUnwindTable {
    <#
    .SYNOPSIS
    Validate the actual x64 PE exception directory before running a consumer.
    .DESCRIPTION
    Reads only documented PE headers and RUNTIME_FUNCTION rows. GNU BigObj
    partial links can otherwise leave duplicate/overlapping ranges whose
    invalid metadata crashes Windows while GNAT merely records an exception
    traceback. This check needs no external disassembler and changes no image.
    It is a structural guard, not a proof of every unwind opcode's semantics;
    the real protected-allocation/error consumers exercise that runtime path.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    [byte[]] $bytes = [IO.File]::ReadAllBytes($resolved)

    function Assert-Range([long] $Offset, [long] $Count) {
        if ($Offset -lt 0 -or $Count -lt 0 -or $Offset -gt $bytes.LongLength - $Count) {
            throw "Truncated PE image: $resolved (offset=$Offset, bytes=$Count)"
        }
    }
    function Read-U16([long] $Offset) {
        Assert-Range $Offset 2
        return [BitConverter]::ToUInt16($bytes, [int]$Offset)
    }
    function Read-U32([long] $Offset) {
        Assert-Range $Offset 4
        return [BitConverter]::ToUInt32($bytes, [int]$Offset)
    }

    Assert-Range 0 64
    if ((Read-U16 0) -ne 0x5A4D) { throw "Missing PE DOS signature: $resolved" }
    [long] $pe = Read-U32 0x3C
    Assert-Range $pe 24
    if ((Read-U32 $pe) -ne 0x4550) { throw "Missing PE signature: $resolved" }
    [long] $coff = $pe + 4
    if ((Read-U16 $coff) -ne 0x8664) {
        throw "PE unwind validation requires an x86-64 image: $resolved"
    }
    [int] $sectionCount = Read-U16 ($coff + 2)
    [int] $optionalSize = Read-U16 ($coff + 16)
    [long] $optional = $coff + 20
    Assert-Range $optional $optionalSize
    if ($optionalSize -lt 144 -or (Read-U16 $optional) -ne 0x20B) {
        throw "Invalid PE32+ optional header: $resolved"
    }
    if ((Read-U32 ($optional + 108)) -lt 4) {
        throw "Missing PE exception directory: $resolved"
    }
    [long] $imageSize = Read-U32 ($optional + 56)
    [long] $headerSize = Read-U32 ($optional + 60)
    [long] $directory = $optional + 112 + 3 * 8
    [long] $tableRva = Read-U32 $directory
    [long] $tableSize = Read-U32 ($directory + 4)
    if ($tableRva -eq 0 -or $tableSize -eq 0) {
        throw "Missing PE exception directory: $resolved"
    }
    if ($tableSize % 12 -ne 0) {
        throw "PE exception directory is not a RUNTIME_FUNCTION table: $resolved"
    }
    [long] $sectionHeaders = $optional + $optionalSize
    Assert-Range $sectionHeaders ($sectionCount * 40)

    function Get-RvaOffset([long] $Rva, [long] $Count) {
        if ($Rva -lt 0 -or $Count -le 0 -or $Rva -gt $imageSize - $Count) {
            throw "PE RVA is outside the image: $resolved (RVA=$Rva, bytes=$Count)"
        }
        if ($Rva -lt $headerSize -and $Rva -le $headerSize - $Count) {
            Assert-Range $Rva $Count
            return $Rva
        }
        for ($section = 0; $section -lt $sectionCount; $section++) {
            [long] $entry = $sectionHeaders + $section * 40
            [long] $start = Read-U32 ($entry + 12)
            [long] $rawSize = Read-U32 ($entry + 16)
            [long] $raw = Read-U32 ($entry + 20)
            if ($Rva -ge $start -and $Count -le $rawSize -and
                $Rva - $start -le $rawSize - $Count) {
                [long] $offset = $raw + $Rva - $start
                Assert-Range $offset $Count
                return $offset
            }
        }
        throw "PE RVA has no initialized section bytes: $resolved (RVA=$Rva, bytes=$Count)"
    }

    [long] $table = Get-RvaOffset $tableRva $tableSize
    [int] $rows = $tableSize / 12
    [long] $previousBegin = -1
    [long] $previousEnd = 0
    for ($index = 0; $index -lt $rows; $index++) {
        [long] $entry = $table + $index * 12
        [long] $begin = Read-U32 $entry
        [long] $end = Read-U32 ($entry + 4)
        [long] $unwind = Read-U32 ($entry + 8)
        if ($begin -ge $end -or $end -gt $imageSize) {
            throw "Invalid PE unwind interval: $resolved (row=$index, begin=$begin, end=$end)"
        }
        if ($begin -lt $previousBegin) {
            throw "Unsorted PE unwind table: $resolved (row=$index)"
        }
        if ($begin -lt $previousEnd) {
            throw ("Overlapping PE unwind intervals: {0} (row={1}, previous=0x{2:x}-0x{3:x}, current=0x{4:x}-0x{5:x})" -f
                $resolved, $index, $previousBegin, $previousEnd, $begin, $end)
        }
        # Each target must have actual file bytes; retained alignment gaps
        # or a plausible in-image number are not valid unwind information.
        $null = Get-RvaOffset $begin 1
        $null = Get-RvaOffset ($end - 1) 1
        $null = Get-RvaOffset $unwind 4
        $previousBegin = $begin
        $previousEnd = $end
    }
    return [pscustomobject]@{
        Path = $resolved
        Entries = $rows
        ExceptionRva = $tableRva
        ExceptionBytes = $tableSize
    }
}

Export-ModuleMember -Function Test-PEUnwindTable
