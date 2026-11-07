param(
    [Parameter(Mandatory)][string] $Manifest,
    [switch] $RequireScopedAcceptance,
    [string] $Report = ''
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceMatrix.psm1') -Force
$result = Test-ScopedMatrix -Root (Split-Path -Parent $PSScriptRoot) -ManifestPath $Manifest `
    -RequireScopedAcceptance:$RequireScopedAcceptance
if ($Report -ne '') {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Report), ($result | ConvertTo-Json -Depth 12) + "`n")
}
Write-Output "Matrix: $($result.operations) file/context operations; scoped acceptance=$($result.scoped_acceptance); full M3 acceptance=False"
