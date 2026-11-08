param(
    [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string] $Configuration,
    [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string] $Implementation,
    [Parameter(Mandatory)][ValidateSet('windows','linux','macos')][string] $Platform,
    [string[]] $EquivalentManifest=@(),
    [string[]] $TAdaptationManifest=@(),
    [string[]] $ReviewedSourceManifest=@(),
    [Parameter(Mandatory)][string] $Output
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
$suite=Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$selections=@();$seen=@{}
foreach($kind in @('equivalent','t-private','reviewed-source')){
    $paths=if($kind -ceq 'equivalent'){$EquivalentManifest}elseif($kind -ceq 't-private'){$TAdaptationManifest}else{$ReviewedSourceManifest}
    foreach($path in $paths){
        $full=if([IO.Path]::IsPathRooted($path)){$path}else{Join-Path $root $path}
        $relative=[IO.Path]::GetRelativePath($root,$full).Replace('\','/')
        $sha=(Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant()
        $null=Resolve-ReviewedFile -Root $root -Path $relative -Sha256 $sha
        $mapping=Get-Content -LiteralPath $full -Raw|ConvertFrom-Json -AsHashtable -Depth 64
        $source=[IO.Path]::GetFileName($mapping.source)
        if($mapping.source -cne ('references/lua/testes/'+$source) -or $source -ceq 'heavy.lua' -or
            $source -cnotin $suite.files.path -or $seen.ContainsKey($source) -or
            $mapping.configuration -cnotin @($Configuration,'default-and-upstream-test')){
            throw 'Aggregate author selections must identify distinct original sources and this configuration'
        }
        $seen[$source]=$true
        $selections+=@{source=$source;kind=$kind;manifest=@{path=$relative;sha256=$sha}}
    }
}
if($selections.Count -eq 0){throw 'Aggregate proposal requires explicit source transformations'}
$proposal=@{schema_version=1;kind='target-aggregate-replay';target='remaining-upstream-compatibility';
    id=('aggregate-'+$Configuration+'-'+$Platform+'-'+$Implementation.ToLowerInvariant());reference_revision=$suite.reference_revision;
    configuration=$Configuration;implementation=$Implementation;platform=$Platform;synthetic_fixture=$false;
    original_sources=@($suite.files|ForEach-Object{@{path=$_.path;sha256=$_.sha256}});selections=$selections;
    review=@{status='pending';author='Codex /root/validation_delivery';reviewer=$null;artifact=$null;artifact_sha256=$null};
    runtime_acceptance=$false;coverage_authority=$false}
$destination=[IO.Path]::GetFullPath($Output)
$relative=[IO.Path]::GetRelativePath($root,$destination).Replace('\','/')
if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $destination)){
    throw 'Aggregate proposals require a new disposable reports path'
}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
[IO.File]::WriteAllText($destination,(ConvertTo-Json -InputObject $proposal -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "AUTHOR PROPOSAL: $destination; single-file semantics and aggregate selection still require independent review; acceptance=False"
