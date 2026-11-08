Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceApiComposite.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceVerifierEquivalents.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceLocalsEquivalent.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')

function Get-TargetReviewedSourceReplay {
    param([Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][Collections.IDictionary]$Specification,
        [Parameter(Mandatory)][string]$Implementation,[Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][string]$PolicySha256,
        [Parameter(Mandatory)][Collections.IDictionary]$ResolvedExclusions)
    # This selector recognizes only independently reviewed instrumented Ada
    # operations. It supplies no diagnostic/synthetic approval switches and
    # never selects these source bytes for the original native counterpart.
    if($Implementation -cne 'Ada' -or $Configuration -cne 'upstream-test'){
        throw 'Reviewed source selection requires instrumented Ada; native C remains original'
    }
    if(-not $Specification.Contains('review') -or $Specification.review.status -cne 'accepted' -or
        $Specification.runtime_acceptance -isnot [bool] -or $Specification.runtime_acceptance -or
        $Specification.coverage_authority -isnot [bool] -or $Specification.coverage_authority){
        throw 'Reviewed source selection requires accepted source-only independent review'
    }
    if($Specification.kind -ceq 'target-api-source-composite'){
        return Get-TargetApiCompositeReplay -Root $Root -Specification $Specification -Implementation $Implementation `
            -Configuration $Configuration -PolicySha256 $PolicySha256 -ResolvedExclusions $ResolvedExclusions
    }
    if($Specification.kind -ceq 't-verifier-equivalent'){
        return Get-ConformanceVerifierReplay -Root $Root -Specification $Specification -Implementation $Implementation -Configuration $Configuration
    }
    if($Specification.id -ceq 'locals-dead-table-storage'){
        return Get-TargetLocalsTableEquivalentReplay -Root $Root -Specification $Specification `
            -Implementation $Implementation -Configuration $Configuration
    }
    if($Specification.kind -cne 'target-source-equivalent' -or $Specification.id -cne 'calls-undump-constant-pool' -or
        $Specification.target -cne 'remaining-upstream-compatibility' -or
        $Specification.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $Specification.configuration -cne 'upstream-test' -or $Specification.disposition -cne 'ada-internal-equivalent' -or
        $Specification.source -cne 'references/lua/testes/calls.lua' -or
        $Specification.source_sha256 -cne 'e0331ba5557c09ba844c11a54810ca7cc01998638316d5192e252a2ab0a2d407' -or
        $Specification.source_exclusions -isnot [Array] -or $Specification.source_exclusions.Count -ne 0 -or
        ($Specification.original_required_obligations -join '|') -cne 'LUA-CALLS-ASSERT-CALL-0097' -or
        $Specification.runtime_acceptance -isnot [bool] -or $Specification.runtime_acceptance -or
        $Specification.coverage_authority -isnot [bool] -or $Specification.coverage_authority -or
        ($Specification.Contains('synthetic_fixture') -and ($Specification.synthetic_fixture -isnot [bool] -or $Specification.synthetic_fixture)) -or
        @($Specification.replacements).Count -ne 1){throw 'Unsupported or widened reviewed source selection'}
    $patch=$Specification.replacements[0]
    $featurePath='tests/conformance/targets/remaining-upstream-compatibility/reviews/calls-undump-constant-pool.independent-feature-review.json'
    if($patch.id -cne 'execute-all-decoded-string-results' -or $patch.start_byte -ne 14425 -or $patch.length_bytes -ne 105 -or
        $patch.source_sha256 -cne 'd350bbaa91f6e9d428a04e5507d4eb0cfb3596e882bffdbf5c30655054063c8e' -or
        (Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes($patch.replacement))) -cne 'e5887588491ee21f67c722ceda7a94ccad3b1a9a8740a9393da99c5f829ba606' -or
        $Specification.output_sha256 -cne 'ffed3d0bb8241c5258a616950552552316b14a1cc122c034d56550410e4b9b6c' -or
        $Specification.feature_review.path -cne $featurePath -or $featurePath -cnotin $patch.counterpart_tests){
        throw 'Decoded-string equivalent differs from its exact retained operations'
    }
    $feature=Get-Content (Resolve-ReviewedFile -Root $Root -Path $featurePath -Sha256 $Specification.feature_review.sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if($feature.kind -cne 't-equivalent-feature-review' -or $feature.candidate_id -cne $Specification.id -or
        $feature.decision -cne 'accepted-feature-only' -or $feature.permitted_resolution -cne 'ada-internal-equivalent' -or
        $feature.source.path -cne $Specification.source -or $feature.source.sha256 -cne $Specification.source_sha256 -or
        $feature.configuration -cne $Configuration -or $feature.original_anchor.id -cne 'LUA-CALLS-ASSERT-CALL-0097' -or
        $feature.counterpart_source.path -cnotin $patch.counterpart_tests -or $feature.runtime_acceptance -or $feature.coverage_authority -or
        @($feature.source_exclusions).Count -ne 0 -or ($feature.Contains('synthetic_fixture') -and $feature.synthetic_fixture)){
        throw 'Decoded-string source selection lacks its independent feature decision'
    }
    $replay=Get-ConformanceEquivalentReplay -Root $Root -Specification $Specification
    # The existing equivalent guard binds every original span, counterpart and
    # independent exact decision. Require actual source-only review labels too:
    # a synthetic or claimed runtime approval cannot authorize this generator.
    $approval=Get-Content (Resolve-ReviewedFile -Root $Root -Path $Specification.review.artifact -Sha256 $Specification.review.artifact_sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $reviews=@($approval)
    foreach($decision in $approval.decisions){
        $reviews+=Get-Content (Resolve-ReviewedFile -Root $Root -Path $decision.review_evidence.path -Sha256 $decision.review_evidence.sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    }
    foreach($review in $reviews){
        foreach($flag in @('synthetic_fixture','runtime_acceptance','coverage_authority')){
            if(-not $review.Contains($flag) -or $review[$flag] -isnot [bool] -or $review[$flag]){throw 'Reviewed source selection requires actual source-only independent decisions'}
        }
        if($review.Contains('execution_evidence') -and @($review.execution_evidence).Count){throw 'Source selection cannot consume fabricated execution evidence'}
    }
    $replay['excluded_obligations']=@();$replay['original_required_obligations']=@($Specification.original_required_obligations)
    $replay['runtime_acceptance']=$false;$replay['coverage_authority']=$false
    return $replay
}

Export-ModuleMember -Function Get-TargetReviewedSourceReplay
