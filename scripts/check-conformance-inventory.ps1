param(
    [string] $InventoryDirectory = '',
    [switch] $RequireComplete,
    [ValidateSet('strict-upstream','remaining-upstream-compatibility')]
    [string] $TargetPolicy = 'strict-upstream'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$result = Test-ConformanceInventory -Root $root -InventoryDirectory $InventoryDirectory `
    -RequireComplete:$RequireComplete -TargetPolicy $TargetPolicy
Write-Output "PASS: M3 inventory ($($result.Files) files, $($result.SourceAnchors) source anchors, $($result.ApiEntries) header entries)"
if (-not $RequireComplete) {
    Write-Output "FOUNDATION ONLY: $($result.PendingSourceAnchors) source anchors pending; this is not M3 conformance acceptance"
}
if ($TargetPolicy -ceq 'remaining-upstream-compatibility') {
    Write-Output "TARGET: $TargetPolicy; reviewed exclusions=$($result.ExcludedSourceObligations); required pending source obligations=$($result.RequiredPendingSourceAnchors); target complete=$($result.TargetComplete); strict upstream complete=$($result.Complete)"
}
exit 0
