Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceExclusionEligibility.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
$base='tests/conformance/targets/remaining-upstream-compatibility'
$temporary=Join-Path $root ('reports/optimizer-v3-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$bytes=[IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/code.lua'))
$original=@(Get-ConformanceCoverageUnits -Path code.lua -Bytes $bytes)
$feature=Get-Content (Join-Path $root "$base/reviews/code-private-optimizer.independent-feature-review.json") -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$feature.source_bindings+=@(@{path='scripts/ConformanceInventory.psm1';sha256=(Get-FileHash (Join-Path $root 'scripts/ConformanceInventory.psm1')).Hash.ToLowerInvariant()})
$retention=Get-Content (Join-Path $root "$base/reviews/code-optimizer-semantic-retention.independent-review.json") -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$scopes=(Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') -Raw|ConvertFrom-Json -AsHashtable).protected_scopes
$paths=@('references/lua/testes/code.lua')+@($feature.source_bindings.path)+@($retention.witness_sources.path)+@($retention.witness.path)+@($scopes.path)
foreach($path in ($paths|Select-Object -Unique)){
    $target=Join-Path $temporary $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    Copy-Item -LiteralPath (Join-Path $root $path) -Destination $target
}
$script:cases=0
function Clone($value){return ConvertTo-Json -InputObject $value -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48}
function Save($path,$value){
    $file=Join-Path $temporary $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
    [IO.File]::WriteAllText($file,(ConvertTo-Json -InputObject $value -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return (Get-FileHash $file).Hash.ToLowerInvariant()
}
function Bind($f){
    $e=$f.exclusion
    $e.feature_review.sha256=Save $e.feature_review.path $f.feature
    $e.semantic_retention_review.sha256=Save $e.semantic_retention_review.path $f.retention
    $narrativeHash=Save ($f.prefix+'-narrative.json') $f.narrative
    $semantic=[ordered]@{};foreach($key in (Get-ConformanceExclusionSemanticFields $e)){$semantic[$key]=$e[$key]}
    $approval=@{schema_version=3;kind='t-exclusion-approval';target='remaining-upstream-compatibility';
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';protected_scopes=$scopes;
        author=$e.review.author;reviewer=$e.review.reviewer;decision='accepted';exclusion=$semantic;
        runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@();synthetic_fixture=$true;
        review_evidence=@{path=($f.prefix+'-narrative.json');sha256=$narrativeHash}}
    $e.review.artifact_sha256=Save $e.review.artifact $approval
}
function Fixture($index=0){
    # All review labels below are deliberately synthetic non-execution input.
    # Only the direct test call can enable them; inventory/runner/final callers
    # never pass that switch. No actual policy or coverage record is changed.
    $row=@(Get-ConformanceOptimizerRegistry)[$index];$prefix=$base+'/reviews/v3-'+[guid]::NewGuid().ToString('N')
    $links=@($original|Where-Object{$_.byte_offset -ge $row.byte_offset -and $_.byte_offset+$_.byte_length -le $row.byte_offset+$row.byte_length}|
        ForEach-Object{@{id=$_.id;kind=$_.kind;byte_offset=$_.byte_offset;byte_length=$_.byte_length;anchor_sha256=$_.anchor_sha256}})
    $e=@{id=$row.id;source='code.lua';source_sha256='b63335ff980dd318f1cc4aa81bbd54952afc7ac3688c7d9042ea4c45e9993663';
        byte_offset=$row.byte_offset;byte_length=$row.byte_length;anchor_sha256=$row.anchor_sha256;
        status='excluded';disposition='reviewed-t-internal-exclusion';configurations=@('upstream-test');eligibility='t-only-private-invariant';
        public_api=$false;mixed_obligation=$false;module_observable=$true;module_compatibility_obligation=$false;
        eligibility_schema_version=3;observation_kind='private-optimization-structure';structure_kind=$row.structure_kind;
        required_semantic_contract_ids=@($row.required_semantic_contract_ids);original_anchor_links=$links;
        invariant='synthetic source-binding fixture, never an actual approval';third_party_irrelevance='synthetic relevance guard input';evidence=@();
        t_guard=@{mode='absent-return';byte_offset=83;byte_length=104;sha256='6cbc2276f7214ec212214a3f5dbf2f48914a46ab90adebe20f15d6c38f631050'};
        feature_review=@{path=($prefix+'-feature.json');sha256=$null};semantic_retention_review=@{path=($prefix+'-retention.json');sha256=$null};
        review=@{status='accepted';author='synthetic-author';reviewer='synthetic-independent-reviewer';artifact=($prefix+'-approval.json');artifact_sha256=$null}}
    $n=@{schema_version=3;kind='t-private-optimizer-exclusion-review';exclusion_id=$e.id;reviewer=$e.review.reviewer;decision='accepted';
        t_dominance='synthetic pinned guard binding';private_invariant='synthetic exact inspection binding';third_party_irrelevance='synthetic retention binding';
        runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@();synthetic_fixture=$true}
    $f=@{exclusion=$e;prefix=$prefix;feature=(Clone $feature);retention=(Clone $retention);narrative=$n;
        record=@{id=$e.id;kind='reviewed-block';byte_offset=$e.byte_offset;byte_length=$e.byte_length;anchor_sha256=$e.anchor_sha256;status='pending';disposition='pending';evidence=@()};records=@{}}
    $f.feature.synthetic_fixture=$true;$f.retention.synthetic_fixture=$true
    foreach($binding in $f.feature.source_bindings){$binding.sha256=(Get-FileHash (Join-Path $temporary $binding.path)).Hash.ToLowerInvariant()}
    foreach($anchor in $original){$f.records[$anchor.id]=Clone $anchor};$f.records[$e.id]=$f.record
    Bind $f;return $f
}
function Validate($f,[switch]$Actual){
    return & (Get-Module ConformanceInventory) {param($r,$b,$f,$synthetic)
        Test-ConformanceTargetExclusion -Root $r -Source code.lua -SourceBytes $b -Record $f.record -Exclusion $f.exclusion -AllowSyntheticReview:$synthetic
    } $temporary $bytes $f (-not $Actual)
}
function Parents($f){
    $excluded=@{};$excluded[$f.exclusion.id]=$f.exclusion
    & (Get-Module ConformanceInventory) {param($b,$f,$x)
        Assert-ConformanceOptimizerParentRecords -Bytes $b -Exclusion $f.exclusion -Records $f.records -Exclusions $x
    } $bytes $f $excluded
}
function Reject([scriptblock]$action,$expected){$failure=$null;try{&$action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $expected){throw "Wrong V3 rejection: $failure; expected $expected"}}
function Case($name,[scriptblock]$action){&$action;$script:cases++;Write-Output "OPTIMIZER V3 BINDING PASS: $name"}
foreach($index in 0..7){Case "exact pinned private structure $index retains original pending identities" {
    $f=Fixture $index;$r=Validate $f;Parents $f
    if($r.evidence.Count -or $f.record.status -cne 'pending' -or $f.records.Count -ne 52){throw 'Source binding fixture acquired pass authority'}
}}
Case 'labelled synthetic reviews cannot authorize the actual target' {$f=Fixture;Reject {Validate $f -Actual} 'synthetic review'}
foreach($flag in @('public_api','mixed_obligation','module_compatibility_obligation')){Case "$flag cannot be waived" {$f=Fixture;$f.exclusion[$flag]=$true;Reject {Validate $f} 'without public or mixed'}}
Case 'observable structures cannot masquerade as invisible v1 metadata' {$f=Fixture;$f.exclusion.module_observable=$false;Reject {Validate $f} 'without public or mixed'}
Case 'a legacy false-visibility label cannot bypass the closed code registry' {$f=Fixture;[void]$f.exclusion.Remove('eligibility_schema_version');$f.exclusion.module_observable=$false;Reject {Validate $f} 'require observable V3'}
Case 'string false is not a compatibility boolean' {$f=Fixture;$f.exclusion.module_compatibility_obligation='false';Reject {Validate $f} 'without public or mixed'}
Case 'a ninth candidate cannot enter the registry' {$f=Fixture;$f.exclusion.id='LUA-CODE-REVIEWED-BLOCK-9009';$f.record.id=$f.exclusion.id;Reject {Validate $f} 'without public or mixed'}
Case 'one-byte widening cannot remove a public neighbour' {$f=Fixture;$f.exclusion.byte_length++;$f.record.byte_length++;$span=$bytes[$f.record.byte_offset..($f.record.byte_offset+$f.record.byte_length-1)];$f.record.anchor_sha256=Get-ConformanceHash $span;$f.exclusion.anchor_sha256=$f.record.anchor_sha256;Reject {Validate $f} 'without public or mixed'}
Case 'private structure kinds cannot be relabelled' {$f=Fixture;$f.exclusion.structure_kind='public-bytecode-validity';Reject {Validate $f} 'without public or mixed'}
Case 'source offsets require real integral JSON numbers' {$f=Fixture;$f.exclusion.byte_offset=[string]$f.exclusion.byte_offset;Reject {Validate $f} 'without public or mixed'}
Case 'a lexical assertion cannot masquerade as the derived block' {$f=Fixture;$f.record.kind='assert-call';Reject {Validate $f} 'exact derived reviewed block'}
Case 'ordinary default applicability cannot borrow T source approval' {$f=Fixture;$f.exclusion.configurations=@('default');Reject {Validate $f} 'T-only private invariant'}
Case 'T guard identity cannot move' {$f=Fixture;$f.exclusion.t_guard.byte_offset++;Reject {Validate $f} 'exact pinned top-level T guard'}
Case 'an original anchor cannot disappear from decomposition' {$f=Fixture;$f.exclusion.original_anchor_links=@($f.exclusion.original_anchor_links|Select-Object -Skip 1);Reject {Validate $f} 'decomposition is incomplete'}
Case 'forged original-anchor identities reject' {$f=Fixture;$f.exclusion.original_anchor_links[0].anchor_sha256='0'*64;Reject {Validate $f} 'original-anchor identity differs'}
Case 'required public semantic contracts cannot disappear' {$f=Fixture;$f.exclusion.required_semantic_contract_ids=@();Reject {Validate $f} 'without public or mixed'}
Case 'previously passing derived obligations reject' {$f=Fixture;$f.record.status='passed';Reject {Validate $f} 'Only pending source runtime'}
Case 'source exclusions cannot carry actual process evidence' {$f=Fixture;$f.exclusion.evidence=@(@{result='passed'});Reject {Validate $f} 'cannot contain execution or pass evidence'}
Case 'self approval rejects' {$f=Fixture;$f.exclusion.review.reviewer=$f.exclusion.review.author;Reject {Validate $f} 'accepted independent review'}
Case 'feature-only input cannot replace the retention decision' {$f=Fixture;$f.retention.decision='pending';Bind $f;Reject {Validate $f} 'public semantic retention'}
Case 'a feature decision cannot widen one child' {$f=Fixture;$f.feature.candidates[0].byte_length++;Bind $f;Reject {Validate $f} 'candidate widened or changed'}
Case 'public witness byte drift rejects even a rehashed review' {$f=Fixture;$f.retention.witness_sources[0].sha256='0'*64;Bind $f;Reject {Validate $f} 'hash differs'}
Case 'stale implementation bindings require a fresh feature decision' {$f=Fixture;$f.feature.source_bindings[0].sha256='0'*64;Bind $f;Reject {Validate $f} 'hash differs'}
Case 'current original-anchor/review validator identity cannot be omitted' {$f=Fixture;$f.feature.source_bindings=@($f.feature.source_bindings|Where-Object path -CNE scripts/ConformanceInventory.psm1);Bind $f;Reject {Validate $f} 'current implementation/source bindings'}
Case 'checkR source retention cannot be weakened' {$f=Fixture;$f.retention.protected_checkR.byte_length--;Bind $f;Reject {Validate $f} 'exact checkR'}
Case 'source retention cannot invent runtime evidence' {$f=Fixture;$f.retention.execution_evidence=@('passed');Bind $f;Reject {Validate $f} 'invent execution evidence'}
Case 'a pending author packet cannot act as retention authority' {$f=Fixture;$f.retention.kind='code-public-semantics-author-witness';Bind $f;Reject {Validate $f} 'public semantic retention'}
Case 'every original51 identity remains mandatory' {$f=Fixture;[void]$f.records.Remove('LUA-CODE-MANUAL-AUDIT-0001');Reject {Parents $f} 'every original51'}
Case 'previously passing original assertions cannot be reclassified away' {$f=Fixture;$f.records[$f.exclusion.original_anchor_links[1].id].status='passed';Reject {Parents $f} 'previously passing original'}
Case 'reviewed references cannot link solely to their private child' {$f=Fixture;$a=$f.records[$f.exclusion.original_anchor_links[0].id];$a.status='reviewed';$a.classification='reference';$a.obligations=@($f.exclusion.id);Reject {Parents $f} 'retained-runtime decomposition'}
Case 'executable transform replacements remain forbidden' {$f=Fixture;$change=@{exclusion_id=$f.exclusion.id;start_byte=$f.exclusion.byte_offset;length_bytes=$f.exclusion.byte_length;source_sha256=$f.exclusion.anchor_sha256;replacement='return'};Reject {& (Get-Module ConformanceTransforms) {param($c,$e)Assert-TTransformReplacement $c $e} $change $f.exclusion} 'executable behavior or a blanket bypass'}
Case 'an unterminated comment cannot swallow retained public code' {$f=Fixture;$change=@{exclusion_id=$f.exclusion.id;start_byte=$f.exclusion.byte_offset;length_bytes=$f.exclusion.byte_length;source_sha256=$f.exclusion.anchor_sha256;replacement='-- swallowed'};Reject {& (Get-Module ConformanceTransforms) {param($c,$e)Assert-TTransformReplacement $c $e} $change $f.exclusion} 'comment must terminate'}
Write-Output "PASS: $script:cases V3 source-binding regressions; synthetic non-execution fixtures, no installed exclusions or passing claims"
