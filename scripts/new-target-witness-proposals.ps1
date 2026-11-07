param(
    [string] $SourceRoot = '',
    [string] $OutputDirectory = '',
    [string] $AdditionalConsumerCases = '',
    [string] $AdditionalAUnitCases = '',
    [string] $AdditionalApiRoutes = '',
    [string] $CompiledWitnessMapping = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($SourceRoot -eq '') { $SourceRoot = $root }
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$sourceGitRoot = (& git -C $SourceRoot rev-parse --show-toplevel 2>$null)
$sourceSnapshot = @{kind='synthetic-or-external-source-fixture';revision=$null;repository_dirty=$null}
if ($LASTEXITCODE -eq 0 -and [IO.Path]::GetFullPath(($sourceGitRoot -join '').Trim()) -ieq $SourceRoot) {
    $sourceRevision = (& git -C $SourceRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify author proposal source revision' }
    $sourceChanges = @(& git -C $SourceRoot -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect author proposal source state' }
    $sourceSnapshot = @{kind='repository-source-snapshot';revision=$sourceRevision;repository_dirty=($sourceChanges.Count -ne 0)}
}
$output = if ($OutputDirectory -ne '') { [IO.Path]::GetFullPath($OutputDirectory) }
    else { Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility' }
$relativeOutput = [IO.Path]::GetRelativePath($root,$output).Replace('\','/')
if ($relativeOutput -cne 'tests/conformance/targets/remaining-upstream-compatibility' -and
    -not $relativeOutput.StartsWith('reports/',[StringComparison]::Ordinal)) {
    throw 'Successor witness proposals must not overwrite historical scope artifacts'
}
$utf8 = [Text.UTF8Encoding]::new($false)
function Preserve-ProposalKeyOrder([object] $Value,[object] $Previous) {
    # A proposal regeneration changes source facts, not object semantics.
    # Retain existing JSON key order so 473 entries and their 26 future
    # routes do not acquire thousands of unrelated formatting changes from
    # PowerShell's randomized Hashtable enumeration.
    if($Value -is [Collections.IDictionary]){
        $ordered=[ordered]@{};$keys=@()
        if($Previous -is [Collections.IDictionary]){$keys+=@($Previous.Keys|Where-Object{$Value.Contains($_)})}
        $keys+=@($Value.Keys|Where-Object{$_ -cnotin $keys})
        foreach($key in $keys){$old=if($Previous -is [Collections.IDictionary] -and $Previous.Contains($key)){$Previous[$key]}else{$null}
            $ordered[$key]=Preserve-ProposalKeyOrder $Value[$key] $old}
        return $ordered
    }
    if($Value -is [Array]){
        $items=@(for($i=0;$i -lt $Value.Count;$i++){
            $old=if($Previous -is [Array] -and $i -lt $Previous.Count){$Previous[$i]}else{$null}
            Preserve-ProposalKeyOrder $Value[$i] $old
        })
        return ,$items
    }
    return $Value
}
function Save-Proposal([string] $Name,[object] $Value) {
    $path = Join-Path $output $Name
    if(Test-Path -LiteralPath $path){
        $previous=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
        $Value=Preserve-ProposalKeyOrder $Value $previous
    }
    [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n") + "`n",$utf8)
    return @{path=[IO.Path]::GetRelativePath($root,$path).Replace('\','/');sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
}
function Source-Hash([string] $Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Witness source identity must be repository-relative' }
    $path = [IO.Path]::GetFullPath((Join-Path $SourceRoot $Relative))
    $within = [IO.Path]::GetRelativePath($SourceRoot,$path)
    if ($within -eq '..' -or $within.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        [IO.Path]::IsPathRooted($within) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing or unsafe successor witness source: $Relative"
    }
    return (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
}
$consumerSource = 'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json'
$unitSource = 'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json'
$consumer = Get-Content (Join-Path $root $consumerSource) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
$unit = Get-Content (Join-Path $root $unitSource) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
if (@($consumer.cases).Count -ne 100 -or @($unit.entries).Count -ne 94) { throw 'Retained witness predecessor catalog changed' }
$predecessors = @(@{kind='consumer';path=$consumerSource;sha256=(Get-FileHash (Join-Path $root $consumerSource)).Hash.ToLowerInvariant()},
    @{kind='aunit';path=$unitSource;sha256=(Get-FileHash (Join-Path $root $unitSource)).Hash.ToLowerInvariant()})
$changed = @{}
foreach ($binding in @($consumer.source_bindings) + @($unit.bindings)) {
    $current = Source-Hash $binding.path
    if ($current -cne $binding.sha256) { $changed[$binding.path] = @{previous=$binding.sha256;current=$current} }
    $binding.sha256 = $current
}
foreach ($case in $consumer.cases) {
    $case.source_sha256 = Source-Hash $case.source
    if ($changed.ContainsKey($case.source) -and $case.Contains('function_sha256')) {
        # Whole-source rebinding is mechanically checkable. Do not carry a
        # stale function-level location/hash onto changed input as though it
        # had received a fresh semantic review; keep it explicitly historical.
        $case['historical_function_binding'] = @{line=$case.function_line;sha256=$case.function_sha256}
        [void]$case.Remove('function_line'); [void]$case.Remove('function_sha256')
        $case['function_source_review'] = 'pending'
    }
}
foreach ($entry in $unit.entries) { $entry.source_sha256 = Source-Hash $entry.case.Split('#')[0] }
if ($AdditionalConsumerCases -ne '') {
    $additional = Get-Content -LiteralPath $AdditionalConsumerCases -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $allowedContexts=(Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable).acceptance_contexts
    foreach ($case in $additional.cases) {
        $key = $case.source + '#' + $case.case_id
        if (@($consumer.cases | Where-Object { ($_.source + '#' + $_.case_id) -ceq $key }).Count -ne 0 -or
            $case.consumer -cnotin @('c-api','gc-api','io-api','foreign-api','format-api','value-api','auxiliary-api',
                'load-dump-api','debug-api','external-api','conversion-api','operator-api','index-type-api','base-closing-api','native-module-api','buffer-api',
                'allocator-api','allocator-panic-string-api','allocator-panic-number-api','substitution-api','buffer-private-t-api',
                'loadfile-api','loadfile-stdin-text-api','loadfile-stdin-binary-c-api','pointer-identity-api','concat-api','thread-reset-api','macro-api','macro-compat-api') -or
            $case.source -cnotmatch '^(?:c_api/tests/[a-zA-Z0-9_-]+\.(?:c|h)|tests/c/[a-zA-Z0-9_-]+\.c)$' -or
            (@($case.exact_witnesses).Count -eq 0 -and ($null -eq $case.pattern_witness -or
                -not $case.pattern_witness.StartsWith('^') -or -not $case.pattern_witness.EndsWith('$'))) -or
            $case.expected_count -ne 1) { throw 'Invalid or duplicate additional consumer witness proposal' }
        if($case.Contains('contexts') -and ($case.contexts -isnot [Array] -or $case.contexts.Count -eq 0 -or
            @($case.contexts|Sort-Object -Unique).Count -ne $case.contexts.Count -or
            @($case.contexts|Where-Object{$_ -cnotin $allowedContexts}).Count)){
            throw 'Additional C receiver applicability requires explicit supported contexts'
        }
        $case.source_sha256 = Source-Hash $case.source
        $case['runtime_acceptance'] = $false; $case['execution_evidence'] = @(); $case['independent_review_status'] = 'pending'
        $consumer.cases += $case
        if (@($consumer.source_bindings | Where-Object path -CEQ $case.source).Count -eq 0) {
            $consumer.source_bindings += @{path=$case.source;sha256=$case.source_sha256}
        }
    }
}
if ($AdditionalAUnitCases -ne '') {
    $additional = Get-Content -LiteralPath $AdditionalAUnitCases -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    foreach ($entry in $additional.entries) {
        if (@($unit.entries | Where-Object case -CEQ $entry.case).Count -ne 0 -or
            $entry.case -cnotmatch '^tests/src/[a-z0-9_-]+\.adb#[A-Za-z0-9_]+$' -or
            [string]::IsNullOrWhiteSpace([string]$entry.registered_label) -or
            $entry.required_stdout_line -cne ('OK ' + $entry.registered_label)) { throw 'Invalid or duplicate additional AUnit witness proposal' }
        $source = $entry.case.Split('#')[0]; $entry.source_sha256 = Source-Hash $source
        $entry.runtime_acceptance = $false; $entry.execution_evidence = @()
        $unit.entries += $entry
        if (@($unit.bindings | Where-Object path -CEQ $source).Count -eq 0) {
            $unit.bindings += @{path=$source;sha256=$entry.source_sha256}
        }
    }
}
foreach ($mapping in @($consumer,$unit)) {
    $mapping['target'] = 'remaining-upstream-compatibility'
    $mapping.author = 'Codex /root/validation_delivery'
    $mapping.independent_review_status = 'pending'
    $mapping.coverage_authority = $false; $mapping.runtime_acceptance = $false; $mapping.execution_evidence = @()
    $mapping['successor_review_requirement'] = 'Review changed source semantics and all named witness routes independently; fresh source hashes alone grant no execution or coverage authority.'
}
$consumer.kind = 'remaining-upstream-consumer-witness-author-proposal'
$unit.kind = 'remaining-upstream-aunit-witness-author-proposal'
[void][IO.Directory]::CreateDirectory($output)
$globalRecords = @(Get-Content -LiteralPath (Join-Path $SourceRoot 'tests/conformance/c-api.jsonl') |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 48 })
$retainedApi = @(Get-Content -LiteralPath (Join-Path $root 'tests/conformance/scopes/expanded-t-conformance.api.jsonl') |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 48 })
if ($globalRecords.Count -ne 473 -or $retainedApi.Count -ne 159) { throw 'Global/retained API predecessor inventory changed' }
$apiProposals = @()
foreach ($record in $globalRecords) {
    $old = @($retainedApi | Where-Object id -CEQ $record.id)
    if ($old.Count -gt 1) { throw 'Retained API predecessor contains duplicate identities' }
    $previous = if ($old.Count -eq 1) { @($consumer.entries | Where-Object id -CEQ $record.id)[0] } else { $null }
    if ($null -ne $previous) {
        # The retained API projection can acquire a separately reviewed repair
        # route after the frozen author catalogue (for example PR10's failed
        # coroutine status witness). Preserve both predecessor route sets in
        # the NEW pending successor; do not silently lose either expectation.
        foreach ($case in $old[0].named_cases) {
            $key = $case.source + '#' + $case.id
            if ($key -cnotin $previous.cases) { $previous.cases += $key }
        }
    }
    # Preserve old semantic routes as proposals needing fresh current-source
    # review. Header kind alone does not classify a macro as a runtime call,
    # constant, conditional alternative, type or configuration declaration.
    $apiProposals += [ordered]@{id=$record.id;header=$record.header;kind=$record.kind;name=$record.name;
        line=$record.line;byte_offset=$record.byte_offset;byte_length=$record.byte_length;anchor_sha256=$record.anchor_sha256;
        declaration=$record.declaration;conditions=@($record.conditions);classification='pending-semantic-review';
        invariant=$(if($null -ne $previous){$previous.invariant}else{$null});
        boundaries=$(if($null -ne $previous){$previous.boundaries}else{$null});
        retained_route=($old.Count -eq 1);
        named_c_cases=@(if($null -ne $previous){$previous.cases});
        named_aunit_cases=@(if($old.Count -eq 1){$old[0].named_aunit_cases | ForEach-Object { $_.source + '#' + $_.id }});
        compiled_witnesses=@();applicability_review=$null;review_status='pending';
        runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@()}
}
$api = [ordered]@{schema_version=1;kind='remaining-upstream-global-api-author-proposal';
    target='remaining-upstream-compatibility';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
    author='Codex /root/validation_delivery';independent_review_status='pending';runtime_acceptance=$false;
    coverage_authority=$false;source_snapshot=$sourceSnapshot;retained_api_routes=159;global_api_entries=473;entries=$apiProposals;
    requirements=@('Every global entry requires independent semantic classification and fresh context-specific evidence.',
        'Actual function/function-like-macro behavior uses named executed C or Ada cases.',
        'Types, constants and declaration-only entries use appropriate actual compiled ABI/layout/header witnesses; do not invent runtime calls.',
        'Conditional declarations require independently reviewed original-source applicability and measured compiled-configuration witnesses.',
        'Preserve all 159 retained API routes and original 100 C/94 AUnit witness identities and protocols.',
        'No passed ledger status, token mention, registration or author proposal alone establishes execution or acceptance.')}
if($AdditionalApiRoutes -ne ''){
    $routes=Get-Content -LiteralPath $AdditionalApiRoutes -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $seenRoutes=@{};$knownC=@{};$knownUnit=@{}
    foreach($case in $consumer.cases){$knownC[$case.source+'#'+$case.case_id]=$case}
    foreach($case in $unit.entries){$knownUnit[$case.case]=$true}
    $suite=Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    foreach($route in $routes.entries){
        $entry=@($api.entries|Where-Object id -CEQ $route.id)
        if($entry.Count -ne 1 -or $seenRoutes.ContainsKey($route.id) -or $route.review_status -cne 'pending' -or
            $route.runtime_acceptance -isnot [bool] -or $route.runtime_acceptance -or
            $route.coverage_authority -isnot [bool] -or $route.coverage_authority -or @($route.execution_evidence).Count -ne 0 -or
            $route.proposed_classification -cne 'runtime-behavior' -or
            [string]::IsNullOrWhiteSpace([string]$route.invariant) -or [string]::IsNullOrWhiteSpace([string]$route.boundaries) -or
            $route.named_c_cases -isnot [Array] -or $route.named_aunit_cases -isnot [Array] -or
            (@($route.named_c_cases).Count+@($route.named_aunit_cases).Count) -eq 0){
            throw 'Additional API routes require distinct pending actual named behavioral witnesses'
        }
        $entry=$entry[0];$seenRoutes[$route.id]=$true
        if($entry.kind -cnotin @('function','data') -and ($entry.kind -cne 'macro' -or
            $entry.declaration -cnotmatch ('^#define\s+'+[regex]::Escape($entry.name)+'\('))){
            throw 'Declaration-only entries cannot acquire invented runtime route proposals'
        }
        foreach($case in $route.named_c_cases){if(-not $knownC.ContainsKey($case)){throw 'Additional API route names an unknown actual C witness'}}
        foreach($case in $route.named_aunit_cases){if(-not $knownUnit.ContainsKey($case)){throw 'Additional API route names an unknown actual AUnit witness'}}
        if(-not $entry.retained_route){$entry.invariant=$route.invariant;$entry.boundaries=$route.boundaries}
        $entry['proposed_classification']=$route.proposed_classification
        $entry['proposed_invariant']=$route.invariant;$entry['proposed_boundaries']=$route.boundaries
        $entry.named_c_cases=@((@($entry.named_c_cases)+@($route.named_c_cases))|Sort-Object -Unique)
        $entry.named_aunit_cases=@((@($entry.named_aunit_cases)+@($route.named_aunit_cases))|Sort-Object -Unique)
        # These are required future evidence routes, not observations. Keep
        # the actual semantic classification/review pending and avoid the
        # final schema's runtime-observed disposition until independent review.
        $entry['proposed_context_witnesses']=@(foreach($context in $suite.acceptance_contexts){
            $activeC=@($route.named_c_cases|Where-Object{-not $knownC[$_].Contains('contexts') -or $context -cin $knownC[$_].contexts})
            @{context=$context;required_disposition=$(if($activeC.Count+@($route.named_aunit_cases).Count -gt 0){'runtime-observed'}else{'pending-original-source-applicability-review'});named_c_cases=$activeC;
                named_aunit_cases=@($route.named_aunit_cases);compiled_witnesses=@();review_status='pending';runtime_acceptance=$false}
        })
    }
}
$consumerIdentity = Save-Proposal 'consumer-witness.author-proposal.json' $consumer
$unitIdentity = Save-Proposal 'aunit-witness.author-proposal.json' $unit
$apiIdentity = Save-Proposal 'global-api.author-proposal.json' $api
$policy = @{schema_version=1;kind='target-witness-policy';target='remaining-upstream-compatibility';
    reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';consumer=$consumerIdentity;aunit=$unitIdentity;global_api=$apiIdentity;
    source_snapshot=$sourceSnapshot;runtime_acceptance=$false;coverage_authority=$false;
    review=@{status='pending';author='Codex /root/validation_delivery';reviewer=$null;artifact=$null;artifact_sha256=$null}}
if($CompiledWitnessMapping -ne ''){
    $compiledFull=if([IO.Path]::IsPathRooted($CompiledWitnessMapping)){$CompiledWitnessMapping}else{Join-Path $root $CompiledWitnessMapping}
    $compiledRelative=[IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($compiledFull)).Replace('\','/')
    if(-not $compiledRelative.StartsWith('tests/conformance/targets/remaining-upstream-compatibility/',[StringComparison]::Ordinal) -and
        -not $compiledRelative.StartsWith('reports/',[StringComparison]::Ordinal)){throw 'Compiled source mapping must remain target-owned or disposable'}
    $compiled=Get-Content $compiledFull -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    Import-Module (Join-Path $PSScriptRoot 'HeaderDeclarationProbes.psm1')
    Assert-HeaderDeclarationMapping -Root $SourceRoot -Mapping $compiled
    $policy.compiled=@{path=$compiledRelative;sha256=(Get-FileHash $compiledFull).Hash.ToLowerInvariant()}
}
$policyIdentity = Save-Proposal 'witness-policy.author-proposal.json' $policy
$summary = @{schema_version=1;kind='remaining-upstream-witness-successor-author-index';target='remaining-upstream-compatibility';
    predecessors=$predecessors;source_snapshot=$sourceSnapshot;changed_source_bindings=$changed;retained_consumer_cases=100;retained_aunit_cases=94;
    proposed_consumer_cases=@($consumer.cases).Count;proposed_aunit_cases=@($unit.entries).Count;
    consumer=$consumerIdentity;aunit=$unitIdentity;global_api=$apiIdentity;witness_policy=$policyIdentity;global_api_entries=473;retained_api_routes=159;
    independent_review_status='pending';coverage_authority=$false;runtime_acceptance=$false}
$index = Save-Proposal 'witnesses.author-index.json' $summary
Write-Output "AUTHOR PROPOSALS ONLY: retained 100 C / 94 AUnit witnesses; proposed $($summary.proposed_consumer_cases) C / $($summary.proposed_aunit_cases) AUnit; changed sources=$($changed.Count); index=$($index.path)"
Write-Output 'No historical artifact, semantic approval, execution evidence or acceptance status was changed.'
