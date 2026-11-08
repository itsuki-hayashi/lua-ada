param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceVerifierEquivalents.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
$base='tests/conformance/targets/remaining-upstream-compatibility'
$manifest=Get-Content (Join-Path $root "$base/memerr-verifier-allocation.equivalent.author-proposal.json") -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$temporary=Join-Path $root ('reports/verifier-equivalent-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Case($Name,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "VERIFIER EQUIVALENT PASS: $Name"}
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert ($null -ne $failure -and $failure -match $Pattern) "Wrong failure: $failure; expected $Pattern"
}
function Save($Path,$Value){
    [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function New-Fixture {
    $fixture=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
    foreach($path in @($manifest.source,$manifest.author_proposal.path)+@($manifest.counterpart_sources.path)){
        $destination=Join-Path $fixture $path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $destination
    }
    return @{root=$fixture;spec=($manifest|ConvertTo-Json -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48)}
}
function Replay($Fixture,[switch]$Diagnostic,[switch]$Synthetic,$Implementation='Ada',$Configuration='upstream-test'){
    Get-ConformanceVerifierReplay -Root $Fixture.root -Specification $Fixture.spec -Implementation $Implementation `
        -Configuration $Configuration -AllowUnreviewedDiagnostics:$Diagnostic -AllowSyntheticReview:$Synthetic
}
function Set-FixtureReview($Fixture){
    # Explicitly synthetic reviewer artifacts exercise binding only. Even
    # accepted-shaped fixtures remain diagnostic and default replay rejects
    # them. They cannot authorize a production transformation or execution.
    $review=@{status='accepted';author='synthetic-author';reviewer='synthetic-reviewer';
        artifact='approval.json';artifact_sha256=('0'*64)}
    $Fixture.spec.review=$review
    $semantic=Get-ConformanceVerifierSemanticHash $Fixture.spec
    $decision=@{schema_version=1;kind='t-verifier-equivalent-review';equivalent_id=$Fixture.spec.id;
        reviewer=$review.reviewer;decision='accepted';semantic_sha256=$semantic;synthetic_fixture=$true;
        source_bound_rationale='Synthetic source-binding fixture; no actual feature review or Lua process.';
        application_refusal_preserved=$true;status_message_assertion_preserved=$true;
        original_reset_preserved=$true;later_campaigns_preserved=$true;no_source_exclusions=$true;
        runtime_acceptance=$false;coverage_authority=$false}
    $decisionHash=Save (Join-Path $Fixture.root 'decision.json') $decision
    $approval=@{schema_version=1;kind='t-verifier-equivalent-approval';equivalent_id=$Fixture.spec.id;
        author=$review.author;reviewer=$review.reviewer;decision='accepted';semantic_sha256=$semantic;
        synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        review_evidence=@{path='decision.json';sha256=$decisionHash}}
    $review.artifact_sha256=Save (Join-Path $Fixture.root 'approval.json') $approval
}
function Mutate-Approval($Fixture,[scriptblock]$Mutation){
    $value=Get-Content (Join-Path $Fixture.root 'approval.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    &$Mutation $value
    $Fixture.spec.review.artifact_sha256=Save (Join-Path $Fixture.root 'approval.json') $value
}
function Mutate-Decision($Fixture,[scriptblock]$Mutation){
    $value=Get-Content (Join-Path $Fixture.root 'decision.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    &$Mutation $value
    $newHash=Save (Join-Path $Fixture.root 'decision.json') $value
    Mutate-Approval $Fixture {param($a)$a.review_evidence.sha256=$newHash}
}
Case 'pending source-only artifact reconstructs exactly one17byte insertion in memory' {
    $f=New-Fixture;$r=Replay $f -Diagnostic
    $original=[IO.File]::ReadAllBytes((Join-Path $f.root $f.spec.source))
    Assert ($r.diagnostic_only -and $r.review_status -ceq 'pending' -and -not $r.runtime_acceptance -and
        -not $r.coverage_authority -and $r.excluded_obligations.Count -eq 0 -and $r.bytes.Length -eq $original.Length+17) 'Pending source data gained authority'
    Assert ((Get-ConformanceHash $r.bytes[0..139]) -ceq (Get-ConformanceHash $original[0..139]) -and
        (Get-ConformanceHash $r.bytes[157..($r.bytes.Length-1)]) -ceq (Get-ConformanceHash $original[140..($original.Length-1)])) 'Untouched source bytes changed'
    $text=[Text.Encoding]::UTF8.GetString($r.bytes)
    Assert ($text.Contains("  local stat, err = pcall(f, ...)`n  T.alloccount()`n  assert(not stat and string.find(err, msg))") -and
        $text.Contains("T.alloccount(10)`ncheckerr(MEMERRMSG, f)`nT.alloccount()          -- remove limit")) 'Protected call/assertion/original reset changed'
}
Case 'production pending artifact rejects default replay without exact independent review' {
    Reject {Replay (New-Fixture)} 'lacks independent exact semantic review'
}
foreach($implementation in @('ReferenceC')){Case 'original native execution cannot use the Ada verifier equivalent' {
    Reject {Replay (New-Fixture) -Diagnostic -Implementation $implementation} 'Invalid bounded T verifier'
}}
Case 'ordinary configuration cannot use the verifier equivalent' {Reject {Replay (New-Fixture) -Diagnostic -Configuration default} 'Invalid bounded T verifier'}
Case 'schema versions must be actual supported integers' {
    foreach($version in @('1',1.0,2)){$f=New-Fixture;$f.spec.schema_version=$version;Reject {Replay $f -Diagnostic} 'Invalid bounded T verifier'}
}
foreach($field in @('source_sha256','reference_revision','kind','operation','id','source')){
    Case "changed $field cannot inherit the bounded operation" {
        $f=New-Fixture;$f.spec[$field]='changed'
        Reject {Replay $f -Diagnostic} 'Invalid bounded T verifier'
    }
}
foreach($replacement in @("T.alloccount()`n","  T.alloccount(0)`n","  T.alloccount(); return`n","  T=nil`n",'  T.alloccount()')){
    Case "changed reset bytes cannot become a verifier equivalent: $replacement" {
        $f=New-Fixture;$f.spec.insertion.replacement=$replacement
        Reject {Replay $f -Diagnostic} 'only the exact reset'
    }
}
foreach($offset in @(106,139,141,993,1010)){
    Case "reset offset$offset cannot precede an application or modify its assertion" {
        $f=New-Fixture;$f.spec.insertion.start_byte=$offset
        Reject {Replay $f -Diagnostic} 'only the exact reset'
    }
}
Case 'zero-width operation cannot consume original assertion bytes' {
    $f=New-Fixture;$f.spec.insertion.length_bytes=44
    Reject {Replay $f -Diagnostic} 'only the exact reset'
}
Case 'original zero-width span hash remains mandatory' {
    $f=New-Fixture;$f.spec.insertion.source_sha256='0'*64
    Reject {Replay $f -Diagnostic} 'only the exact reset'
}
Case 'generic historical transformation engine still rejects insertions' {
    $f=New-Fixture
    Reject {Get-ConformancePatchedBytes -SourceBytes ([IO.File]::ReadAllBytes((Join-Path $f.root $f.spec.source))) `
        -Replacements @(@{id='generic-zero-width';start_byte=140;length_bytes=0;source_sha256=$f.spec.insertion.source_sha256;replacement="  T.alloccount()`n"})} 'Invalid, duplicate or overlapping'
}
Case 'retained later campaigns cannot be omitted from source review' {
    $f=New-Fixture;$f.spec.retained_spans=@($f.spec.retained_spans|Where-Object id -CNE later-campaigns)
    Reject {Replay $f -Diagnostic} 'retained application/status/campaign spans'
}
Case 'retained original status assertion hash cannot be substituted' {
    $f=New-Fixture;$f.spec.retained_spans[1].sha256='0'*64
    Reject {Replay $f -Diagnostic} 'retained application/status/campaign span differs'
}
Case 'source exclusions cannot replace verifier evidence' {
    $f=New-Fixture;$f.spec.excluded_obligations=@('LUA-MEMERR-ASSERT-CALL-0001')
    Reject {Replay $f -Diagnostic} 'exclusion/acceptance claim'
}
Case 'unrecognized execution flags cannot widen the source schema' {
    $f=New-Fixture;$f.spec.extra_flags=@('_soft=true')
    Reject {Replay $f -Diagnostic} 'Invalid bounded T verifier'
}
Case 'source-only schema cannot stamp runtime acceptance' {
    $f=New-Fixture;$f.spec.runtime_acceptance=$true
    Reject {Replay $f -Diagnostic} 'exclusion/acceptance claim'
}
Case 'source bytes must still be the pinned original' {
    $f=New-Fixture;[IO.File]::AppendAllText((Join-Path $f.root $f.spec.source),'changed')
    Reject {Replay $f -Diagnostic} 'Review file hash differs'
}
Case 'counterpart source/configuration bindings cannot be stale' {
    $f=New-Fixture;$f.spec.counterpart_sources[2].sha256='0'*64
    Reject {Replay $f -Diagnostic} 'Review file hash differs'
}
Case 'missing or duplicated source counterparts cannot be laundered through review' {
    $f=New-Fixture;$f.spec.counterpart_sources=@($f.spec.counterpart_sources|Select-Object -Skip 1)
    Reject {Replay $f -Diagnostic} 'counterpart bindings missing'
    $f=New-Fixture;$f.spec.counterpart_sources[1]=$f.spec.counterpart_sources[0]
    Reject {Replay $f -Diagnostic} 'counterpart binding differs'
}
Case 'native allocator source hash cannot be replaced by a different private test implementation' {
    $f=New-Fixture;$f.spec.counterpart_sources[0].sha256='0'*64
    Reject {Replay $f -Diagnostic} 'pinned test implementation'
}
Case 'author proposal must bind the reviewed operation and exact content' {
    $f=New-Fixture;$f.spec.author_proposal.path='other.json'
    Reject {Replay $f -Diagnostic} 'another source operation'
    $f=New-Fixture;$f.spec.author_proposal.sha256='0'*64
    Reject {Replay $f -Diagnostic} 'Review file hash differs'
}
Case 'exact insertion output hash must match the unchanged source slices' {
    $f=New-Fixture;$f.spec.output_sha256='0'*64
    Reject {Replay $f -Diagnostic} 'exact output hash differs'
}
Case 'explicit synthetic review remains diagnostic even when its complete binding validates' {
    $f=New-Fixture;Set-FixtureReview $f;$r=Replay $f -Synthetic
    Assert ($r.diagnostic_only -and $r.review_status -ceq 'synthetic-fixture' -and -not $r.coverage_authority) 'Synthetic review acquired actual authority'
}
Case 'synthetic approval or narrative cannot authorize actual replay' {
    foreach($which in @('both','approval','narrative')){
        $f=New-Fixture;Set-FixtureReview $f
        if($which -ceq 'approval'){Mutate-Decision $f {param($d)$d.synthetic_fixture=$false}}
        if($which -ceq 'narrative'){Mutate-Approval $f {param($a)$a.synthetic_fixture=$false}}
        Reject {Replay $f} 'Synthetic verifier review'
    }
}
Case 'self-review cannot be enabled by the synthetic fixture switch' {
    $f=New-Fixture;Set-FixtureReview $f;$f.spec.review.reviewer=$f.spec.review.author
    Reject {Replay $f -Synthetic} 'cannot be self-approved'
}
Case 'accepted-shaped review cannot name another complete semantic operation' {
    $f=New-Fixture;Set-FixtureReview $f;Mutate-Approval $f {param($a)$a.semantic_sha256='0'*64}
    Reject {Replay $f -Synthetic} 'complete source operation differs'
}
foreach($flag in @('application_refusal_preserved','status_message_assertion_preserved','original_reset_preserved','later_campaigns_preserved','no_source_exclusions')){
    Case "independent decision must explicitly retain $flag" {
        $f=New-Fixture;Set-FixtureReview $f;Mutate-Decision $f {param($d)$d[$flag]=$false}
        Reject {Replay $f -Synthetic} 'retain every application/status/campaign obligation'
    }
}
Case 'review flags must be real booleans' {
    $f=New-Fixture;Set-FixtureReview $f;Mutate-Decision $f {param($d)$d.application_refusal_preserved='true'}
    Reject {Replay $f -Synthetic} 'retain every application/status/campaign obligation'
}
Case 'source approval cannot claim whole-file runtime acceptance' {
    $f=New-Fixture;Set-FixtureReview $f;Mutate-Approval $f {param($a)$a.runtime_acceptance=$true}
    Reject {Replay $f -Synthetic} 'cannot supply runtime acceptance'
}
Case 'review narrative hash must identify the actual reviewed bytes' {
    $f=New-Fixture;Set-FixtureReview $f
    [IO.File]::AppendAllText((Join-Path $f.root 'decision.json'),'changed')
    Reject {Replay $f -Synthetic} 'Review file hash differs'
}
Case 'semantic hash ignores JSON object order without losing empty arrays' {
    $f=New-Fixture;$before=Get-ConformanceVerifierSemanticHash $f.spec
    $reordered=[ordered]@{};foreach($key in @($f.spec.Keys|Sort-Object -Descending)){$reordered[$key]=$f.spec[$key]}
    Assert ((Get-ConformanceVerifierSemanticHash $reordered) -ceq $before) 'Object ordering changed semantic identity'
    $reordered.excluded_obligations=$null
    Assert ((Get-ConformanceVerifierSemanticHash $reordered) -cne $before) 'Null and explicit empty exclusions collapsed'
}
Write-Output "PASS: $script:cases verifier-equivalent source/security regressions; memory reconstruction and synthetic review fixtures only, no adapted file write or Lua execution"
