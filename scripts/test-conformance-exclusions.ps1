param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
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
    $approval = [ordered]@{schema_version=1;kind='t-exclusion-approval';
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

Case 'reviewed T-private exclusion stays separate from a pass' {
    # A bound source decision can discharge only the authorized target. Its
    # original record remains pending and its exclusion has no execution data.
    $f = New-Fixture
    $result = Invoke-Fixture $f
    Assert-True ($result.status -ceq 'excluded' -and @($result.evidence).Count -eq 0) 'Exclusion became a pass'
    Assert-True ($f.record.status -ceq 'pending') 'Original ledger record changed'
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
    $strict = Test-ConformanceInventory -Root $root
    $target = Test-ConformanceInventory -Root $root -TargetPolicy remaining-upstream-compatibility
    Assert-True ($target.SourceAnchors -eq $strict.SourceAnchors -and
        $target.PendingSourceAnchors -eq $strict.PendingSourceAnchors -and
        $target.ExcludedSourceObligations -eq 0) 'Target overlay changed original inventory'
    Assert-True (-not $target.Complete -and -not $target.TargetComplete) 'Foundation claimed completion'
    Assert-Rejected { Test-ConformanceInventory -Root $root -RequireComplete `
        -TargetPolicy remaining-upstream-compatibility } 'Unresolved coverage'
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

Write-Output "PASS: $script:Cases focused conformance exclusion tests"
exit 0
