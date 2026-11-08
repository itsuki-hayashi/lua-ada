param([Parameter(Mandatory)][string] $Context,[Parameter(Mandatory)][string] $WitnessPolicy,
    [Parameter(Mandatory)][string] $Compiler,[switch] $DevelopmentObservation)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'HeaderDeclarationProbes.psm1')
$policy=Read-TargetWitnessPolicy -Root $root -Path $WitnessPolicy -RequireReview:(-not $DevelopmentObservation)
$cases=@($policy.compiled.cases|Where-Object{ $Context -cin $_.contexts })
if($cases.Count -eq 0){throw 'NOT RUN: no compiled declaration witnesses are installed; global API acceptance remains pending'}
$revision=(& git -C $root rev-parse HEAD).Trim()
$changes=@(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if($LASTEXITCODE -ne 0 -or $changes.Count -ne 0){throw 'Compiled context witnesses require clean committed sources'}
$directory=Join-Path $root ('reports/target-builds/'+$Context.Replace('/','-')+'/compiled')
[void][IO.Directory]::CreateDirectory($directory)
$records=@()
foreach($case in $cases){
    if($case.Contains('protocol') -and $case.protocol -ceq 'paired-header-profile-v1'){
        $records+=Invoke-HeaderDeclarationPair -Root $root -Compiler $Compiler -Case $case
        continue
    }
    $source=Resolve-ReviewedFile -Root $root -Path $case.source.path -Sha256 $case.source.sha256
    if(($case.source.path -cnotmatch '\.c$') -or '-Werror' -cnotin $case.compile_arguments -or
        '-Wall' -cnotin $case.compile_arguments -or '-Wextra' -cnotin $case.compile_arguments -or
        ('{root}/'+$case.source.path) -cnotin @($case.compile_arguments|ForEach-Object{$_.Replace('\','/')})){
        throw 'Compiled declaration probe lacks its exact source or strict C diagnostics'
    }
    $arguments=@($case.compile_arguments|ForEach-Object{$_.Replace('{root}',$root)})
    $artifact=[IO.Path]::GetFullPath($case.output.Replace('{root}',$root))
    $relative=[IO.Path]::GetRelativePath($root,$artifact).Replace('\','/')
    if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $artifact)){
        throw 'Compiled witness executable output must be a new reports artifact'
    }
    $outputIndex=[Array]::IndexOf($arguments,'-o')
    if($outputIndex -lt 0 -or $outputIndex+1 -ge $arguments.Count -or
        [IO.Path]::GetFullPath($arguments[$outputIndex+1]) -cne $artifact -or
        @($arguments|Where-Object{$_ -ceq '-o'}).Count -ne 1){throw 'Compiled probe arguments select another executable output'}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $artifact))
    $compile=Invoke-ConformanceProcess -Executable $Compiler -Arguments $arguments -Directory $root `
        -OutputPrefix (Join-Path $directory ($case.id+'-compile')) -TimeoutSeconds 120
    if($compile.exit_code -ne 0 -or $compile.timed_out -or -not (Test-Path -LiteralPath $artifact)){
        throw "Compiled declaration probe failed: $($case.id)"
    }
    $execution=Invoke-ConformanceProcess -Executable $artifact `
        -Arguments @($case.execution_arguments|ForEach-Object{$_.Replace('{root}',$root)}) -Directory $root `
        -OutputPrefix (Join-Path $directory ($case.id+'-execution')) -TimeoutSeconds 30
    $records+=@{id=$case.id;source_bindings=$case.source_bindings;compile=$compile;execution=$execution;
        artifact=@{path=$artifact;sha256=(Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant()}}
}
$report=@{schema_version=1;kind='target-compiled-context-observations';context=$Context;revision=$revision;
    source_root=$root;repository_dirty=$false;synthetic_fixture=$false;
    development_observation=[bool]$DevelopmentObservation;
    source_review_status=$(if($policy.source_reviewed){'accepted'}else{'pending'});
    compiler_sha256=(Get-FileHash -LiteralPath $Compiler).Hash.ToLowerInvariant();cases=$records;
    runtime_acceptance=$false;coverage_authority=$false}
$path=Join-Path $directory 'observations.json'
[IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $report -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Import-Module (Join-Path $PSScriptRoot 'TargetCompiledWitnesses.psm1')
$verified=Test-TargetCompiledWitnesses -Root $root -Mapping $policy.compiled -Report $report -ArtifactRoot $root `
    -Context $Context -Revision $revision -CompilerSha256 $report.compiler_sha256
Write-Output "OBSERVED: $($verified.Count) source-bound compiled context witnesses; acceptance=False; report=$path"
