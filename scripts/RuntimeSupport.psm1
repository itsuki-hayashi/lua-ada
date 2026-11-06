Set-StrictMode -Version Latest

function Get-SelectedAdaRuntime {
    # Ask the selected compiler, not the shell's ambient GCC or a pinned local
    # installation path. Its real archive path also identifies the clean shared
    # runtime directory, avoiding malformed leading-space Alire DYLD entries.
    $output = & alr exec -- gcc '-print-file-name=adalib/libgnat.a'
    $archive = ($output -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw 'Cannot locate the selected GNAT runtime archive'
    }
    $archive = [IO.Path]::GetFullPath($archive)
    $directory = Split-Path -Parent $archive
    $tasking = Join-Path $directory 'libgnarl.a'
    if (-not (Test-Path -LiteralPath $tasking -PathType Leaf)) {
        throw "Selected GNAT tasking archive is absent: $tasking"
    }
    return [pscustomobject]@{ Directory = $directory;
        CoreArchive = $archive; TaskingArchive = $tasking }
}

Export-ModuleMember -Function Get-SelectedAdaRuntime
