param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceApiComposite.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
$base='tests/conformance/targets/remaining-upstream-compatibility/'
$compositePath=$base+'api-private-bound-and-userdata-lifetimes.composite.author-proposal.json'
$lifetimePath=$base+'api-finalized-userdata-reclamation.equivalent.author-proposal.json'
$template=Get-Content (Join-Path $root $compositePath) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$temporary=Join-Path $root ('reports/api-composite-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Case($Name,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "API COMPOSITE PASS: $Name"}
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert ($null -ne $failure -and $failure -match $Pattern) "Wrong failure: $failure; expected $Pattern"
}
function Save($Fixture,$Path,$Value){
    $full=Join-Path $Fixture.root $Path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
    [IO.File]::WriteAllText($full,(ConvertTo-Json -InputObject $Value -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return (Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant()
}
function Copy-Graph($Fixture){
    $queue=[Collections.Generic.Queue[string]]::new()
    foreach($path in @($compositePath,'tests/conformance/coverage/api.jsonl','tests/conformance/targets/remaining-upstream-compatibility.exclusions.json')){$queue.Enqueue($path)}
    $seen=@{}
    function Add-Value($Value){
        if($Value -is [Collections.IDictionary]){foreach($key in $Value.Keys){Add-Value $Value[$key]}}
        elseif($Value -is [Array]){foreach($item in $Value){Add-Value $item}}
        elseif($Value -is [string] -and $Value -cmatch '^(?:references|tests|src|scripts|c_api)/[A-Za-z0-9_./#-]+$'){
            $path=$Value.Split('#')[0]
            if(Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf){$queue.Enqueue($path)}
        }
    }
    while($queue.Count){
        $path=$queue.Dequeue();if($seen.ContainsKey($path)){continue};$seen[$path]=$true
        $destination=Join-Path $Fixture.root $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $destination
        # Immutable scope descriptors protect their source partitions. Their
        # historical report/contract graph is not a composite test input.
        if($path.EndsWith('.json',[StringComparison]::Ordinal) -and -not $path.StartsWith('tests/conformance/scopes/')){
            Add-Value (Get-Content (Join-Path $root $path) -Raw|ConvertFrom-Json -AsHashtable -Depth 48)
        }
    }
}
function Set-LifetimeReview($Fixture){
    $mapping=$Fixture.lifetime;$mapping.review=@{status='accepted';author='synthetic-author';reviewer='synthetic-reviewer';
        artifact=($base+'reviews/synthetic-lifetime-approval.json');artifact_sha256=('0'*64)}
    $evidencePath=$base+'reviews/synthetic-lifetime-decision.json'
    $evidenceHash=Save $Fixture $evidencePath @{schema_version=1;kind='synthetic-equivalent-source-review';
        reviewer='synthetic-reviewer';decision='accepted';synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        rationale='Synthetic binding fixture only; no actual source approval or runtime evidence.'}
    $decisions=@(foreach($patch in $mapping.replacements){
        @{id=$patch.id;start_byte=$patch.start_byte;length_bytes=$patch.length_bytes;source_sha256=$patch.source_sha256;
            replacement_sha256=(Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes($patch.replacement)));
            author='synthetic-author';reviewer='synthetic-reviewer';decision='accepted';rationale='Synthetic exact binding only';
            review_evidence=@{path=$evidencePath;sha256=$evidenceHash};
            counterparts=@(foreach($path in $patch.counterpart_tests){@{path=$path;sha256=(Get-FileHash (Join-Path $Fixture.root $path)).Hash.ToLowerInvariant()}})}
    })
    $approval=@{schema_version=1;kind='equivalent-approval';author='synthetic-author';reviewer='synthetic-reviewer';decision='accepted';
        synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        equivalent=@{id=$mapping.id;source=$mapping.source;source_sha256=$mapping.source_sha256;configuration=$mapping.configuration;
            disposition=$mapping.disposition;platform=$null;generated_sha256=$mapping.output_sha256};decisions=$decisions}
    $mapping.review.artifact_sha256=Save $Fixture $mapping.review.artifact $approval
    $hash=Save $Fixture $lifetimePath $mapping
    @($Fixture.spec.components|Where-Object kind -CEQ equivalent)[0].manifest.sha256=$hash
}
function Set-CompositeReview($Fixture){
    $Fixture.spec.review=@{status='accepted';author='synthetic-composer';reviewer='synthetic-composition-reviewer';
        artifact=($base+'reviews/synthetic-composition-approval.json');artifact_sha256=('0'*64)}
    $claims=Get-TargetWitnessPayloadHash (Get-TargetApiCompositeClaims $Fixture.spec)
    $evidencePath=$base+'reviews/synthetic-composition-decision.json'
    $evidenceHash=Save $Fixture $evidencePath @{schema_version=1;kind='target-api-source-composite-review';
        reviewer='synthetic-composition-reviewer';decision='accepted';composite_id=$Fixture.spec.id;claims_sha256=$claims;
        synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;component_reviews_preserved=$true;
        original_obligations_retained=$true;exact_source_exclusions=$true;disjoint_original_coordinates=$true}
    $Fixture.spec.review.artifact_sha256=Save $Fixture $Fixture.spec.review.artifact @{schema_version=1;kind='target-api-source-composite-approval';
        author='synthetic-composer';reviewer='synthetic-composition-reviewer';decision='accepted';composite_id=$Fixture.spec.id;
        claims_sha256=$claims;synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        review_evidence=@{path=$evidencePath;sha256=$evidenceHash}}
}
function New-Fixture {
    $f=@{root=(Join-Path $temporary ([guid]::NewGuid().ToString('N')));spec=($template|ConvertTo-Json -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48)}
    Copy-Graph $f
    $f.lifetime=Get-Content (Join-Path $f.root $lifetimePath) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $policy=Get-Content (Join-Path $f.root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $f.resolved=@{};foreach($excluded in $policy.exclusions){$f.resolved[$excluded.id]=$excluded}
    $f.spec.synthetic_fixture=$true
    Set-LifetimeReview $f;Set-CompositeReview $f
    return $f
}
function Replay($Fixture,[switch]$Actual,$Implementation='Ada',$Configuration='upstream-test'){
    Get-TargetApiCompositeReplay -Root $Fixture.root -Specification $Fixture.spec -Implementation $Implementation -Configuration $Configuration `
        -PolicySha256 $Fixture.spec.exclusion_policy_sha256 -ResolvedExclusions $Fixture.resolved -AllowSyntheticReview:(-not $Actual)
}
function Set-ActualShapedOuter($Fixture){
    # Actual-shaped outer metadata must still fail on explicitly synthetic
    # inner authority. This never creates a passing actual-review fixture.
    $Fixture.spec.synthetic_fixture=$false;Set-CompositeReview $Fixture
    $approval=Get-Content (Join-Path $Fixture.root $Fixture.spec.review.artifact) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $decision=Get-Content (Join-Path $Fixture.root $approval.review_evidence.path) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $decision.synthetic_fixture=$false
    $approval.review_evidence.sha256=Save $Fixture $approval.review_evidence.path $decision
    $approval.synthetic_fixture=$false
    $Fixture.spec.review.artifact_sha256=Save $Fixture $Fixture.spec.review.artifact $approval
}
Case 'accepted-shaped synthetic inner reviews reconstruct exact disjoint union without authority' {
    $f=New-Fixture;$r=Replay $f
    Assert ($r.diagnostic_only -and -not $r.runtime_acceptance -and -not $r.coverage_authority -and
        $r.sha256 -ceq $template.output_sha256 -and $r.components.Count -eq 2 -and
        ($r.source_exclusion_ids-join '|') -ceq 'LUA-API-REVIEWED-BLOCK-9001' -and
        ($r.original_required_obligations-join '|') -ceq 'LUA-API-ASSERT-CALL-0125|LUA-API-ASSERT-CALL-0195') 'Source composition lost authorities or acquired a pass'
    $text=[Text.Encoding]::UTF8.GetString($r.bytes)
    Assert ($text.Contains('assert(m2 > m1)') -and $text.Contains('checkerr(":301:", code)') -and
        $text.Contains('assert(udata_finalized == 1000)') -and $text.Contains('assert(next(udata_keys) == nil and next(udata_values) == nil)')) 'Retained public source checks changed'
}
Case 'synthetic composition cannot authorize actual replay' {Reject {Replay (New-Fixture) -Actual} 'Synthetic API composite'}
Case 'actual-shaped outer review cannot launder synthetic inner approval or narrative' {
    foreach($which in @('approval','narrative')){
        $f=New-Fixture
        if($which -ceq 'narrative'){
            $approval=Get-Content (Join-Path $f.root $f.lifetime.review.artifact) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
            $approval.synthetic_fixture=$false
            $f.lifetime.review.artifact_sha256=Save $f $f.lifetime.review.artifact $approval
            @($f.spec.components|Where-Object kind -CEQ equivalent)[0].manifest.sha256=Save $f $lifetimePath $f.lifetime
        }
        Set-ActualShapedOuter $f
        Reject {Replay $f -Actual} 'Synthetic API composite or component review'
    }
}
Case 'ordinary configuration cannot select the API T composite' {Reject {Replay (New-Fixture) -Configuration default} 'Invalid bounded API composite'}
Case 'original native C cannot use the Ada source composite' {Reject {Replay (New-Fixture) -Implementation ReferenceC} 'Invalid bounded API composite'}
Case 'component approval alone cannot replace separate composition review' {
    $f=New-Fixture;$f.spec.review.status='pending';Reject {Replay $f} 'separate independent exact composition review'
}
Case 'a composer cannot review its own source selection' {
    $f=New-Fixture;$f.spec.review.reviewer=$f.spec.review.author;Reject {Replay $f} 'separate independent exact composition review'
}
Case 'dropping either approved source operation rejects the composite' {
    foreach($kind in @('equivalent','t-private')){$f=New-Fixture;$f.spec.components=@($f.spec.components|Where-Object kind -CNE $kind);Reject {Replay $f} 'required operation set'}
}
Case 'source composite versions must be actual supported integers' {
    $f=New-Fixture;$f.spec.schema_version='1';Reject {Replay $f} 'Invalid bounded API composite'
}
Case 'duplicate operations do not replace both independent source authorities' {
    $f=New-Fixture;$f.spec.components[1]=$f.spec.components[0];Set-CompositeReview $f
    Reject {Replay $f} 'missing duplicated'
}
Case 'the original private exclusion cannot be omitted from composition claims' {
    $f=New-Fixture;$f.spec.source_exclusion_ids=@();Reject {Replay $f} 'required operation set'
}
Case 'retained original parent obligations cannot be deleted' {
    $f=New-Fixture;$f.spec.original_required_obligations=@('LUA-API-ASSERT-CALL-0195');Reject {Replay $f} 'required operation set'
}
Case 'policy drift invalidates the independently bound original T operation' {
    $f=New-Fixture;$f.spec.exclusion_policy_sha256='0'*64;Set-CompositeReview $f
    Reject {Replay $f} 'Review file hash differs'
}
Case 'resolved exclusion metadata must equal the actual reviewed policy' {
    $f=New-Fixture;$f.resolved=@{};Reject {Replay $f} 'actual reviewed source exclusion'
}
Case 'stale component source hashes reject before replay' {
    $f=New-Fixture;$f.spec.components[1].manifest.sha256='0'*64;Set-CompositeReview $f
    Reject {Replay $f} 'Review file hash differs'
}
Case 'one component cannot use an already edited base or another configuration' {
    foreach($field in @('source_sha256','configuration')){
        $f=New-Fixture;$f.lifetime[$field]=if($field -ceq 'configuration'){'default'}else{'0'*64}
        Set-LifetimeReview $f;Set-CompositeReview $f
        Reject {Replay $f} 'same pinned original source/configuration'
    }
}
Case 'an inner pending equivalent is not approved by the outer composition' {
    $f=New-Fixture;$f.lifetime.review.status='pending'
    @($f.spec.components|Where-Object kind -CEQ equivalent)[0].manifest.sha256=Save $f $lifetimePath $f.lifetime
    Set-CompositeReview $f;Reject {Replay $f} 'not independent and accepted'
}
Case 'overlap or wider source transformations cannot be laundered through inner review' {
    $f=New-Fixture;$f.lifetime.replacements[0].start_byte=17053;$f.lifetime.replacements[0].length_bytes=18
    $f.lifetime.replacements[0].source_sha256='f89400b75cf254feed3cc991449a9e7bc1679e6cd9b5b6be1b6598dfa176bf55'
    Set-LifetimeReview $f;Set-CompositeReview $f
    Reject {Replay $f} 'bounded original patch'
}
Case 'a claimed exact reviewer cannot turn lifetime checks into a blanket bypass' {
    $f=New-Fixture;$f.lifetime.replacements[2].replacement='T=nil; return';Set-LifetimeReview $f;Set-CompositeReview $f
    Reject {Replay $f} 'bounded original patch'
}
Case 'losing the actual lifetime feature counterpart is rejected' {
    $f=New-Fixture;$f.lifetime.replacements[0].counterpart_tests=@('src/lua-engine.adb');Set-LifetimeReview $f;Set-CompositeReview $f
    Reject {Replay $f} 'bounded original patch'
}
Case 'changed selected-owner counterpart source cannot reuse inner exact approval' {
    $f=New-Fixture;[IO.File]::AppendAllText((Join-Path $f.root 'src/lua-engine.adb'),'changed')
    Reject {Replay $f} 'Review file hash differs'
}
Case 'original source anchors cannot be removed from the ledger' {
    $f=New-Fixture;$path=Join-Path $f.root 'tests/conformance/coverage/api.jsonl'
    $rows=@(Read-ConformanceJsonLines $path|Where-Object id -CNE 'LUA-API-ASSERT-CALL-0125');Write-ConformanceJsonLines $path $rows
    Reject {Replay $f} 'remove or downgrade an original required anchor'
}
Case 'a changed component output cannot inherit its composition decision' {
    $f=New-Fixture;$f.spec.components[1].output_sha256='0'*64;Set-CompositeReview $f
    Reject {Replay $f} 'inner operation lacks exact accepted review/output'
}
Case 'exact union output is independently checked after accepted inner replays' {
    $f=New-Fixture;$f.spec.output_sha256='0'*64;Set-CompositeReview $f
    Reject {Replay $f} 'exact union output hash differs'
}
Case 'changing composition claims requires a fresh independent decision' {
    $f=New-Fixture;$f.spec.output_sha256='0'*64
    Reject {Replay $f} 'independent exact claims differ'
}
Case 'source-only composition cannot contain fabricated runtime evidence' {
    $f=New-Fixture;$f.spec.runtime_acceptance=$true
    Reject {Replay $f} 'cannot supply runtime acceptance'
}
Case 'a component cannot smuggle execution evidence into the source selection schema' {
    $f=New-Fixture;$f.spec.components[1].execution_evidence=@(@{passed=$true});Set-CompositeReview $f
    Reject {Replay $f} 'components are missing duplicated'
}
Case 'standalone pending equivalences require every counterpart and exact review' {
    foreach($name in @('api-finalized-userdata-reclamation','calls-undump-constant-pool')){
        $spec=Get-Content (Join-Path $root ($base+$name+'.equivalent.author-proposal.json')) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        Assert ($spec.review.status -ceq 'pending' -and -not $spec.runtime_acceptance -and -not $spec.coverage_authority) 'Pending source proposal acquired authority'
        foreach($patch in $spec.replacements){
            foreach($path in $patch.counterpart_tests){Assert (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf) 'Required source counterpart is absent'}
        }
        $bytes=Get-ConformancePatchedBytes -SourceBytes ([IO.File]::ReadAllBytes((Join-Path $root $spec.source))) -Replacements $spec.replacements
        Assert ((Get-ConformanceHash $bytes) -ceq $spec.output_sha256) 'Pending exact output differs'
        Reject {Get-ConformanceEquivalentReplay -Root $root -Specification $spec} 'not independent and accepted'
    }
}
Write-Output "PASS: $script:cases bounded API composite regressions; memory reconstruction and explicitly synthetic review fixtures only, no adapted-source write or execution"
