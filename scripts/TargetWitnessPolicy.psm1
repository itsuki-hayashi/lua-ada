Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConsumerEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'AUnitEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'HeaderDeclarationProbes.psm1')

function Read-TargetWitnessJson {
    param([string] $Root,[Collections.IDictionary] $Identity)
    $path = Resolve-ReviewedFile -Root $Root -Path $Identity.path -Sha256 $Identity.sha256
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
}

function Get-TargetWitnessPayloadHash {
    param([Collections.IDictionary] $Value)
    function Canonical([object] $Item) {
        if($Item -is [Collections.IDictionary]){
            $keys=[string[]]@($Item.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal)
            $ordered=[ordered]@{}
            foreach($key in $keys){$ordered[$key]=Canonical $Item[$key]}
            return $ordered
        }
        if($Item -is [Collections.IList]){
            $array=[Collections.Generic.List[object]]::new()
            foreach($element in $Item){$array.Add((Canonical $element))}
            Write-Output -NoEnumerate $array.ToArray()
            return
        }
        return $Item
    }
    $canonical=Canonical $Value
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $canonical -Compress -Depth 48))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Assert-TargetWitnessArrays {
    param([Collections.IDictionary] $Value,[string[]] $Names)
    foreach ($name in $Names) {
        if (-not $Value.Contains($name) -or $Value[$name] -isnot [Collections.IList]) {
            throw "Target witness field must be an explicit array: $name"
        }
        foreach ($id in $Value[$name]) {
            if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) { throw 'Target witness route contains an invalid identity' }
        }
    }
}

function Read-TargetWitnessPolicy {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $Path,[switch] $RequireReview)
    $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $Root $Path }
    $relative = [IO.Path]::GetRelativePath($Root,[IO.Path]::GetFullPath($full)).Replace('\','/')
    $identity = @{path=$relative;sha256=(Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant()}
    $policy = Read-TargetWitnessJson -Root $Root -Identity $identity
    if ($policy.schema_version -ne 1 -or $policy.kind -cne 'target-witness-policy' -or
        $policy.target -cne 'remaining-upstream-compatibility' -or
        $policy.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $policy.runtime_acceptance -isnot [bool] -or $policy.runtime_acceptance -or
        $policy.coverage_authority -isnot [bool] -or $policy.coverage_authority) { throw 'Invalid target witness policy identity' }
    $consumer = Read-TargetWitnessJson -Root $Root -Identity $policy.consumer
    $unit = Read-TargetWitnessJson -Root $Root -Identity $policy.aunit
    $api = Read-TargetWitnessJson -Root $Root -Identity $policy.global_api
    $compiled=@{kind='target-compiled-witness-mapping';cases=@()}
    if($policy.Contains('compiled') -and $null -ne $policy.compiled){
        $compiled=Read-TargetWitnessJson -Root $Root -Identity $policy.compiled
        if($compiled.kind -cne 'target-compiled-witness-mapping'){throw 'Invalid compiled witness source mapping'}
    }
    $predecessors = @{
        'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json'='f89fd3127e44266863dbf44e6e01863c2f590536a906325936a6f0bc1435813e';
        'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json'='21005e003734cd3419a84b8e61f87ff8458b22eab85f439744181e8c6f159de6';
        'tests/conformance/scopes/expanded-t-conformance.api.jsonl'='1333a0525d601bb6c88c32bff5443ee6a0beb05d90c09bc53b0f8d59123e7b27'
    }
    foreach ($entry in $predecessors.GetEnumerator()) {
        [void](Resolve-ReviewedFile -Root $Root -Path $entry.Key -Sha256 $entry.Value)
    }
    $oldConsumer = Get-Content (Join-Path $Root 'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $oldUnit = Get-Content (Join-Path $Root 'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $oldApi = @(Get-Content (Join-Path $Root 'tests/conformance/scopes/expanded-t-conformance.api.jsonl') |
        ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 64 })
    $suite = Get-Content (Join-Path $Root 'tests/conformance/suite.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    if (@($suite.acceptance_contexts).Count -ne 26 -or @($suite.files | Where-Object role -CEQ primary).Count -ne 30) {
        throw 'Target witness policy requires all original contexts and primaries'
    }
    $global = @(Get-Content (Join-Path $Root 'tests/conformance/c-api.jsonl') |
        ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 48 })
    if ($oldConsumer.cases.Count -ne 100 -or $oldUnit.entries.Count -ne 94 -or $oldApi.Count -ne 159 -or $global.Count -ne 473 -or
        @($consumer.cases).Count -lt 100 -or @($unit.entries).Count -lt 94 -or @($api.entries).Count -ne 473) {
        throw 'Full-target witness catalogues omit retained or global entries'
    }
    foreach ($mapping in @($consumer,$unit,$api)) {
        if ($mapping.target -cne $policy.target -or $mapping.runtime_acceptance -isnot [bool] -or $mapping.runtime_acceptance -or
            $mapping.coverage_authority -isnot [bool] -or $mapping.coverage_authority) { throw 'Witness source mapping cannot claim runtime acceptance' }
    }
    # Preserve names, exact output protocols and the retained semantic routes.
    # Fresh source hashes may change only through the successor's own review;
    # they never mutate or supersede the old scope's historical authority.
    foreach ($old in $oldConsumer.cases) {
        $next = @($consumer.cases | Where-Object { $_.source -ceq $old.source -and $_.case_id -ceq $old.case_id })
        if ($next.Count -ne 1) { throw 'Missing or duplicate retained C witness identity' }
        foreach ($field in @('consumer','expected_count','pattern_witness')) {
            $before = if ($old.Contains($field)) { $old[$field] } else { $null }
            $after = if ($next[0].Contains($field)) { $next[0][$field] } else { $null }
            if ($before -cne $after) { throw 'Retained C witness protocol changed' }
        }
        if ((@($old.exact_witnesses) -join '|') -cne (@($next[0].exact_witnesses) -join '|') -or
            @($old.exact_witnesses).Count -ne @($next[0].exact_witnesses).Count) { throw 'Retained C witness protocol changed' }
    }
    foreach ($old in $oldUnit.entries) {
        $next = @($unit.entries | Where-Object case -CEQ $old.case)
        if ($next.Count -ne 1 -or $next[0].registered_label -cne $old.registered_label -or
            $next[0].required_stdout_line -cne $old.required_stdout_line) { throw 'Retained AUnit witness protocol changed' }
    }
    if($unit.expected_stderr -cne $oldUnit.expected_stderr){throw 'Retained AUnit finalizer warning protocol changed'}
    $cIds = @{}; $unitIds = @{}
    foreach ($case in $consumer.cases) {
        $key = $case.source + '#' + $case.case_id
        if ($cIds.ContainsKey($key)) { throw 'Duplicate target C witness identity' }
        $cIds[$key] = $true
        [void](Resolve-ReviewedFile -Root $Root -Path $case.source -Sha256 $case.source_sha256)
        if (@($consumer.source_bindings | Where-Object { $_.path -ceq $case.source -and $_.sha256 -ceq $case.source_sha256 }).Count -ne 1) {
            throw 'Target C witness lacks its current source binding'
        }
        if ($RequireReview -and $case.Contains('function_source_review') -and $case.function_source_review -cne 'accepted-current-source') {
            throw 'Changed named C function source still needs independent review'
        }
    }
    foreach ($entry in $unit.entries) {
        if ($unitIds.ContainsKey($entry.case)) { throw 'Duplicate target AUnit witness identity' }
        $unitIds[$entry.case] = $true
        [void](Resolve-ReviewedFile -Root $Root -Path $entry.case.Split('#')[0] -Sha256 $entry.source_sha256)
        if (@($unit.bindings | Where-Object { $_.path -ceq $entry.case.Split('#')[0] -and $_.sha256 -ceq $entry.source_sha256 }).Count -ne 1) {
            throw 'Target AUnit witness lacks its current source binding'
        }
    }
    foreach ($binding in @($consumer.source_bindings) + @($unit.bindings)) {
        [void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)
    }
    $compiledIds=@{}
    if(@($compiled.cases|Where-Object{ $_.Contains('protocol') -and $_.protocol -ceq 'paired-header-profile-v1' }).Count){
        Assert-HeaderDeclarationMapping -Root $Root -Mapping $compiled
        if($RequireReview){$null=Assert-HeaderDeclarationSourceReview -Root $Root -Mapping $compiled}
    }
    foreach($case in $compiled.cases){
        if($case.id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$' -or $compiledIds.ContainsKey($case.id) -or
            @($case.contexts).Count -eq 0 -or @($case.source_bindings).Count -eq 0 -or
            -not $case.Contains('source') -or $case.source.path -cnotmatch '\.c$' -or
            @($case.source_bindings|Where-Object{ $_.path -ceq $case.source.path -and $_.sha256 -ceq $case.source.sha256 }).Count -ne 1){
            throw 'Invalid compiled source witness identity'
        }
        $compiledIds[$case.id]=$case
        foreach($context in $case.contexts){if($context -cnotin $suite.acceptance_contexts){throw 'Unknown compiled witness context'}}
        foreach($binding in $case.source_bindings){[void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)}
    }
    $seen = @{}
    foreach ($entry in $api.entries) {
        Assert-TargetWitnessArrays -Value $entry -Names @('named_c_cases','named_aunit_cases','compiled_witnesses')
        if($entry.runtime_acceptance -isnot [bool] -or $entry.runtime_acceptance -or
            $entry.coverage_authority -isnot [bool] -or $entry.coverage_authority -or @($entry.execution_evidence).Count -ne 0){
            throw 'Source-only API catalogue cannot carry passing execution authority'
        }
        $original = @($global | Where-Object id -CEQ $entry.id)
        if ($original.Count -ne 1 -or $seen.ContainsKey($entry.id)) { throw 'Global API catalogue contains unknown duplicate or missing entry' }
        $seen[$entry.id] = $true
        foreach ($field in @('header','kind','name','line','byte_offset','byte_length','anchor_sha256','declaration')) {
            if ($entry[$field] -cne $original[0][$field]) { throw 'Global API original declaration anchor differs' }
        }
        if ((@($entry.conditions) -join '|') -cne (@($original[0].conditions) -join '|')) { throw 'Global API original conditions differ' }
        $retained = @($oldApi | Where-Object id -CEQ $entry.id)
        if ($retained.Count -eq 1) {
            foreach ($case in $retained[0].named_cases) {
                if (($case.source + '#' + $case.id) -cnotin $entry.named_c_cases) { throw 'Global API catalogue lost a retained C route' }
            }
            foreach ($case in $retained[0].named_aunit_cases) {
                if (($case.source + '#' + $case.id) -cnotin $entry.named_aunit_cases) { throw 'Global API catalogue lost a retained AUnit route' }
            }
        }
        foreach ($case in $entry.named_c_cases) { if (-not $cIds.ContainsKey($case)) { throw 'Global API route names an unknown C witness' } }
        foreach ($case in $entry.named_aunit_cases) { if (-not $unitIds.ContainsKey($case)) { throw 'Global API route names an unknown AUnit witness' } }
        if ($RequireReview) {
            if ($entry.classification -cnotin @('runtime-behavior','compiled-declaration','conditional-declaration') -or
                $entry.review_status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$entry.invariant) -or
                [string]::IsNullOrWhiteSpace([string]$entry.boundaries) -or -not $entry.Contains('context_witnesses') -or
                @($entry.context_witnesses).Count -ne @($suite.acceptance_contexts).Count) { throw 'Global API semantic/context mapping is incomplete' }
            if (($entry.kind -ceq 'type' -and $entry.classification -ceq 'runtime-behavior') -or
                ($entry.kind -ceq 'function' -and $entry.classification -ceq 'compiled-declaration') -or
                ($entry.classification -ceq 'conditional-declaration' -and @($entry.conditions).Count -eq 0)) {
                throw 'Global API function/type classification requires appropriate behavioral or compiled evidence'
            }
            $contexts = @{}
            foreach ($route in $entry.context_witnesses) {
                Assert-TargetWitnessArrays -Value $route -Names @('named_c_cases','named_aunit_cases','compiled_witnesses')
                if ($route.context -cnotin $suite.acceptance_contexts -or $contexts.ContainsKey($route.context) -or
                    $route.disposition -cnotin @('runtime-observed','compiled-observed','compiled-not-applicable')) { throw 'Invalid global API context route' }
                $contexts[$route.context] = $true
                $runtime = @($route.named_c_cases).Count + @($route.named_aunit_cases).Count
                $compiledCount = @($route.compiled_witnesses).Count
                if (($route.disposition -ceq 'runtime-observed' -and $runtime -lt 1) -or
                    ($route.disposition -cne 'runtime-observed' -and $compiledCount -lt 1) -or
                    ($entry.classification -ceq 'compiled-declaration' -and $route.disposition -ceq 'runtime-observed') -or
                    ($entry.classification -ceq 'runtime-behavior' -and $route.disposition -ceq 'compiled-observed') -or
                    ($entry.kind -ceq 'function' -and $route.disposition -ceq 'compiled-observed') -or
                    ($entry.kind -ceq 'type' -and $route.disposition -ceq 'runtime-observed') -or
                    ($route.disposition -ceq 'compiled-not-applicable' -and @($entry.conditions).Count -eq 0)) {
                    throw 'Global API classification lacks appropriate runtime or compiled context evidence'
                }
                foreach ($case in $route.named_c_cases) { if (-not $cIds.ContainsKey($case)) { throw 'Global API context names unknown C witness' } }
                foreach ($case in $route.named_aunit_cases) { if (-not $unitIds.ContainsKey($case)) { throw 'Global API context names unknown AUnit witness' } }
                foreach($case in $route.compiled_witnesses){
                    if(-not $compiledIds.ContainsKey($case) -or $route.context -cnotin $compiledIds[$case].contexts){
                        throw 'Global API context names unknown or inapplicable compiled witness'
                    }
                }
                if($route.disposition -cne 'runtime-observed' -and
                    @($compiledIds.Values|Where-Object{ $_.Contains('protocol') -and $_.protocol -ceq 'paired-header-profile-v1' }).Count){
                    $required=@($compiledIds.Values|Where-Object{ $_.Contains('protocol') -and
                        $_.protocol -ceq 'paired-header-profile-v1' -and $route.context -cin $_.contexts }|ForEach-Object id)
                    foreach($case in $required){if($case -cnotin $route.compiled_witnesses){throw 'Global declaration/applicability route omits a required C++ or configuration probe'}}
                    if($entry.id -cnotin @($compiled.api_anchors.id) -and $entry.id -cnotin @($compiled.applicability_anchors.id)){
                        throw 'Global declaration route names an unmeasured original API anchor'
                    }
                }
            }
        }
    }
    if ($RequireReview) {
        $review = $policy.review
        if ($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$review.author) -or
            [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer) {
            throw 'Target witness policy requires accepted independent review'
        }
        $approval = Read-TargetWitnessJson -Root $Root -Identity @{path=$review.artifact;sha256=$review.artifact_sha256}
        if ($approval.schema_version -ne 1 -or $approval.kind -cne 'target-witness-policy-approval' -or
            $approval.target -cne $policy.target -or $approval.decision -cne 'accepted' -or
            $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
            @($approval.global_api_decisions).Count -ne 473) { throw 'Target witness approval identity differs' }
        foreach ($kind in @('consumer','aunit','global_api')) {
            if ($approval[$kind].path -cne $policy[$kind].path -or $approval[$kind].sha256 -cne $policy[$kind].sha256) {
                throw 'Target witness approved catalogue differs'
            }
        }
        if($policy.Contains('compiled') -and $null -ne $policy.compiled){
            if(-not $approval.Contains('compiled') -or $approval.compiled.path -cne $policy.compiled.path -or
                $approval.compiled.sha256 -cne $policy.compiled.sha256){throw 'Compiled catalogue is not independently approved'}
        }
        foreach ($entry in $api.entries) {
            $decision = @($approval.global_api_decisions | Where-Object id -CEQ $entry.id)
            if ($decision.Count -ne 1 -or $decision[0].decision -cne 'accepted' -or
                $decision[0].mapping_sha256 -cne (Get-TargetWitnessPayloadHash $entry) -or
                [string]::IsNullOrWhiteSpace([string]$decision[0].rationale)) { throw 'Global API independent semantic decision differs' }
        }
        $narrative = Read-TargetWitnessJson -Root $Root -Identity $approval.review_evidence
        if ($narrative.reviewer -cne $review.reviewer -or $narrative.decision -cne 'accepted' -or
            $narrative.target -cne $policy.target) { throw 'Target witness review narrative differs' }
    }
    return @{policy=$policy;identity=$identity;consumer=$consumer;aunit=$unit;global_api=$api;compiled=$compiled;
        source_reviewed=[bool]$RequireReview;runtime_acceptance=$false;coverage_authority=$false}
}

function Test-TargetNamedContextEvidence {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][Collections.IDictionary] $Policy,
          [Parameter(Mandatory)][string] $ConsumerReport,[Parameter(Mandatory)][string] $AUnitReport,
          [Parameter(Mandatory)][string] $Context,[Parameter(Mandatory)][string] $Revision,
          [string] $ConsumerArtifactRoot = '',[string] $AUnitArtifactRoot = '')
    $consumer = Get-Content -LiteralPath $ConsumerReport -Raw | ConvertFrom-Json -AsHashtable -Depth 48
    $unit = Get-Content -LiteralPath $AUnitReport -Raw | ConvertFrom-Json -AsHashtable -Depth 48
    foreach($kind in @('gc','io')){
        foreach($name in @("${kind}_api_contract.c","${kind}_contract.h",'consumer_allocator.h')){
            $source=@($consumer["${kind}_contract"].sources|Where-Object file -CEQ "c_api/tests/$name")
            if($source.Count -ne 1){throw 'Target named native oracle driver source is missing or duplicated'}
            [void](Resolve-ReviewedFile -Root $Root -Path $source[0].file -Sha256 $source[0].sha256)
        }
    }
    foreach($name in @('c_api/tests/foreign_api_contract.c','tests/c/foreign_continuation_contract.c',
        'tests/c/foreign_hook_contract.c','tests/c/math_reopen_contract.c','tests/c/library_opener_contract.c')){
        $source=@($consumer.foreign_contract.sources|Where-Object file -CEQ $name)
        if($source.Count -ne 1){throw 'Target named foreign oracle driver source is missing or duplicated'}
        [void](Resolve-ReviewedFile -Root $Root -Path $name -Sha256 $source[0].sha256)
    }
    $activeArtifactRoot = $ConsumerArtifactRoot
    $resolve = {
        param($path,$hash)
        $fullRoot = [IO.Path]::GetFullPath($(if($activeArtifactRoot -ne ''){$activeArtifactRoot}else{$Root}))
        if($activeArtifactRoot -ne ''){
            $normalized=$path.Replace('\','/')
            $offset=$normalized.LastIndexOf('/reports/',[StringComparison]::Ordinal)
            if($offset -lt 0){throw 'Target named capture is outside reports'}
            $actual=[IO.Path]::GetFullPath((Join-Path $fullRoot $normalized.Substring($offset+1)))
        }else{$actual = [IO.Path]::GetFullPath($path)}
        $relative = [IO.Path]::GetRelativePath($fullRoot,$actual).Replace('\','/')
        if (-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or
            (Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $hash) { throw 'Target named capture path or hash differs' }
        return $actual
    }
    # Same-image imports and unload-after-close are mandatory whole-target
    # behavior, including when no individual API row chooses these witnesses.
    $additional=@('native-module')
    $driverNames=@{format='format_api_contract.c';value='value_api_contract.c';auxiliary='auxiliary_api_contract.c';
        'load-dump'='load_dump_api_contract.c';debug='debug_api_contract.c';external='external_string_contract.c';
        conversion='conversion_api_contract.c';operator='operator_api_contract.c';'index-type'='index_type_api_contract.c';
        'base-closing'='base_closing_api_contract.c';'native-module'='native_module_contract.c';buffer='buffer_api_contract.c';
        allocator='allocator_api_contract.c';substitution='substitution_api_contract.c';loadfile='loadfile_api_contract.c'}
    foreach($kind in $driverNames.Keys){if($kind -ceq 'native-module' -or @($Policy.consumer.cases|Where-Object consumer -CEQ "$kind-api").Count -gt 0){
        if($kind -cnotin $additional){$additional+=$kind}
        $names=@(('c_api/tests/'+$driverNames[$kind]))
        if($kind -cne 'allocator'){$names+='c_api/tests/consumer_allocator.h'}
        if($kind -ceq 'load-dump'){$names+='c_api/tests/load_dump_contract.h'}
        foreach($name in $names){
            $source=@($consumer[$kind.Replace('-','_')+'_contract'].sources|Where-Object file -CEQ $name)
            if($source.Count -ne 1){throw 'Target additional oracle source binding is missing or duplicated'}
            [void](Resolve-ReviewedFile -Root $Root -Path $name -Sha256 $source[0].sha256)
        }
    }}
    $c = Test-NamedConsumerEvidence -Report $consumer -Mapping $Policy.consumer -Revision $Revision -Context $Context `
        -ResolveCapture $resolve -RequireForeignContract -AdditionalContracts $additional
    $activeArtifactRoot = $AUnitArtifactRoot
    $a = Test-NamedAUnitEvidence -Report $unit -Mapping $Policy.aunit -Revision $Revision -Context $Context -ResolveCapture $resolve
    foreach ($library in $unit.library_files) {
        if (@($consumer.library_files | Where-Object { $_.file -ceq $library.file -and $_.sha256 -ceq $library.sha256 }).Count -ne 1) {
            throw 'Target named C and AUnit runtime images differ'
        }
    }
    return @{context=$Context;revision=$Revision;named_c_cases=$c.cases;named_aunit_cases=$a.cases;
        source_reviewed=$Policy.source_reviewed;runtime_observed=$true;runtime_acceptance=$false;coverage_authority=$false;
        consumer=@{path=$ConsumerReport;sha256=(Get-FileHash -LiteralPath $ConsumerReport).Hash.ToLowerInvariant()};
        aunit=@{path=$AUnitReport;sha256=(Get-FileHash -LiteralPath $AUnitReport).Hash.ToLowerInvariant()}}
}

function Assert-TargetGlobalApiRoutes {
    param([Parameter(Mandatory)][Collections.IDictionary] $Policy,
          [Parameter(Mandatory)][Collections.IDictionary] $NamedEvidence,
          [Parameter(Mandatory)][Collections.IDictionary] $CompiledCases,
          [Parameter(Mandatory)][string] $Context)
    if (-not $Policy.source_reviewed -or $NamedEvidence.context -cne $Context -or -not $NamedEvidence.runtime_observed) {
        throw 'Global API reconciliation requires reviewed mapping and actual named context evidence'
    }
    $ids = @{}
    foreach ($entry in $Policy.global_api.entries) {
        $route = @($entry.context_witnesses | Where-Object context -CEQ $Context)
        if ($route.Count -ne 1) { throw 'Global API context route missing or duplicated' }
        foreach ($case in $route[0].named_c_cases) {
            if ($case -cnotin $NamedEvidence.named_c_cases) { throw 'Global API actual C witness was not observed' }
        }
        foreach ($case in $route[0].named_aunit_cases) {
            if ($case -cnotin $NamedEvidence.named_aunit_cases) { throw 'Global API actual AUnit witness was not observed' }
        }
        foreach ($case in $route[0].compiled_witnesses) {
            if (-not $CompiledCases.Contains($case) -or $CompiledCases[$case].context -cne $Context -or
                $CompiledCases[$case].revision -cne $NamedEvidence.revision -or $CompiledCases[$case].runtime_observed -ne $true -or
                $CompiledCases[$case].actual_evidence -ne $true -or $CompiledCases[$case].validation_kind -cne 'verified-compiled-context-witness') {
                throw 'Global API actual compiled ABI/layout/header witness was not observed'
            }
        }
        $paired=@($CompiledCases.Values|Where-Object{ $_.Contains('protocol') -and $_.protocol -ceq 'paired-header-profile-v1' -and $_.context -ceq $Context })
        if($route[0].disposition -cne 'runtime-observed' -and $paired.Count){
            $states=@()
            foreach($case in $paired){
                if(-not $case.api_anchor_states.ContainsKey($entry.id) -or
                    $case.api_anchor_states[$entry.id].anchor_sha256 -cne $entry.anchor_sha256){throw 'Global compiled witness lacks its exact original declaration anchor'}
                $states+=$case.api_anchor_states[$entry.id]
            }
            if($route[0].disposition -ceq 'compiled-observed'){
                if(@($states|Where-Object{ -not $_.declaration_only }).Count -or
                    @($states|Where-Object state -CNE not-selected).Count -eq 0){
                    throw 'Global compiled declaration cannot certify callable behavior or an inactive definition'
                }
            }elseif($route[0].disposition -ceq 'compiled-not-applicable'){
                # A selected callable macro stays a runtime obligation. An
                # earlier definition overwritten before use is recorded as a
                # source fact; its reviewed applicability cannot hide a mode
                # where that same original definition remains effective.
                if(@($states|Where-Object{ $_.state -cin @('measured-type','processed-effective') -or
                    ($_.declaration_only -and $_.state -ceq 'processed-overridden') }).Count){
                    throw 'Global not-applicable route hides an active C++ or configuration definition'
                }
            }
        }
        $ids[$entry.id] = $true
    }
    if ($ids.Count -ne 473) { throw 'Global API evidence does not reconcile all 473 declarations' }
    return @{context=$Context;observed_global_api_entries=$ids.Count;runtime_acceptance=$false;coverage_authority=$false}
}

function Write-TargetBuildWitnesses {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][Collections.IDictionary] $Policy,
          [Parameter(Mandatory)][string] $Context,[string[]] $PreviousReports=@())
    $revision = (& git -C $Root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify target build witness revision' }
    $parts = $Context.Split('/')
    $library = if ($parts[3] -ceq 'shared') { 'relocatable' } else { $parts[3] }
    $consumerPaths = @(); $unitPaths = @()
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root 'reports/core-image') -Filter result.json -File -Recurse) {
        if ($file.FullName -cin $PreviousReports) { continue }
        $value = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 48
        if ($value.repository_revision -cne $revision -or $value.configuration -cne $parts[0] -or
            $value.platform -cne $parts[1] -or $value.profile -cne $parts[2] -or $value.library_type -cne $library) { continue }
        if ($value.Contains('consumers')) { $consumerPaths += $file.FullName }
        elseif ($value.Contains('configuration_probe') -and $value.Contains('sources')) { $unitPaths += $file.FullName }
    }
    if ($consumerPaths.Count -ne 1 -or $unitPaths.Count -ne 1) { throw 'Target build requires exactly one fresh C consumer and AUnit capture for its context' }
    $result = Test-TargetNamedContextEvidence -Root $Root -Policy $Policy -ConsumerReport $consumerPaths[0] `
        -AUnitReport $unitPaths[0] -Context $Context -Revision $revision
    $directory = Join-Path $Root ('reports/target-builds/' + $Context.Replace('/','-'))
    [void][IO.Directory]::CreateDirectory($directory)
    $result['schema_version'] = 1; $result['kind'] = 'target-build-named-witnesses'
    $result['witness_policy'] = $Policy.identity
    $path = Join-Path $directory 'witnesses.json'
    [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $result -Depth 48).Replace("`r`n","`n") + "`n",[Text.UTF8Encoding]::new($false))
    Write-Output "PASS: fresh named target build witnesses ($($result.named_c_cases.Count) C/$($result.named_aunit_cases.Count) AUnit); target runtime acceptance=False; path=$path"
    return $result
}

Export-ModuleMember -Function Read-TargetWitnessPolicy, Test-TargetNamedContextEvidence,
    Assert-TargetGlobalApiRoutes, Get-TargetWitnessPayloadHash, Write-TargetBuildWitnesses
