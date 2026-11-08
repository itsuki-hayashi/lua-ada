Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceExclusionEligibility.psm1') -Force
$base='tests/conformance/targets/remaining-upstream-compatibility'
$temporary=Join-Path $root ('reports/resource-v4-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$bytes=[IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/memerr.lua'))
$row=@(Get-ConformanceResourceRegistry)[0]
$original=@(Get-ConformanceCoverageUnits -Path memerr.lua -Bytes $bytes)
$scopes=(Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') -Raw|ConvertFrom-Json -AsHashtable).protected_scopes
$featurePaths=@(& (Get-Module ConformanceInventory) {Get-ConformanceResourceFeatureSources})
$witnessPaths=@('tests/lua/materialized_vararg.lua','tests/lua/materialized_vararg_refusal.lua',
    'tests/src/lua-materialized_vararg_tests.ads','tests/src/lua-materialized_vararg_tests.adb')
foreach($path in (@('references/lua/testes/memerr.lua')+$featurePaths+$witnessPaths+@($scopes.path)|Select-Object -Unique)){
    $target=Join-Path $temporary $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    Copy-Item -LiteralPath (Join-Path $root $path) -Destination $target
}
$script:cases=0
function Clone($value){return ConvertTo-Json -InputObject $value -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48}
function Save($path,$value){
    $file=Join-Path $temporary $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
    $json=(ConvertTo-Json -InputObject $value -Depth 48).Replace([string][char]13,'')+[char]10
    [IO.File]::WriteAllText($file,$json,[Text.UTF8Encoding]::new($false))
    return (Get-FileHash $file).Hash.ToLowerInvariant()
}
function Sources($paths){@($paths|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $temporary $_)).Hash.ToLowerInvariant()}})}
function Bind($f){
    $e=$f.exclusion
    $e.feature_review.sha256=Save $e.feature_review.path $f.feature
    $e.semantic_retention_review.sha256=Save $e.semantic_retention_review.path $f.retention
    $narrativeHash=Save ($f.prefix+'-narrative.json') $f.narrative
    $semantic=[ordered]@{};foreach($key in (Get-ConformanceExclusionSemanticFields $e)){$semantic[$key]=$e[$key]}
    $approval=@{schema_version=4;kind='t-exclusion-approval';target='remaining-upstream-compatibility';
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';protected_scopes=$scopes;
        author=$e.review.author;reviewer=$e.review.reviewer;decision='accepted';exclusion=$semantic;
        runtime_acceptance=$false;coverage_authority=$false;source_adaptation_authority=$false;
        execution_evidence=@();source_exclusions=@();synthetic_fixture=$true;
        review_evidence=@{path=($f.prefix+'-narrative.json');sha256=$narrativeHash}}
    $e.review.artifact_sha256=Save $e.review.artifact $approval
}
function Fixture {
    # These reviews are disposable, explicitly synthetic test input. Only the
    # direct verifier call below enables them; actual inventory/runner callers
    # never do. No target policy, real approval or coverage file is changed.
    $prefix=$base+'/reviews/v4-'+[guid]::NewGuid().ToString('N')
    $e=@{id=$row.id;source=$row.source;source_sha256=$row.source_sha256;
        byte_offset=$row.byte_offset;byte_length=$row.byte_length;anchor_sha256=$row.anchor_sha256;
        status='excluded';disposition='reviewed-t-internal-exclusion';configurations=@('upstream-test');
        eligibility='t-only-private-invariant';eligibility_schema_version=4;public_api=$false;mixed_obligation=$false;
        module_observable=$true;module_compatibility_obligation=$false;observation_kind='private-resource-geometry';
        structure_kind=$row.structure_kind;required_semantic_contract_ids=@($row.required_semantic_contract_ids);
        original_anchor_links=@((Clone $row.original_anchor));retained_materialization=(Clone $row.retained_materialization);
        invariant='synthetic exact-count binding input, never actual source authority';
        third_party_irrelevance='synthetic independent relevance input';evidence=@();t_guard=(Clone $row.t_guard);
        feature_review=@{path=($prefix+'-feature.json');sha256=$null};semantic_retention_review=@{path=($prefix+'-retention.json');sha256=$null};
        review=@{status='accepted';author='synthetic-resource-author';reviewer='synthetic-independent-reviewer';
            artifact=($prefix+'-approval.json');artifact_sha256=$null}}
    $common=@{schema_version=4;reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        author=$e.review.author;reviewer=$e.review.reviewer;source=@{path='references/lua/testes/memerr.lua';sha256=$row.source_sha256};
        candidate=@{id=$row.id;byte_offset=$row.byte_offset;byte_length=$row.byte_length;anchor_sha256=$row.anchor_sha256};
        runtime_acceptance=$false;coverage_authority=$false;source_adaptation_authority=$false;
        execution_evidence=@();source_exclusions=@();synthetic_fixture=$true}
    $feature=Clone $common;$feature.kind='t-private-resource-feature-review';$feature.decision='accepted-feature-only-with-required-counterparts'
    $feature.configuration='upstream-test';$feature.public_api=$false;$feature.mixed_obligation=$false;$feature.module_observable=$true;$feature.module_compatibility_obligation=$false
    $feature.no_public_positive_allocation_guarantee=$true;$feature.rationale='synthetic fixture does not establish a real relevance review'
    $feature.source_bindings=Sources $featurePaths
    $retention=Clone $common;$retention.kind='t-private-resource-semantic-retention-review';$retention.decision='accepted-source-retention-contract-only'
    $retention.required_semantic_contract_ids=@($row.required_semantic_contract_ids)
    $retention.actual_provider_refusal_required=$true;$retention.T_absence_is_failure=$true;$retention.positive_allocation_count_is_not_asserted=$true
    $retention.retained_materialization=Clone $row.retained_materialization;$retention.protected_optimized=Clone $row.protected_optimized
    $retention.witness_sources=Sources $witnessPaths
    $narrative=Clone $common;$narrative.kind='t-private-resource-exclusion-review';$narrative.exclusion_id=$row.id;$narrative.decision='accepted'
    $narrative.t_dominance='synthetic pinned guard';$narrative.private_invariant='synthetic exact resource comparison';$narrative.third_party_irrelevance='synthetic retained public contract'
    $record=@{id=$row.id;kind='reviewed-block';byte_offset=$row.byte_offset;byte_length=$row.byte_length;anchor_sha256=$row.anchor_sha256;
        status='pending';disposition='pending';evidence=@()}
    $public=Clone $row.retained_materialization;$public.kind='reviewed-block';$public.status='pending';$public.disposition='pending';$public.evidence=@()
    $records=@{};foreach($anchor in $original){$records[$anchor.id]=Clone $anchor};$records[$row.id]=$record;$records[$public.id]=$public
    $f=@{prefix=$prefix;exclusion=$e;record=$record;feature=$feature;retention=$retention;narrative=$narrative;records=$records}
    Bind $f;return $f
}
function Validate($f,[switch]$Actual){
    Test-ConformanceTargetExclusion -Root $temporary -Source memerr.lua -SourceBytes $bytes -Record $f.record -Exclusion $f.exclusion -AllowSyntheticReview:(-not $Actual)
}
function Parents($f,$excluded=$null){
    if($null -eq $excluded){$excluded=@{};$excluded[$f.exclusion.id]=$f.exclusion}
    & (Get-Module ConformanceInventory) {param($b,$f,$x)
        Assert-ConformanceResourceParentRecords -Bytes $b -Exclusion $f.exclusion -Records $f.records -Exclusions $x
    } $bytes $f $excluded
}
function Reject([scriptblock]$action,$expected){$failure=$null;try{&$action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $expected){throw "Wrong V4 rejection: $failure; expected $expected"}}
function Case($name,[scriptblock]$action){&$action;$script:cases++;Write-Output "RESOURCE V4 BINDING PASS: $name"}
Case 'one exact closed row retains pending original and real workload' {$f=Fixture;$r=Validate $f;Parents $f
    if(@(Get-ConformanceResourceRegistry).Count -ne 1 -or $r.evidence.Count -or $f.records[$row.original_anchor.id].status -cne 'pending'){throw 'fixture acquired runtime authority'}}
Case 'synthetic source input cannot authorize the actual target' {$f=Fixture;Reject {Validate $f -Actual} 'synthetic review'}
foreach($flag in @('public_api','mixed_obligation','module_compatibility_obligation')){Case "$flag cannot be waived" {$f=Fixture;$f.exclusion[$flag]=$true;Reject {Validate $f} 'without public or mixed'}}
Case 'observable cost cannot masquerade as invisible' {$f=Fixture;$f.exclusion.module_observable=$false;Reject {Validate $f} 'without public or mixed'}
Case 'string false is not a compatibility boolean' {$f=Fixture;$f.exclusion.module_compatibility_obligation='false';Reject {Validate $f} 'without public or mixed'}
Case 'a second resource or querystr row cannot be added by data' {$f=Fixture;$f.exclusion.id='LUA-API-REVIEWED-BLOCK-9001';$f.record.id=$f.exclusion.id;Reject {Validate $f} 'source|anchor|public or mixed'}
Case 'a shifted comparison rejects' {$f=Fixture;$f.exclusion.byte_offset++;$f.record.byte_offset++;$hash=Get-ConformanceHash $bytes[$f.record.byte_offset..($f.record.byte_offset+$f.record.byte_length-1)];$f.record.anchor_sha256=$hash;$f.exclusion.anchor_sha256=$hash;Bind $f;Reject {Validate $f} 'public or mixed'}
Case 'whole mixed block cannot replace the private comparison' {$f=Fixture;$f.exclusion.byte_offset=3382;$f.record.byte_offset=3382;$f.exclusion.byte_length=480;$f.record.byte_length=480;$hash=Get-ConformanceHash $bytes[3382..3861];$f.record.anchor_sha256=$hash;$f.exclusion.anchor_sha256=$hash;Bind $f;Reject {Validate $f} 'public or mixed'}
Case 'wrong source digest rejects' {$f=Fixture;$f.exclusion.source_sha256='0'*64;Reject {Validate $f} 'source or disposition'}
Case 'exact counts cannot be relabelled public behavior' {$f=Fixture;$f.exclusion.structure_kind='public-materialization';Reject {Validate $f} 'without public or mixed'}
Case 'derived block cannot be the original six-byte assertion anchor' {$f=Fixture;$f.record.kind='assert-call';Reject {Validate $f} 'exact derived comparison'}
Case 'ordinary default applicability cannot borrow T approval' {$f=Fixture;$f.exclusion.configurations=@('default');Reject {Validate $f} 'T-only private invariant'}
Case 'legacy v1 cannot hide this known observable comparison' {$f=Fixture;[void]$f.exclusion.Remove('eligibility_schema_version');$f.exclusion.module_observable=$false;Reject {Validate $f} 'requires V4'}
Case 'v2 conjunct eligibility cannot cover the whole assertion' {$f=Fixture;$f.exclusion.eligibility_schema_version=2;$f.exclusion.retained_parent=Clone $row.retained_materialization;Reject {Validate $f} 'without public or mixed|requires V4'}
Case 'v3 optimizer registry cannot lend resource authority' {$f=Fixture;$f.exclusion.eligibility_schema_version=3;Reject {Validate $f} 'without public or mixed'}
Case 'source numbers must be actual integers' {$f=Fixture;$f.exclusion.byte_offset=[string]$row.byte_offset;Reject {Validate $f} 'without public or mixed'}
Case 'nested original identities also require actual integers' {$f=Fixture;$f.exclusion.original_anchor_links[0].byte_offset=[string]$row.byte_offset;Reject {Validate $f} 'without public or mixed'}
Case 'original identity cannot be dropped' {$f=Fixture;$f.exclusion.original_anchor_links=@();Reject {Validate $f} 'without public or mixed'}
Case 'materialization source child cannot be broadened' {$f=Fixture;$f.exclusion.retained_materialization.byte_length++;Reject {Validate $f} 'without public or mixed'}
Case 'required public and T fault contracts cannot disappear' {$f=Fixture;$f.exclusion.required_semantic_contract_ids=@('Payload_Types');Reject {Validate $f} 'without public or mixed'}
Case 'the T guard cannot move' {$f=Fixture;$f.exclusion.t_guard.byte_offset++;Reject {Validate $f} 'exact pinned top-level T guard'}
foreach($flag in @('runtime_acceptance','coverage_authority','source_adaptation_authority')){Case "review cannot grant $flag" {$f=Fixture;$f.feature[$flag]=$true;Bind $f;Reject {Validate $f} 'cannot grant'}}
Case 'review cannot invent passing evidence' {$f=Fixture;$f.retention.execution_evidence=@('pretend-pass');Bind $f;Reject {Validate $f} 'cannot invent'}
Case 'review cannot introduce another source waiver' {$f=Fixture;$f.feature.source_exclusions=@('querystr');Bind $f;Reject {Validate $f} 'another source waiver'}
Case 'self review is rejected' {$f=Fixture;$f.feature.reviewer=$f.feature.author;Bind $f;Reject {Validate $f} 'independence'}
Case 'candidate review cannot widen the source span' {$f=Fixture;$f.feature.candidate.byte_length++;Bind $f;Reject {Validate $f} 'widened or changed'}
Case 'feature cannot claim a public positive allocation guarantee' {$f=Fixture;$f.feature.no_public_positive_allocation_guarantee=$false;Bind $f;Reject {Validate $f} 'public allocation behavior'}
Case 'missing actual provider contract rejects' {$f=Fixture;$f.retention.actual_provider_refusal_required=$false;Bind $f;Reject {Validate $f} 'retention contracts'}
Case 'T absence cannot become a passing counterpart' {$f=Fixture;$f.retention.T_absence_is_failure=$false;Bind $f;Reject {Validate $f} 'retention contracts'}
Case 'a fixed positive count cannot become the retained oracle' {$f=Fixture;$f.retention.positive_allocation_count_is_not_asserted=$false;Bind $f;Reject {Validate $f} 'retention contracts'}
Case 'optimized zero-allocation bytes cannot be revised' {$f=Fixture;$f.retention.protected_optimized.byte_length--;Bind $f;Reject {Validate $f} 'optimized result32'}
Case 'counterpart binding set cannot omit the T body' {$f=Fixture;$f.retention.witness_sources=@($f.retention.witness_sources|Where-Object path -CNE 'tests/lua/materialized_vararg_refusal.lua');Bind $f;Reject {Validate $f} 'source binding set'}
Case 'current implementation binding cannot be omitted' {$f=Fixture;$f.feature.source_bindings=@($f.feature.source_bindings|Select-Object -Skip 1);Bind $f;Reject {Validate $f} 'source binding set'}
Case 'stale counterpart digest rejects' {$f=Fixture;$f.retention.witness_sources[0].sha256='0'*64;Bind $f;Reject {Validate $f} 'Review file hash differs'}
Case 'stale verifier digest rejects' {$f=Fixture;$binding=@($f.feature.source_bindings|Where-Object path -CEQ 'scripts/ConformanceInventory.psm1')[0];$binding.sha256='0'*64;Bind $f;Reject {Validate $f} 'Review file hash differs'}
Case 'original anchor cannot disappear' {$f=Fixture;[void]$f.records.Remove($row.original_anchor.id);Reject {Parents $f} 'must remain'}
Case 'original six-byte source identity cannot change' {$f=Fixture;$f.records[$row.original_anchor.id].byte_length=19;Reject {Parents $f} 'identity changed'}
Case 'actual materialization child cannot disappear' {$f=Fixture;[void]$f.records.Remove($row.retained_materialization.id);Reject {Parents $f} 'must remain'}
Case 'public child cannot itself be excluded' {$f=Fixture;$x=@{};$x[$row.id]=$f.exclusion;$x[$row.retained_materialization.id]=@{source='memerr.lua'};Reject {Parents $f $x} 'must remain'}
Case 'previously passing original cannot become private' {$f=Fixture;$f.records[$row.original_anchor.id].status='passed';Reject {Parents $f} 'previously passing'}
Case 'reviewed original must link its required runtime child' {$f=Fixture;$a=$f.records[$row.original_anchor.id];$a.status='reviewed';$a.classification='reference';$a.obligations=@($row.id);Reject {Parents $f} 'public-runtime child linkage'}
Case 'reviewed original can link both children without becoming a pass' {$f=Fixture;$a=$f.records[$row.original_anchor.id];$a.status='reviewed';$a.classification='reference';$a.obligations=@($row.id,$row.retained_materialization.id);Parents $f}
Case 'optimized original cannot disappear' {$f=Fixture;$anchor=@($original|Where-Object{$_.byte_offset -ge 3604 -and $_.byte_offset+$_.byte_length -le 3858})[0];[void]$f.records.Remove($anchor.id);Reject {Parents $f} 'optimized public obligations'}
Case 'another legacy row cannot exclude the retained optimized block' {$f=Fixture;$x=@{};$x[$row.id]=$f.exclusion;$x.extra=@{source='memerr.lua';byte_offset=3604;byte_length=254};Reject {Parents $f $x} 'cannot be excluded'}
Case 'unsupported versions cannot borrow this registry' {$f=Fixture;$f.exclusion.eligibility_schema_version=5;Reject {Validate $f} 'Unsupported'}
Case 'version metadata is not a string conversion' {$f=Fixture;$f.exclusion.eligibility_schema_version='4';Reject {Validate $f} 'Unsupported'}
Case 'review schema versions are actual integers' {$f=Fixture;$f.feature.schema_version='4';Bind $f;Reject {Validate $f} 'integer four'}
Case 'reviewed candidate offsets are actual integers' {$f=Fixture;$f.feature.candidate.byte_offset='3544';Bind $f;Reject {Validate $f} 'must be integral'}
Case 'review candidate cannot carry hidden extra scope' {$f=Fixture;$f.feature.candidate.other_span='querystr';Bind $f;Reject {Validate $f} 'candidate fields differ'}
Case 'feature cannot call the candidate public' {$f=Fixture;$f.feature.public_api=$true;Bind $f;Reject {Validate $f} 'public allocation behavior'}
Case 'feature cannot erase a mixed obligation' {$f=Fixture;$f.feature.mixed_obligation=$true;Bind $f;Reject {Validate $f} 'public allocation behavior'}
Case 'duplicate contracts cannot replace omitted fault coverage' {$f=Fixture;$f.exclusion.required_semantic_contract_ids[-1]='Payload_Types';Reject {Validate $f} 'public or mixed'}
Case 'unknown exclusion fields cannot acquire approval by omission' {$f=Fixture;$f.exclusion.extra_waiver='querystr';Bind $f;Reject {Validate $f} 'approval field set'}
Case 'approval cannot authorize changed invariant text' {$f=Fixture;$f.exclusion.invariant='changed after review';Reject {Validate $f} 'approved semantics differ'}
Case 'the original anchor cannot itself be excluded' {$f=Fixture;$x=@{};$x[$row.id]=$f.exclusion;$x[$row.original_anchor.id]=@{source='memerr.lua'};Reject {Parents $f $x} 'must remain'}
Case 'an unknown retained-materialization field is rejected' {$f=Fixture;$f.exclusion.retained_materialization.extra='ignored';Reject {Validate $f} 'public or mixed'}
foreach($part in @('feature','retention','narrative')){
    Case "a missing $part synthetic label cannot become actual authority" {
        $f=Fixture;[void]$f[$part].Remove('synthetic_fixture');Bind $f
        Reject {Validate $f} 'explicit actual/synthetic boolean label'
    }
}
Case 'a missing approval synthetic label cannot become actual authority' {
    $f=Fixture
    $a=Get-Content (Join-Path $temporary $f.exclusion.review.artifact) -Raw|ConvertFrom-Json -AsHashtable
    [void]$a.Remove('synthetic_fixture')
    $f.exclusion.review.artifact_sha256=Save $f.exclusion.review.artifact $a
    Reject {Validate $f} 'explicit actual/synthetic boolean label'
}
foreach($path in @('tests/c/conformance_api.c','tests/c/conformance_api.h')){
    Case "the actual public command driver dependency cannot be omitted: $path" {
        $f=Fixture;$f.feature.source_bindings=@($f.feature.source_bindings|Where-Object path -CNE $path);Bind $f
        Reject {Validate $f} 'source binding set'
    }
    Case "stale public command driver bytes invalidate source authority: $path" {
        $f=Fixture;$binding=@($f.feature.source_bindings|Where-Object path -CEQ $path)[0]
        $binding.sha256='0'*64;Bind $f
        Reject {Validate $f} 'Review file hash differs'
    }
}
Write-Output "PASS: $script:cases observable resource source-binding cases; no policy installation or runtime authority"
