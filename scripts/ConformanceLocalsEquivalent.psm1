Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
$script:LocalsSource='references/lua/testes/locals.lua'
$script:LocalsHash='56b5126c40f48bb1a701f041af28cd72a3a7d50b3db9b05da5659f2485f740c1'
$script:LocalsFeature='tests/conformance/targets/remaining-upstream-compatibility/reviews/locals-dead-table-storage.independent-feature-review.json'
$script:LocalsFeatureHash='110246c59dbb2765133b718b24aa3256cd7457b5286fa4a0878b6a152a812f91'
$script:LocalsOutput='54481f4b2c760ef1f8efd747706a3e6eb02553f582e15210aaaab6ec72c448d8'
$script:LocalsCounterparts=@(
    'tests/lua/table_storage_public.lua','tests/lua/table_storage_private.lua',
    'tests/src/lua-conformance_adapter.ads','tests/src/lua-conformance_adapter.adb',
    'tests/src/lua-engine-table_storage_probe.ads','tests/src/lua-engine-table_storage_probe.adb',
    'tests/src/lua-table_storage_inspection_tests.adb','tests/src/table_storage_public_tests.adb',
    'src/lua-engine-collector.adb','src/lua-engine-tables.adb','src/lua-engine.ads',$script:LocalsFeature,
    'src/lua-engine.adb','references/lua/manual/manual.of',
    'src/lua-engine-machine.adb','src/lua-engine-stacks.adb',
    'src/lua-engine-canonical.adb','src/lua-canonical_compiler.adb',
    'tests/src/lua-table_storage_inspection_tests.ads','tests/src/table_storage_public_tests.ads',
    'scripts/ConformanceLocalsEquivalent.psm1','scripts/ConformanceReviewedSources.psm1')
$script:LocalsClosingCounterparts=@(
    'tests/src/lua-conformance_memory.adb','tests/lua/scalar_closing_refusal.lua',
    'tests/lua/scalar_closing_mutation.lua',
    'tests/src/lua-scalar_closing_tests.ads','tests/src/lua-scalar_closing_tests.adb',
    'tests/src/lua-closing_prefix_tests.adb','tests/src/lua-execution_retirement_tests.adb',
    'src/lua-engine-stacks.ads','src/lua-engine-canonical.ads','src/lua-engine-machine.ads',
    'tests/src/lua-conformance_memory.ads','tests/src/lua-closing_prefix_tests.ads',
    'tests/src/lua-execution_retirement_tests.ads','tests/src/lua-storage-conformance.ads',
    'tests/src/lua-storage-conformance.adb','tests/src/lua-conformance_allocator.ads',
    'tests/src/lua-conformance_allocator.adb')

function Get-LocalsCounterpartBindingVersion {
    param([Collections.IDictionary]$Snapshot)
    # V1 is the original22-path source contract. Closing metadata changes add
    # a real checker dependency and its fault/root regressions; select that
    # closed39-path successor explicitly instead of widening old metadata.
    # Its boundary includes the actual checker/allocator controls, declaration
    # interfaces and public/fault/root regressions used by the new close walk.
    # Shared compiler/storage/AUnit infrastructure is still bound by final
    # compiled-image evidence; this list is no independent runtime acceptance.
    if(-not $Snapshot.Contains('binding_schema_version')){return 1}
    if(($Snapshot.binding_schema_version -isnot [int] -and $Snapshot.binding_schema_version -isnot [long]) -or
        $Snapshot.binding_schema_version -ne 2){throw 'Unsupported locals counterpart binding schema version'}
    return 2
}

function Get-LocalsCounterpartSnapshotHash {
    param([Collections.IDictionary]$Snapshot)
    $lines=[string[]]@($Snapshot.bindings|ForEach-Object{$_.path+'|'+$_.sha256})
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $pending=if($Snapshot.pending_owner_guard_and_resetCI_changes_not_included){'1'}else{'0'}
    $payload=$Snapshot.repository_revision+"`n"+$pending+"`n"+($lines -join "`n")+"`n"
    return Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes($payload))
}

function Assert-LocalsSourceOnlyFlags {
    param([Collections.IDictionary]$Record,[switch]$ActualReview)
    foreach($flag in @('runtime_acceptance','coverage_authority')){
        if(-not $Record.Contains($flag) -or $Record[$flag] -isnot [bool] -or $Record[$flag]){
            throw 'Locals source-only definition or review cannot supply runtime authority'
        }
    }
    if($ActualReview -and (-not $Record.Contains('synthetic_fixture') -or
        $Record.synthetic_fixture -isnot [bool] -or $Record.synthetic_fixture)){
        throw 'Locals replay requires actual nonsynthetic independent source review'
    }
    if($Record.Contains('synthetic_fixture') -and
        ($Record.synthetic_fixture -isnot [bool] -or $Record.synthetic_fixture)){
        throw 'Synthetic locals metadata cannot authorize source replay'
    }
    if(-not $Record.Contains('execution_evidence') -or $Record.execution_evidence -isnot [Array] -or
        $Record.execution_evidence.Count -ne 0){throw 'Locals source definition/review must retain empty execution evidence'}
    if($Record.Contains('source_exclusions') -and
        ($Record.source_exclusions -isnot [Array] -or $Record.source_exclusions.Count -ne 0)){
        throw 'Locals source-only definition/review cannot introduce an exclusion'
    }
}

function Assert-TargetLocalsTableEquivalentDefinition {
    param([Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][Collections.IDictionary]$Specification,
        [string]$Implementation='Ada',[string]$Configuration='upstream-test')
    # This definition-only path returns hashes/metadata, never source bytes or
    # approval. Authors can test exact pending claims without emitting a Lua
    # file or manufacturing an accepted review in order to exercise guards.
    if($Implementation -cne 'Ada' -or $Configuration -cne 'upstream-test'){
        throw 'Locals equivalent is instrumented Ada only; native/default retain original source'
    }
    $fields=@('schema_version','kind','id','target','reference_revision','source','source_sha256',
        'configuration','disposition','runtime_acceptance','coverage_authority','execution_evidence',
        'source_exclusions','original_required_obligations','feature_review','counterpart_source_snapshot',
        'replacements','output_sha256','review','integration_status','synthetic_fixture','draft_provenance')
    if(@($Specification.Keys).Count -ne $fields.Count -or
        @($fields|Where-Object{-not $Specification.Contains($_)}).Count -ne 0 -or
        ($Specification.schema_version -isnot [int] -and $Specification.schema_version -isnot [long]) -or
        $Specification.schema_version -ne 1 -or $Specification.kind -cne 'target-source-equivalent' -or
        $Specification.id -cne 'locals-dead-table-storage' -or
        $Specification.target -cne 'remaining-upstream-compatibility' -or
        $Specification.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $Specification.source -cne $script:LocalsSource -or $Specification.source_sha256 -cne $script:LocalsHash -or
        $Specification.configuration -cne $Configuration -or $Specification.disposition -cne 'ada-internal-equivalent' -or
        $Specification.source_exclusions -isnot [Array] -or $Specification.source_exclusions.Count -ne 0 -or
        $Specification.original_required_obligations -isnot [Array] -or
        ($Specification.original_required_obligations -join '|') -cne
          'LUA-LOCALS-INTERNAL-REFERENCE-0001|LUA-LOCALS-ASSERT-CALL-0023' -or
        $Specification.replacements -isnot [Array] -or $Specification.replacements.Count -ne 2){
        throw 'Unsupported, widened or incomplete locals equivalent definition'
    }
    Assert-LocalsSourceOnlyFlags $Specification
    if($Specification.review.author -cne 'Codex /root' -or
        $Specification.draft_provenance.author -cne 'Codex /root' -or
        $Specification.draft_provenance.revision_author -cne 'Codex /root/remaining_suite' -or
        $Specification.draft_provenance.original_draft_sha256 -cne
          '332c372e6c1e0a6b1660bf678141972e6c12164b0d5db46b8835469711598d85'){
        throw 'Locals definition cannot rename or hide its original/revision authors'
    }
    if($Specification.feature_review.path -cne $script:LocalsFeature -or
        $Specification.feature_review.sha256 -cne $script:LocalsFeatureHash){
        throw 'Locals equivalent lacks its exact independent feature snapshot'
    }
    $feature=Get-Content (Resolve-ReviewedFile -Root $Root -Path $script:LocalsFeature -Sha256 $script:LocalsFeatureHash) -Raw|
        ConvertFrom-Json -AsHashtable -Depth 64
    if($feature.kind -cne 't-equivalent-feature-review' -or $feature.candidate_id -cne $Specification.id -or
        $feature.decision -cne 'accepted-feature-only' -or $feature.permitted_resolution -cne 'ada-internal-equivalent' -or
        $feature.source.path -cne $script:LocalsSource -or $feature.source.sha256 -cne $script:LocalsHash -or
        $feature.configuration -cne $Configuration -or $feature.author -ceq $feature.reviewer -or
        $feature.authorizes_exact_source_transform -or $feature.authorizes_runtime_equivalence -or
        $feature.authorizes_ledger_resolution -or @($feature.source_exclusions).Count){
        throw 'Locals feature snapshot does not retain the independent feature-only decision'
    }
    $bounds=@(
        @('observe-original-object-key-and-live-entries',2355,26,
          '04035d9ee038af9e7f37506bbf2f8c5ae6917c7ecd8de5a99c5205551cd00bc6',
          'b75d7d1f14fd6c90f85b1c90658a1d1eca36aa717ef34d049c669d758a89c0ed'),
        @('inspect-deleted-table-storage-and-key-reclamation',2490,110,
          '00b85ae4732a06e844c82cd987ba31de93c22d726a4cbd18f3914cf8fde5f628',
          '42c9256c7ee4e7a32c95c7e01682cd837e7d287cfbd3b8482b721d738e781518'))
    $snapshot=$Specification.counterpart_source_snapshot
    $bindingVersion=Get-LocalsCounterpartBindingVersion $snapshot
    $counterparts=@($script:LocalsCounterparts)
    if($bindingVersion -eq 2){$counterparts+=@($script:LocalsClosingCounterparts)}
    $counterparts=@($counterparts|Sort-Object)
    foreach($bound in $bounds){
        $patch=@($Specification.replacements|Where-Object id -CEQ $bound[0])
        if($patch.Count -ne 1 -or
            ($patch[0].start_byte -isnot [int] -and $patch[0].start_byte -isnot [long]) -or
            ($patch[0].length_bytes -isnot [int] -and $patch[0].length_bytes -isnot [long]) -or
            $patch[0].start_byte -ne $bound[1] -or
            $patch[0].length_bytes -ne $bound[2] -or $patch[0].source_sha256 -cne $bound[3] -or
            $patch[0].replacement -isnot [string] -or
            (Get-ConformanceHash ([Text.UTF8Encoding]::new($false,$true).GetBytes($patch[0].replacement))) -cne $bound[4] -or
            [string]::IsNullOrWhiteSpace([string]$patch[0].invariant) -or
            $patch[0].counterpart_tests -isnot [Array] -or
            (@($patch[0].counterpart_tests|Sort-Object)-join '|') -cne ($counterparts-join '|')){
            throw 'Locals equivalent differs from the two exact retained operations or counterpart set'
        }
    }
    $snapshotFields=@('repository_revision','bindings','pending_owner_guard_and_resetCI_changes_not_included')
    if($bindingVersion -eq 2){$snapshotFields+='binding_schema_version'}
    if(@($snapshot.Keys).Count -ne $snapshotFields.Count -or
        @($snapshotFields|
            Where-Object{-not $snapshot.Contains($_)}).Count -ne 0 -or
        $snapshot.repository_revision -cnotmatch '^[0-9a-f]{40}$' -or
        $snapshot.bindings -isnot [Array] -or
        $snapshot.pending_owner_guard_and_resetCI_changes_not_included -isnot [bool] -or
        (@($snapshot.bindings.path|Sort-Object)-join '|') -cne ($counterparts-join '|')){
        throw 'Locals counterpart snapshot is incomplete, duplicated or lacks its pending-change label'
    }
    foreach($binding in $snapshot.bindings){
        [void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)
    }
    # Hash the proposed output incrementally. No reconstructed Lua program is
    # returned, stored or executed by this pending-author definition check.
    $source=[IO.File]::ReadAllBytes((Resolve-ReviewedFile -Root $Root -Path $script:LocalsSource -Sha256 $script:LocalsHash))
    $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    $cursor=0
    try{
        foreach($patch in ($Specification.replacements|Sort-Object start_byte)){
            $slice=[byte[]]::new($patch.length_bytes)
            [Array]::Copy($source,$patch.start_byte,$slice,0,$slice.Length)
            if((Get-ConformanceHash $slice) -cne $patch.source_sha256){throw 'Locals original span hash differs'}
            $hash.AppendData($source,$cursor,$patch.start_byte-$cursor)
            $hash.AppendData([Text.UTF8Encoding]::new($false,$true).GetBytes($patch.replacement))
            $cursor=$patch.start_byte+$patch.length_bytes
        }
        $hash.AppendData($source,$cursor,$source.Length-$cursor)
        $planned=[Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()
    }finally{$hash.Dispose()}
    if($Specification.output_sha256 -cne $script:LocalsOutput -or $planned -cne $script:LocalsOutput){
        throw 'Locals planned output hash differs from exact retained source'
    }
    return @{id=$Specification.id;planned_sha256=$planned;definition_validated=$true;source_emission=$false;
        counterpart_binding_version=$bindingVersion;counterpart_count=$counterparts.Count;
        diagnostic_only=$true;review_status='not-granted';runtime_acceptance=$false;coverage_authority=$false;
        pending_counterpart_changes=$snapshot.pending_owner_guard_and_resetCI_changes_not_included}
}

function Get-TargetLocalsTableEquivalentReplay {
    param([Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][Collections.IDictionary]$Specification,
        [Parameter(Mandatory)][string]$Implementation,[Parameter(Mandatory)][string]$Configuration)
    if($Implementation -cne 'Ada' -or $Configuration -cne 'upstream-test'){
        throw 'Locals replay requires instrumented Ada; native/default retain original source'
    }
    $review=$Specification.review
    $authors=@($review.author,$Specification.draft_provenance.author,$Specification.draft_provenance.revision_author)
    if($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or
        $review.reviewer -cin $authors){throw 'Locals replay requires a new independent exact source review outside both authors'}
    $bindingVersion=Get-LocalsCounterpartBindingVersion $Specification.counterpart_source_snapshot
    if($bindingVersion -eq 1 -and
        (Get-LocalsCounterpartSnapshotHash $Specification.counterpart_source_snapshot) -cne
          '981f4ceb94d7a272c41f3e2c29f8836c4e8abd351d36f6edf070f5a24ad01f01'){
        throw 'Legacy V1 locals approval is frozen to its dated76 counterpart snapshot; current closing requires explicit binding V2'
    }
    # Inspect source-only review labels before constructing output bytes. A
    # synthetic approval/narrative is a negative-test artifact, never authority
    # to emit the real locals source, even when its other labels say accepted.
    # ConformanceReview exports the full equivalent guard, not its private
    # approval reader. This small preflight checks labels before that guard
    # reconstructs any bytes; the full identity/span/counterpart check still
    # runs below through Get-ConformanceEquivalentReplay.
    $approval=Get-Content (Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256) -Raw|
        ConvertFrom-Json -AsHashtable -Depth 64
    if($approval.schema_version -ne 1 -or $approval.kind -cne 'equivalent-approval' -or
        $approval.decision -cne 'accepted' -or $approval.author -cne $review.author -or
        $approval.reviewer -cne $review.reviewer){throw 'Locals exact source approval identity differs'}
    Assert-LocalsSourceOnlyFlags $approval -ActualReview
    foreach($decision in $approval.decisions){
        $detail=Get-Content (Resolve-ReviewedFile -Root $Root -Path $decision.review_evidence.path -Sha256 $decision.review_evidence.sha256) -Raw|
            ConvertFrom-Json -AsHashtable -Depth 64
        Assert-LocalsSourceOnlyFlags $detail -ActualReview
        if($detail.kind -cne 'equivalent-source-review' -or $detail.decision -cne 'accepted' -or
            $detail.equivalent_id -cne 'locals-dead-table-storage' -or $detail.source -cne $script:LocalsSource -or
            $detail.source_sha256 -cne $script:LocalsHash -or $detail.generated_sha256 -cne $script:LocalsOutput -or
            $detail.configuration -cne 'upstream-test' -or $detail.author -cne $review.author -or
            $detail.reviewer -cne $review.reviewer){throw 'Locals exact narrative belongs to another source, actor or output'}
    }
    [void](Assert-TargetLocalsTableEquivalentDefinition -Root $Root -Specification $Specification `
        -Implementation $Implementation -Configuration $Configuration)
    if($Specification.counterpart_source_snapshot.pending_owner_guard_and_resetCI_changes_not_included){
        throw 'Locals replay still awaits committed owner/resetCI counterpart bindings and exact review'
    }
    $replay=Get-ConformanceEquivalentReplay -Root $Root -Specification $Specification
    $replay['excluded_obligations']=@()
    $replay['original_required_obligations']=@($Specification.original_required_obligations)
    $replay['runtime_acceptance']=$false;$replay['coverage_authority']=$false
    return $replay
}

Export-ModuleMember -Function Assert-TargetLocalsTableEquivalentDefinition,Get-TargetLocalsTableEquivalentReplay
