param(
    [ValidateSet('gc-io-events')][string] $Scope = 'gc-io-events',
    [string] $InventoryDirectory = '',
    [switch] $RequireScopedComplete,
    [string] $Report = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1') -Force
$result = Test-ConformanceScope -Root $root -Scope $Scope `
    -InventoryDirectory $InventoryDirectory -RequireScopedComplete:$RequireScopedComplete
if ($Report -ne '') {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Report),
        ($result | ConvertTo-Json -Depth 12) + "`n")
}
Write-Output "PASS: scope structure $Scope ($($result.Files) files, $($result.SourceAnchors) anchors, $($result.ApiEntries) API entries); full inventory checked"
Write-Output "Scoped completion=$($result.ScopeComplete); full M3 completion=False"
if (-not $RequireScopedComplete) {
    Write-Output "PENDING: $($result.UnresolvedSourceAnchors) source anchors and $($result.UnresolvedApiEntries) API entries; no acceptance claim"
}
exit 0
