param([Parameter(Mandatory)][string] $ArtifactDirectory,[Parameter(Mandatory)][string] $OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
$plan=Get-TargetContextPlan -Root $root
$revision=(& git -C $root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Cannot identify observation bundle revision'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Observation bundle output must be new'}
[void][IO.Directory]::CreateDirectory($output)
$utf8=[Text.UTF8Encoding]::new($false)
$suite=Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 32
function Save([string]$Path,[object]$Value){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n")+"`n",$utf8);return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function Rebase([string]$ArtifactRoot,[string]$Original){
    $normalized=$Original.Replace('\','/');$offset=$normalized.LastIndexOf('/reports/',[StringComparison]::Ordinal)
    if($offset -lt 0){throw 'Observation artifact is outside reports'}
    return Resolve-TargetImagePath -Root $ArtifactRoot -Relative $normalized.Substring($offset+1)
}
$images=@();$pairs=@{};$warnings=@();$namedC=@();$namedUnit=@();$compiled=@();$nativeOriginal=@();$nativeKeys=@{};$policies=@{};$failures=@()
foreach($context in $plan.contexts){
    $source=Join-Path $ArtifactDirectory ('target-image-'+$context.id)
    $image=Assert-TargetContextImage -ImageDirectory $source -Context $context.context -Revision $revision -RequireActual
    $relative='images/'+$context.id;$destination=Join-Path $output $relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath $source -Destination $destination -Recurse
    $images+=@{context=$context.context;path=$relative+'/image.json';sha256=$image.sha256;image_directory=$relative}
    $receiptPath=Join-Path $destination ('payload/reports/target-builds/'+$context.id+'/witnesses.json')
    $receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $policies[$receipt.witness_policy.path+'#'+$receipt.witness_policy.sha256]=$receipt.witness_policy
    foreach($kind in @('consumer','aunit')){
        $actual=Rebase (Join-Path $destination 'payload') $receipt[$kind].path
        if((Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $receipt[$kind].sha256){throw 'Build named report differs from frozen receipt'}
        $record=@{context=$context.context;report=[IO.Path]::GetRelativePath($output,$actual).Replace('\','/');
            sha256=$receipt[$kind].sha256;artifact_root=$relative+'/payload'}
        if($kind -ceq 'consumer'){$namedC+=$record}else{$namedUnit+=$record}
    }
    $compiledPath=Join-Path $destination ('payload/reports/target-builds/'+$context.id+'/compiled/observations.json')
    if(Test-Path -LiteralPath $compiledPath){$compiled+=@{context=$context.context;report=[IO.Path]::GetRelativePath($output,$compiledPath).Replace('\','/');
        sha256=(Get-FileHash -LiteralPath $compiledPath).Hash.ToLowerInvariant();artifact_root=$relative+'/payload'}}
}
foreach($partition in $plan.partitions){
    $source=Join-Path $ArtifactDirectory ('target-observations-'+$partition.id+'-'+$partition.partition)
    $relative='artifacts/'+$partition.id+'/'+$partition.partition;$destination=Join-Path $output $relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath $source -Destination $destination -Recurse
    $indexPath=Join-Path $destination ('reports/target-partitions/'+$partition.id+'/'+$partition.partition+'/index.json')
    $index=Get-Content -LiteralPath $indexPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if($index.revision -cne $revision -or $index.context -cne $partition.context -or $index.partition -cne $partition.partition -or
        $index.runtime_acceptance -ne $false -or $index.coverage_authority -ne $false -or -not $index.completed){throw 'Incomplete or mislabeled target observation partition'}
    if(@($index.failures).Count -ne 0){$failures+=@($index.failures|ForEach-Object{$partition.context+'/'+$_})}
    $image=@($images|Where-Object context -CEQ $partition.context)[0]
    if($index.image.sha256 -cne $image.sha256){throw 'Partitions did not consume their one frozen context image'}
    if($index.Contains('native_original_observations')){foreach($observation in $index.native_original_observations){
        $key=$partition.context+'/'+$observation.operation
        if($observation.target -cne 'ReferenceC' -or $observation.variant -cne 'native-original' -or $nativeKeys.ContainsKey($key)){
            throw 'Invalid or duplicate original C applicability observation'
        }
        $nativeKeys[$key]=$true
        $actual=Rebase $destination $observation.report
        if((Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $observation.sha256){throw 'Original C applicability report bytes differ'}
        $nativeOriginal+=@{context=$partition.context;operation=$observation.operation;target='ReferenceC';variant='native-original';
            report=[IO.Path]::GetRelativePath($output,$actual).Replace('\','/');sha256=$observation.sha256;artifact_root=$relative;
            source_mapping=$observation.source_mapping;runtime_acceptance=$false;coverage_authority=$false}
    }}
    foreach($observation in $index.observations){
        $key=$partition.context+'/'+$observation.operation+'/'+$observation.variant
        if(-not $pairs.ContainsKey($key)){$pairs[$key]=@{context=$partition.context;operation=$observation.operation;
            variant=$observation.variant;comparison='reviewed-semantic'}}
        $target=if($observation.target -ceq 'Ada'){'ada'}elseif($observation.target -ceq 'ReferenceC'){'c'}else{throw 'Unknown observation target'}
        if($pairs[$key].ContainsKey($target)){throw 'Duplicate physical target observation'}
        $actual=Rebase $destination $observation.report
        if((Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $observation.sha256){throw 'Physical raw report bytes differ from partition index'}
        $pairs[$key][$target]=@{report=[IO.Path]::GetRelativePath($output,$actual).Replace('\','/');sha256=$observation.sha256;artifact_root=$relative}
    }
    if($null -ne $index.warning_observations){
        $actual=Rebase $destination $index.warning_observations.path
        if((Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $index.warning_observations.sha256){throw 'Warning index bytes differ'}
        $warnings+=@{context=$partition.context;report=[IO.Path]::GetRelativePath($output,$actual).Replace('\','/');
            sha256=$index.warning_observations.sha256;artifact_root=$relative}
    }
}
$operations=@();$supplements=@();$retainedOperations=@()
foreach($pair in $pairs.Values|Sort-Object context,operation,variant){
    if(-not $pair.ContainsKey('c') -or -not $pair.ContainsKey('ada')){throw 'Observation bundle lost one side of a C/Ada pair'}
    $sourceName=if($pair.operation.StartsWith('file:',[StringComparison]::Ordinal)){$pair.operation.Substring(5)}elseif($pair.operation -ceq 'aggregate'){'all.lua'}else{'heavy.lua'}
    $source=@($suite.files|Where-Object path -CEQ $sourceName)[0]
    $sourceHashes=@{$sourceName=$source.sha256}
    if($pair.operation -ceq 'aggregate'){$sourceHashes=@{};foreach($item in $suite.files){$sourceHashes[$item.path]=$item.sha256}}
    $contractPath='contracts/'+$pair.context.Replace('/','-')+'/'+$pair.operation.Replace(':','-')+'-'+$pair.variant+'.author-proposal.json'
    $contract=@{schema_version=1;operation=$pair.operation;context=$pair.context;reference_revision=$plan.reference_revision;
        source_hashes=$sourceHashes;completion_marker='';stdout_required=@();stderr_expected=@();expected_skips=@();
        review=@{author='Codex /root/validation_delivery';reviewer=$null;artifact=$null;artifact_sha256=$null;
            rationale='Pending source semantic protocol and exact observed interpretation review; never infer expectations from successful output.';
            original_c_evidence=$pair.c.report};runtime_acceptance=$false;coverage_authority=$false}
    if($pair.operation -ceq 'aggregate'){
        # These are only byte identities from the raw observation. Semantic
        # completion/warning/return expectations remain empty until review.
        # C and Ada can select different independently reviewed source sets.
        $contract.aggregate_replays=@{}
        foreach($target in @('ada','c')){
            $raw=Get-Content -LiteralPath (Join-Path $output $pair[$target].report) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
            if($raw.Contains('aggregate_replay') -and $null -ne $raw.aggregate_replay){
                $implementation=if($target -ceq 'ada'){'Ada'}else{'ReferenceC'}
                $contract.aggregate_replays[$implementation]=@{manifest_sha256=$raw.aggregate_replay.manifest_sha256;
                    selection_sha256=$raw.aggregate_replay.selection_sha256;
                    executed_sources_sha256=(Get-TargetWitnessPayloadHash @{sources=$raw.aggregate_replay.expected_sources});
                    setup_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($raw.process.arguments[1]))).ToLowerInvariant();
                    disposition='reviewed-aggregate-replay'}
            }
        }
    }
    $contractHash=Save (Join-Path $output $contractPath) $contract
    $pair.contract=@{path=$contractPath;sha256=$contractHash}
    if($pair.variant -ceq 'primary'){
        [void]$pair.Remove('variant');$operations+=$pair
        if($pair.operation -ceq 'file:events.lua'){$retainedOperations+=@{context=$pair.context;file='events.lua';c=$pair.c;ada=$pair.ada}}
    }else{$supplements+=$pair}
}
if($operations.Count -ne 832 -or $supplements.Count -ne 26 -or $warnings.Count -ne 26){throw 'Observation collection lacks all primaries Aggregate Heavy constructs variants or warning contexts'}
$retained=@{scope='expanded-t-conformance';revision=$revision;operations=$retainedOperations;warning_regressions=$warnings;
    named_consumers=$namedC;named_aunit=$namedUnit;compiled_observations=$compiled;
    native_original_observations=$nativeOriginal;
    witness_policy=$(if($policies.Count -eq 1){@($policies.Values)[0]}else{$null});
    diagnostic_witness_policies=@($policies.Values);runtime_acceptance=$false;coverage_authority=$false}
$retainedHash=Save (Join-Path $output 'retained-evidence.json') $retained
$policy='tests/conformance/targets/remaining-upstream-compatibility.exclusions.json'
$matrix=@{schema_version=1;kind='full-target-matrix';target=$plan.target;revision=$revision;reference_revision=$plan.reference_revision;
    synthetic_fixture=$false;operations=$operations;supplemental=$supplements;context_images=$images;
    retained_evidence=@{path='retained-evidence.json';sha256=$retainedHash};exclusion_policy=@{path=$policy;sha256=(Get-FileHash (Join-Path $root $policy)).Hash.ToLowerInvariant()};
    review=@{status='pending';author='Codex /root/validation_delivery';reviewer=$null;artifact=$null;artifact_sha256=$null}}
$matrixHash=Save (Join-Path $output 'matrix.author-proposal.json') $matrix
$summary=@{schema_version=1;kind='target-observation-bundle';revision=$revision;context_images=$images.Count;
    primary_pairs=$operations.Count;supplemental_pairs=$supplements.Count;warning_contexts=$warnings.Count;
    native_original_observations=$nativeOriginal.Count;
    failures=$failures;matrix=@{path='matrix.author-proposal.json';sha256=$matrixHash};runtime_acceptance=$false;coverage_authority=$false}
$null=Save (Join-Path $output 'observation-index.json') $summary
Write-Output "COLLECTED: $($images.Count) images, $($operations.Count) primary pairs, $($supplements.Count) supplements, $($nativeOriginal.Count) original C native baselines; independent protocol/envelope/global review pending; acceptance=False"
if($failures.Count -ne 0){exit 1}
exit 0
