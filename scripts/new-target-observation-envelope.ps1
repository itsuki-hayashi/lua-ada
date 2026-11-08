param(
    [Parameter(Mandatory)][string] $BundleRoot,
    [Parameter(Mandatory)][string] $RawReport,
    [Parameter(Mandatory)][string] $Contract,
    [Parameter(Mandatory)][string] $ContextImage,
    [Parameter(Mandatory)][string] $Output,
    [string] $NativeApplicability = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TargetObservationEnvelope.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
$root=Split-Path -Parent $PSScriptRoot
function Identity([string] $Relative){
    $path=Resolve-TargetImagePath -Root $BundleRoot -Relative $Relative
    return @{path=$Relative;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
}
$rawIdentity=Identity $RawReport
$report=Get-Content -LiteralPath (Join-Path $BundleRoot $RawReport) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
$native=$null
if($NativeApplicability -ne ''){
    $nativePath=if([IO.Path]::IsPathRooted($NativeApplicability)){$NativeApplicability}else{Join-Path $root $NativeApplicability}
    $native=@{path=[IO.Path]::GetRelativePath($root,$nativePath).Replace('\','/');sha256=(Get-FileHash -LiteralPath $nativePath).Hash.ToLowerInvariant()}
}
$claims=Get-TargetObservationClaims -Report $report -RawIdentity $rawIdentity -ContractIdentity (Identity $Contract) `
    -ImageIdentity (Identity $ContextImage) -NativeApplicability $native
$envelope=@{schema_version=1;kind='target-post-observation-envelope';claims=$claims;
    synthetic_fixture=$report.synthetic_fixture;
    runtime_acceptance=$false;coverage_authority=$false;
    review=@{status='pending';author='Codex /root/validation_delivery';reviewer=$null;artifact=$null;artifact_sha256=$null}}
$destination=[IO.Path]::GetFullPath($Output)
$outputRelative=[IO.Path]::GetRelativePath($root,$destination).Replace('\','/')
if(-not $outputRelative.StartsWith('reports/',[StringComparison]::Ordinal)){throw 'Post-observation envelope proposals must stay inside reports'}
$source=[IO.Path]::GetFullPath((Join-Path $BundleRoot $RawReport))
if($destination -ieq $source){throw 'Envelope output must not overwrite the immutable raw report'}
if(Test-Path -LiteralPath $destination){throw 'Envelope proposal output must be new'}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
[IO.File]::WriteAllText($destination,(ConvertTo-Json -InputObject $envelope -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "AUTHOR PROPOSAL: post-observation envelope=$destination; raw report unchanged; acceptance=False"
