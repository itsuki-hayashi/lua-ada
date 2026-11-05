param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$files = @('README.md', 'AGENTS.md', 'ARCHITECTURE.md', 'CONTRIBUTING.md') +
    @(Get-ChildItem (Join-Path $projectRoot 'docs') -Recurse -Filter *.md |
        Where-Object { $_.FullName -notmatch '[/\\]generated[/\\]' } |
        ForEach-Object { [IO.Path]::GetRelativePath($projectRoot, $_.FullName) }) +
    @('tests/README.md', 'references/README.md',
      'experiments/abi/README.md', 'experiments/frontend/README.md',
      'tests/modules/README.md')
$checked = 0

foreach ($relativePath in $files) {
    $path = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing document: $relativePath" }
    # Throw on malformed UTF-8 rather than silently replacing source bytes.
    $text = $utf8.GetString([IO.File]::ReadAllBytes($path))
    if ($text.Contains("`r") -or $text.Contains("`t") -or -not $text.EndsWith("`n")) {
        throw "Expected LF, spaces, and final newline: $relativePath"
    }
    foreach ($match in [regex]::Matches($text, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value.Trim('<', '>')
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) {
            continue
        }
        $target = [Uri]::UnescapeDataString(($target -split '#', 2)[0])
        $destination = Join-Path (Split-Path -Parent $path) $target
        if (-not (Test-Path -LiteralPath $destination)) {
            throw "Broken link in ${relativePath}: $target"
        }
    }
    # Aligned table columns make raw Markdown reviewable by humans and AI.
    $widths = $null
    foreach ($line in ($text -split "`n")) {
        if ($line.StartsWith('|')) {
            $cells = $line.Trim('|').Split('|')
            $current = @($cells | ForEach-Object { $_.Length })
            if ($null -ne $widths -and ($current -join ',') -ne ($widths -join ',')) {
                throw "Unaligned table in $relativePath"
            }
            $widths = $current
        }
        else { $widths = $null }
    }
    $checked++
}
Write-Output "PASS: $checked Markdown files (UTF-8/LF, local links, aligned tables)"
exit 0
