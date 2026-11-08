Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
$script:VerifierSource='references/lua/testes/memerr.lua'
$script:VerifierSourceHash='02cc2a754e688bdfcbf507e009d899c4d367f27ced45094b68fdf208a6912491'
$script:VerifierReference='7579fc9d7ed90240487251dfb69168f8e64e9294'

function Get-VerifierRetainedSpans {
    param([byte[]]$Bytes)
    $text=[Text.Encoding]::Latin1.GetString($Bytes)
    $patterns=[ordered]@{
        'protected-call'="  local stat, err = pcall(f, ...)`n"
        'status-message-assertion'='  assert(not stat and string.find(err, msg))'
        'oversized-application'='checkerr("block too big", T.newuserdata, math.maxinteger)'
        'limited-application-and-reset'="T.alloccount(10)`ncheckerr(MEMERRMSG, f)`nT.alloccount()          -- remove limit"
        'later-campaigns'=$text.Substring($text.IndexOf('-- preallocate stack space',[StringComparison]::Ordinal))
    }
    foreach($id in $patterns.Keys){
        $offset=$text.IndexOf($patterns[$id],[StringComparison]::Ordinal)
        if($offset -lt 0){throw 'Pinned verifier preservation span missing'}
        $span=[Text.Encoding]::Latin1.GetBytes($patterns[$id])
        @{id=$id;byte_offset=$offset;byte_length=$span.Length;sha256=(Get-ConformanceHash $span)}
    }
}

function Get-ConformanceVerifierSemanticHash {
    param([Parameter(Mandatory)][Collections.IDictionary]$Specification)
    # A review binds the complete source operation, including empty exclusion
    # set and exact retained spans. Omit only the referring review metadata
    # itself, avoiding an approval hash cycle. JSON object order is irrelevant.
    function Canonical($Value){
        if($Value -is [Collections.IDictionary]){
            $keys=[string[]]@($Value.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal)
            $ordered=[ordered]@{};foreach($key in $keys){$ordered[$key]=Canonical $Value[$key]};return $ordered
        }
        if($Value -is [Array]){
            $items=[Collections.Generic.List[object]]::new()
            foreach($item in $Value){$items.Add((Canonical $item))}
            Write-Output -NoEnumerate $items.ToArray();return
        }
        return $Value
    }
    $payload=[ordered]@{};foreach($key in $Specification.Keys){if($key -cne 'review'){$payload[$key]=$Specification[$key]}}
    return Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject (Canonical $payload) -Depth 48 -Compress)))
}

function Get-ConformanceVerifierReplay {
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][Collections.IDictionary]$Specification,
          [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string]$Implementation,
          [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string]$Configuration,
          [switch]$AllowUnreviewedDiagnostics,[switch]$AllowSyntheticReview)
    $fields=@('schema_version','kind','id','target','reference_revision','source','source_sha256',
        'implementation','configuration','operation','insertion','retained_spans','counterpart_sources',
        'excluded_obligations','output_sha256','author_proposal','runtime_acceptance','coverage_authority','review')
    if(@($Specification.Keys).Count -ne $fields.Count -or @($fields|Where-Object{-not $Specification.Contains($_)}).Count -ne 0 -or
        ($Specification.schema_version -isnot [int] -and $Specification.schema_version -isnot [long]) -or
        $Specification.schema_version -ne 1 -or $Specification.kind -cne 't-verifier-equivalent' -or
        $Specification.id -cne 'memerr-verifier-allocation' -or $Specification.target -cne 'remaining-upstream-compatibility' -or
        $Specification.reference_revision -cne $script:VerifierReference -or $Specification.source -cne $script:VerifierSource -or
        $Specification.source_sha256 -cne $script:VerifierSourceHash -or
        $Implementation -cne 'Ada' -or $Configuration -cne 'upstream-test' -or
        $Specification.implementation -cne $Implementation -or $Specification.configuration -cne $Configuration -or
        $Specification.operation -cne 'reset-allocator-after-protected-call' -or
        $Specification.runtime_acceptance -isnot [bool] -or $Specification.runtime_acceptance -or
        $Specification.coverage_authority -isnot [bool] -or $Specification.coverage_authority -or
        $Specification.excluded_obligations -isnot [Array] -or $Specification.excluded_obligations.Count -ne 0){
        throw 'Invalid bounded T verifier equivalent identity or exclusion/acceptance claim'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $Specification.source -Sha256 $Specification.source_sha256
    $bytes=[IO.File]::ReadAllBytes($path)
    $insertion=$Specification.insertion
    # This successor is intentionally not a general zero-width patch engine.
    # Only one literal statement can be inserted at the exact boundary after
    # the original helper pcall and before its unchanged assertion. Original
    # application calls, limits, resets and every later source byte stay owned
    # by the pinned source. An asserted reviewer cannot widen this operation.
    if($insertion -isnot [Collections.IDictionary] -or
        (@($insertion.Keys|Sort-Object)-join '|') -cne 'length_bytes|replacement|source_sha256|start_byte' -or
        ($insertion.start_byte -isnot [int] -and $insertion.start_byte -isnot [long]) -or $insertion.start_byte -ne 140 -or
        ($insertion.length_bytes -isnot [int] -and $insertion.length_bytes -isnot [long]) -or $insertion.length_bytes -ne 0 -or
        $insertion.source_sha256 -cne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' -or
        $insertion.replacement -cne "  T.alloccount()`n"){
        throw 'Verifier equivalent must insert only the exact reset after the actual protected call'
    }
    $retained=@(Get-VerifierRetainedSpans $bytes)
    if($Specification.retained_spans -isnot [Array] -or $Specification.retained_spans.Count -ne $retained.Count){throw 'Verifier retained application/status/campaign spans differ'}
    for($index=0;$index -lt $retained.Count;$index++){
        $actual=$Specification.retained_spans[$index];$expected=$retained[$index]
        if($actual -isnot [Collections.IDictionary] -or (@($actual.Keys|Sort-Object)-join '|') -cne 'byte_length|byte_offset|id|sha256'){
            throw 'Verifier retained application/status/campaign span fields differ'
        }
        foreach($field in @('byte_offset','byte_length')){
            if($actual[$field] -isnot [int] -and $actual[$field] -isnot [long]){throw 'Verifier retained source spans must be integral'}
        }
        foreach($field in $expected.Keys){if($actual[$field] -cne $expected[$field]){throw 'Verifier retained application/status/campaign span differs'}}
    }
    $requiredSources=@('references/lua/ltests.c','tests/src/lua-conformance_adapter.adb',
        'tests/src/lua-conformance_allocator.adb','tests/c/conformance_adapter.c','tests/src/lua-sessions-conformance.adb',
        'tests/conformance/targets/remaining-upstream-compatibility/memerr-verifier.author.lua',
        'scripts/ConformanceVerifierEquivalents.psm1')
    if($Specification.counterpart_sources -isnot [Array] -or $Specification.counterpart_sources.Count -ne $requiredSources.Count){throw 'Verifier source/configuration counterpart bindings missing'}
    foreach($name in $requiredSources){
        $binding=@($Specification.counterpart_sources|Where-Object path -CEQ $name)
        if($binding.Count -ne 1 -or @($binding[0].Keys).Count -ne 2){throw 'Verifier source/configuration counterpart binding differs'}
        if($name -ceq 'references/lua/ltests.c' -and $binding[0].sha256 -cne '62a7015b036d366addd131e4f046f38557d66b8f48aae120e8aad992f3d90199'){
            throw 'Verifier native allocator source differs from its pinned test implementation'
        }
        [void](Resolve-ReviewedFile -Root $Root -Path $name -Sha256 $binding[0].sha256)
    }
    if($Specification.author_proposal.path -cne 'tests/conformance/targets/remaining-upstream-compatibility/memerr-verifier-allocation.author-proposal.json'){
        throw 'Verifier equivalent author proposal identifies another source operation'
    }
    [void](Resolve-ReviewedFile -Root $Root -Path $Specification.author_proposal.path -Sha256 $Specification.author_proposal.sha256)
    $replacement=[Text.Encoding]::UTF8.GetBytes($insertion.replacement)
    $output=[byte[]]::new($bytes.Length+$replacement.Length)
    [Array]::Copy($bytes,0,$output,0,$insertion.start_byte)
    [Array]::Copy($replacement,0,$output,$insertion.start_byte,$replacement.Length)
    [Array]::Copy($bytes,$insertion.start_byte,$output,$insertion.start_byte+$replacement.Length,$bytes.Length-$insertion.start_byte)
    $outputHash=Get-ConformanceHash $output
    if($Specification.output_sha256 -cne $outputHash){throw 'Verifier equivalent exact output hash differs'}
    $review=$Specification.review
    if($review -isnot [Collections.IDictionary] -or $review.status -cnotin @('pending','accepted') -or
        [string]::IsNullOrWhiteSpace([string]$review.author)){throw 'Verifier equivalent review identity missing'}
    $accepted=$review.status -ceq 'accepted';$synthetic=$false
    if(-not $accepted -and -not $AllowUnreviewedDiagnostics){throw 'Verifier equivalent lacks independent exact semantic review'}
    $semanticHash=Get-ConformanceVerifierSemanticHash $Specification
    if($accepted){
        if([string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer){throw 'Verifier equivalent review cannot be self-approved'}
        $approvalPath=Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
        $approval=Get-Content -LiteralPath $approvalPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        if(($approval.schema_version -isnot [int] -and $approval.schema_version -isnot [long]) -or
            $approval.schema_version -ne 1 -or $approval.kind -cne 't-verifier-equivalent-approval' -or
            $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
            $approval.decision -cne 'accepted' -or $approval.equivalent_id -cne $Specification.id -or
            $approval.semantic_sha256 -cne $semanticHash -or $approval.synthetic_fixture -isnot [bool]){
            throw 'Verifier equivalent approval identity or complete source operation differs'
        }
        foreach($flag in @('runtime_acceptance','coverage_authority')){
            if($approval[$flag] -isnot [bool] -or $approval[$flag]){throw 'Verifier source approval cannot supply runtime acceptance'}
        }
        $narrativePath=Resolve-ReviewedFile -Root $Root -Path $approval.review_evidence.path -Sha256 $approval.review_evidence.sha256
        $decision=Get-Content -LiteralPath $narrativePath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        if(($decision.schema_version -isnot [int] -and $decision.schema_version -isnot [long]) -or
            $decision.schema_version -ne 1 -or $decision.kind -cne 't-verifier-equivalent-review' -or
            $decision.equivalent_id -cne $Specification.id -or $decision.semantic_sha256 -cne $semanticHash -or
            $decision.reviewer -cne $review.reviewer -or $decision.decision -cne 'accepted' -or
            $decision.synthetic_fixture -isnot [bool] -or [string]::IsNullOrWhiteSpace([string]$decision.source_bound_rationale)){
            throw 'Verifier equivalent independent source decision differs'
        }
        foreach($flag in @('runtime_acceptance','coverage_authority')){
            if($decision[$flag] -isnot [bool] -or $decision[$flag]){throw 'Verifier source decision cannot supply runtime acceptance'}
        }
        foreach($flag in @('application_refusal_preserved','status_message_assertion_preserved','original_reset_preserved','later_campaigns_preserved','no_source_exclusions')){
            if($decision[$flag] -isnot [bool] -or -not $decision[$flag]){throw 'Verifier equivalent review does not retain every application/status/campaign obligation'}
        }
        $synthetic=$approval.synthetic_fixture -or $decision.synthetic_fixture
        if($synthetic -and -not $AllowSyntheticReview){throw 'Synthetic verifier review cannot authorize an actual source equivalent'}
    }
    # This function reconstructs memory only. There is deliberately no file
    # installation, runner selection or process execution in this checkpoint.
    return @{bytes=$output;sha256=$outputHash;source=$Specification.source;source_sha256=$Specification.source_sha256;
        id=$Specification.id;kind=$Specification.kind;disposition='ada-internal-equivalent';
        diagnostic_only=(-not $accepted -or $synthetic);review_status=$(if($synthetic){'synthetic-fixture'}elseif($accepted){'accepted'}else{'pending'});
        semantic_sha256=$semanticHash;excluded_obligations=@();runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Get-ConformanceVerifierReplay, Get-ConformanceVerifierSemanticHash
