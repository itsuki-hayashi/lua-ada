param(
    [string] $InventoryDirectory = '',
    [switch] $RequireComplete
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$result = Test-ConformanceInventory -Root $root -InventoryDirectory $InventoryDirectory `
    -RequireComplete:$RequireComplete
Write-Output "PASS: M3 inventory ($($result.Files) files, $($result.SourceAnchors) source anchors, $($result.ApiEntries) header entries)"
if (-not $RequireComplete) {
    Write-Output "FOUNDATION ONLY: $($result.PendingSourceAnchors) source anchors pending; this is not M3 conformance acceptance"
}
exit 0
