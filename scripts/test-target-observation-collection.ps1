param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$temporary=Join-Path $root ('reports/target-collection-selftests/'+[Guid]::NewGuid().ToString('N'))
$artifacts=Join-Path $temporary 'artifacts';[void][IO.Directory]::CreateDirectory($artifacts)
$utf8=[Text.UTF8Encoding]::new($false);$plan=Get-TargetContextPlan -Root $root
$revision=(& git -C $root rev-parse HEAD).Trim();$script:Cases=0;$script:Serial=0
function Save([string]$Path,[object]$Value){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 32).Replace("`r`n","`n")+"`n",$utf8);return (Get-FileHash $Path).Hash.ToLowerInvariant()}
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "TARGET COLLECTION TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
# All image flags, raw reports and observations below are deliberate transport
# counterfeits, not executed evidence. The fixture omits executable/ABI/build
# witness semantics on purpose. Collection must keep every acceptance/review
# gate false/pending; the final verifier cannot accept these records.
foreach($context in $plan.contexts){
    $directory=Join-Path $artifacts ('target-image-'+$context.id);$files=@()
    $ada='tests/bin/'+$context.library_type+'/host';$oracle='build/conformance/'+$context.configuration+'/bin/lua'
    $adaRuntime='lib/'+$context.profile+'/'+$context.library_type;$cRuntime='build/conformance/'+$context.configuration+'/lib'
    foreach($path in @($ada,$oracle,($adaRuntime+'/liblua.a'),($cRuntime+'/libconformance_lua.a'))){
        $full=Join-Path $directory ('payload/'+$path);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
        [IO.File]::WriteAllText($full,'counterfeit transport bytes',$utf8)
        $files+=@{path=$path;bytes=(Get-Item $full).Length;sha256=(Get-FileHash $full).Hash.ToLowerInvariant();
            unix_mode=$(if($IsWindows){0}else{[int][IO.File]::GetUnixFileMode($full)})}
    }
    $consumer='reports/core-image/c-'+$context.id+'/result.json';$unit='reports/core-image/a-'+$context.id+'/result.json'
    $cHash=Save (Join-Path $directory ('payload/'+$consumer)) @{deliberate_nonexecution_fixture=$true}
    $aHash=Save (Join-Path $directory ('payload/'+$unit)) @{deliberate_nonexecution_fixture=$true}
    $receipt=@{context=$context.context;revision=$revision;consumer=@{path=('/original/'+$consumer);sha256=$cHash};
        aunit=@{path=('/original/'+$unit);sha256=$aHash};witness_policy=@{path='fixture-policy.json';sha256=('1'*64)}}
    $null=Save (Join-Path $directory ('payload/reports/target-builds/'+$context.id+'/witnesses.json')) $receipt
    $image=@{schema_version=1;kind='immutable-target-context-image';target=$plan.target;context=$context.context;revision=$revision;
        reference_revision=$plan.reference_revision;repository_dirty=$false;synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
        launcher_basename=$(if($context.platform -ceq 'windows'){'lua.exe'}else{'lua'});files=$files;build_witnesses=@();
        paths=@{ada_launcher=$ada;c_oracle=$oracle;ada_runtime=$adaRuntime;c_runtime=$cRuntime}}
    $null=Save (Join-Path $directory 'image.json') $image
}
foreach($partition in $plan.partitions){
    $directory=Join-Path $artifacts ('target-observations-'+$partition.id+'-'+$partition.partition)
    $imagePath=Join-Path $artifacts ('target-image-'+$partition.id+'/image.json')
    $observations=@();$names=if($partition.operation -ceq 'file'){@($partition.files|ForEach-Object{'file:'+$_})}else{@($partition.operation)}
    foreach($operation in $names){
        $variants=if($operation -ceq 'file:constructs.lua'){@('primary','constructs-branch-1')}else{@('primary')}
        foreach($variant in $variants){foreach($target in @('Ada','ReferenceC')){
            $relative='reports/target-partitions/'+$partition.id+'/'+$partition.partition+'/'+$target+'-'+$operation.Replace(':','-')+'-'+$variant+'.json'
            $hash=Save (Join-Path $directory $relative) @{deliberate_nonexecution_fixture=$true;runtime_acceptance=$false}
            $observations+=@{operation=$operation;variant=$variant;target=$target;report=('/original/'+$relative);sha256=$hash}
        }}
    }
    $warning=$null
    if($partition.partition -ceq 'files-1'){
        $relative='reports/target-partitions/'+$partition.id+'/'+$partition.partition+'/warnings/index.json'
        $hash=Save (Join-Path $directory $relative) @{deliberate_nonexecution_fixture=$true}
        $warning=@{path=('/original/'+$relative);sha256=$hash}
    }
    $nativeOriginal=@()
    $platform=$partition.context.Split('/')[1]
    if('files.lua' -cin $partition.files -and $platform -cin @('windows','macos')){
        $relative='reports/target-partitions/'+$partition.id+'/'+$partition.partition+'/ReferenceC-file-files.lua-native-original.json'
        $hash=Save (Join-Path $directory $relative) @{deliberate_nonexecution_fixture=$true;runtime_acceptance=$false;status='failed'}
        $mapping='tests/conformance/equivalents/files-'+$platform+'-platform.json'
        $nativeOriginal+=@{operation='file:files.lua';variant='native-original';target='ReferenceC';report=('/original/'+$relative);sha256=$hash;
            source_mapping=@{path=$mapping;sha256=(Get-FileHash (Join-Path $root $mapping)).Hash.ToLowerInvariant()}}
    }
    $index=@{revision=$revision;context=$partition.context;partition=$partition.partition;runtime_acceptance=$false;coverage_authority=$false;
        native_original_observations=$nativeOriginal;
        completed=$true;failures=@();observations=$observations;warning_observations=$warning;image=@{sha256=(Get-FileHash $imagePath).Hash.ToLowerInvariant()}}
    $null=Save (Join-Path $directory ('reports/target-partitions/'+$partition.id+'/'+$partition.partition+'/index.json')) $index
}
function Collect{
    $script:Serial++;$output=Join-Path $temporary "bundle-$script:Serial"
    $p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Directory $root `
        -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'collect-target-observations.ps1'),'-ArtifactDirectory',$artifacts,'-OutputDirectory',$output) `
        -OutputPrefix (Join-Path $temporary "collector-$script:Serial") -TimeoutSeconds 120
    return @{process=$p;output=$output}
}
Case 'all synthetic transport rows assemble without acquiring acceptance or semantic expectations'{
    $r=Collect;Assert-True ($r.process.exit_code -eq 0) ([IO.File]::ReadAllText($r.process.stderr_path))
    $index=Get-Content (Join-Path $r.output 'observation-index.json') -Raw|ConvertFrom-Json -AsHashtable
    $matrix=Get-Content (Join-Path $r.output 'matrix.author-proposal.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    Assert-True ($index.context_images -eq 26 -and $index.primary_pairs -eq 832 -and $index.supplemental_pairs -eq 26 -and
        $index.warning_contexts -eq 26 -and -not $index.runtime_acceptance -and -not $index.coverage_authority -and
        $matrix.review.status -ceq 'pending') 'Collector promoted incomplete fixture semantics'
    $contract=Get-Content (Join-Path $r.output $matrix.operations[0].contract.path) -Raw|ConvertFrom-Json -AsHashtable
    Assert-True ($contract.stdout_required.Count -eq 0 -and $null -eq $contract.review.reviewer) 'Collector inferred a passing stdout protocol'
    $retained=Get-Content (Join-Path $r.output 'retained-evidence.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    Assert-True ($index.native_original_observations -gt 0 -and $retained.native_original_observations.Count -eq $index.native_original_observations -and
        @($retained.native_original_observations|Where-Object{ $_.runtime_acceptance -or $_.coverage_authority }).Count -eq 0) 'Native baseline was lost or counted as passing target evidence'
}
Case 'original C baseline transport requires its original bytes and cannot duplicate a context operation'{
    $p=@($plan.partitions|Where-Object{'files.lua' -cin $_.files -and $_.context.Split('/')[1] -ceq 'windows'})[0]
    $path=Join-Path $artifacts ('target-observations-'+$p.id+'-'+$p.partition+'/reports/target-partitions/'+$p.id+'/'+$p.partition+'/index.json')
    $value=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -Depth 32;$original=[IO.File]::ReadAllText($path)
    $value.native_original_observations[0].sha256='0'*64;$null=Save $path $value
    $r=Collect;Assert-True ($r.process.exit_code -ne 0 -and [IO.File]::ReadAllText($r.process.stderr_path) -match 'Original C applicability report bytes differ') 'Changed original C baseline bytes were accepted'
    [IO.File]::WriteAllText($path,$original,$utf8);$value=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -Depth 32
    $value.native_original_observations+=@($value.native_original_observations[0]);$null=Save $path $value
    $r=Collect;Assert-True ($r.process.exit_code -ne 0 -and [IO.File]::ReadAllText($r.process.stderr_path) -match 'duplicate original C applicability') 'Duplicated original baseline was accepted'
    [IO.File]::WriteAllText($path,$original,$utf8)
}
Case 'duplicate raw implementation observations cannot replace an absent counterpart'{
    $p=$plan.partitions[0];$path=Join-Path $artifacts ('target-observations-'+$p.id+'-'+$p.partition+'/reports/target-partitions/'+$p.id+'/'+$p.partition+'/index.json')
    $value=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -Depth 32;$value.observations[1]=$value.observations[0];$null=Save $path $value
    $r=Collect;Assert-True ($r.process.exit_code -ne 0 -and [IO.File]::ReadAllText($r.process.stderr_path) -match 'Duplicate physical') 'Duplicate observation hid a target'
}
Write-Output "PASS: $script:Cases observation transport regressions; counterfeit byte fixtures only, no compiled/runtime/conformance acceptance"
