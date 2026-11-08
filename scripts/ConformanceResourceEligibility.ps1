# Private functions are dot-sourced into ConformanceInventory's module scope.
# They reuse its byte scanner, reviewed-file resolver and immutable baseline.
# No policy data, reviewer identity or execution evidence is installed here.
function Assert-ConformanceResourceDomain {
    param([string]$Source,[Collections.IDictionary]$Record,[int]$Version)
    foreach($row in @(Get-ConformanceResourceRegistry|Where-Object source -CEQ $Source)){
        $start=[long]$Record.byte_offset;$end=$start+[long]$Record.byte_length
        foreach($protected in @($row.retained_materialization,$row.protected_optimized)){
            if($start -lt $protected.byte_offset+$protected.byte_length -and $end -gt $protected.byte_offset){
                throw 'V4 public materialization and optimized zero-allocation bytes cannot be excluded'
            }
        }
        if($start -lt $row.byte_offset+$row.byte_length -and $end -gt $row.byte_offset -and $Version -ne 4){
            throw 'Pinned observable resource comparison requires V4 eligibility'
        }
    }
}

function Assert-ConformanceResourceSource {
    param([byte[]]$Bytes,[Collections.IDictionary]$Record,[Collections.IDictionary]$Exclusion)
    $row=@(Get-ConformanceResourceRegistry|Where-Object id -CEQ $Exclusion.id)[0]
    if($Record.kind -cne 'reviewed-block'){throw 'V4 resource must use its exact derived comparison block'}
    if($Exclusion.t_guard -isnot [Collections.IDictionary] -or
        (($Exclusion.t_guard.Keys|Sort-Object)-join '|') -cne (($row.t_guard.Keys|Sort-Object)-join '|')){
        throw 'V4 resource requires its exact pinned top-level T guard'
    }
    foreach($key in $row.t_guard.Keys){
        if(-not $Exclusion.t_guard.Contains($key) -or $Exclusion.t_guard[$key] -cne $row.t_guard[$key]){
            throw 'V4 resource requires its exact pinned top-level T guard'
        }
    }
    # Full source identity and the closed span bind the only assert permitted
    # here. Do not generalize this into a parser for arbitrary private calls.
    if((Get-ConformanceHash $Bytes) -cne $row.source_sha256){throw 'V4 resource source hash differs'}
    foreach($span in @($row.retained_materialization,$row.protected_optimized)){
        $part=[byte[]]::new($span.byte_length)
        [Array]::Copy($Bytes,$span.byte_offset,$part,0,$part.Length)
        if((Get-ConformanceHash $part) -cne $span.anchor_sha256){throw 'V4 retained public source span differs'}
    }
    $anchors=@(Get-ConformanceCoverageUnits -Path $row.source -Bytes $Bytes|Where-Object id -CEQ $row.original_anchor.id)
    if($anchors.Count -ne 1){throw 'V4 original resource anchor is absent'}
    foreach($key in $row.original_anchor.Keys){
        if($anchors[0][$key] -cne $row.original_anchor[$key]){throw 'V4 original resource identity differs'}
    }
}

function Get-ConformanceResourceFeatureSources {
    # Exact current source roles. Neither a review nor a policy can omit the
    # implementation, real provider/checker, primary native context or verifier.
    @('references/lua/manual/manual.of','references/lua/ltests.c','references/lua/ltm.c','references/lua/ltable.c',
      'src/lua-engine.ads','src/lua-engine.adb','src/lua-engine-canonical.adb','src/lua-canonical_compiler.adb',
      'src/lua-engine-machine.adb','src/lua-engine-stacks.ads','src/lua-engine-stacks.adb','src/lua-engine-tables.adb',
      'src/lua-engine-collector.adb','src/lua-engine-foreign.adb','src/lua-storage.adb','src/lua-storage-vectors.adb',
      'tests/src/lua-conformance_adapter.adb','tests/c/conformance_adapter.c',
      'tests/src/lua-conformance_allocator.adb','tests/src/lua-conformance_memory.adb',
      'scripts/ConformanceExclusionEligibility.psm1','scripts/ConformanceInventory.psm1',
      'scripts/ConformanceResourceEligibility.ps1','scripts/ConformanceTransforms.psm1')
}

function Assert-ConformanceResourceReviews {
    param([string]$Root,[Collections.IDictionary]$Exclusion,[Collections.IDictionary]$Decision,
        [Collections.IDictionary]$Approval,[switch]$AllowSyntheticReview)
    function Source-Only($value){
        if(-not $value.Contains('schema_version') -or
            ($value.schema_version -isnot [int] -and $value.schema_version -isnot [long]) -or
            $value.schema_version -ne 4){throw 'V4 source review schema must be integer four'}
        foreach($flag in @('runtime_acceptance','coverage_authority','source_adaptation_authority')){
            if(-not $value.Contains($flag) -or $value[$flag] -isnot [bool] -or $value[$flag]){
                throw 'V4 source review cannot grant runtime, coverage or adaptation authority'
            }
        }
        if($value.Contains('synthetic_fixture') -and
            ($value.synthetic_fixture -isnot [bool] -or ($value.synthetic_fixture -and -not $AllowSyntheticReview))){
            throw 'V4 actual target cannot use synthetic review authority'
        }
        foreach($field in @('execution_evidence','source_exclusions')){
            if(-not $value.Contains($field) -or $value[$field] -isnot [Array] -or $value[$field].Count){
                throw 'V4 source review cannot invent execution evidence or another source waiver'
            }
        }
    }
    function Bindings($bindings,$expected){
        if($bindings -isnot [Array] -or (($bindings.path|Sort-Object)-join '|') -cne (($expected|Sort-Object)-join '|') -or
            @($bindings.path|Sort-Object -Unique).Count -ne $expected.Count){throw 'V4 exact current source binding set differs'}
        foreach($binding in $bindings){[void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)}
    }
    $row=@(Get-ConformanceResourceRegistry|Where-Object id -CEQ $Exclusion.id)[0]
    Source-Only $Approval;Source-Only $Decision
    if($Decision.schema_version -ne 4 -or $Decision.kind -cne 't-private-resource-exclusion-review'){
        throw 'V4 resource lacks independent exact source narrative'
    }
    $feature=Get-Content (Resolve-ReviewedFile -Root $Root -Path $Exclusion.feature_review.path -Sha256 $Exclusion.feature_review.sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $retention=Get-Content (Resolve-ReviewedFile -Root $Root -Path $Exclusion.semantic_retention_review.path -Sha256 $Exclusion.semantic_retention_review.sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    foreach($review in @($feature,$retention)){
        Source-Only $review
        if([string]::IsNullOrWhiteSpace($review.author) -or [string]::IsNullOrWhiteSpace($review.reviewer) -or
            $review.author -ceq $review.reviewer -or $review.reviewer -ceq $Exclusion.review.author -or
            $review.reference_revision -cne $script:ReferenceRevision -or
            $review.source.path -cne 'references/lua/testes/memerr.lua' -or $review.source.sha256 -cne $row.source_sha256){
            throw 'V4 review identity, source or independence differs'
        }
        if($review.candidate -isnot [Collections.IDictionary] -or
            (($review.candidate.Keys|Sort-Object)-join '|') -cne 'anchor_sha256|byte_length|byte_offset|id'){
            throw 'V4 exact review candidate fields differ'
        }
        foreach($key in @('byte_offset','byte_length')){
            if($review.candidate[$key] -isnot [int] -and $review.candidate[$key] -isnot [long]){
                throw 'V4 reviewed candidate source numbers must be integral'
            }
        }
        foreach($key in @('id','byte_offset','byte_length','anchor_sha256')){
            if($review.candidate[$key] -cne $row[$key]){throw 'V4 reviewed resource candidate widened or changed'}
        }
    }
    if($feature.schema_version -ne 4 -or $feature.kind -cne 't-private-resource-feature-review' -or
        $feature.decision -cne 'accepted-feature-only-with-required-counterparts' -or $feature.configuration -cne 'upstream-test' -or
        $feature.public_api -isnot [bool] -or $feature.public_api -or
        $feature.mixed_obligation -isnot [bool] -or $feature.mixed_obligation -or
        $feature.module_observable -isnot [bool] -or -not $feature.module_observable -or
        $feature.module_compatibility_obligation -isnot [bool] -or $feature.module_compatibility_obligation -or
        $feature.no_public_positive_allocation_guarantee -isnot [bool] -or -not $feature.no_public_positive_allocation_guarantee -or
        [string]::IsNullOrWhiteSpace($feature.rationale)){
        throw 'V4 feature cannot hide resource visibility or waive public allocation behavior'
    }
    Bindings $feature.source_bindings @(Get-ConformanceResourceFeatureSources)
    $sources=@('tests/lua/materialized_vararg.lua','tests/lua/materialized_vararg_refusal.lua',
        'tests/src/lua-materialized_vararg_tests.ads','tests/src/lua-materialized_vararg_tests.adb')
    if($retention.schema_version -ne 4 -or $retention.kind -cne 't-private-resource-semantic-retention-review' -or
        $retention.decision -cne 'accepted-source-retention-contract-only' -or
        $retention.required_semantic_contract_ids -isnot [Array] -or
        (($retention.required_semantic_contract_ids|Sort-Object)-join '|') -cne (($row.required_semantic_contract_ids|Sort-Object)-join '|') -or
        $retention.actual_provider_refusal_required -isnot [bool] -or -not $retention.actual_provider_refusal_required -or
        $retention.T_absence_is_failure -isnot [bool] -or -not $retention.T_absence_is_failure -or
        $retention.positive_allocation_count_is_not_asserted -isnot [bool] -or -not $retention.positive_allocation_count_is_not_asserted){
        throw 'V4 requires all public and real-provider fault retention contracts'
    }
    foreach($key in $row.protected_optimized.Keys){
        if($retention.protected_optimized[$key] -cne $row.protected_optimized[$key]){throw 'V4 optimized result32/count0/byte0 source must remain unchanged'}
    }
    foreach($key in $row.retained_materialization.Keys){
        if($retention.retained_materialization[$key] -cne $row.retained_materialization[$key]){throw 'V4 actual five-argument materialization must remain required'}
    }
    Bindings $retention.witness_sources $sources
}

function Assert-ConformanceResourceParentRecords {
    param([byte[]]$Bytes,[Collections.IDictionary]$Exclusion,[Collections.IDictionary]$Records,[Collections.IDictionary]$Exclusions)
    $row=@(Get-ConformanceResourceRegistry|Where-Object id -CEQ $Exclusion.id)[0]
    $anchor=$row.original_anchor;$public=$row.retained_materialization
    if(-not $Records.Contains($anchor.id) -or $Exclusions.Contains($anchor.id) -or
        -not $Records.Contains($public.id) -or $Exclusions.Contains($public.id)){
        throw 'V4 original anchor and required materialization runtime child must remain'
    }
    foreach($entry in @(@{actual=$Records[$anchor.id];expected=$anchor},@{actual=$Records[$public.id];expected=$public})){
        foreach($key in $entry.expected.Keys){if($entry.actual[$key] -cne $entry.expected[$key]){throw 'V4 retained original or runtime source identity changed'}}
    }
    if($Records[$public.id].kind -cne 'reviewed-block'){throw 'V4 materialization child must retain actual workload bytes'}
    foreach($other in $Exclusions.Values){
        if($other.source -cne $row.source){continue}
        Assert-ConformanceResourceDomain -Source $row.source -Record $other -Version (Get-ConformanceExclusionEligibilityVersion $other)
    }
    # Preserve every original optimized anchor, not only the final comparison.
    $optimized=@(Get-ConformanceCoverageUnits -Path $row.source -Bytes $Bytes|Where-Object{
        $_.byte_offset -ge $row.protected_optimized.byte_offset -and
        $_.byte_offset+ $_.byte_length -le $row.protected_optimized.byte_offset+$row.protected_optimized.byte_length})
    foreach($original in $optimized){
        if(-not $Records.Contains($original.id) -or $Exclusions.Contains($original.id)){throw 'V4 optimized public obligations cannot disappear or be excluded'}
        foreach($key in @('kind','byte_offset','byte_length','anchor_sha256')){
            if($Records[$original.id][$key] -cne $original[$key]){throw 'V4 optimized original identity changed'}
        }
    }
    $record=$Records[$anchor.id]
    if($record.status -ceq 'passed' -or @($record.evidence).Count){throw 'V4 a previously passing original cannot become a private exclusion'}
    if($record.status -ceq 'pending'){return}
    if($record.status -cne 'reviewed' -or $record.classification -cne 'reference' -or
        $record.obligations -isnot [Array] -or $Exclusion.id -cnotin $record.obligations -or $public.id -cnotin $record.obligations){
        throw 'V4 original reference requires exact private and public-runtime child linkage'
    }
}
