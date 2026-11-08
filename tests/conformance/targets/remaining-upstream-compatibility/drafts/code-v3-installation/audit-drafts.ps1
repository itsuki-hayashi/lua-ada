param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '../../../../../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Root 'scripts/ConformanceInventory.psm1')
Import-Module (Join-Path $Root 'scripts/ConformanceTransforms.psm1')
Import-Module (Join-Path $Root 'scripts/ConformanceExclusionEligibility.psm1')
$checks = [Collections.Generic.List[string]]::new()
function Read-Json([string]$Name) {
    Get-Content (Join-Path $PSScriptRoot $Name) -Raw | ConvertFrom-Json -AsHashtable -Depth 100
}
function Assert-Draft([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Draft audit failed: $Name" }
    $checks.Add($Name)
}
function Assert-Identity($Identity) {
    Assert-Draft ((Get-FileHash (Join-Path $Root $Identity.path)).Hash.ToLowerInvariant() -ceq $Identity.sha256) $Identity.path
}
function Assert-Rejected([scriptblock]$Action, [string]$Message, [string]$Name) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-Draft ($null -ne $caught -and $caught.Contains($Message, [StringComparison]::Ordinal)) $Name
}
$policy = Read-Json 'code-v3.policy.candidate.json'
$wrapper = Read-Json 'code-v3.policy.draft.json'
$decomposition = Read-Json 'code-v3.decomposition.draft.json'
$requests = Read-Json 'review-requests.json'
$installed = Get-Content (Join-Path $Root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
$code = [IO.File]::ReadAllBytes((Join-Path $Root 'references/lua/testes/code.lua'))
$api = [IO.File]::ReadAllBytes((Join-Path $Root 'references/lua/testes/api.lua'))
$sourceByName = @{'code.lua'=$code; 'api.lua'=$api}
$json = { param($Value) ConvertTo-Json -InputObject $Value -Depth 100 -Compress }
Assert-Identity $wrapper.base_installed_policy
Assert-Identity $wrapper.candidate_payload
Assert-Identity $wrapper.decomposition_draft
Assert-Draft ((& $json $policy.protected_scopes) -ceq (& $json $installed.protected_scopes)) 'protected historical scope bindings unchanged'
Assert-Draft ($policy.exclusions.Count -eq 9 -and $installed.exclusions.Count -eq 1 -and
    (& $json $policy.exclusions[0]) -ceq (& $json $installed.exclusions[0])) 'installed API18 row copied without renewal'
$originals = @(Read-ConformanceJsonLines (Join-Path $Root 'tests/conformance/coverage/code.jsonl'))
Assert-Identity $decomposition.original_ledger
Assert-Draft ($originals.Count -eq 51 -and
    (& $json $originals) -ceq (& $json $decomposition.original_ledger.records_unchanged)) 'all 51 original records preserved exactly'
$children = @($decomposition.private_children_pending)
$public = @($decomposition.required_semantic_nodes_pending)
$records = @($originals) + $children + $public
$byId = @{}
foreach ($record in $records) {
    Assert-Draft (-not $byId.Contains($record.id) -and $record.status -ceq 'pending' -and
        $record.disposition -ceq 'pending' -and @($record.evidence).Count -eq 0) ('pending unique record '+$record.id)
    $byId[$record.id] = $record
    Assert-Draft ((Get-ConformanceHash $code[$record.byte_offset..($record.byte_offset+$record.byte_length-1)]) -ceq $record.anchor_sha256) ('source anchor '+$record.id)
    if ($record.Contains('retained_original_fragments')) {
        foreach ($fragment in $record.retained_original_fragments) {
            Assert-Draft ((Get-ConformanceHash $code[$fragment.byte_offset..($fragment.byte_offset+$fragment.byte_length-1)]) -ceq $fragment.anchor_sha256) ('retained fragment '+$record.id+'/'+$fragment.byte_offset)
        }
    }
}
Assert-Draft ($children.Count -eq 8 -and $public.Count -eq 9 -and
    $decomposition.proposed_original_reference_decompositions.Count -eq 18) 'closed 8 private / 9 public / 18 reference shape'
$derived = @(Read-ConformanceJsonLines (Join-Path $PSScriptRoot 'code-v3.ledger-derived.draft.jsonl'))
Assert-Draft ((& $json $derived) -ceq (& $json @($children+$public))) 'derived ledger contains only the 17 pending additions'
$resolved = @{}
$inventoryModule = Get-Module ConformanceInventory
foreach ($exclusion in $policy.exclusions) {
    $resolved[$exclusion.id] = $exclusion
    if ($exclusion.source -cne 'code.lua') { continue }
    $request = @($requests.approvals | Where-Object id -CEQ $exclusion.id)[0]
    Assert-Identity $request.approval
    Assert-Identity $request.narrative
    $approval = Get-Content (Join-Path $Root $request.approval.path) -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $narrative = Get-Content (Join-Path $Root $request.narrative.path) -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    # This helper validates the real feature/retention input graph only. It
    # does not inspect an exclusion's pending authority and is not approval.
    & $inventoryModule { param($r,$e,$a,$n)
        Assert-ConformanceOptimizerReviews -Root $r -Exclusion $e -Approval $a -Decision $n
    } $Root $exclusion $approval $narrative
    Assert-Draft ($approval.decision -ceq 'pending' -and $null -eq $approval.reviewer -and
        $narrative.decision -ceq 'pending' -and $null -eq $narrative.reviewer) ('independent decision remains pending '+$exclusion.id)
    Assert-Rejected {
        Test-ConformanceTargetExclusion -Root $Root -Source 'code.lua' -SourceBytes $code -Record $byId[$exclusion.id] -Exclusion $exclusion
    } 'Exclusion requires accepted independent review' ('ordinary exclusion reader rejects '+$exclusion.id)
}
foreach ($name in @('code-v3.transform.draft.json','api18.transform.successor.draft.json')) {
    $transform = Read-Json $name
    Assert-Draft ($transform.review.status -ceq 'pending' -and $null -eq $transform.review.reviewer -and
        -not $transform.installed -and -not $transform.source_adaptation_authority -and
        -not $transform.runtime_acceptance -and -not $transform.coverage_authority -and
        $transform.execution_evidence.Count -eq 0) ('no authority in '+$name)
    Assert-Rejected {
        Get-ConformanceTReplay -Root $Root -Specification $transform -PolicySha256 $wrapper.candidate_payload.sha256 -ResolvedExclusions $resolved
    } 'T transform lacks independent semantic approval' ('ordinary transform reader rejects '+$name)
    # Explicit diagnostic mode reconstructs bytes IN MEMORY. No adapted file
    # or interpreter process is created. Its result is still diagnostic_only.
    $memory = Get-ConformanceTReplay -Root $Root -Specification $transform -PolicySha256 $wrapper.candidate_payload.sha256 -ResolvedExclusions $resolved -AllowUnreviewedDiagnostics
    Assert-Draft ($memory.diagnostic_only -and $memory.review_status -ceq 'pending' -and
        $memory.sha256 -ceq $transform.output_sha256) ('exact diagnostic reconstruction '+$name)
    if ($name -ceq 'code-v3.transform.draft.json') {
        $checkR = $code[2079..2205]
        Assert-Draft ((Get-ConformanceHash $checkR) -ceq '324530f639ef49280bcc33a77b56351c3369cdfd13290c63934071985bb880dc' -and
            [Text.Encoding]::Latin1.GetString($memory.bytes).Contains([Text.Encoding]::Latin1.GetString($checkR),[StringComparison]::Ordinal) -and
            $memory.bytes.Length -eq 14299) 'exact checkR retained in 14299-byte memory output'
    } else {
        foreach ($parent in $transform.original_parents) {
            Assert-Draft ($parent.status -ceq 'pending' -and $parent.required -and
                (Get-ConformanceHash $api[$parent.byte_offset..($parent.byte_offset+$parent.byte_length-1)]) -ceq $parent.anchor_sha256) ('API parent retained pending '+$parent.id)
        }
    }
}
$classification = Read-Json 'code-v3.decomposition-approval.draft.json'
foreach ($decision in $classification.decisions) {
    Assert-Rejected {
        Test-ConformanceResolvedRecord -Record $decision.prospective_record -Contexts @('upstream-test/windows/validation/static')
    } 'Missing independent classification review' ('ordinary classification reader rejects '+$decision.original.id)
}
Write-Output "DRAFT AUDIT PASS: $($checks.Count) source/hash/pending-authority checks; no adapted files or runtime executions"
