Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-ConformanceExclusionEligibilityVersion {
    param([Parameter(Mandatory)][Collections.IDictionary] $Exclusion)
    if(-not $Exclusion.Contains('eligibility_schema_version')){return 1}
    if(($Exclusion.eligibility_schema_version -isnot [int] -and $Exclusion.eligibility_schema_version -isnot [long]) -or
        $Exclusion.eligibility_schema_version -ne 2){throw 'Unsupported exclusion eligibility schema version'}
    return 2
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
    return $fields
}

Export-ModuleMember -Function Get-ConformanceExclusionEligibilityVersion,
    Test-ConformanceExclusionCompatibilityShape, Get-ConformanceExclusionSemanticFields
