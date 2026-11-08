param(
    [Parameter(Mandatory)][string] $Manifest,
    [Parameter(Mandatory)][string] $Output
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceVerifierEquivalents.psm1') -Force
$manifestPath=(Resolve-Path -LiteralPath $Manifest).Path
$specification=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
# Reconstruct and independently validate the complete operation before writing
# anything. The bounded validator permits only Ada's instrumented verifier;
# no diagnostic/synthetic approval switches are exposed by this generator.
$replay=Get-ConformanceVerifierReplay -Root $root -Specification $specification `
    -Implementation Ada -Configuration upstream-test
$target=[IO.Path]::GetFullPath($Output)
$relative=[IO.Path]::GetRelativePath($root,$target).Replace('\','/')
if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal)){
    throw 'Verifier equivalent output must be a disposable reports artifact'
}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
[IO.File]::WriteAllBytes($target,$replay.bytes)
[ordered]@{
    id=$replay.id;disposition=$replay.disposition;review_status=$replay.review_status
    source_sha256=$replay.source_sha256;output_sha256=$replay.sha256
    semantic_sha256=$replay.semantic_sha256
    manifest_path=[IO.Path]::GetRelativePath($root,$manifestPath).Replace('\','/')
    manifest_sha256=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant()
    output=$target;excluded_obligations=@();runtime_acceptance=$false;coverage_authority=$false
}|ConvertTo-Json -Compress -Depth 16
