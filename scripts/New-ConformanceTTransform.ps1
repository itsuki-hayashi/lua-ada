param(
    [Parameter(Mandatory)][string] $Manifest,
    [Parameter(Mandatory)][string] $Output
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
$inventory = Test-ConformanceInventory -Root $root -TargetPolicy remaining-upstream-compatibility
$resolved = @{}
foreach ($entry in $inventory.Exclusions) { $resolved[$entry.id] = $entry }
$policy = Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json'
$policyHash = (Get-FileHash -LiteralPath $policy).Hash.ToLowerInvariant()
$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$specification = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
$replay = Get-ConformanceTReplay -Root $root -Specification $specification `
    -PolicySha256 $policyHash -ResolvedExclusions $resolved
$target = [IO.Path]::GetFullPath($Output)
$relative = [IO.Path]::GetRelativePath($root,$target).Replace('\','/')
if (-not $relative.StartsWith('reports/',[StringComparison]::Ordinal)) {
    throw 'T transform output must be a disposable reports artifact'
}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
[IO.File]::WriteAllBytes($target,$replay.bytes)
[ordered]@{id=$replay.id;disposition=$replay.disposition;review_status=$replay.review_status;
    diagnostic_only=$false;source_sha256=$replay.source_sha256;output_sha256=$replay.sha256;
    manifest_path=[IO.Path]::GetRelativePath($root,$manifestPath).Replace('\','/');
    manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant();
    output=$target;exclusion_policy_sha256=$policyHash;excluded_obligations=$replay.excluded_obligations} |
    ConvertTo-Json -Compress -Depth 16
