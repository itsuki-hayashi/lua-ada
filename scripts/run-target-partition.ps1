param(
    [Parameter(Mandatory)][string] $Context,
    [Parameter(Mandatory)][ValidateSet('files-1','files-2','files-3','aggregate','heavy')][string] $Partition,
    [string] $ImageDirectory = '',
    [string] $ExecutionPolicy = '',
    [switch] $DevelopmentObservation,
    [switch] $PlanOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceFileProtocols.psm1')
$plan=Get-TargetContextPlan -Root $root
$entry=@($plan.partitions | Where-Object { $_.context -ceq $Context -and $_.partition -ceq $Partition })
if($entry.Count -ne 1){throw 'Unknown target execution partition'}
$entry=$entry[0]
$operations=@()
if($entry.operation -ceq 'file'){
    foreach($file in $entry.files){
        foreach($target in @('ReferenceC','Ada')){$operations+=@{operation='file:'+$file;file=$file;target=$target;variant='primary';constructs_branch=0}}
        if($file -ceq 'constructs.lua'){
            foreach($target in @('ReferenceC','Ada')){$operations+=@{operation='file:'+$file;file=$file;target=$target;variant='constructs-branch-1';constructs_branch=1}}
        }
    }
}else{
    foreach($target in @('ReferenceC','Ada')){$operations+=@{operation=$entry.operation;file='';target=$target;variant='primary';constructs_branch=0}}
}
if($PlanOnly){
    @{context=$Context;partition=$Partition;observations=$operations;runtime_build_requested=$false;
        file_protocol_selection=$(if($DevelopmentObservation){'pending-author-proposal-for-diagnostics'}else{'explicit-reviewed-manifest-required'});
        runtime_acceptance=$false;coverage_authority=$false}|ConvertTo-Json -Depth 12
    exit 0
}
if($ImageDirectory -eq ''){throw 'A target partition requires its immutable context image'}
$revision=(& git -C $root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Cannot identify target partition revision'}
$dirty=@(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0){throw 'Target partition requires a clean checkout'}
$image=Restore-TargetContextImage -Root $root -ImageDirectory $ImageDirectory -Context $Context -Revision $revision
$policy=$null
if($ExecutionPolicy -ne ''){
    $full=if([IO.Path]::IsPathRooted($ExecutionPolicy)){$ExecutionPolicy}else{Join-Path $root $ExecutionPolicy}
    $relative=[IO.Path]::GetRelativePath($root,$full).Replace('\','/')
    $hash=(Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant()
    [void](Resolve-ReviewedFile -Root $root -Path $relative -Sha256 $hash)
    $policy=Get-Content -LiteralPath $full -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if($policy.schema_version -ne 1 -or $policy.kind -cne 'target-execution-selections' -or
        $policy.target -cne 'remaining-upstream-compatibility'){throw 'Invalid target execution selections'}
}
$parts=$Context.Split('/')
$hostPlatform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
if($parts[1] -cne $hostPlatform){throw 'Target partition context identifies another host'}
$directory=Join-Path $root ('reports/target-partitions/'+$entry.id+'/'+$Partition)
[void][IO.Directory]::CreateDirectory($directory)
$records=@();$nativeOriginal=@();$failures=@();$warningIdentity=$null
$variables=@('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH');$saved=@{}
foreach($name in $variables){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
$support=Join-Path $root $image.manifest.paths.compiler_support
foreach($name in $variables){[Environment]::SetEnvironmentVariable($name,$support+[IO.Path]::PathSeparator+$saved[$name])}
try{
    foreach($operation in $operations){
        $name=$operation.target+'-'+$operation.operation.Replace(':','-')+'-'+$operation.variant
        $report=Join-Path $directory ($name+'.json')
        $arguments=@{Target=$operation.target;Configuration=$parts[0];Context=$Context;
            Mode=$(if($entry.operation -ceq 'file'){'File'}else{$entry.operation});File=$operation.file;
            TargetPolicy='remaining-upstream-compatibility';Variant=$operation.variant;ConstructsBranch=$operation.constructs_branch;
            Report=$report;ReportOnly=$true;
            Interpreter=(Join-Path $root $(if($operation.target -ceq 'Ada'){$image.manifest.paths.ada_launcher}else{$image.manifest.paths.c_oracle}))}
        if($operation.target -ceq 'Ada'){
            $arguments.RuntimeDirectory=Join-Path $root $image.manifest.paths.ada_runtime
            $arguments.NativeLibraryDirectory=$arguments.RuntimeDirectory
        }
        if($null -ne $policy){
            $selected=@($policy.operations|Where-Object{
                $_.operation -ceq $operation.operation -and $_.target -ceq $operation.target -and
                $_.context -ceq $Context -and $_.variant -ceq $operation.variant})
            if($selected.Count -gt 1){throw 'Duplicate execution selection'}
            if($selected.Count -eq 1){
                foreach($field in @('EquivalentManifest','TAdaptationManifest','FileProtocolManifest','NativeApplicability')){
                    if($selected[0].Contains($field) -and $null -ne $selected[0][$field]){
                        $identity=$selected[0][$field]
                        $arguments[$field]=Resolve-ReviewedFile -Root $root -Path $identity.path -Sha256 $identity.sha256
                    }
                }
            }
        }elseif($operation.file -ceq 'gc.lua' -and $operation.target -ceq 'Ada'){
            $arguments.EquivalentManifest=Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/gc-ada-equivalence.json'
        }elseif($operation.file -ceq 'files.lua' -and $parts[1] -cin @('windows','macos')){
            $arguments.EquivalentManifest=Join-Path $root ('tests/conformance/equivalents/files-'+$parts[1]+'-platform.json')
        }
        if($operation.file -ne '' -and $null -ne (Get-TargetFileProtocolDefinition -File $operation.file)){
            if(-not $arguments.ContainsKey('FileProtocolManifest')){
                if(-not $DevelopmentObservation){throw 'Remaining primary requires an explicit independently reviewed FileProtocolManifest selection'}
                $arguments.FileProtocolManifest=Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/file-completion.author-proposal.json'
            }
            $null=Read-TargetFileProtocolManifest -Root $root -Path $arguments.FileProtocolManifest -RequireReview:(-not $DevelopmentObservation)
        }
        if($operation.target -ceq 'ReferenceC' -and $arguments.ContainsKey('EquivalentManifest')){
            $mapping=Get-Content -LiteralPath $arguments.EquivalentManifest -Raw|ConvertFrom-Json -AsHashtable -Depth 48
            if($mapping.disposition -ceq 'native-platform-equivalent'){
                # Preserve the exact original C observation separately, even
                # when its native assumption fails. It is applicability input
                # for a later independent source-linked review, never a passing
                # primary or a replacement for the transformed C/Ada pair.
                $baseline=$arguments.Clone()
                foreach($field in @('EquivalentManifest','TAdaptationManifest','NativeApplicability')){[void]$baseline.Remove($field)}
                $baseline.Variant='native-original'
                $baseline.Report=Join-Path $directory ('ReferenceC-'+$operation.operation.Replace(':','-')+'-native-original.json')
                & (Join-Path $PSScriptRoot 'run-conformance.ps1') @baseline
                $baselineExit=$LASTEXITCODE
                $baselineReport=Get-Content -LiteralPath $baseline.Report -Raw|ConvertFrom-Json -AsHashtable -Depth 48
                if($baselineReport.setup_error -or $null -eq $baselineReport.process -or
                    $baselineReport.process.timed_out -or $baselineReport.process.capture_exceeded -or
                    $baselineReport.process.pipe_drain_failed -or $baselineReport.process.process_tree_kill_error -or
                    $baselineReport.process.abnormal_exit_kind -or -not $baselineReport.configuration_verified){
                    $failures+='invalid-original-C-native-capture-'+$operation.operation
                }
                $nativeOriginal+=@{operation=$operation.operation;target='ReferenceC';variant='native-original';
                    report=$baseline.Report;sha256=(Get-FileHash -LiteralPath $baseline.Report).Hash.ToLowerInvariant();
                    source_mapping=@{path=[IO.Path]::GetRelativePath($root,$arguments.EquivalentManifest).Replace('\','/');
                        sha256=(Get-FileHash -LiteralPath $arguments.EquivalentManifest).Hash.ToLowerInvariant()};
                    status=$baselineReport.status;collector_exit_code=$baselineExit;runtime_acceptance=$false;coverage_authority=$false}
            }
        }
        & (Join-Path $PSScriptRoot 'run-conformance.ps1') @arguments
        $exitCode=$LASTEXITCODE
        $value=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        $records+=@{operation=$operation.operation;target=$operation.target;variant=$operation.variant;report=$report;
            sha256=(Get-FileHash -LiteralPath $report).Hash.ToLowerInvariant();status=$value.status;collector_exit_code=$exitCode;
            disposition=$value.execution_disposition;runtime_acceptance=$false}
        if($exitCode -ne 0 -or $value.setup_error -or $value.status -cnotin @('passed','completed-with-skips')){$failures+=$name}
    }
    if($Partition -ceq 'files-1'){
        try{
            & (Join-Path $PSScriptRoot 'test-scoped-warnings.ps1') -Interpreter (Join-Path $root $image.manifest.paths.ada_launcher) `
                -ReferenceInterpreter (Join-Path $root $image.manifest.paths.c_oracle) -RuntimeDirectory (Join-Path $root $image.manifest.paths.ada_runtime) `
                -Configuration $parts[0] -Scope expanded-t-conformance -Profile $parts[2] `
                -LibraryType $(if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]}) -OutputDirectory (Join-Path $directory 'warnings')
            if($LASTEXITCODE -ne 0){throw 'Warning protocol failed'}
            $warningPath=Join-Path $directory 'warnings/index.json'
            $warningIdentity=@{path=$warningPath;sha256=(Get-FileHash -LiteralPath $warningPath).Hash.ToLowerInvariant()}
        }catch{$failures+='warning-protocol';Write-Output $_.Exception.Message}
    }
}finally{
    $imageFailure=$null
    try{$null=Assert-TargetContextImage -ImageDirectory $ImageDirectory -Context $Context -Revision $revision -RequireActual -RestoredRoot $root}
    catch{$imageFailure=$_.Exception.Message;$failures+='immutable-context-image'}
    foreach($name in $variables){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
    $index=@{schema_version=1;kind='target-partition-observations';target='remaining-upstream-compatibility';
        context=$Context;partition=$Partition;revision=$revision;image=@{path=$image.manifest_path;sha256=$image.sha256};
        observations=$records;native_original_observations=$nativeOriginal;warning_observations=$warningIdentity;failures=$failures;image_failure=$imageFailure;
        completed=($records.Count -eq $operations.Count);runtime_build_requested=$false;runtime_acceptance=$false;coverage_authority=$false}
    [IO.File]::WriteAllText((Join-Path $directory 'index.json'),(ConvertTo-Json -InputObject $index -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
}
Write-Output "OBSERVED: $Context/$Partition $($records.Count) primary/supplement processes, $($nativeOriginal.Count) original C native baselines, $($failures.Count) campaign failures; runtime acceptance=False"
if($failures.Count -ne 0){exit 1}
exit 0
