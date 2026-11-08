Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
$script:ApiBase='1601abc0d700cba2240c123afd513c2bb638e378b7cf11470edbbac8291efce0'
$script:ApiTarget='tests/conformance/targets/remaining-upstream-compatibility/'

function Get-TargetApiCompositeClaims {
    param([Parameter(Mandatory)][Collections.IDictionary]$Specification)
    $claims=[ordered]@{}
    foreach($key in $Specification.Keys){if($key -cne 'review'){$claims[$key]=$Specification[$key]}}
    return $claims
}

function Assert-ApiSourceOnlyReview {
    param([Collections.IDictionary]$Artifact,[switch]$RequireActualLabel,[switch]$AllowSyntheticReview)
    if($RequireActualLabel -and (-not $Artifact.Contains('synthetic_fixture') -or $Artifact.synthetic_fixture -isnot [bool])){
        throw 'API composite source approval lacks an explicit actual/synthetic label'
    }
    $synthetic=$false
    if($Artifact.Contains('synthetic_fixture')){
        if($Artifact.synthetic_fixture -isnot [bool]){throw 'API composite synthetic label must be boolean'}
        $synthetic=$Artifact.synthetic_fixture
    }
    if($synthetic -and -not $AllowSyntheticReview){throw 'Synthetic API composite or component review cannot authorize actual replay'}
    foreach($flag in @('runtime_acceptance','coverage_authority')){
        if(($RequireActualLabel -or $Artifact.Contains($flag)) -and
            (-not $Artifact.Contains($flag) -or $Artifact[$flag] -isnot [bool] -or $Artifact[$flag])){
            throw 'API source composition approval cannot supply runtime acceptance'
        }
    }
    if($Artifact.Contains('execution_evidence') -and @($Artifact.execution_evidence).Count -ne 0){throw 'API source composition cannot consume fabricated execution evidence'}
    return $synthetic
}

function Assert-ApiLifetimeEquivalent {
    param([string]$Root,[Collections.IDictionary]$Mapping)
    $featurePath=$script:ApiTarget+'reviews/api-finalized-userdata-reclamation.independent-feature-review.json'
    if($Mapping.id -cne 'api-finalized-userdata-reclamation' -or $Mapping.disposition -cne 'ada-internal-equivalent' -or
        $Mapping.runtime_acceptance -isnot [bool] -or $Mapping.runtime_acceptance -or
        $Mapping.coverage_authority -isnot [bool] -or $Mapping.coverage_authority -or
        $Mapping.source_exclusions -isnot [Array] -or $Mapping.source_exclusions.Count -ne 0 -or
        (@($Mapping.original_required_obligations)-join '|') -cne 'LUA-API-ASSERT-CALL-0195' -or
        $Mapping.feature_review.path -cne $featurePath -or @($Mapping.replacements).Count -ne 3){
        throw 'API lifetime component is not the bounded reviewed equivalent'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $featurePath -Sha256 $Mapping.feature_review.sha256
    $feature=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if($feature.kind -cne 't-equivalent-feature-review' -or $feature.candidate_id -cne $Mapping.id -or
        $feature.decision -cne 'accepted-feature-only' -or $feature.permitted_resolution -cne 'ada-internal-equivalent' -or
        $feature.configuration -cne 'upstream-test' -or $feature.source.path -cne 'references/lua/testes/api.lua' -or
        $feature.source.sha256 -cne $script:ApiBase -or $feature.original_anchor.id -cne 'LUA-API-ASSERT-CALL-0195' -or
        $feature.runtime_acceptance -isnot [bool] -or $feature.runtime_acceptance -or
        $feature.coverage_authority -isnot [bool] -or $feature.coverage_authority -or
        $feature.source_exclusions -isnot [Array] -or $feature.source_exclusions.Count -ne 0 -or
        ($feature.Contains('synthetic_fixture') -and ($feature.synthetic_fixture -isnot [bool] -or $feature.synthetic_fixture))){
        throw 'API lifetime component lacks its exact independent feature decision'
    }
    # This selector composes only these three reviewed source operations. It
    # is not a new general patch engine: a claimed reviewer cannot move them
    # to another API test or replace their retained lifetime checks with a skip.
    $bounds=@(
        @('observe-real-finalization-identities',26342,92,'e317c746eb09899963ef954a7c055c9586786d38b6d3105bd098aaf924eaaca0','4ea83215dcd39b88d65939f1e31cfe4e2b8511056d4fac64af85f582993b4862'),
        @('retain-first-cycle-resurrection-and-growth',26477,118,'bffa07bc389e6c96386f1726d0164b7cb4b8289659e54fd4fa3491a66390396b','bfb330581234832119aeb09029f3f29374bf5c1a86cf8ea9ba68a3918dd63e4d'),
        @('replace-only-byte-tolerance-with-real-reclamation',26638,38,'24b4ad560648daf4c61aabcc8daed4abc769e3a202dfb754d39fce6e7ded7250','6091003d71d920a9fb2ad7166f3b67a8c4981cd9e66f09f55b6e4816d824a6ae')
    )
    foreach($bound in $bounds){
        $patch=@($Mapping.replacements|Where-Object id -CEQ $bound[0])
        if($patch.Count -ne 1 -or $patch[0].start_byte -ne $bound[1] -or $patch[0].length_bytes -ne $bound[2] -or
            $patch[0].source_sha256 -cne $bound[3] -or
            (Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes($patch[0].replacement))) -cne $bound[4] -or
            $featurePath -cnotin $patch[0].counterpart_tests -or $feature.counterpart_source.path -cnotin $patch[0].counterpart_tests){
            throw 'API lifetime equivalent differs from its bounded original patch and retained checks'
        }
    }
}

function Get-TargetApiCompositeReplay {
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][Collections.IDictionary]$Specification,
          [Parameter(Mandatory)][string]$Implementation,[Parameter(Mandatory)][string]$Configuration,
          [Parameter(Mandatory)][string]$PolicySha256,
          [Parameter(Mandatory)][Collections.IDictionary]$ResolvedExclusions,
          [switch]$AllowSyntheticReview)
    $fields=@('schema_version','kind','id','target','reference_revision','implementation','configuration','source','source_sha256',
        'composition','components','exclusion_policy_sha256','source_exclusion_ids','original_required_obligations','output_sha256',
        'runtime_acceptance','coverage_authority','synthetic_fixture','review','integration_status')
    if(@($Specification.Keys).Count -ne $fields.Count -or @($fields|Where-Object{-not $Specification.Contains($_)}).Count -ne 0 -or
        ($Specification.schema_version -isnot [int] -and $Specification.schema_version -isnot [long]) -or
        $Specification.schema_version -ne 1 -or $Specification.kind -cne 'target-api-source-composite' -or
        $Specification.id -cne 'api-private-bound-and-userdata-lifetimes' -or $Specification.target -cne 'remaining-upstream-compatibility' -or
        $Specification.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $Implementation -cne 'Ada' -or $Configuration -cne 'upstream-test' -or
        $Specification.implementation -cne $Implementation -or $Specification.configuration -cne $Configuration -or
        $Specification.source -cne 'references/lua/testes/api.lua' -or $Specification.source_sha256 -cne $script:ApiBase -or
        $Specification.composition -cne 'union-disjoint-original-byte-spans' -or $PolicySha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Specification.exclusion_policy_sha256 -cne $PolicySha256 -or $Specification.components -isnot [Array] -or $Specification.components.Count -ne 2 -or
        $Specification.source_exclusion_ids -isnot [Array] -or (@($Specification.source_exclusion_ids)-join '|') -cne 'LUA-API-REVIEWED-BLOCK-9001' -or
        $Specification.original_required_obligations -isnot [Array] -or
        (@($Specification.original_required_obligations)-join '|') -cne 'LUA-API-ASSERT-CALL-0125|LUA-API-ASSERT-CALL-0195'){
        throw 'Invalid bounded API composite identity/configuration/policy or required operation set'
    }
    $synthetic=Assert-ApiSourceOnlyReview -Artifact $Specification -RequireActualLabel -AllowSyntheticReview:$AllowSyntheticReview
    $review=$Specification.review
    if($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$review.author) -or
        [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer){
        throw 'API composite requires separate independent exact composition review'
    }
    $approvalPath=Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval=Get-Content -LiteralPath $approvalPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $synthetic=(Assert-ApiSourceOnlyReview -Artifact $approval -RequireActualLabel -AllowSyntheticReview:$AllowSyntheticReview) -or $synthetic
    $claimsHash=Get-TargetWitnessPayloadHash (Get-TargetApiCompositeClaims $Specification)
    if(($approval.schema_version -isnot [int] -and $approval.schema_version -isnot [long]) -or
        $approval.schema_version -ne 1 -or $approval.kind -cne 'target-api-source-composite-approval' -or
        $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or $approval.decision -cne 'accepted' -or
        $approval.composite_id -cne $Specification.id -or $approval.claims_sha256 -cne $claimsHash){throw 'API composite independent exact claims differ'}
    $narrativePath=Resolve-ReviewedFile -Root $Root -Path $approval.review_evidence.path -Sha256 $approval.review_evidence.sha256
    $narrative=Get-Content -LiteralPath $narrativePath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $synthetic=(Assert-ApiSourceOnlyReview -Artifact $narrative -RequireActualLabel -AllowSyntheticReview:$AllowSyntheticReview) -or $synthetic
    if(($narrative.schema_version -isnot [int] -and $narrative.schema_version -isnot [long]) -or $narrative.schema_version -ne 1 -or
        $narrative.kind -cne 'target-api-source-composite-review' -or $narrative.reviewer -cne $review.reviewer -or
        $narrative.decision -cne 'accepted' -or $narrative.composite_id -cne $Specification.id -or $narrative.claims_sha256 -cne $claimsHash){
        throw 'API composite independent source narrative differs'
    }
    foreach($flag in @('component_reviews_preserved','original_obligations_retained','exact_source_exclusions','disjoint_original_coordinates')){
        if($narrative[$flag] -isnot [bool] -or -not $narrative[$flag]){throw 'API composite narrative does not preserve all source authorities'}
    }
    $sourcePath=Resolve-ReviewedFile -Root $Root -Path $Specification.source -Sha256 $script:ApiBase
    $sourceBytes=[IO.File]::ReadAllBytes($sourcePath)
    $policyPath=Resolve-ReviewedFile -Root $Root -Path 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json' -Sha256 $PolicySha256
    $policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if($policy.schema_version -ne 1 -or $policy.target -cne 'remaining-upstream-compatibility' -or
        $policy.reference_revision -cne $Specification.reference_revision){throw 'API composite actual exclusion policy identity differs'}
    $apiExclusions=@($policy.exclusions|Where-Object source -CEQ api.lua)
    $resolvedApi=@($ResolvedExclusions.Values|Where-Object source -CEQ api.lua)
    if($apiExclusions.Count -ne 1 -or $apiExclusions[0].id -cne 'LUA-API-REVIEWED-BLOCK-9001' -or
        $resolvedApi.Count -ne 1 -or -not $ResolvedExclusions.Contains('LUA-API-REVIEWED-BLOCK-9001') -or
        (Get-TargetWitnessPayloadHash $resolvedApi[0]) -cne (Get-TargetWitnessPayloadHash $apiExclusions[0])){
        throw 'API composite must preserve exactly its actual reviewed source exclusion'
    }
    $records=@(Read-ConformanceJsonLines (Join-Path $Root 'tests/conformance/coverage/api.jsonl'))
    foreach($pair in @(@('LUA-API-ASSERT-CALL-0125',17039),@('LUA-API-ASSERT-CALL-0195',26638))){
        $record=@($records|Where-Object id -CEQ $pair[0])
        if($record.Count -ne 1 -or $record[0].kind -cne 'assert-call' -or $record[0].byte_offset -ne $pair[1] -or
            $record[0].byte_length -ne 6 -or $record[0].anchor_sha256 -cne '25450689bdd44d014020b238021b313431cb1f7a86f24e29cecbd1e442edae0a'){
            throw 'API composite cannot remove or downgrade an original required anchor'
        }
    }
    $child=@($records|Where-Object id -CEQ 'LUA-API-REVIEWED-BLOCK-9001')
    if($child.Count -ne 1){throw 'API composite original private child ledger record missing or duplicate'}
    $null=Test-ConformanceTargetExclusion -Root $Root -Source api.lua -SourceBytes $sourceBytes -Record $child[0] -Exclusion $apiExclusions[0]
    $seen=@{};$patches=@();$parts=@();$excluded=@()
    foreach($part in $Specification.components){
        if($part -isnot [Collections.IDictionary] -or (@($part.Keys|Sort-Object)-join '|') -cne 'kind|manifest|output_sha256' -or
            $part.manifest -isnot [Collections.IDictionary] -or (@($part.manifest.Keys|Sort-Object)-join '|') -cne 'path|sha256' -or
            $part.kind -cnotin @('t-private','equivalent') -or $seen.ContainsKey($part.kind) -or
            $part.manifest.path -cnotmatch '^tests/conformance/targets/remaining-upstream-compatibility/[a-z0-9.-]+\.json$'){
            throw 'API composite components are missing duplicated or outside the target source directory'
        }
        $seen[$part.kind]=$true
        $path=Resolve-ReviewedFile -Root $Root -Path $part.manifest.path -Sha256 $part.manifest.sha256
        $mapping=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        if($mapping.source -cne $Specification.source -or $mapping.source_sha256 -cne $script:ApiBase -or $mapping.configuration -cne 'upstream-test'){
            throw 'API composite component does not use the same pinned original source/configuration'
        }
        if($part.kind -ceq 't-private'){
            if($mapping.id -cne 'api-fixed-buffer-private-bound' -or @($mapping.replacements).Count -ne 1 -or
                $mapping.output_sha256 -cne '51389bf3404ab2f13ae88a8cc3f88e7188ac0639f77b7871f4c9baf1830492bc'){
                throw 'API composite private component is not the preserved18byte transformation'
            }
            $replay=Get-ConformanceTReplay -Root $Root -Specification $mapping -PolicySha256 $PolicySha256 -ResolvedExclusions $ResolvedExclusions
            $excluded+=@($replay.excluded_obligations)
        }else{
            Assert-ApiLifetimeEquivalent -Root $Root -Mapping $mapping
            $replay=Get-ConformanceEquivalentReplay -Root $Root -Specification $mapping
        }
        if($replay.diagnostic_only -or $replay.review_status -cne 'accepted' -or $replay.sha256 -cne $part.output_sha256 -or
            $replay.sha256 -cne $mapping.output_sha256){throw 'API composite inner operation lacks exact accepted review/output'}
        $innerPath=Resolve-ReviewedFile -Root $Root -Path $mapping.review.artifact -Sha256 $mapping.review.artifact_sha256
        $inner=Get-Content -LiteralPath $innerPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        $synthetic=(Assert-ApiSourceOnlyReview -Artifact $inner -RequireActualLabel:($part.kind -ceq 'equivalent') -AllowSyntheticReview:$AllowSyntheticReview) -or $synthetic
        $evidence=@()
        if($part.kind -ceq 't-private'){$evidence+=@($inner.review_evidence)}
        else{foreach($decision in $inner.decisions){
            if($decision.author -cne $mapping.review.author -or $decision.reviewer -cne $mapping.review.reviewer){throw 'API lifetime inner span reviewer differs from its independent source authority'}
            $evidence+=@($decision.review_evidence)
        }}
        foreach($identity in $evidence){
            $path=Resolve-ReviewedFile -Root $Root -Path $identity.path -Sha256 $identity.sha256
            $value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 48
            $synthetic=(Assert-ApiSourceOnlyReview -Artifact $value -RequireActualLabel:($part.kind -ceq 'equivalent') -AllowSyntheticReview:$AllowSyntheticReview) -or $synthetic
        }
        $patches+=@($mapping.replacements)
        $parts+=@{kind=$part.kind;id=$mapping.id;manifest=$part.manifest;output_sha256=$replay.sha256}
    }
    if((@($excluded|Sort-Object)-join '|') -cne 'LUA-API-REVIEWED-BLOCK-9001'){
        throw 'API composite lost its original source-exclusion linkage'
    }
    # Each accepted component was replayed against the same original bytes.
    # Apply their disjoint original-coordinate union once; never sequentially
    # rebase offsets after the earlier18-byte removal. The historical patch
    # engine rejects overlap, duplicate ids and altered original span hashes.
    $bytes=Get-ConformancePatchedBytes -SourceBytes $sourceBytes -Replacements $patches
    $hash=Get-ConformanceHash $bytes
    if($Specification.output_sha256 -cne $hash){throw 'API composite exact union output hash differs'}
    return @{bytes=$bytes;sha256=$hash;source=$Specification.source;source_sha256=$script:ApiBase;id=$Specification.id;
        disposition='reviewed-source-composite';components=$parts;excluded_obligations=@($excluded);source_exclusion_ids=@($excluded);
        original_required_obligations=@($Specification.original_required_obligations);claims_sha256=$claimsHash;
        diagnostic_only=$synthetic;review_status=$(if($synthetic){'synthetic-fixture'}else{'accepted'});
        runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Get-TargetApiCompositeClaims, Get-TargetApiCompositeReplay
