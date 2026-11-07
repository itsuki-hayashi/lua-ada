param(
    [string] $SourceRoot = '',
    [string] $OutputDirectory = '',
    [string] $AdditionalConsumerCases = '',
    [string] $AdditionalAUnitCases = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($SourceRoot -eq '') { $SourceRoot = $root }
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$output = if ($OutputDirectory -ne '') { [IO.Path]::GetFullPath($OutputDirectory) }
    else { Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility' }
$relativeOutput = [IO.Path]::GetRelativePath($root,$output).Replace('\','/')
if ($relativeOutput -cne 'tests/conformance/targets/remaining-upstream-compatibility' -and
    -not $relativeOutput.StartsWith('reports/',[StringComparison]::Ordinal)) {
    throw 'Successor witness proposals must not overwrite historical scope artifacts'
}
$utf8 = [Text.UTF8Encoding]::new($false)
function Save-Proposal([string] $Name,[object] $Value) {
    $path = Join-Path $output $Name
    [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n") + "`n",$utf8)
    return @{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
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
    foreach ($case in $additional.cases) {
        $key = $case.source + '#' + $case.case_id
        if (@($consumer.cases | Where-Object { ($_.source + '#' + $_.case_id) -ceq $key }).Count -ne 0 -or
            $case.consumer -cnotin @('c-api','gc-api','io-api','foreign-api') -or
            $case.source -cnotmatch '^(c_api/tests|tests/c)/[a-zA-Z0-9_-]+\.c$' -or
            @($case.exact_witnesses).Count -eq 0 -or $case.expected_count -ne 1) { throw 'Invalid or duplicate additional consumer witness proposal' }
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
$consumerIdentity = Save-Proposal 'consumer-witness.author-proposal.json' $consumer
$unitIdentity = Save-Proposal 'aunit-witness.author-proposal.json' $unit
$summary = @{schema_version=1;kind='remaining-upstream-witness-successor-author-index';target='remaining-upstream-compatibility';
    predecessors=$predecessors;changed_source_bindings=$changed;retained_consumer_cases=100;retained_aunit_cases=94;
    proposed_consumer_cases=@($consumer.cases).Count;proposed_aunit_cases=@($unit.entries).Count;
    consumer=$consumerIdentity;aunit=$unitIdentity;independent_review_status='pending';coverage_authority=$false;runtime_acceptance=$false}
$index = Save-Proposal 'witnesses.author-index.json' $summary
Write-Output "AUTHOR PROPOSALS ONLY: retained 100 C / 94 AUnit witnesses; proposed $($summary.proposed_consumer_cases) C / $($summary.proposed_aunit_cases) AUnit; changed sources=$($changed.Count); index=$($index.path)"
Write-Output 'No historical artifact, semantic approval, execution evidence or acceptance status was changed.'
