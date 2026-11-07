Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')

function Get-TargetAggregateClaims {
    param([Collections.IDictionary] $Specification)
    $claims=@{}
    foreach($field in @('id','target','reference_revision','configuration','implementation','platform','original_sources','selections','synthetic_fixture')){
        $claims[$field]=$Specification[$field]
    }
    return $claims
}

function Get-TargetAggregateReplay {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][Collections.IDictionary] $Specification,
          [Parameter(Mandatory)][Collections.IDictionary] $Suite,
          [Parameter(Mandatory)][string] $Configuration,
          [Parameter(Mandatory)][string] $Implementation,
          [Parameter(Mandatory)][string] $Platform,
          [Parameter(Mandatory)][string] $PolicySha256,
          [Parameter(Mandatory)][Collections.IDictionary] $ResolvedExclusions,
          [switch] $AllowSynthetic)
    if($Specification.schema_version -ne 1 -or $Specification.kind -cne 'target-aggregate-replay' -or
        $Specification.id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
        $Specification.target -cne 'remaining-upstream-compatibility' -or
        $Specification.reference_revision -cne $Suite.reference_revision -or
        $Specification.configuration -cne $Configuration -or $Specification.implementation -cne $Implementation -or
        $Specification.platform -cne $Platform -or $Implementation -cnotin @('Ada','ReferenceC') -or
        $Specification.synthetic_fixture -isnot [bool] -or ($Specification.synthetic_fixture -and -not $AllowSynthetic) -or
        $Specification.runtime_acceptance -isnot [bool] -or $Specification.runtime_acceptance -or
        $Specification.coverage_authority -isnot [bool] -or $Specification.coverage_authority -or
        @($Suite.files).Count -ne 34 -or @($Specification.original_sources).Count -ne 34 -or
        @($Specification.selections).Count -eq 0){throw 'Invalid aggregate replay identity or complete original source set'}
    # Every unchanged and transformed source remains an explicit obligation.
    # Selection cannot hide an omitted helper or replace the all.lua protocol.
    $sources=@{};$expected=@();$transforms=@();$excluded=@();$seen=@{}
    foreach($source in $Suite.files){
        $matches=@($Specification.original_sources|Where-Object path -CEQ $source.path)
        if($sources.ContainsKey($source.path) -or $matches.Count -ne 1 -or $matches[0].sha256 -cne $source.sha256){
            throw 'Aggregate replay original source hash or partition differs'
        }
        $null=Resolve-ReviewedFile -Root $Root -Path ('references/lua/testes/'+$source.path) -Sha256 $source.sha256
        $sources[$source.path]=$source
    }
    foreach($selection in $Specification.selections){
        if(-not $sources.ContainsKey($selection.source) -or $selection.source -ceq 'heavy.lua' -or
            $seen.ContainsKey($selection.source) -or $selection.kind -cnotin @('equivalent','t-private')){
            throw 'Aggregate replay has unknown duplicate heavy or mixed source selections'
        }
        $seen[$selection.source]=$true
        $path=Resolve-ReviewedFile -Root $Root -Path $selection.manifest.path -Sha256 $selection.manifest.sha256
        $mapping=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
        if($mapping.source -cne ('references/lua/testes/'+$selection.source) -or
            $mapping.source_sha256 -cne $sources[$selection.source].sha256 -or
            $mapping.configuration -cnotin @($Configuration,'default-and-upstream-test')){
            throw 'Aggregate selection identifies another source or configuration'
        }
        if($selection.kind -ceq 't-private'){
            if($Implementation -cne 'Ada' -or $Configuration -cne 'upstream-test'){
                throw 'Aggregate T adaptation cannot replace default or original C execution'
            }
            $replay=Get-ConformanceTReplay -Root $Root -Specification $mapping -PolicySha256 $PolicySha256 -ResolvedExclusions $ResolvedExclusions
            $excluded+=@($replay.excluded_obligations)
        }else{
            $replay=Get-ConformanceEquivalentReplay -Root $Root -Specification $mapping
            if($replay.disposition -ceq 'ada-internal-equivalent' -and $Implementation -cne 'Ada'){
                throw 'Aggregate Ada equivalent cannot replace original C execution'
            }
            if($replay.disposition -ceq 'native-platform-equivalent' -and $mapping.platform -cne $Platform){
                throw 'Aggregate native equivalent identifies another platform'
            }
        }
        $transforms+=@{source=$selection.source;kind=$selection.kind;manifest=$selection.manifest;mapping=$mapping;replay=$replay}
    }
    $required=if($Implementation -ceq 'Ada' -and $Configuration -ceq 'upstream-test'){
        @($ResolvedExclusions.Values|Where-Object source -CNE heavy.lua|ForEach-Object id|Sort-Object)
    }else{@()}
    if((@($excluded|Sort-Object) -join '|') -cne (@($required) -join '|') -or
        @($excluded|Sort-Object -Unique).Count -ne $excluded.Count){throw 'Aggregate T replay does not cover exactly its approved exclusions'}
    foreach($source in $Suite.files){
        $changed=@($transforms|Where-Object source -CEQ $source.path)
        $expected+=@{path=$source.path;sha256=$(if($changed.Count){$changed[0].replay.sha256}else{$source.sha256});original_sha256=$source.sha256}
    }
    $review=$Specification.review
    if($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$review.author) -or
        [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer){
        throw 'Aggregate replay requires independent source selection review'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    if($approval.schema_version -ne 1 -or $approval.kind -cne 'target-aggregate-replay-approval' -or
        $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or $approval.decision -cne 'accepted' -or
        $approval.synthetic_fixture -isnot [bool] -or ($approval.synthetic_fixture -and -not $AllowSynthetic) -or
        $approval.selection_sha256 -cne (Get-TargetWitnessPayloadHash (Get-TargetAggregateClaims $Specification))){
        throw 'Aggregate replay independent approval differs from its exact source selection'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $approval.review_evidence.path -Sha256 $approval.review_evidence.sha256
    $narrative=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if($narrative.reviewer -cne $review.reviewer -or $narrative.decision -cne 'accepted' -or $narrative.replay_id -cne $Specification.id -or
        $narrative.synthetic_fixture -isnot [bool] -or ($narrative.synthetic_fixture -and -not $AllowSynthetic) -or
        $narrative.preserves_aggregate_protocol -isnot [bool] -or -not $narrative.preserves_aggregate_protocol -or
        $narrative.preserves_public_assertions -isnot [bool] -or -not $narrative.preserves_public_assertions -or
        [string]::IsNullOrWhiteSpace([string]$narrative.source_preservation)){
        throw 'Aggregate replay narrative does not preserve the original driver and public checks'
    }
    return @{transforms=$transforms;expected_sources=$expected;original_sources=@($Specification.original_sources);
        excluded_obligations=@($excluded|Sort-Object);selection_sha256=$approval.selection_sha256;
        disposition='reviewed-aggregate-replay';runtime_acceptance=$false;coverage_authority=$false}
}

function New-TargetAggregateExecutionTree {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $SourceDirectory,
          [Parameter(Mandatory)][string] $Destination,[Parameter(Mandatory)][Collections.IDictionary] $Replay)
    $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),[IO.Path]::GetFullPath($Destination)).Replace('\','/')
    if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal)){
        throw 'Aggregate execution tree must be a new disposable reports directory'
    }
    $originalChanges=Test-ConformanceFixtureHashes -Directory $SourceDirectory -Records $Replay.original_sources
    if($originalChanges.Count -ne 0){
        throw 'Aggregate original fixture snapshot changed before execution'
    }
    # Copy the complete prepared fixture tree, including native modules and
    # helpers, before changing only explicitly reviewed Lua source bytes. The
    # first copy remains immutable evidence of the pinned original inputs.
    $records=Copy-ConformanceFixtures -Source $SourceDirectory -Destination $Destination
    foreach($transform in $Replay.transforms){
        [IO.File]::WriteAllBytes((Join-Path $Destination $transform.source),$transform.replay.bytes)
        $record=@($records|Where-Object path -CEQ $transform.source)
        if($record.Count -ne 1){throw 'Aggregate transformed source missing from execution copy'}
        $record[0].sha256=$transform.replay.sha256
    }
    $copyChanges=Test-ConformanceFixtureHashes -Directory $Destination -Records $records
    $originalChanges=Test-ConformanceFixtureHashes -Directory $SourceDirectory -Records $Replay.original_sources
    if($copyChanges.Count -ne 0 -or $originalChanges.Count -ne 0){
        throw 'Aggregate execution copy or preserved original source differs'
    }
    return ,$records
}

function Assert-TargetAggregateReportReplay {
    param([string] $Root,[string] $ArtifactRoot,[Collections.IDictionary] $Report,
          [Collections.IDictionary] $Contract,[Collections.IDictionary] $Suite,
          [Collections.IDictionary] $ResolvedExclusions,[switch] $AllowSynthetic)
    $identity=$Report.aggregate_replay
    if($Report.operation -cne 'aggregate' -or $Report.execution_disposition -cne 'reviewed-aggregate-replay' -or
        $identity.entry -cne 'all.lua' -or $Report.process.working_directory -cne $identity.execution_directory -or
        $identity.original_directory -ceq $identity.execution_directory -or
        @($Report.process.arguments).Count -ne 3 -or $Report.process.arguments[0] -cne '-e' -or
        $Report.process.arguments[2] -cne 'all.lua' -or @($identity.execution_changes).Count -ne 0){
        throw 'Aggregate process does not execute the exact reviewed driver tree'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $identity.manifest_path -Sha256 $identity.manifest_sha256
    $spec=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $replay=Get-TargetAggregateReplay -Root $Root -Specification $spec -Suite $Suite -Configuration $Report.requested_configuration `
        -Implementation $Report.target -Platform $Report.host.platform -PolicySha256 $Report.exclusion_policy_sha256 `
        -ResolvedExclusions $ResolvedExclusions -AllowSynthetic:$AllowSynthetic
    $contractIdentity=$Contract.aggregate_replays[$Report.target]
    if($contractIdentity.manifest_sha256 -cne $identity.manifest_sha256 -or
        $contractIdentity.selection_sha256 -cne $replay.selection_sha256 -or
        $contractIdentity.executed_sources_sha256 -cne (Get-TargetWitnessPayloadHash @{sources=$replay.expected_sources}) -or
        $contractIdentity.setup_sha256 -cne (Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes($Report.process.arguments[1]))) -or
        $contractIdentity.disposition -cne 'reviewed-aggregate-replay' -or
        $identity.selection_sha256 -cne $replay.selection_sha256 -or
        (Get-TargetWitnessPayloadHash @{sources=$identity.expected_sources}) -cne (Get-TargetWitnessPayloadHash @{sources=$replay.expected_sources}) -or
        (@($Report.excluded_obligations|Sort-Object) -join '|') -cne (@($replay.excluded_obligations) -join '|')){
        throw 'Aggregate execution contract or exclusion set differs from reviewed reconstruction'
    }
    foreach($record in $Report.fixture_records){
        $null=Resolve-ConformanceObservation -Root $ArtifactRoot -Identity @{
            path=($identity.original_directory.TrimEnd('/','\')+'/'+$record.path);sha256=$record.sha256}
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($record in $identity.execution_input_records){
        if($record.path -cne $record.path.Replace('\','/') -or [IO.Path]::IsPathRooted($record.path) -or
            $record.path.Contains(':') -or $record.path.Contains('//') -or $record.path -match '(^|/)\.\.?(/|$)' -or
            -not $seen.Add($record.path)){throw 'Aggregate execution input aliases or duplicate files'}
        $null=Resolve-ConformanceObservation -Root $ArtifactRoot -Identity @{
            path=($identity.execution_directory.TrimEnd('/','\')+'/'+$record.path);sha256=$record.sha256}
    }
    foreach($expected in $replay.expected_sources){
        $records=@($identity.execution_input_records|Where-Object path -CEQ $expected.path)
        if($records.Count -ne 1 -or $records[0].sha256 -cne $expected.sha256){throw 'Aggregate executed source set differs from exact reviewed bytes'}
    }
    return $replay
}

function Get-TargetAggregateNativeProofs {
    param([string] $Root,[string] $ArtifactRoot,[Collections.IDictionary] $Report,
          [Collections.IDictionary] $Replay,[Collections.IDictionary] $Identity=$null,[switch] $RequireRuntimeEvidence)
    $native=@($Replay.transforms|Where-Object{ $_.replay.disposition -ceq 'native-platform-equivalent' })
    if($native.Count -eq 0){return ,@()}
    if($null -eq $Identity){
        if($RequireRuntimeEvidence){throw 'Aggregate native transformations lack source-linked original C applicability'}
        return ,@()
    }
    $path=Resolve-ConformanceObservation -Root $ArtifactRoot -Identity $Identity
    $index=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    if($index.schema_version -ne 1 -or $index.kind -cne 'target-aggregate-native-applicability' -or
        $index.context -cne $Report.acceptance_context -or $index.revision -cne $Report.repository_revision -or
        $index.synthetic_fixture -isnot [bool] -or ($index.synthetic_fixture -and $RequireRuntimeEvidence) -or
        @($index.mappings).Count -ne $native.Count){throw 'Aggregate native applicability index identifies another context or transform set'}
    $proofs=@();$seen=@{}
    foreach($transform in $native){
        $matches=@($index.mappings|Where-Object{ $_.source -ceq $transform.source -and $_.manifest_sha256 -ceq $transform.manifest.sha256 })
        if($matches.Count -ne 1 -or $seen.ContainsKey($transform.source)){throw 'Aggregate native applicability has missing or duplicate source bindings'}
        $seen[$transform.source]=$true
        $proofs+=Assert-ConformanceNativeApplicability -Root $Root -ArtifactRoot $ArtifactRoot -Identity $matches[0].identity `
            -Specification $transform.mapping -ManifestSha256 $transform.manifest.sha256 -Configuration $Report.requested_configuration `
            -Platform $Report.host.platform -Revision $Report.repository_revision -ExpectedContext $Report.acceptance_context `
            -RequireRuntimeEvidence:$RequireRuntimeEvidence
    }
    return ,$proofs
}

Export-ModuleMember -Function Get-TargetAggregateClaims, Get-TargetAggregateReplay, New-TargetAggregateExecutionTree,
    Assert-TargetAggregateReportReplay, Get-TargetAggregateNativeProofs
