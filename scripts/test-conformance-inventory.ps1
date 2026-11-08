param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$utf8 = [Text.UTF8Encoding]::new($false)
$source = Join-Path $root 'tests/conformance'
$temporary = Join-Path $root ('reports/inventory-selftest/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary) | Out-Null
$script:Cases = 0

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Rejected {
    param([scriptblock] $Action, [string] $Expected)
    $message = $null
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message) 'Invalid inventory unexpectedly passed'
    Assert-True ($message -match $Expected) "Wrong failure: $message; expected $Expected"
}

function Case {
    param([string] $Name, [scriptblock] $Action)
    & $Action
    $script:Cases++
    Write-Output "INVENTORY TEST PASS: $Name"
}

function Copy-Fixture {
    param([string] $Name)
    $destination = Join-Path $temporary $Name
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'suite.json') -Destination $destination
    Copy-Item -LiteralPath (Join-Path $source 'c-api.jsonl') -Destination $destination
    Copy-Item -LiteralPath (Join-Path $source 'coverage') -Destination $destination -Recurse
    return $destination
}

function Read-Manifest {
    param([string] $Directory)
    Get-Content -LiteralPath (Join-Path $Directory 'suite.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 32
}

function Save-Manifest {
    param([string] $Directory, [object] $Manifest)
    [IO.File]::WriteAllText((Join-Path $Directory 'suite.json'),
        (ConvertTo-Json -InputObject $Manifest -Depth 24) + "`n", $utf8)
}

function New-GitReferenceFixture {
    param([string] $Name)
    $fixture = Join-Path $temporary $Name
    $reference = Join-Path $fixture 'references/lua'
    [IO.Directory]::CreateDirectory($reference) | Out-Null
    [IO.File]::WriteAllText((Join-Path $reference 'sample.c'), "/* original */`n", $utf8)
    & git -c core.fsmonitor=false init --quiet $reference
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create isolated reference fixture' }
    & git -c core.fsmonitor=false -C $reference add sample.c
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage isolated reference fixture' }
    # Hooks/signing are disabled only for this newly created disposable repo.
    # No real reference or user Git configuration is changed by these tests.
    & git -c core.fsmonitor=false -c commit.gpgsign=false -c core.hooksPath=$temporary `
        -c user.name='Inventory Test' -c user.email='inventory@example.invalid' `
        -C $reference commit --quiet -m 'Reference fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot commit isolated reference fixture' }
    $revision = (& git -c core.fsmonitor=false -C $reference rev-parse HEAD).Trim()
    return @{root=$fixture;reference=$reference;revision=$revision}
}

function New-ReviewedCandidate {
    # These small records exercise classification independently of the real
    # ledger. No test ever resolves or changes an upstream pending obligation.
    return @{id='LUA-SAMPLE-CONDITIONAL-GUARD-0001';kind='conditional-guard';status='reviewed';
        disposition='candidate-reviewed';classification='guard';
        invariant='This guard selects the linked runtime block';configurations=@('default');
        obligations=@('LUA-SAMPLE-REVIEWED-BLOCK-0001');evidence=@();
        review=@{author='author';reviewer='reviewer';rationale='Source control flow inspected';artifact='review'}}
}

function New-RuntimeObligation {
    # A real runtime record needs a distinct C observation and concrete Ada
    # evidence, even when a classification merely points at it as a dependency.
    return @{id='LUA-SAMPLE-REVIEWED-BLOCK-0001';kind='reviewed-block';status='passed';
        disposition='unchanged';invariant='The guarded block executes';configurations=@('default');
        review=@{author='author';reviewer='reviewer';rationale='Both results inspected';
            artifact='review';original_c_evidence='original-c-result'};
        evidence=@(@{context='default/windows/validation/static';result='passed';
            revision=('a'*40);artifact='ada-result';case_id='block'})}
}

Case 'pinned foundation is structurally valid, not complete' {
    # The baseline contains every pinned source/header but deliberately has
    # unresolved coverage. A foundation pass must retain those pending totals.
    $result = Test-ConformanceInventory -Root $root
    Assert-True ($result.Files -eq 34 -and $result.PendingSourceAnchors -gt 0) 'Missing pending inventory'
    Assert-True (-not $result.Complete) 'Foundation claimed milestone completion'
}

Case 'completion rejects pending semantic audits' {
    # Final acceptance cannot reuse the weaker foundation mode and silently
    # turn a successful JSON/hash check into a compatibility claim.
    Assert-Rejected { Test-ConformanceInventory -Root $root -RequireComplete } 'Unresolved coverage'
}

Case 'JSONL serialization uses LF and UTF-8 without a BOM' {
    # Regeneration must produce identical bytes on all supported hosts. Two
    # records exercise the inter-record separator and final terminator; a
    # non-ASCII value distinguishes UTF-8 from an accidental legacy encoding.
    $path = Join-Path $temporary 'portable-lines.jsonl'
    Write-ConformanceJsonLines $path @([ordered]@{id='café'}, [ordered]@{id='second'})
    $bytes = [IO.File]::ReadAllBytes($path)
    $expected = '{"id":"café"}' + "`n" + '{"id":"second"}' + "`n"
    Assert-True ([Convert]::ToBase64String($bytes) -ceq
        [Convert]::ToBase64String($utf8.GetBytes($expected))) 'JSONL is not exact LF/BOM-free UTF-8'
    Assert-True (@(Read-ConformanceJsonLines $path).Count -eq 2) 'JSONL records no longer round-trip'
}

Case 'missing source file is rejected' {
    # Removing a troublesome file from the manifest must fail even though the
    # original source remains present in the pinned checkout.
    $fixture = Copy-Fixture 'missing-file'
    $manifest = Read-Manifest $fixture
    $manifest.files = @($manifest.files | Select-Object -Skip 1)
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Missing suite files'
}

Case 'duplicate source file is rejected' {
    # Repetition cannot compensate for an omitted source or create apparent
    # aggregate coverage through a duplicated successful entry.
    $fixture = Copy-Fixture 'duplicate-file'
    $manifest = Read-Manifest $fixture
    $manifest.files = @($manifest.files) + @($manifest.files[0])
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'duplicate suite file'
}

Case 'source checksum drift is rejected' {
    # Deliberately corrupt only tracked inventory metadata; reference source
    # files are never edited by negative tests.
    $fixture = Copy-Fixture 'source-hash'
    $manifest = Read-Manifest $fixture
    $manifest.files[0].sha256 = '0' * 64
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Source hash drift'
}

Case 'orchestrator role cannot become a primary' {
    # The 30 primaries, two helpers, orchestrator and heavy stress case are
    # distinct acceptance roles; changing their labels must not inflate counts.
    $fixture = Copy-Fixture 'role'
    $manifest = Read-Manifest $fixture
    $manifest.files[0].role = 'primary'
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Wrong suite role'
}

Case 'historical M2b evidence cannot be invented' {
    # Only the three previously accepted primary files carry M2b evidence.
    # Copying their result onto api.lua must fail, not broaden history.
    $fixture = Copy-Fixture 'historical-pass'
    $manifest = Read-Manifest $fixture
    $known = @($manifest.files | Where-Object { $_.path -eq 'tpack.lua' })[0]
    $target = @($manifest.files | Where-Object { $_.path -eq 'api.lua' })[0]
    $target.m2b_execution = $known.m2b_execution
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Invented M2b pass'
}

Case 'missing lexical anchor is rejected' {
    # Regeneration discovers omitted assertion/guard candidates independently
    # of the ledger. Deleting one record must leave a detectable mismatch.
    $fixture = Copy-Fixture 'missing-anchor'
    $path = Join-Path $fixture 'coverage/all.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    Write-ConformanceJsonLines $path @($records | Select-Object -Skip 1)
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Coverage anchor set changed'
}

Case 'duplicate source unit IDs are rejected' {
    # A duplicate cannot stand in for a different source obligation.
    $fixture = Copy-Fixture 'duplicate-anchor'
    $path = Join-Path $fixture 'coverage/all.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $records[1].id = $records[0].id
    Write-ConformanceJsonLines $path $records
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'duplicate unit ID'
}

Case 'source anchor hash drift is rejected' {
    # Per-span hashes protect source citations as well as whole-file pins.
    $fixture = Copy-Fixture 'anchor-hash'
    $path = Join-Path $fixture 'coverage/all.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $records[0].anchor_sha256 = '0' * 64
    Write-ConformanceJsonLines $path $records
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Anchor drift'
}

Case 'bare passed status is rejected' {
    # A successful process exit is insufficient evidence for an assertion.
    # A forged status without reviewed disposition must fail closed.
    $fixture = Copy-Fixture 'fake-pass'
    $path = Join-Path $fixture 'coverage/all.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $records[0].status = 'passed'
    Write-ConformanceJsonLines $path $records
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Invalid pass disposition'
}

Case 'equivalent requires review evidence' {
    # Equivalence is an independently reviewed invariant, not a test skip.
    $record = @{id='LUA-SAMPLE-ASSERT-CALL-0001';kind='assert-call';status='passed';
        disposition='ada-internal-equivalent';invariant='A real invariant';
        configurations=@('default');review=$null;evidence=@()}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'Missing independent review'
}

Case 'equivalent requires original C evidence' {
    # A platform exception is justified by the reference implementation's
    # observed limitation; an Ada-only failure must not be reclassified.
    $record = @{id='LUA-SAMPLE-ASSERT-CALL-0001';kind='assert-call';status='passed';
        disposition='native-platform-equivalent';invariant='A real invariant';
        configurations=@('default');review=@{reviewer='reviewer';author='author';rationale='reason';artifact='review';original_c_evidence=''};
        evidence=@()}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'Runtime source lacks original C evidence'
}

Case 'unchanged runtime assertions require original C evidence' {
    # Keeping source unchanged does not prove that the pinned C configuration
    # ran its assertion. Reject an otherwise complete Ada-only evidence record.
    $record = @{id='LUA-SAMPLE-ASSERT-CALL-0001';kind='assert-call';status='passed';
        disposition='unchanged';invariant='The assertion succeeds';configurations=@('default');
        review=@{reviewer='reviewer';author='author';rationale='reason';artifact='review';original_c_evidence=''};
        evidence=@(@{context='default/windows/validation/static';result='passed';
            revision=('a'*40);artifact='ada-result';case_id='assertion'})}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -RequireComplete } 'Runtime source lacks original C evidence'
}

Case 'unchanged runtime assertions retain the reference result' {
    # A legitimate unchanged obligation has both its independently reviewed
    # original C observation and an actual passing target-context result.
    $record = @{id='LUA-SAMPLE-ASSERT-CALL-0001';kind='assert-call';status='passed';
        disposition='unchanged';invariant='The assertion succeeds';configurations=@('default');
        review=@{reviewer='reviewer';author='author';rationale='reason';artifact='review';original_c_evidence='c-result'};
        evidence=@(@{context='default/windows/validation/static';result='passed';
            revision=('a'*40);artifact='ada-result';case_id='assertion'})}
    Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -RequireComplete
}

Case 'inventory reviews are distinct from runtime observations' {
    # A manual audit records the source obligations, rather than an assertion
    # execution. It remains reviewable without fabricating an original C run.
    $record = @{id='LUA-SAMPLE-MANUAL-AUDIT-0001';kind='manual-audit';status='passed';
        disposition='inventory-reviewed';invariant='All source obligations are inventoried';configurations=@('default');
        review=@{reviewer='reviewer';author='author';rationale='reason';artifact='review'};
        evidence=@(@{context='default/windows/validation/static';result='passed';
            revision=('a'*40);artifact='inventory-review';case_id='audit'})}
    Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -RequireComplete
}

Case 'resolved evidence must cover every required context' {
    # One OS/link result is not a complete ABI matrix result.
    $record = @{id='CAPI-SAMPLE';status='passed';evidence=@(@{context='default/windows/validation/static';
        result='passed';revision=('a'*40);artifact='artifact';case_id='case'})}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static','default/linux/validation/static') -Api -RequireComplete } 'Missing default/linux'
}

Case 'duplicate evidence contexts are rejected' {
    # Counting the same successful job twice cannot fill matrix gaps.
    $entry = @{context='default/windows/validation/static';result='passed';revision=('a'*40);artifact='artifact';case_id='case'}
    $record = @{id='CAPI-SAMPLE';status='passed';evidence=@($entry,$entry)}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -Api } 'duplicate pass evidence'
}

Case 'failed evidence cannot justify a pass' {
    # A timeout or failure remains a failed gate, even if a record's status
    # was manually edited to passed.
    $record = @{id='CAPI-SAMPLE';status='passed';evidence=@(@{context='default/windows/validation/static';
        result='timed-out';revision=('a'*40);artifact='artifact';case_id='case'})}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -Api } 'Invalid/duplicate pass evidence'
}

Case 'exported functions cannot use preprocessor absence as pass evidence' {
    # lua_gettop is an active exported function. A preprocessor claim cannot
    # replace a real API call, even if it names every required matrix context.
    $record = @{id='CAPI-LUA-H-FUNCTION-LUA_GETTOP-185';kind='function';conditions=@();
        applicability_review=$null;status='passed';evidence=@(@{context='default/windows/validation/static';
        result='not-applicable';kind='preprocessor';reason='not tested';revision=('a'*40);
        artifact='artifact';case_id='case'})}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -Api -RequireComplete } 'Invalid/duplicate pass evidence'
}

Case 'unconditional macros cannot claim an inactive branch' {
    # Header include guards are excluded from real conditional applicability.
    $record = @{id='CAPI-LUA-H-MACRO-LUA_TNIL-65';kind='macro';conditions=@();
        applicability_review=$null;status='passed';evidence=@(@{context='default/windows/validation/static';
        result='not-applicable';kind='preprocessor';reason='not tested';revision=('a'*40);
        artifact='artifact';case_id='case'})}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -Api } 'Invalid/duplicate pass evidence'
}

Case 'inactive macro branches require independent applicability review' {
    # Conditional source is necessary but insufficient: a compiler-derived
    # definition result must also receive a distinct review before acceptance.
    $record = @{id='CAPI-CONDITIONAL';kind='macro';conditions=@('#if WINDOWS');
        applicability_review=$null;status='passed';evidence=@(@{context='default/windows/validation/static';
        result='not-applicable';kind='preprocessor';reason='inactive';definition_id='CAPI-CONDITIONAL';
        active=$false;revision=('a'*40);artifact='artifact';case_id='case'})}
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -Api } 'Invalid/duplicate pass evidence'
}

Case 'reviewed guard links to a separately executed runtime obligation' {
    # Setup a guard review with no process results and a distinct real block.
    # Both validate in final mode: review of syntax is not reported as execution.
    $candidate = New-ReviewedCandidate
    $runtime = New-RuntimeObligation
    $contexts = @('default/windows/validation/static')
    Test-ConformanceResolvedRecord $candidate $contexts -RequireComplete
    Test-ConformanceResolvedRecord $runtime $contexts -RequireComplete
    Test-ConformanceSourceLinks @($candidate, $runtime) -RequireComplete
}

Case 'inert quoted data is reviewable without invented runtime evidence' {
    # An assert-looking literal can be ordinary data. Only quoted-template
    # candidates may take this reviewed path, and their execution list is empty.
    $candidate = New-ReviewedCandidate
    $candidate.kind = 'generated-template'; $candidate.classification = 'data'
    $candidate.id = 'LUA-SAMPLE-GENERATED-TEMPLATE-0001'; $candidate.obligations = @()
    Test-ConformanceResolvedRecord $candidate @('default/windows/validation/static') -RequireComplete
    Test-ConformanceSourceLinks @($candidate) -RequireComplete
}

Case 'generated assertions require a source-cited runtime block' {
    # A string later passed to load contains dynamic assertions. Link it to
    # an explicitly inventoried block rather than pretending the literal ran.
    $candidate = New-ReviewedCandidate
    $candidate.kind = 'generated-template'; $candidate.classification = 'template'
    $candidate.id = 'LUA-SAMPLE-GENERATED-TEMPLATE-0001'
    Test-ConformanceResolvedRecord $candidate @('default/windows/validation/static') -RequireComplete
    Test-ConformanceSourceLinks @($candidate, (New-RuntimeObligation)) -RequireComplete
}

Case 'foundation review may discover a pending runtime obligation' {
    # Classification can be finished before implementation, but it does not
    # change the target status or manufacture its evidence. Final mode rejects it.
    $candidate = New-ReviewedCandidate
    $runtime = New-RuntimeObligation
    $runtime.status = 'pending'; $runtime.disposition = 'pending'; $runtime.evidence = @()
    Test-ConformanceSourceLinks @($candidate, $runtime)
    Assert-True ($runtime.status -eq 'pending') 'Link validation resolved a pending runtime obligation'
    Assert-Rejected { Test-ConformanceSourceLinks @($candidate, $runtime) -RequireComplete } 'remains pending'
}

Case 'T-absent early return cannot stamp its guard as a runtime pass' {
    # A successful process which returned before the T tests proves no API
    # coverage. Even otherwise valid pass metadata cannot turn the if into a test.
    $record = New-RuntimeObligation
    $record.kind = 'conditional-guard'; $record.id = 'LUA-SAMPLE-CONDITIONAL-GUARD-0001'
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'Lexical candidate cannot claim runtime pass'
}

Case 'non-runtime classifications cannot contain execution evidence' {
    # Classification is a review state. Copying the enclosing file result into
    # it would blur that distinction, so the validator rejects the packet.
    $record = New-ReviewedCandidate
    $record.evidence = (New-RuntimeObligation).evidence
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'Non-runtime candidate has execution evidence'
}

Case 'API entries cannot use non-runtime source review' {
    # Functions/types/macros retain the stricter original API evidence rules;
    # the new source-candidate state must not become an ABI waiver.
    $record = New-ReviewedCandidate
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') -Api } 'Invalid status'
}

Case 'classification requires an independent source reviewer' {
    # The author cannot self-approve an interpretation that removes a runtime
    # candidate. Distinct review identities and an artifact remain mandatory.
    $record = New-ReviewedCandidate
    $record.review.reviewer = $record.review.author
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'independent classification review'
}

Case 'real assert calls cannot be reclassified as inert data' {
    # The data exception belongs to quoted candidates only. A false assertion
    # cannot disappear through a permissive classification label.
    $record = New-ReviewedCandidate
    $record.kind = 'assert-call'; $record.classification = 'data'; $record.obligations = @()
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'Invalid non-runtime classification'
}

Case 'reviewed guards cannot omit the runtime block they control' {
    # False guards are not passing assertions. Their source review must retain
    # the omitted block as a linked obligation with its own execution evidence.
    $record = New-ReviewedCandidate
    $record.obligations = @()
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'runtime obligation links'
}

Case 'duplicate runtime links cannot inflate classification coverage' {
    # Repeating one block is neither independent evidence nor another branch.
    $record = New-ReviewedCandidate
    $record.obligations += $record.obligations[0]
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'duplicate runtime obligation links'
}

Case 'dangling obligation IDs are rejected' {
    # A plausible string is not a real source obligation. Resolve IDs against
    # the containing file before accepting the classification graph.
    $record = New-ReviewedCandidate
    Assert-Rejected { Test-ConformanceSourceLinks @($record) } 'Missing/self runtime obligation link'
}

Case 'self links cannot satisfy guard coverage' {
    # Direct self-reference would let a reviewed candidate certify itself.
    $record = New-ReviewedCandidate
    $record.obligations = @($record.id)
    Assert-Rejected { Test-ConformanceSourceLinks @($record) } 'Missing/self runtime obligation link'
}

Case 'candidate cycles cannot replace executed obligations' {
    # Two reviews pointing at each other still execute nothing. Direct edges
    # may terminate only at actual pending/passed runtime records.
    $first = New-ReviewedCandidate
    $second = New-ReviewedCandidate
    $second.id = 'LUA-SAMPLE-INTERNAL-REFERENCE-0001'; $second.kind = 'internal-reference'
    $second.classification = 'reference'; $second.obligations = @($first.id)
    $first.obligations = @($second.id)
    Assert-Rejected { Test-ConformanceSourceLinks @($first, $second) } 'not a direct runtime obligation'
}

Case 'whole-file review cannot replace runtime evidence' {
    # Bulk stamping every anchor with a whole-file audit is forbidden. The
    # audit inventories obligations and is never itself a runtime block.
    $record = New-ReviewedCandidate
    $audit = New-RuntimeObligation
    $audit.kind = 'manual-audit'; $audit.id = 'LUA-SAMPLE-MANUAL-AUDIT-0001'
    $record.obligations = @($audit.id)
    Assert-Rejected { Test-ConformanceSourceLinks @($record, $audit) } 'not a direct runtime obligation'
}

Case 'runtime links cannot borrow another file result' {
    # Per-file graphs prevent api.lua from inheriting a successful tpack case.
    $record = New-ReviewedCandidate
    $runtime = New-RuntimeObligation
    $runtime.id = 'LUA-OTHER-REVIEWED-BLOCK-0001'; $record.obligations = @($runtime.id)
    Assert-Rejected { Test-ConformanceSourceLinks @($record, $runtime) } 'crosses source file'
}

Case 'generated templates cannot link only to a static call-site token' {
    # Dynamic source needs an expanded semantic block with accurate span/hash,
    # rather than an unrelated assert token which happens to execute nearby.
    $record = New-ReviewedCandidate
    $record.kind = 'generated-template'; $record.classification = 'template'
    $runtime = New-RuntimeObligation; $runtime.kind = 'assert-call'
    Assert-Rejected { Test-ConformanceSourceLinks @($record, $runtime) } 'not a direct runtime obligation'
}

Case 'linked blocks must cover every classified configuration' {
    # Default-only execution cannot resolve an instrumented branch. Preserve
    # the distinct ltests.h configuration even when source spans overlap.
    $record = New-ReviewedCandidate
    $record.configurations = @('default', 'upstream-test')
    Assert-Rejected { Test-ConformanceSourceLinks @($record, (New-RuntimeObligation)) } 'applicability gap'
}

Case 'pending records cannot carry unaudited classifications' {
    # A status typo must not leave classification metadata silently ignored.
    $record = New-ReviewedCandidate
    $record.status = 'pending'; $record.disposition = 'pending'
    Assert-Rejected { Test-ConformanceResolvedRecord $record @('default/windows/validation/static') } 'unreviewed classification'
}

Case 'containing-file validation accepts reviewed links without changing source anchors' {
    # Copy the ledger into ignored test storage. Review its first real guard
    # and add one pending, hash-cited block; the structural pass must preserve
    # pending runtime status and independently verify the original anchor set.
    $fixture = Copy-Fixture 'classified-file'
    $before = Test-ConformanceInventory -Root $root -InventoryDirectory $fixture
    $path = Join-Path $fixture 'coverage/api.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $candidate = @($records | Where-Object { $_.kind -eq 'conditional-guard' })[0]
    $review = New-ReviewedCandidate
    foreach ($field in @('status','disposition','classification','invariant','configurations','review','evidence')) {
        $candidate[$field] = $review[$field]
    }
    $block = $records[0].Clone()
    $block.id = 'LUA-API-REVIEWED-BLOCK-0001'; $block.kind = 'reviewed-block'
    $block.configurations = @('default')
    $candidate.obligations = @($block.id)
    Write-ConformanceJsonLines $path (@($records) + @($block))
    $result = Test-ConformanceInventory -Root $root -InventoryDirectory $fixture
    # One new pending block offsets the guard moved to reviewed status. Other
    # files may gain reviewed blocks without changing this fixture's invariant.
    Assert-True ($result.SourceAnchors -eq ($before.SourceAnchors + 1) -and
        $result.PendingSourceAnchors -eq $before.PendingSourceAnchors) 'Review erased or passed a runtime obligation'
    Assert-True ($block.status -eq 'pending') 'Structural validation executed no runtime test'
}

Case 'containing-file validation rejects a dangling reviewed link' {
    # Correct source hashes alone cannot certify a nonexistent runtime block.
    # Exercise the integrated graph pass after regeneration/span validation.
    $fixture = Copy-Fixture 'classified-missing-block'
    $path = Join-Path $fixture 'coverage/api.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $candidate = @($records | Where-Object { $_.kind -eq 'conditional-guard' })[0]
    $review = New-ReviewedCandidate
    foreach ($field in @('status','disposition','classification','invariant','configurations','review','evidence')) {
        $candidate[$field] = $review[$field]
    }
    $candidate.obligations = @('LUA-API-REVIEWED-BLOCK-0001')
    Write-ConformanceJsonLines $path $records
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Missing/self runtime obligation link'
}

Case 'comments and strings do not create executed assert sites' {
    # Quoted assertions remain template candidates for manual inspection;
    # neither short comments nor literals become actual call-site anchors.
    $text = "-- assert(false)`nlocal s='assert(false)'; assert(true)"
    $units = @(Get-ConformanceCoverageUnits sample.lua ($utf8.GetBytes($text)))
    Assert-True (@($units | Where-Object { $_.kind -eq 'assert-call' }).Count -eq 1) 'False assertion call'
    Assert-True (@($units | Where-Object { $_.kind -eq 'generated-template' }).Count -eq 1) 'Missing quoted candidate'
}

Case 'long delimiter levels keep nested-looking text masked' {
    # A shorter closing delimiter must not terminate a long comment.
    $text = '--[==[ assert(false) ]=] assert(false) ]==] assert(true)'
    $units = @(Get-ConformanceCoverageUnits sample.lua ($utf8.GetBytes($text)))
    Assert-True (@($units | Where-Object { $_.kind -eq 'assert-call' }).Count -eq 1) 'Premature long-comment close'
}

Case 'escaped quotes remain inside short strings' {
    # The escaped quote cannot expose the string's apparent assert text.
    $text = 'local s="escaped\" assert(false)"; assert(true)'
    $units = @(Get-ConformanceCoverageUnits sample.lua ($utf8.GetBytes($text)))
    Assert-True (@($units | Where-Object { $_.kind -eq 'assert-call' }).Count -eq 1) 'Escaped quote exposed literal'
}

Case 'Lua newline pairs count once' {
    # LF, CR, CRLF and LFCR each represent one logical line boundary.
    $text = "-- header`r`nassert(true)`n`rassert(false)`rassert(0)"
    $units = @(Get-ConformanceCoverageUnits sample.lua ($utf8.GetBytes($text)))
    $lines = @($units | Where-Object { $_.kind -eq 'assert-call' } | ForEach-Object line)
    Assert-True (($lines -join ',') -eq '2,3,4') 'Wrong logical source lines'
}

Case 'source anchors use byte offsets for UTF-8' {
    # Inventory offsets must index the original bytes, not UTF-16 characters.
    $prefix = "local s='あ';"
    $units = @(Get-ConformanceCoverageUnits sample.lua ($utf8.GetBytes($prefix + 'assert(true)')))
    $site = @($units | Where-Object { $_.kind -eq 'assert-call' })[0]
    Assert-True ($site.byte_offset -eq $utf8.GetByteCount($prefix)) 'UTF-8 offset was character based'
}

Case 'unterminated long strings are reported' {
    # Malformed helper input is an inventory error, never a partial site list.
    Assert-Rejected { Get-ConformanceTokens ($utf8.GetBytes('[=[assert(true)')) } 'Unterminated long string'
}

Case 'Lua 5.5 C signatures and layouts are inventoried' {
    # In particular, older two-argument lua_newstate bindings and omitted
    # external-string callbacks would miss essential 5.5 API contracts.
    $entries = @(Get-ConformanceApiInventory -Root $root)
    $newstate = @($entries | Where-Object { $_.name -eq 'lua_newstate' })[0]
    Assert-True ($newstate.declaration -match 'unsigned seed') 'Missing seeded state signature'
    Assert-True (@($entries | Where-Object { $_.name -eq 'lua_pushexternalstring' }).Count -eq 1) 'Missing external strings'
    Assert-True (@($entries | Where-Object { $_.kind -eq 'function' }).Count -eq 156) 'Missing exported declarations'
    Assert-True (@($entries | Where-Object { $_.name -eq 'lua_ident' -and $_.kind -eq 'data' }).Count -eq 1) 'Missing exported data'
    Assert-True (@($entries | Where-Object { $_.name -eq 'luaL_Buffer' -and $_.declaration -match 'LUAI_MAXALIGN' }).Count -eq 1) 'Missing concrete buffer layout'
}

Case 'missing C header entry is rejected' {
    # Header discovery independently regenerates all declarations/macros/types.
    $fixture = Copy-Fixture 'missing-api'
    $path = Join-Path $fixture 'c-api.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    Write-ConformanceJsonLines $path @($records | Select-Object -Skip 1)
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'C API anchor set changed'
}

Case 'C signature metadata drift is rejected' {
    # Replacing a seeded signature with a familiar older version must fail
    # even while the original header's whole-file hash is still correct.
    $fixture = Copy-Fixture 'api-signature'
    $path = Join-Path $fixture 'c-api.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $entry = @($records | Where-Object { $_.name -eq 'lua_newstate' })[0]
    $entry.declaration = 'lua_State *lua_newstate(lua_Alloc f, void *ud);'
    Write-ConformanceJsonLines $path $records
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'C API anchor drift'
}

Case 'matrix contexts cannot silently be substituted' {
    # A second Linux entry cannot replace a Windows static-PIC requirement.
    $fixture = Copy-Fixture 'contexts'
    $manifest = Read-Manifest $fixture
    $manifest.acceptance_contexts[25] = 'default/linux/release/static-pic'
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Acceptance context set changed'
}

Case 'instrumented and default configurations stay distinct' {
    # ltests.h intentionally changes semantics/ABI. A manifest may not relabel
    # its zero global-compatibility setting as the production default.
    $fixture = Copy-Fixture 'configuration'
    $manifest = Read-Manifest $fixture
    $manifest.configurations[0].lua_compat_global = 0
    Save-Manifest $fixture $manifest
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Configuration drift'
}

Case 'manual source blocks retain accurate file and line citations' {
    # Semantic review may add obligations, but a fabricated line number cannot
    # pass merely because its byte hash points somewhere in the right file.
    $fixture = Copy-Fixture 'manual-line'
    $path = Join-Path $fixture 'coverage/all.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $entry = $records[1].Clone()
    $entry.id = 'LUA-ALL-REVIEWED-BLOCK-0001'
    $entry.kind = 'reviewed-block'
    $entry.line = 99999
    Write-ConformanceJsonLines $path (@($records) + @($entry))
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Manual block source line drift'
}

Case 'manual blocks cannot borrow a different file ID' {
    # Stable IDs identify one containing source file, not an arbitrary label.
    $fixture = Copy-Fixture 'manual-file'
    $path = Join-Path $fixture 'coverage/all.jsonl'
    $records = @(Read-ConformanceJsonLines $path)
    $entry = $records[1].Clone()
    $entry.id = 'LUA-API-REVIEWED-BLOCK-0001'
    $entry.kind = 'reviewed-block'
    Write-ConformanceJsonLines $path (@($records) + @($entry))
    Assert-Rejected { Test-ConformanceInventory -Root $root -InventoryDirectory $fixture } 'Invalid manually expanded source block'
}

Case 'unstaged reference edits invalidate the pin' {
    # This changes a disposable miniature Git repository, never Lua's tree.
    $fixture = New-GitReferenceFixture 'reference-unstaged'
    Test-ConformanceReferenceTree -Root $fixture.root -ExpectedRevision $fixture.revision
    [IO.File]::WriteAllText((Join-Path $fixture.reference 'sample.c'), "/* changed */`n", $utf8)
    Assert-Rejected { Test-ConformanceReferenceTree -Root $fixture.root -ExpectedRevision $fixture.revision } 'Tracked reference tree differs'
}

Case 'staged reference edits also invalidate the pin' {
    # HEAD comparison must inspect the index too; an empty unstaged diff alone
    # does not prove that the compiler reads pinned source bytes.
    $fixture = New-GitReferenceFixture 'reference-staged'
    [IO.File]::WriteAllText((Join-Path $fixture.reference 'sample.c'), "/* staged */`n", $utf8)
    & git -c core.fsmonitor=false -C $fixture.reference add sample.c
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage negative fixture edit' }
    Assert-Rejected { Test-ConformanceReferenceTree -Root $fixture.root -ExpectedRevision $fixture.revision } 'Tracked reference tree differs'
}

Case 'untracked ignored reference sources are rejected' {
    # GPR discovery must not pick up a source hidden by ignore rules. Ignore
    # rules themselves are local metadata in this disposable repository.
    $fixture = New-GitReferenceFixture 'reference-untracked'
    [IO.File]::WriteAllText((Join-Path $fixture.reference '.git/info/exclude'), '*.c', $utf8)
    [IO.File]::WriteAllText((Join-Path $fixture.reference 'injected.c'), 'void injected(void) {}', $utf8)
    Assert-Rejected { Test-ConformanceReferenceTree -Root $fixture.root -ExpectedRevision $fixture.revision } 'Untracked reference source input'
}

Case 'untracked non-source test fixtures are rejected' {
    # Native modules and extensionless data are copied as execution inputs.
    # Each boundary has its own clean disposable reference repository; neither
    # can hide behind ignored files or rely on a source-code extension check.
    foreach ($relative in @('testes/libs/extra.so', 'testes/extensionless')) {
        $fixture = New-GitReferenceFixture ('reference-fixture-' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText((Join-Path $fixture.reference '.git/info/exclude'), '*.so', $utf8)
        $path = Join-Path $fixture.reference $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        [IO.File]::WriteAllText($path, 'untracked fixture input', $utf8)
        Assert-Rejected { Test-ConformanceReferenceTree -Root $fixture.root -ExpectedRevision $fixture.revision } 'Untracked reference fixture input'
    }
}

Case 'unrelated root build artifacts do not become fixture inputs' {
    # An ordinary non-source artifact outside the copied test subtree is not
    # an execution input. Keep that allowance narrow while guarding fixtures.
    $fixture = New-GitReferenceFixture 'reference-root-artifact'
    [IO.File]::WriteAllText((Join-Path $fixture.reference 'build.log'), 'build observation', $utf8)
    Test-ConformanceReferenceTree -Root $fixture.root -ExpectedRevision $fixture.revision
}

Write-Output "PASS: $script:Cases focused conformance inventory tests"
& (Join-Path $PSScriptRoot 'test-conformance-exclusions.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Conformance exclusion regressions failed' }
exit 0
