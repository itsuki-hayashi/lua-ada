param(
    [Parameter(Mandatory)][string] $ArtifactsDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string] $Revision,
    [string] $Output = '',
    [string] $ConsumerMapping = 'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json',
    [string] $AUnitMapping = 'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json',
    [switch] $Replay
)
$ErrorActionPreference = 'Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module "$PSScriptRoot/ExpandedMatrixBundle.psm1" -Force
$result=New-ExpandedMatrixCandidate -Root $root -ArtifactsDirectory $ArtifactsDirectory `
    -Revision $Revision -Output $Output -ConsumerMapping $ConsumerMapping -AUnitMapping $AUnitMapping
Write-Output "COLLECTED: 26 contexts,338 primary pairs,26 constructs supplements,728 process reports; candidate=$($result.manifest)"
Write-Output 'DIAGNOSTIC ONLY: contracts,mappings,coverage and final matrix acceptance require independent review'
if ($Replay) {
    & "$PSScriptRoot/check-conformance-matrix.ps1" -Manifest $result.manifest `
        -Report (Join-Path (Split-Path -Parent $result.manifest) 'expanded-matrix.diagnostic-replay.json')
    if ($LASTEXITCODE -ne 0) { throw 'Expanded diagnostic matrix replay failed' }
}
