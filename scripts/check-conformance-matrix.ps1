param(
    [Parameter(Mandatory)][string] $Manifest,
    [switch] $RequireScopedAcceptance,
    [ValidateSet('','remaining-upstream-compatibility')][string] $TargetPolicy = '',
    [switch] $RequireTargetAcceptance,
    [string] $Report = ''
)
$ErrorActionPreference = 'Stop'
if (($TargetPolicy -ne '' -and $RequireScopedAcceptance) -or
    ($TargetPolicy -eq '' -and $RequireTargetAcceptance)) {
    throw 'Select either historical scoped acceptance or the explicit full-target policy'
}
if ($TargetPolicy -ne '') {
    Import-Module (Join-Path $PSScriptRoot 'ConformanceTargetMatrix.psm1') -Force
    $result = Test-FullTargetMatrix -Root (Split-Path -Parent $PSScriptRoot) -ManifestPath $Manifest `
        -TargetPolicy $TargetPolicy -RequireTargetAcceptance:$RequireTargetAcceptance
} else {
    Import-Module (Join-Path $PSScriptRoot 'ConformanceMatrix.psm1') -Force
    $result = Test-ScopedMatrix -Root (Split-Path -Parent $PSScriptRoot) -ManifestPath $Manifest `
        -RequireScopedAcceptance:$RequireScopedAcceptance
}
if ($Report -ne '') {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Report), ($result | ConvertTo-Json -Depth 12) + "`n")
}
if ($TargetPolicy -ne '') {
    Write-Output "Target matrix: $($result.operations) required and $($result.supplemental_operations) supplemental pairs; target acceptance=$($result.target_acceptance); reviewed exclusions=$($result.excluded_obligation_count); original unchanged suite=$($result.original_suite_unchanged_pass); full M3 acceptance=False"
} else {
    Write-Output "Matrix: $($result.operations) file/context operations; scoped acceptance=$($result.scoped_acceptance); full M3 acceptance=False"
}
