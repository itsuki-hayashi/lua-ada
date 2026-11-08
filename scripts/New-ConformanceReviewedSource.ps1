param([Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][string]$Output)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceReviewedSources.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
$target=[IO.Path]::GetFullPath($Output)
$relative=[IO.Path]::GetRelativePath($root,$target).Replace('\','/')
if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $target)){
    throw 'Reviewed source output must be a new disposable reports artifact'
}
$manifestPath=(Resolve-Path -LiteralPath $Manifest).Path
$specification=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -AsHashtable -Depth 64
$inventory=Test-ConformanceInventory -Root $root -TargetPolicy remaining-upstream-compatibility
$resolved=@{};foreach($entry in $inventory.Exclusions){$resolved[$entry.id]=$entry}
$policyHash=(Get-FileHash (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json')).Hash.ToLowerInvariant()
$replay=Get-TargetReviewedSourceReplay -Root $root -Specification $specification -Implementation Ada -Configuration upstream-test `
    -PolicySha256 $policyHash -ResolvedExclusions $resolved
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
[IO.File]::WriteAllBytes($target,$replay.bytes)
[ordered]@{id=$replay.id;disposition=$replay.disposition;diagnostic_only=$replay.diagnostic_only;review_status=$replay.review_status;
    source_sha256=$replay.source_sha256;output_sha256=$replay.sha256;output=$target;
    manifest_path=[IO.Path]::GetRelativePath($root,$manifestPath).Replace('\','/');
    manifest_sha256=(Get-FileHash $manifestPath).Hash.ToLowerInvariant();exclusion_policy_sha256=$policyHash;
    excluded_obligations=@($replay.excluded_obligations);runtime_acceptance=$false;coverage_authority=$false}|
    ConvertTo-Json -Compress -Depth 16
