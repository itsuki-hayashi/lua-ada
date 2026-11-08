param(
    [Parameter(Mandatory)][string] $Manifest,
    [Parameter(Mandatory)][string] $Output
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = [IO.Path]::GetFullPath($Output)
$relative = [IO.Path]::GetRelativePath($root,$target).Replace('\','/')
if (-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or
    (Test-Path -LiteralPath $target)) {
    throw 'T transform output must be a new disposable reports artifact'
}
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
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
# Creation is exclusive: a concurrent producer cannot turn the check above
# into permission to replace an earlier observation's source bytes.
$stream = [IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
try { $stream.Write($replay.bytes,0,$replay.bytes.Length) }
finally { $stream.Dispose() }
[ordered]@{id=$replay.id;disposition=$replay.disposition;review_status=$replay.review_status;
    diagnostic_only=$false;source_sha256=$replay.source_sha256;output_sha256=$replay.sha256;
    manifest_path=[IO.Path]::GetRelativePath($root,$manifestPath).Replace('\','/');
    manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant();
    output=$target;exclusion_policy_sha256=$policyHash;excluded_obligations=$replay.excluded_obligations} |
    ConvertTo-Json -Compress -Depth 16
