param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceExclusionEligibility.psm1')
$utf8 = [Text.UTF8Encoding]::new($false)
$temporary = Join-Path $root ('reports/exclusion-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:Cases = 0
$protectedScopes = (Get-Content -LiteralPath (Join-Path $root `
    'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 32).protected_scopes

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Rejected {
    param([scriptblock] $Action, [string] $Expected)
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message) 'Invalid exclusion unexpectedly passed'
    Assert-True ($message -match $Expected) "Wrong failure: $message; expected $Expected"
}

function Case {
    param([string] $Name, [scriptblock] $Action)
    & $Action
    $script:Cases++
    Write-Output "EXCLUSION TEST PASS: $Name"
}

function Write-Json {
    param([string] $Path, [object] $Value)
    $json = (ConvertTo-Json -InputObject $Value -Depth 32).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($Path, $json + "`n", $utf8)
}

function Set-Approval {
    param([Collections.IDictionary] $Fixture)
    # These disposable author/reviewer fixtures exercise the verifier. They
    # never install an exclusion or claim review of an upstream obligation.
    $exclusion = $Fixture.exclusion
    $approved = [ordered]@{}
    foreach ($key in $exclusion.Keys) { if ($key -cne 'review') { $approved[$key] = $exclusion[$key] } }
    $narrativePath = if ($Fixture.Contains('review_prefix')) { $Fixture.review_prefix + '/narrative.json' } else { 'narrative.json' }
    $approval = [ordered]@{schema_version=(Get-ConformanceExclusionEligibilityVersion $exclusion);kind='t-exclusion-approval';
        target='remaining-upstream-compatibility';
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        protected_scopes=$protectedScopes;
        author=$exclusion.review.author;reviewer=$exclusion.review.reviewer;decision='accepted';
        exclusion=$approved;review_evidence=@{path=$narrativePath;
            sha256=(Get-FileHash -LiteralPath (Join-Path $Fixture.root 'narrative.json')).Hash.ToLowerInvariant()}}
    Write-Json (Join-Path $Fixture.root 'approval.json') $approval
    $exclusion.review.artifact_sha256 = (Get-FileHash -LiteralPath (Join-Path $Fixture.root 'approval.json')).Hash.ToLowerInvariant()
}

function New-Fixture {
    param([string] $Text = "if T then`n  assert(T.checkmemory())`nend`n",
          [string] $Mode = 'positive-guard', [int] $GuardStart = 0, [int] $GuardLength = -1)
    $directory = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    $scopeDirectory = Join-Path $directory 'tests/conformance/scopes'
    [void][IO.Directory]::CreateDirectory($scopeDirectory)
    foreach ($identity in $protectedScopes) {
        Copy-Item -LiteralPath (Join-Path $root $identity.path) -Destination $scopeDirectory
    }
    $bytes = $utf8.GetBytes($Text)
    $record = @(Get-ConformanceCoverageUnits -Path 'sample.lua' -Bytes $bytes |
        Where-Object { $_.kind -ceq 'assert-call' })[0]
    if ($GuardLength -lt 0) { $GuardLength = $bytes.Length - $GuardStart }
    $guardBytes = [byte[]]::new($GuardLength)
    [Array]::Copy($bytes, $GuardStart, $guardBytes, 0, $GuardLength)
    $exclusion = [ordered]@{id=$record.id;source='sample.lua';source_sha256=(Get-ConformanceHash $bytes);
        byte_offset=$record.byte_offset;byte_length=$record.byte_length;anchor_sha256=$record.anchor_sha256;
        status='excluded';disposition='reviewed-t-internal-exclusion';configurations=@('upstream-test');
        eligibility='t-only-private-invariant';public_api=$false;mixed_obligation=$false;module_observable=$false;
        invariant='The C-private collector topology is checked';
        third_party_irrelevance='Public collector behavior has separate required runtime tests';
        t_guard=@{mode=$Mode;byte_offset=$GuardStart;byte_length=$GuardLength;sha256=(Get-ConformanceHash $guardBytes)};
        evidence=@();review=@{status='accepted';author='fixture-author';reviewer='fixture-reviewer';
            artifact='approval.json';artifact_sha256=('0'*64)}}
    $fixture = @{root=$directory;source='sample.lua';bytes=$bytes;record=$record;exclusion=$exclusion}
    Write-Json (Join-Path $directory 'narrative.json') @{reviewer='fixture-reviewer';
        exclusion_id=$record.id;decision='accepted';t_dominance='Original control flow reviewed';
        private_invariant='Only private collector topology is tested';
        third_party_irrelevance='No observable module contract is waived'}
    Set-Approval $fixture
    return $fixture
}

function Invoke-Fixture {
    param([Collections.IDictionary] $Fixture)
    Test-ConformanceTargetExclusion -Root $Fixture.root -Source $Fixture.source `
        -SourceBytes $Fixture.bytes -Record $Fixture.record -Exclusion $Fixture.exclusion
}

function Set-V2BoundFixture {
    param([Collections.IDictionary] $Fixture,[Collections.IDictionary] $Parent)
    # Synthetic reviewers test the new source/feature binding. This helper
    # installs nothing in the repository's actual policy or source ledger.
    $e=$Fixture.exclusion;$e.eligibility_schema_version=2;$e.module_observable=$true
    $e.module_compatibility_obligation=$false;$e.observation_kind='private-resource-bound';$e.retained_parent=$Parent
    foreach($relative in @('references/lua/manual/manual.of','c_api/tests/load_dump_contract.h')){
        $destination=Join-Path $Fixture.root $relative;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination
    }
    $manual=[IO.File]::ReadAllBytes((Join-Path $root 'references/lua/manual/manual.of'))
    Write-Json (Join-Path $Fixture.root 'narrative.json') @{schema_version=2;kind='t-private-bound-feature-review';reviewer='fixture-reviewer';
        exclusion_id=$e.id;decision='accepted';t_dominance='Synthetic source guard binding';private_invariant='Synthetic exact implementation-bound child';
        third_party_irrelevance='Synthetic source-review fixture, never feature approval';feature_review=@{
            module_observable=$true;module_compatibility_obligation=$false;observation_kind='private-resource-bound';retained_parent_id=$Parent.id;
            no_public_bound_guarantee=$true;rationale='Fixture binding only; visible physical resource counts do not by themselves define a portable bound';
            retained_behaviors=@('positive growth','application execution','allocation-refusal cleanup and reader lifetime');
            public_contract_source=@{path='references/lua/manual/manual.of';source_sha256=(Get-ConformanceHash $manual);
                byte_offset=0;byte_length=$manual.Length;anchor_sha256=(Get-ConformanceHash $manual)};
            counterpart_source_bindings=@(@{path='c_api/tests/load_dump_contract.h';sha256=(Get-FileHash (Join-Path $root 'c_api/tests/load_dump_contract.h')).Hash.ToLowerInvariant()})}}
    Set-Approval $Fixture
}

function New-V2Fixture {
    param([string]$Guard='T',[string]$Private=' and m2 - m1 < 400')
    $whole='assert(m2 > m1'+$Private+')';$text="if $Guard then`n  $whole`nend`n"
    $f=New-Fixture -Text $text;$private=$Private
    $parent=@{id=$f.record.id;byte_offset=$text.IndexOf($whole);byte_length=$whole.Length;anchor_sha256=(Get-ConformanceHash ($utf8.GetBytes($whole)))}
    $record=@{id='LUA-SAMPLE-REVIEWED-BLOCK-9001';kind='reviewed-block';status='pending';disposition='pending';evidence=@();
        byte_offset=$text.IndexOf($private);byte_length=$private.Length;anchor_sha256=(Get-ConformanceHash ($utf8.GetBytes($private)))}
    $f.record=$record;foreach($key in @('id','byte_offset','byte_length','anchor_sha256')){$f.exclusion[$key]=$record[$key]}
    Set-V2BoundFixture $f $parent
    return $f
}

Case 'reviewed T-private exclusion stays separate from a pass' {
    # A bound source decision can discharge only the authorized target. Its
    # original record remains pending and its exclusion has no execution data.
    $f = New-Fixture
    $result = Invoke-Fixture $f
    Assert-True ($result.status -ceq 'excluded' -and @($result.evidence).Count -eq 0) 'Exclusion became a pass'
    Assert-True ($f.record.status -ceq 'pending') 'Original ledger record changed'
}

Case 'v2 records visible private GC thresholds without claiming a module compatibility promise' {
    $f=New-V2Fixture;$result=Invoke-Fixture $f
    Assert-True ($result.module_observable -and -not $result.module_compatibility_obligation -and
        $result.eligibility_schema_version -eq 2 -and $f.record.status -ceq 'pending' -and $result.evidence.Count -eq 0) 'Visible measurement became a public waiver or a pass'
}
Case 'v2 ordinary Lua cannot borrow a private resource threshold decision' {
    $f=New-V2Fixture -Guard ordinary
    Assert-Rejected {Invoke-Fixture $f} 'not inside its positive T guard'
}
Case 'v2 public API mixed and promised module behavior remain ineligible' {
    foreach($field in @('public_api','mixed_obligation','module_compatibility_obligation')){
        $f=New-V2Fixture;$f.exclusion[$field]=$true
        Assert-Rejected {Invoke-Fixture $f} 'without public or mixed behavior'
    }
    $f=New-V2Fixture;$f.exclusion.module_compatibility_obligation='false'
    Assert-Rejected {Invoke-Fixture $f} 'without public or mixed behavior'
}
Case 'v2 a fabricated private label cannot hide an application or public API call' {
    foreach($private in @(' and collectgarbage("count") < 400',' and public_operation() < 400',' and m2 < 400 or public_flag == 1')){
        $f=New-V2Fixture -Private $private
        Assert-Rejected {Invoke-Fixture $f} 'pure comparison|cannot remove a public'
    }
}
Case 'v2 cannot widen a child into the complete mixed parent assertion' {
    $f=New-V2Fixture;$parent=$f.exclusion.retained_parent
    foreach($key in @('byte_offset','byte_length','anchor_sha256')){$f.record[$key]=$parent[$key];$f.exclusion[$key]=$parent[$key]}
    Assert-Rejected {Invoke-Fixture $f} 'derived child inside'
}
Case 'v2 requires bound independent feature relevance beyond a generic private rationale' {
    $f=New-V2Fixture;$n=Get-Content (Join-Path $f.root 'narrative.json') -Raw|ConvertFrom-Json -AsHashtable
    [void]$n.Remove('feature_review');Write-Json (Join-Path $f.root 'narrative.json') $n;Set-Approval $f
    Assert-Rejected {Invoke-Fixture $f} 'explicit independent feature review'
    foreach($field in @('module_compatibility_obligation','no_public_bound_guarantee')){
        $f=New-V2Fixture;$n=Get-Content (Join-Path $f.root 'narrative.json') -Raw|ConvertFrom-Json -AsHashtable
        $n.feature_review[$field]=($field -ceq 'module_compatibility_obligation')
        Write-Json (Join-Path $f.root 'narrative.json') $n;Set-Approval $f
        Assert-Rejected {Invoke-Fixture $f} 'explicit independent feature relevance'
    }
}
Case 'v2 feature decisions bind the real pinned contract span and retained counterpart source' {
    foreach($change in @('fake-contract','changed-span','missing-counterpart','changed-counterpart')){
        $f=New-V2Fixture;$n=Get-Content (Join-Path $f.root 'narrative.json') -Raw|ConvertFrom-Json -AsHashtable
        switch($change){
            fake-contract{$n.feature_review.public_contract_source.path='narrative.json'}
            changed-span{$n.feature_review.public_contract_source.anchor_sha256='0'*64}
            missing-counterpart{$n.feature_review.counterpart_source_bindings=@()}
            changed-counterpart{$n.feature_review.counterpart_source_bindings[0].sha256='0'*64}
        }
        Write-Json (Join-Path $f.root 'narrative.json') $n;Set-Approval $f
        Assert-Rejected {Invoke-Fixture $f} 'pinned public contract|source span hash|counterpart source bindings|Review file hash differs'
    }
}
Case 'v2 eligibility cannot inherit approval after compatibility fields or parent bindings change' {
    $f=New-V2Fixture;$f.exclusion.module_observable=$false
    Assert-Rejected {Invoke-Fixture $f} 'approved semantics differ'
    $f=New-V2Fixture;$f.exclusion.retained_parent.anchor_sha256='0'*64
    Assert-Rejected {Invoke-Fixture $f} 'retained parent source hash'
    $f=New-V2Fixture;$f.exclusion.eligibility_schema_version=3
    Assert-Rejected {Invoke-Fixture $f} 'Unsupported exclusion eligibility'
    $f=New-V2Fixture;$f.exclusion.review.reviewer=$f.exclusion.review.author
    Assert-Rejected {Invoke-Fixture $f} 'accepted independent review'
}
Case 'v2 private resolution cannot stand in for the retained mixed parent runtime obligation' {
    # Fabricated record states exercise source-link restrictions only.
    $f=New-V2Fixture;$bound=$f.exclusion.retained_parent
    $parent=@{id=$bound.id;kind='assert-call';status='pending';byte_offset=$bound.byte_offset;byte_length=6;configurations=@('upstream-test')}
    $records=@{};$records[$parent.id]=$parent;$records[$f.record.id]=$f.record
    $exclusions=@{};$exclusions[$f.record.id]=$f.exclusion
    $check={& (Get-Module ConformanceInventory) {param($e,$r,$x) Assert-ConformancePrivateBoundParentRecord -Exclusion $e -Records $r -Exclusions $x} $f.exclusion $records $exclusions}
    &$check
    $parent.status='reviewed';$parent.classification='reference';$parent.obligations=@($f.record.id)
    Assert-Rejected $check 'separately retained public runtime'
    $public=@{id='LUA-SAMPLE-REVIEWED-BLOCK-9002';kind='reviewed-block';status='pending';
        byte_offset=$bound.byte_offset+7;byte_length=7;configurations=@('upstream-test')}
    $records[$public.id]=$public;$parent.obligations+=@($public.id);&$check
    $resolved=@{};$resolved[$f.record.id]=Invoke-Fixture $f
    Assert-Rejected {Test-ConformanceSourceLinks @($parent,$f.record,$public) -RequireComplete -TargetPolicy remaining-upstream-compatibility -ResolvedExclusions $resolved} 'Linked runtime obligation remains pending'
    $parent.status='passed';$parent.disposition='unchanged';$parent.source_exclusion_ids=@($f.record.id)
    Assert-Rejected $check 'own executed reviewed-equivalent evidence'
    $parent.disposition='ada-internal-equivalent';$parent.source_exclusion_ids=@()
    Assert-Rejected $check 'own executed reviewed-equivalent evidence'
    $exclusions[$parent.id]=$f.exclusion
    Assert-Rejected $check 'parent cannot be absent or excluded'
}

Case 'nested T guard keeps the original block boundary' {
    # Nested Lua blocks do not end the enclosing T guard. Literal keywords in
    # strings are data, and loop do/end pairs contribute one nested block.
    $f = New-Fixture -Text "if T then`n for i=1,2 do if i>0 then assert(T.checkmemory('end')) end end`nend`n"
    Invoke-Fixture $f | Out-Null
}

Case 'outer else branch cannot borrow positive T eligibility' {
    $f = New-Fixture -Text "if T then print('private') else assert(public()) end`n"
    Assert-Rejected { Invoke-Fixture $f } 'cannot include outer alternatives'
}

Case 'outer elseif branch cannot borrow positive T eligibility' {
    $f = New-Fixture -Text "if T then print('private') elseif ordinary then assert(public()) end`n"
    Assert-Rejected { Invoke-Fixture $f } 'cannot include outer alternatives'
}

Case 'nested alternatives remain inside the positive T arm' {
    $f = New-Fixture -Text "if T then if choice then print('private') elseif other then print('other') else assert(T.checkmemory()) end end`n"
    Invoke-Fixture $f | Out-Null
}

Case 'T-absent top-level return can establish file suffix applicability' {
    # api/code/memerr use this original shape. The return itself does not
    # certify the excluded body or execute its omitted assertion.
    $text = "if T==nil then print('not active') return end`nassert(T.checkmemory())`n"
    $length = $text.IndexOf('end') + 3
    $f = New-Fixture -Text $text -Mode absent-return -GuardLength $length
    Invoke-Fixture $f | Out-Null
}

Case 'literal not-T return with no report is valid' {
    $text = "if not T then return end`nassert(T.checkmemory())`n"
    $f = New-Fixture -Text $text -Mode absent-return -GuardLength ($text.IndexOf('end') + 3)
    Invoke-Fixture $f | Out-Null
}

Case 'previously passing records cannot be downgraded to exclusions' {
    $f = New-Fixture
    $f.record.status = 'passed'; $f.record.disposition = 'unchanged'
    Assert-Rejected { Invoke-Fixture $f } 'Only pending source runtime'
}

Case 'accepted partitions stay protected after a passed-to-pending downgrade' {
    # Eligibility comes from immutable accepted descriptor hashes, not only
    # today's editable record status. Protect the accepted helper as well.
    foreach ($sourceName in @('tpack.lua','closure.lua','files.lua','bwcoercion.lua')) {
        $f = New-Fixture
        $f.record.status = 'passed'; $f.record.status = 'pending'
        $f.source = $sourceName
        Assert-Rejected { Invoke-Fixture $f } 'Previously accepted source partitions'
    }
}

Case 'missing or changed accepted descriptors cannot bypass protection' {
    $f = New-Fixture
    Remove-Item -LiteralPath (Join-Path $f.root $protectedScopes[0].path)
    Assert-Rejected { Invoke-Fixture $f } 'Protected acceptance descriptor missing or changed'
    $f = New-Fixture
    $path = Join-Path $f.root $protectedScopes[1].path
    [IO.File]::AppendAllText($path, "`n", $utf8)
    Assert-Rejected { Invoke-Fixture $f } 'Protected acceptance descriptor missing or changed'
}

Case 'independent approval binds the immutable accepted descriptor hashes' {
    $f = New-Fixture
    $path = Join-Path $f.root 'approval.json'
    $approval = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    $approval.protected_scopes[0].sha256 = '0'*64
    Write-Json $path $approval
    $f.exclusion.review.artifact_sha256 = (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    Assert-Rejected { Invoke-Fixture $f } 'protected descriptor bindings differ'
}

Case 'public C API entries cannot be excluded' {
    $f = New-Fixture
    $f.record.id = 'CAPI-LUA-H-FUNCTION-LUA_GETTOP-185'; $f.record.kind = 'function'
    Assert-Rejected { Invoke-Fixture $f } 'Only pending source runtime'
}

Case 'guards and whole-file audits cannot themselves become exclusions' {
    foreach ($kind in @('conditional-guard','manual-audit','generated-template','internal-reference')) {
        $f = New-Fixture; $f.record.kind = $kind
        Assert-Rejected { Invoke-Fixture $f } 'Only pending source runtime'
    }
}

Case 'mixed private and public obligations must be split or implemented' {
    $f = New-Fixture; $f.exclusion.mixed_obligation = $true
    Assert-Rejected { Invoke-Fixture $f } 'without public or mixed behavior'
}

Case 'public API and module-visible invariants remain required' {
    foreach ($field in @('public_api','module_observable')) {
        $f = New-Fixture; $f.exclusion[$field] = $true
        Assert-Rejected { Invoke-Fixture $f } 'without public or mixed behavior'
    }
}

Case 'eligibility flags must be real false booleans' {
    $f = New-Fixture; $f.exclusion.public_api = 'false'
    Assert-Rejected { Invoke-Fixture $f } 'without public or mixed behavior'
}

Case 'ordinary default behavior cannot be excluded under the T policy' {
    $f = New-Fixture; $f.exclusion.configurations = @('default','upstream-test')
    Assert-Rejected { Invoke-Fixture $f } 'T-only private invariant'
}

Case 'an ordinary non-T guard cannot establish eligibility' {
    $f = New-Fixture -Text "if ordinary then`n assert(T.checkmemory())`nend`n"
    Assert-Rejected { Invoke-Fixture $f } 'not inside its positive T guard'
}

Case 'a guard cannot extend past its matching end into public behavior' {
    # A forged enlarged span ends in a second end token, but the first end
    # already closed if T. Reject it before a source review can be reused.
    $f = New-Fixture -Text "if T then assert(T.checkmemory()) end`nassert(public())`nend`n"
    Assert-Rejected { Invoke-Fixture $f } 'extends into unguarded behavior'
}

Case 'a quoted pseudo-guard is not source control flow' {
    $text = "local s='if T then assert(T.checkmemory()) end'`nassert(T.checkmemory())`n"
    $start = $text.IndexOf('if T'); $length = $text.IndexOf("'", $start) - $start
    $f = New-Fixture -Text $text -GuardStart $start -GuardLength $length
    Assert-Rejected { Invoke-Fixture $f } 'source token span|Unterminated|not inside'
}

Case 'a conditional return does not dominate a T-only suffix' {
    $text = "if not T then if maybe then return end end`nassert(T.checkmemory())`n"
    $f = New-Fixture -Text $text -Mode absent-return -GuardLength ($text.LastIndexOf('end') + 3)
    Assert-Rejected { Invoke-Fixture $f } 'unconditional return'
}

Case 'a function-local early return cannot gate later top-level tests' {
    $text = "local function f() if not T then return end`nend`nassert(T.checkmemory())`n"
    $start = $text.IndexOf('if not T'); $length = $text.IndexOf('end') + 3 - $start
    $f = New-Fixture -Text $text -Mode absent-return -GuardStart $start -GuardLength $length
    Assert-Rejected { Invoke-Fixture $f } 'must be at source top level'
}

Case 'source and anchor checksums bind the original bytes' {
    foreach ($field in @('source_sha256','anchor_sha256')) {
        $f = New-Fixture; $f.exclusion[$field] = '0'*64
        Assert-Rejected { Invoke-Fixture $f } 'anchor differs|source or disposition differs'
    }
}

Case 'a matching forged anchor is checked against source bytes' {
    $f = New-Fixture; $f.record.anchor_sha256 = '0'*64; $f.exclusion.anchor_sha256 = '0'*64
    Assert-Rejected { Invoke-Fixture $f } 'original span hash differs'
}

Case 'source offset and guard checksums cannot drift' {
    $f = New-Fixture; $f.exclusion.byte_offset++
    Assert-Rejected { Invoke-Fixture $f } 'anchor differs'
    $f = New-Fixture; $f.exclusion.t_guard.sha256 = '0'*64
    Assert-Rejected { Invoke-Fixture $f } 'T guard hash differs'
}

Case 'exclusions cannot carry successful process evidence' {
    foreach ($field in @('record','exclusion')) {
        $f = New-Fixture; $f[$field].evidence = @(@{result='passed'})
        Assert-Rejected { Invoke-Fixture $f } 'cannot contain execution or pass evidence'
    }
}

Case 'exclusion author cannot approve their own decision' {
    $f = New-Fixture; $f.exclusion.review.reviewer = $f.exclusion.review.author
    Assert-Rejected { Invoke-Fixture $f } 'accepted independent review'
}

Case 'stale or absent independent approval bytes are rejected' {
    $f = New-Fixture; $f.exclusion.review.artifact_sha256 = '0'*64
    Assert-Rejected { Invoke-Fixture $f } 'Review file hash differs'
    $f = New-Fixture; $f.exclusion.review.artifact = 'missing.json'
    Assert-Rejected { Invoke-Fixture $f } 'missing or outside repository'
}

Case 'approval cannot be reused after invariant or guard changes' {
    $f = New-Fixture; $f.exclusion.invariant = 'Broadened private invariant'
    Assert-Rejected { Invoke-Fixture $f } 'approved semantics differ'
}

Case 'an approval narrative must explain T dominance and irrelevance' {
    $f = New-Fixture
    Write-Json (Join-Path $f.root 'narrative.json') @{reviewer='fixture-reviewer';exclusion_id=$f.record.id;
        decision='accepted';t_dominance='';private_invariant='private';third_party_irrelevance='reason'}
    Set-Approval $f
    Assert-Rejected { Invoke-Fixture $f } 'lacks rationale'
}

Case 'strict source-link completion never consumes target exclusions' {
    $f = New-Fixture
    $candidate = @{id='LUA-SAMPLE-CONDITIONAL-GUARD-0001';status='reviewed';classification='guard';
        configurations=@('upstream-test');obligations=@($f.record.id)}
    $resolved = @{}; $resolved[$f.record.id] = Invoke-Fixture $f
    Assert-Rejected { Test-ConformanceSourceLinks @($candidate,$f.record) -RequireComplete } 'remains pending'
    Assert-Rejected { Test-ConformanceSourceLinks @($candidate,$f.record) -RequireComplete `
        -ResolvedExclusions $resolved } 'Strict upstream coverage cannot use exclusions'
    Test-ConformanceSourceLinks @($candidate,$f.record) -RequireComplete `
        -TargetPolicy remaining-upstream-compatibility -ResolvedExclusions $resolved
}

Case 'empty authorized policy preserves every pending anchor' {
    # Keep testing the empty-policy contract after a real independently
    # reviewed source-only exclusion exists. Never clear production authority
    # or rewrite original records merely to satisfy a unit-test baseline.
    $inventory=Join-Path $temporary 'empty-policy-inventory'
    [void][IO.Directory]::CreateDirectory((Join-Path $inventory 'targets'))
    foreach($name in @('suite.json','c-api.jsonl','coverage')) {
        Copy-Item -LiteralPath (Join-Path $root "tests/conformance/$name") -Destination $inventory -Recurse
    }
    $policy=Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $policy.exclusions=@()
    Write-Json (Join-Path $inventory 'targets/remaining-upstream-compatibility.exclusions.json') $policy
    $strict = Test-ConformanceInventory -Root $root -InventoryDirectory $inventory
    $target = Test-ConformanceInventory -Root $root -InventoryDirectory $inventory -TargetPolicy remaining-upstream-compatibility
    Assert-True ($target.SourceAnchors -eq $strict.SourceAnchors -and
        $target.PendingSourceAnchors -eq $strict.PendingSourceAnchors -and
        $target.ExcludedSourceObligations -eq 0) 'Target overlay changed original inventory'
    Assert-True (-not $target.Complete -and -not $target.TargetComplete) 'Foundation claimed completion'
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $inventory -RequireComplete `
        -TargetPolicy remaining-upstream-compatibility } 'Unresolved coverage'
}

Case 'installed API feature approval excludes only its derived child and grants no parent or transform pass' {
    # This checks actual committed source metadata and reconstructs bytes in
    # memory only. It neither invokes Lua nor writes an adapted upstream file.
    $strict=Test-ConformanceInventory -Root $root
    $target=Test-ConformanceInventory -Root $root -TargetPolicy remaining-upstream-compatibility
    $parent=@(Read-ConformanceJsonLines (Join-Path $root 'tests/conformance/coverage/api.jsonl')|
        Where-Object id -CEQ 'LUA-API-ASSERT-CALL-0125')
    Assert-True ($parent.Count -eq 1 -and $parent[0].status -ceq 'pending' -and $parent[0].disposition -ceq 'pending' -and
        @($parent[0].evidence).Count -eq 0 -and $target.ExcludedSourceObligations -eq 1 -and
        $target.Exclusions[0].id -ceq 'LUA-API-REVIEWED-BLOCK-9001' -and
        $target.PendingSourceAnchors -eq $strict.PendingSourceAnchors -and
        $target.RequiredPendingSourceAnchors -eq $strict.PendingSourceAnchors-1 -and
        -not $target.TargetComplete -and -not $target.Complete) 'Feature approval discharged an original runtime obligation'
    $base='tests/conformance/targets/remaining-upstream-compatibility'
    $spec=Get-Content (Join-Path $root "$base/api-fixed-buffer-private-bound.transform.json") -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $hash=(Get-FileHash (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json')).Hash.ToLowerInvariant()
    $resolved=@{};$resolved[$target.Exclusions[0].id]=$target.Exclusions[0]
    $pending=$spec|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64
    $pending.review.status='pending'
    Assert-Rejected {Get-ConformanceTReplay -Root $root -Specification $pending -PolicySha256 $hash -ResolvedExclusions $resolved} 'lacks independent semantic approval'
    $replay=Get-ConformanceTReplay -Root $root -Specification $pending -PolicySha256 $hash -ResolvedExclusions $resolved -AllowUnreviewedDiagnostics
    $text=[Text.Encoding]::UTF8.GetString($replay.bytes)
    Assert-True ($replay.diagnostic_only -and $replay.sha256 -ceq '51389bf3404ab2f13ae88a8cc3f88e7188ac0639f77b7871f4c9baf1830492bc' -and
        $text.Contains('assert(m2 > m1)') -and $text.Contains('checkerr(":301:", code)')) 'Pending transform changed retained behavior or acquired acceptance'
    $approved=Get-ConformanceTReplay -Root $root -Specification $spec -PolicySha256 $hash -ResolvedExclusions $resolved
    Assert-True (-not $approved.diagnostic_only -and $approved.sha256 -ceq $replay.sha256 -and
        $parent[0].status -ceq 'pending' -and @($parent[0].evidence).Count -eq 0) 'Exact transform review became runtime evidence'
}

Case 'target overlay resolves one cited obligation without rewriting its ledger' {
    # Copy the complete ledger, append a private-opcode inspection obligation,
    # and approve it only in disposable fixture metadata. This tests the real
    # inventory path without installing an exclusion in the production ledger.
    $sourceBytes = [IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/code.lua'))
    $sourceText = [Text.Encoding]::Latin1.GetString($sourceBytes)
    $start = $sourceText.IndexOf('if T==nil then')
    $length = $sourceText.IndexOf('end', $start) + 3 - $start
    $f = New-Fixture -Text $sourceText -Mode absent-return -GuardStart $start -GuardLength $length
    $f.bytes = $sourceBytes
    $inventory = Join-Path $f.root 'inventory'
    [void][IO.Directory]::CreateDirectory((Join-Path $inventory 'targets'))
    foreach ($name in @('suite.json','c-api.jsonl','coverage')) {
        Copy-Item -LiteralPath (Join-Path $root "tests/conformance/$name") -Destination $inventory -Recurse
    }
    $path = Join-Path $inventory 'coverage/code.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $entry = @(Get-ConformanceCoverageUnits -Path code.lua -Bytes $sourceBytes |
        Where-Object { $_.kind -ceq 'internal-reference' -and
            [Text.Encoding]::Latin1.GetString($sourceBytes,$_.byte_offset,$_.byte_length) -ceq 'T.listcode' })[0]
    $entry.id = 'LUA-CODE-REVIEWED-BLOCK-9999'; $entry.kind = 'reviewed-block'
    Write-ConformanceJsonLines $path (@($records) + @($entry))
    $f.record = $entry
    foreach ($key in @('id','byte_offset','byte_length','anchor_sha256')) { $f.exclusion[$key] = $entry[$key] }
    $f.exclusion.source = 'code.lua'
    $f.review_prefix = [IO.Path]::GetRelativePath($root,$f.root).Replace('\','/')
    $f.exclusion.review.artifact = $f.review_prefix + '/approval.json'
    Write-Json (Join-Path $f.root 'narrative.json') @{reviewer='fixture-reviewer';exclusion_id=$entry.id;
        decision='accepted';t_dominance='The literal top-level absent-T return precedes this source';
        private_invariant='Private optimizer instruction inspection';third_party_irrelevance='Fixture policy only'}
    Set-Approval $f
    $policyPath = Join-Path $inventory 'targets/remaining-upstream-compatibility.exclusions.json'
    $policy = @{schema_version=1;target='remaining-upstream-compatibility';
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        protected_scopes=$protectedScopes;exclusions=@($f.exclusion)}
    Write-Json $policyPath $policy
    $strict = Test-ConformanceInventory -Root $root -InventoryDirectory $inventory
    $target = Test-ConformanceInventory -Root $root -InventoryDirectory $inventory `
        -TargetPolicy remaining-upstream-compatibility
    Assert-True ($target.SourceAnchors -eq $strict.SourceAnchors -and
        $target.PendingSourceAnchors -eq $strict.PendingSourceAnchors -and
        $target.ExcludedSourceObligations -eq 1 -and
        $target.RequiredPendingSourceAnchors -eq $strict.PendingSourceAnchors - 1 -and
        -not $target.Complete -and -not $target.TargetComplete) 'Target resolution rewrote history or claimed completion'
    $stillPending = @(Read-ConformanceJsonLines $path | Where-Object { $_.id -ceq $entry.id })[0]
    Assert-True ($stillPending.status -ceq 'pending' -and @($stillPending.evidence).Count -eq 0) 'Overlay wrote to ledger'
    $policy.exclusions = @($f.exclusion,$f.exclusion); Write-Json $policyPath $policy
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $inventory `
        -TargetPolicy remaining-upstream-compatibility } 'duplicate source exclusion'
}

Case 'a private child of a mixed assertion preserves its original anchor and retained runtime bytes' {
    # Real pinned source spans plus synthetic decisions exercise the schema.
    # No Lua process runs and no production source/exclusion record changes.
    $source='api.lua';$bytes=[IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/api.lua'))
    $text=[Text.Encoding]::Latin1.GetString($bytes)
    $guardStart=$text.IndexOf('if T==nil then');$guardLength=$text.IndexOf('end',$guardStart)+3-$guardStart
    $f=New-Fixture -Text $text -Mode absent-return -GuardStart $guardStart -GuardLength $guardLength
    $whole='assert(m2 > m1 and m2 - m1 < 400)';$private=' and m2 - m1 < 400'
    $parentOffset=$text.IndexOf($whole);$privateOffset=$text.IndexOf($private,$parentOffset)
    Assert-True ($parentOffset -gt 0 -and $privateOffset -gt $parentOffset) 'Pinned mixed assertion changed'
    $inventory=Join-Path $f.root 'inventory';[void][IO.Directory]::CreateDirectory((Join-Path $inventory 'targets'))
    foreach($name in @('suite.json','c-api.jsonl','coverage')){Copy-Item -LiteralPath (Join-Path $root "tests/conformance/$name") -Destination $inventory -Recurse}
    $path=Join-Path $inventory 'coverage/api.jsonl';$records=@(Read-ConformanceJsonLines $path)
    $parent=@($records|Where-Object{$_.kind -ceq 'assert-call' -and $_.byte_offset -eq $parentOffset})[0]
    $parentBefore=ConvertTo-Json $parent -Depth 32 -Compress
    $child=@{id='LUA-API-REVIEWED-BLOCK-9999';kind='reviewed-block';byte_offset=$privateOffset;
        byte_length=$private.Length;anchor_sha256=(Get-ConformanceHash ($utf8.GetBytes($private)));
        line=580;end_line=580;status='pending';disposition='pending';invariant=$null;configurations=@();evidence=@();review=$null}
    Write-ConformanceJsonLines $path (@($records)+@($child))
    $f.source=$source;$f.bytes=$bytes;$f.record=$child
    foreach($key in @('id','byte_offset','byte_length','anchor_sha256')){$f.exclusion[$key]=$child[$key]}
    $f.exclusion.source=$source
    $f.exclusion.invariant='Only the exact C storage optimization allocation upper bound'
    $f.review_prefix=[IO.Path]::GetRelativePath($root,$f.root).Replace('\','/')
    $f.exclusion.review.artifact=$f.review_prefix+'/approval.json'
    Set-V2BoundFixture $f @{id=$parent.id;byte_offset=$parentOffset;byte_length=$whole.Length;anchor_sha256=(Get-ConformanceHash ($utf8.GetBytes($whole)))}
    $policy=@{schema_version=1;target='remaining-upstream-compatibility';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        protected_scopes=$protectedScopes;exclusions=@($f.exclusion)}
    Write-Json (Join-Path $inventory 'targets/remaining-upstream-compatibility.exclusions.json') $policy
    $strict=Test-ConformanceInventory -Root $root -InventoryDirectory $inventory
    $target=Test-ConformanceInventory -Root $root -InventoryDirectory $inventory -TargetPolicy remaining-upstream-compatibility
    $parentAfter=@(Read-ConformanceJsonLines $path|Where-Object id -CEQ $parent.id)[0]
    Assert-True ((ConvertTo-Json $parentAfter -Depth 32 -Compress) -ceq $parentBefore) 'Original mixed assertion anchor was rewritten'
    Assert-True ($target.ExcludedSourceObligations -eq 1 -and $target.PendingSourceAnchors -eq $strict.PendingSourceAnchors -and
        $target.RequiredPendingSourceAnchors -eq $strict.PendingSourceAnchors-1 -and -not $target.Complete -and -not $target.TargetComplete) 'Private child discharged its retained original anchor'
    $change=@{id='private-upper-bound';start_byte=$privateOffset;length_bytes=$private.Length;source_sha256=$child.anchor_sha256;replacement=''}
    $patched=Get-ConformancePatchedBytes -SourceBytes $bytes -Replacements @($change)
    $expected=$text.Remove($privateOffset,$private.Length)
    Assert-True ((Get-ConformanceHash $patched) -ceq (Get-ConformanceHash ($utf8.GetBytes($expected))) -and
        [Text.Encoding]::UTF8.GetString($patched).Contains('assert(m2 > m1)') -and
        [Text.Encoding]::UTF8.GetString($patched).Contains('X = 0; code(); assert(X == N and Y == string.rep("a", N))')) 'Private child altered retained execution bytes'
    $f.exclusion.mixed_obligation=$true
    Assert-Rejected {Test-ConformanceTargetExclusion -Root $root -Source $source -SourceBytes $bytes -Record $child -Exclusion $f.exclusion} 'without public or mixed behavior'
}

Case 'a reviewed split cannot complete while its retained public runtime child is pending' {
    # These are fabricated linked record states, not executed observations.
    $candidate=@{id='LUA-SAMPLE-ASSERT-CALL-0001';kind='assert-call';status='reviewed';classification='reference';
        configurations=@('upstream-test');obligations=@('LUA-SAMPLE-REVIEWED-BLOCK-9001','LUA-SAMPLE-REVIEWED-BLOCK-9002')}
    $private=@{id='LUA-SAMPLE-REVIEWED-BLOCK-9001';kind='reviewed-block';status='pending';configurations=@()}
    $public=@{id='LUA-SAMPLE-REVIEWED-BLOCK-9002';kind='reviewed-block';status='pending';configurations=@('upstream-test')}
    $resolved=@{$private.id=@{configurations=@('upstream-test')}}
    Assert-Rejected {Test-ConformanceSourceLinks @($candidate,$private,$public) -RequireComplete -TargetPolicy remaining-upstream-compatibility -ResolvedExclusions $resolved} 'Linked runtime obligation remains pending'
    $public.status='passed'
    Test-ConformanceSourceLinks @($candidate,$private,$public) -RequireComplete -TargetPolicy remaining-upstream-compatibility -ResolvedExclusions $resolved
    Assert-Rejected {Test-ConformanceSourceLinks @($candidate,$private,$public) -RequireComplete} 'Linked runtime obligation remains pending'
}

Write-Output "PASS: $script:Cases focused conformance exclusion tests"
exit 0
