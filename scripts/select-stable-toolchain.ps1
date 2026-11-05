param()

$ErrorActionPreference = 'Stop'
# Alire's unconstrained toolchain selection can choose a prerelease (observed
# on macOS). Inspect every release, exclude unavailable/prerelease versions,
# and choose the newest stable version for this host without a committed pin.
$releases = & alr -n search --full gnat_native
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate native GNAT releases' }
$candidates = @()
foreach ($line in $releases) {
    $fields = $line.Trim() -split '\s+'
    if ($fields[0] -ne 'gnat_native') { continue }
    $release = @($fields | Where-Object { $_ -match '^\d+\.\d+\.\d+$' })
    if ($release.Count -ne 1 -or $fields -contains 'U' -or $fields -contains 'X') {
        continue
    }
    $candidates += $release[0]
}
if ($candidates.Count -eq 0) { throw 'No stable native GNAT is available for this host' }
$selected = $candidates | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
Write-Output "Selecting latest stable native GNAT: $selected"
for ($attempt = 1; $attempt -le 3; $attempt++) {
    & alr -n toolchain --select "gnat_native=$selected"
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -eq 3) { throw "Cannot select native GNAT $selected" }
    # GitHub archive downloads occasionally return HTTP 504. Retry the same
    # stable release; never silently fall back to a different compiler.
    Write-Output "Retrying stable compiler deployment (attempt $($attempt + 1))"
    Start-Sleep -Seconds 2
}
exit 0
