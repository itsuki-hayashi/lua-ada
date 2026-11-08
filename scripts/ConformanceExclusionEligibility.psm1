Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-ConformanceExclusionEligibilityVersion {
    param([Parameter(Mandatory)][Collections.IDictionary] $Exclusion)
    if(-not $Exclusion.Contains('eligibility_schema_version')){return 1}
    if(($Exclusion.eligibility_schema_version -isnot [int] -and $Exclusion.eligibility_schema_version -isnot [long]) -or
        $Exclusion.eligibility_schema_version -cnotin @(2,3,4)){throw 'Unsupported exclusion eligibility schema version'}
    return $Exclusion.eligibility_schema_version
}

function Get-ConformanceOptimizerRegistry {
    # This is a closed source registry, not a general compiler/debug exemption.
    # Each row is the independently scoped pinned candidate. Expansion needs a
    # new reviewed implementation; a policy or author packet cannot add rows.
    $rows=@(
        @(800,143,'26aad09cfda55023d09d73d23353c892cb5e19ba423488629606efc828ddf3fd','constant-pool-layout',@('compile-original','numeric-values-types-arity','callback-sequence','assignment-sequence')),
        @(1808,205,'41b6d2b52bb8f3f0d16dc0cf595c5fd6a4ca1b124b16b1bef028a1dda5f27f6b','opcode-sequence',@('compile-original','retained-checkR','safe-return-cardinality')),
        @(2288,239,'5b3ddc7feef1ddadfa4a18c2526a31ced0495324141bde683ac399700a67e762','opcode-equality',@('compile-original','retained-checkR')),
        @(13327,32,'13c9570d19cf580345c831907370413a0a9b7c0c3d39f7b6660459373cd8e8af','outer-constant-placement',@('nested-constant-lifetimes')),
        @(13359,32,'4b1b8301af5f0f06a693bc66df7fa421860fdf06c9821e447ae6d4af791d8907','middle-constant-placement',@('nested-constant-lifetimes')),
        @(13587,10,'01169ab3aa9b67d6e268a238d869205be891f6403052061cdf5de5d1a9bf9e54','private-register-inspection-wrapper',@('register-load-boundaries')),
        @(13655,79,'120c5699b24c0b9102eded9963b92049e2d0f8213c5c43d77a64dc7dd3ecdac9','physical-register-numbering',@('register-load-boundaries')),
        @(14141,175,'212b31fe72e0800322053802b52608dd3940d8b601b23d3e36350ae17ffe61b6','constructor-opcode-count',@('constructor-and-vararg-boundaries')))
    for($index=0;$index -lt $rows.Count;$index++){
        $row=$rows[$index]
        @{id=('LUA-CODE-REVIEWED-BLOCK-'+(9001+$index));byte_offset=$row[0];byte_length=$row[1];
            anchor_sha256=$row[2];structure_kind=$row[3];required_semantic_contract_ids=@($row[4])}
    }
}

function Get-ConformanceResourceRegistry {
    # A source author cannot extend this registry. Its sole row is the reviewed
    # positive allocation count, never the materialization or optimized path.
    @{id='LUA-MEMERR-REVIEWED-BLOCK-9001';source='memerr.lua';
        source_sha256='02cc2a754e688bdfcbf507e009d899c4d367f27ced45094b68fdf208a6912491';
        byte_offset=3544;byte_length=19;
        anchor_sha256='671d423d19a8f100b52a4f4a1402dcbc11e2aa6eadaa7a1eaa77bf09640add01';
        structure_kind='materialized-vararg-positive-allocation-count';
        original_anchor=@{id='LUA-MEMERR-ASSERT-CALL-0004';kind='assert-call';byte_offset=3544;byte_length=6;
            anchor_sha256='25450689bdd44d014020b238021b313431cb1f7a86f24e29cecbd1e442edae0a'};
        retained_materialization=@{id='LUA-MEMERR-REVIEWED-BLOCK-9002';byte_offset=3403;byte_length=141;
            anchor_sha256='8a0db9fbb14b03483f9ecc074070ea3c02fd9ea7d994058fd2547717e01fabdb'};
        protected_optimized=@{byte_offset=3604;byte_length=254;
            anchor_sha256='065e3973d7ca76db008fd02bda7d3321d0daeffa35b11a18281ec77b01917976'};
        t_guard=@{mode='absent-return';byte_offset=190;byte_length=117;
            sha256='a33dea5a26d991a7e1f74e509f20ce5a7c857f418a094145bb634dcf6ed8eafb'};
        required_semantic_contract_ids=@('Payload_Types','Nil_Holes','Fresh_Aliases','Captured_Table',
            'Count_Faults','Byte_Faults','Partial_Release','Retained_Recovery')}
}

function Test-ConformanceExclusionCompatibilityShape {
    param([Parameter(Mandatory)][Collections.IDictionary] $Exclusion)
    # V1 retains its exact historical meaning. V2 distinguishes visibility of
    # a measurement from a promised module contract, and is intentionally
    # limited to a private bound inside a retained original assertion. Source
    # spans and independent feature authority are checked by the inventory.
    $version=Get-ConformanceExclusionEligibilityVersion $Exclusion
    if($Exclusion.public_api -isnot [bool] -or $Exclusion.public_api -or
        $Exclusion.mixed_obligation -isnot [bool] -or $Exclusion.mixed_obligation -or
        $Exclusion.module_observable -isnot [bool]){return $false}
    if($version -eq 1){return -not $Exclusion.module_observable}
    if($version -eq 4){
        $required=@('module_compatibility_obligation','observation_kind','structure_kind',
            'required_semantic_contract_ids','original_anchor_links','retained_materialization',
            'feature_review','semantic_retention_review')
        if(@($required|Where-Object{-not $Exclusion.Contains($_)}).Count -or -not $Exclusion.module_observable -or
            $Exclusion.module_compatibility_obligation -isnot [bool] -or $Exclusion.module_compatibility_obligation -or
            $Exclusion.observation_kind -cne 'private-resource-geometry'){return $false}
        $rows=@(Get-ConformanceResourceRegistry|Where-Object id -CEQ $Exclusion.id)
        if($rows.Count -ne 1){return $false};$row=$rows[0]
        foreach($key in @('source','source_sha256','byte_offset','byte_length','anchor_sha256','structure_kind')){
            if($Exclusion[$key] -cne $row[$key]){return $false}
        }
        foreach($key in @('byte_offset','byte_length')){
            if($Exclusion[$key] -isnot [int] -and $Exclusion[$key] -isnot [long]){return $false}
        }
        if($Exclusion.required_semantic_contract_ids -isnot [Array] -or
            (($Exclusion.required_semantic_contract_ids|Sort-Object)-join '|') -cne
                (($row.required_semantic_contract_ids|Sort-Object)-join '|') -or
            $Exclusion.original_anchor_links -isnot [Array] -or
            $Exclusion.original_anchor_links.Count -ne 1){return $false}
        foreach($entry in @(@{actual=$Exclusion.original_anchor_links[0];expected=$row.original_anchor},
                @{actual=$Exclusion.retained_materialization;expected=$row.retained_materialization})){
            if($entry.actual -isnot [Collections.IDictionary] -or
                (($entry.actual.Keys|Sort-Object)-join '|') -cne (($entry.expected.Keys|Sort-Object)-join '|')){return $false}
            foreach($key in $entry.expected.Keys){
                if($entry.expected[$key] -is [int] -and $entry.actual[$key] -isnot [int] -and $entry.actual[$key] -isnot [long]){return $false}
                if($entry.actual[$key] -cne $entry.expected[$key]){return $false}
            }
        }
        foreach($key in @('feature_review','semantic_retention_review')){
            $identity=$Exclusion[$key]
            if($identity -isnot [Collections.IDictionary] -or
                (($identity.Keys|Sort-Object)-join '|') -cne 'path|sha256' -or
                $identity.path -cnotmatch '^tests/conformance/targets/remaining-upstream-compatibility/reviews/[a-z0-9.-]+\.json$' -or
                $identity.sha256 -cnotmatch '^[0-9a-f]{64}$'){return $false}
        }
        return $true
    }
    if($version -eq 3){
        $required=@('module_compatibility_obligation','observation_kind','structure_kind',
            'required_semantic_contract_ids','original_anchor_links','feature_review','semantic_retention_review')
        if(@($required|Where-Object{-not $Exclusion.Contains($_)}).Count -or -not $Exclusion.module_observable -or
            $Exclusion.module_compatibility_obligation -isnot [bool] -or $Exclusion.module_compatibility_obligation -or
            $Exclusion.observation_kind -cne 'private-optimization-structure' -or $Exclusion.source -cne 'code.lua' -or
            $Exclusion.source_sha256 -cne 'b63335ff980dd318f1cc4aa81bbd54952afc7ac3688c7d9042ea4c45e9993663'){
            return $false
        }
        $row=@(Get-ConformanceOptimizerRegistry|Where-Object id -CEQ $Exclusion.id)
        if($row.Count -ne 1){return $false}
        foreach($key in @('byte_offset','byte_length')){
            if($Exclusion[$key] -isnot [int] -and $Exclusion[$key] -isnot [long]){return $false}
        }
        foreach($key in @('byte_offset','byte_length','anchor_sha256','structure_kind')){
            if($Exclusion[$key] -cne $row[0][$key]){return $false}
        }
        if($Exclusion.required_semantic_contract_ids -isnot [Array] -or
            (($Exclusion.required_semantic_contract_ids|Sort-Object)-join '|') -cne
                (($row[0].required_semantic_contract_ids|Sort-Object)-join '|') -or
            $Exclusion.original_anchor_links -isnot [Array]){return $false}
        foreach($key in @('feature_review','semantic_retention_review')){
            $identity=$Exclusion[$key]
            if($identity -isnot [Collections.IDictionary] -or
                (($identity.Keys|Sort-Object)-join '|') -cne 'path|sha256' -or
                $identity.path -cnotmatch '^tests/conformance/targets/remaining-upstream-compatibility/reviews/[a-z0-9.-]+\.json$' -or
                $identity.sha256 -cnotmatch '^[0-9a-f]{64}$'){return $false}
        }
        return $true
    }
    if(@(@('module_compatibility_obligation','observation_kind','retained_parent')|Where-Object{-not $Exclusion.Contains($_)}).Count -ne 0 -or
        $Exclusion.module_compatibility_obligation -isnot [bool] -or $Exclusion.module_compatibility_obligation -or
        $Exclusion.observation_kind -cnotin @('private-resource-bound','private-optimization-bound') -or
        $Exclusion.retained_parent -isnot [Collections.IDictionary]){return $false}
    $parent=$Exclusion.retained_parent
    if((@($parent.Keys|Sort-Object)-join '|') -cne 'anchor_sha256|byte_length|byte_offset|id' -or
        $parent.id -cnotmatch '^LUA-[A-Z0-9]+-ASSERT-CALL-[0-9]{4}$' -or
        ($parent.byte_offset -isnot [int] -and $parent.byte_offset -isnot [long]) -or $parent.byte_offset -lt 0 -or
        ($parent.byte_length -isnot [int] -and $parent.byte_length -isnot [long]) -or $parent.byte_length -le 0 -or
        $parent.anchor_sha256 -cnotmatch '^[0-9a-f]{64}$'){return $false}
    return $true
}

function Get-ConformanceExclusionSemanticFields {
    param([Parameter(Mandatory)][Collections.IDictionary] $Exclusion)
    $fields=@('id','source','source_sha256','byte_offset','byte_length','anchor_sha256',
        'status','disposition','configurations','eligibility','public_api','mixed_obligation',
        'module_observable','invariant','third_party_irrelevance','t_guard','evidence')
    if((Get-ConformanceExclusionEligibilityVersion $Exclusion) -eq 2){
        $fields+=@('eligibility_schema_version','module_compatibility_obligation','observation_kind','retained_parent')
    }
    if((Get-ConformanceExclusionEligibilityVersion $Exclusion) -eq 3){
        $fields+=@('eligibility_schema_version','module_compatibility_obligation','observation_kind','structure_kind',
            'required_semantic_contract_ids','original_anchor_links','feature_review','semantic_retention_review')
    }
    if((Get-ConformanceExclusionEligibilityVersion $Exclusion) -eq 4){
        $fields+=@('eligibility_schema_version','module_compatibility_obligation','observation_kind','structure_kind',
            'required_semantic_contract_ids','original_anchor_links','retained_materialization',
            'feature_review','semantic_retention_review')
    }
    return $fields
}

Export-ModuleMember -Function Get-ConformanceExclusionEligibilityVersion,
    Test-ConformanceExclusionCompatibilityShape, Get-ConformanceExclusionSemanticFields,Get-ConformanceOptimizerRegistry,Get-ConformanceResourceRegistry
