Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConsumerEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'AUnitEvidence.psm1')

function Assert-MatrixReview {
    param([Collections.IDictionary] $Review)
    # Use the same status vocabulary as New-ConformanceEquivalent. A valid
    # shape does not grant review authority: the caller still verifies the
    # source-bound artifact, execution contracts and complete scoped ledger.
    if ($null -eq $Review) { throw 'Matrix requires completed independent review' }
    foreach ($field in @('author','reviewer','artifact')) {
        if ([string]::IsNullOrWhiteSpace([string]$Review[$field])) {
            throw 'Matrix requires completed independent review'
        }
    }
    if ($Review.status -cne 'accepted' -or $Review.author -ceq $Review.reviewer) {
        throw 'Matrix requires completed independent review'
    }
}

function Assert-ScopedMatrixIndex {
    param([Parameter(Mandatory)][Collections.IDictionary] $Manifest,
          [Parameter(Mandatory)][string[]] $Contexts)
    if ($Manifest.schema_version -ne 1 -or $Manifest.scope -cne 'gc-io-events' -or
        $Manifest.revision -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid scoped matrix identity' }
    $files = @('events.lua','gc.lua','gengc.lua','files.lua')
    $seen = @{}
    foreach ($entry in $Manifest.operations) {
        if ($entry.file -cnotin $files -or $entry.context -cnotin $Contexts) {
            throw 'Unknown scoped matrix file/context'
        }
        $key = $entry.context + '/' + $entry.file
        if ($seen.ContainsKey($key)) { throw "Duplicate scoped matrix operation: $key" }
        $seen[$key] = $true
        foreach ($target in @('ada','c')) {
            if ($null -eq $entry[$target] -or
                [string]::IsNullOrWhiteSpace([string]$entry[$target].report) -or
                [string]::IsNullOrWhiteSpace([string]$entry[$target].artifact_root) -or
                $entry[$target].sha256 -cnotmatch '^[0-9a-f]{64}$') {
                throw "Missing matrix $target report identity: $key"
            }
        }
    }
    foreach ($context in $Contexts) {
        foreach ($file in $files) {
            if (-not $seen.ContainsKey("$context/$file")) {
                throw "Incomplete scoped matrix: $context/$file"
            }
        }
    }
}

function Read-MatrixHashedJson {
    param([string] $Path, [string] $Hash)
    if ($Hash -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Hash) {
        throw "Matrix artifact hash mismatch: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
}

function Resolve-MatrixCapture {
    param([string] $Original, [string] $ArtifactRoot, [string] $Hash)
    # CI hosts have different absolute workspaces. Bundles retain the reports/
    # subtree; rebase only that subtree, and verify every byte after rebasing.
    $normalized = $Original.Replace('\','/')
    $offset = $normalized.LastIndexOf('/reports/', [StringComparison]::Ordinal)
    if ($offset -lt 0) { throw 'Matrix capture is outside the reports subtree' }
    $rootPath = [IO.Path]::GetFullPath($ArtifactRoot)
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $normalized.Substring($offset + 1)))
    $relative = [IO.Path]::GetRelativePath($rootPath, $path)
    if ($relative.StartsWith('..') -or [IO.Path]::IsPathRooted($relative)) {
        throw 'Matrix capture escapes its artifact bundle'
    }
    if ($Hash -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Hash) {
        throw "Matrix capture hash mismatch: $Original"
    }
    return $path
}

function Set-MatrixProcessCaptures {
    param([Collections.IDictionary] $Process, [string] $ArtifactRoot)
    foreach ($stream in @('stdout','stderr')) {
        $Process["${stream}_path"] = Resolve-MatrixCapture -Original $Process["${stream}_path"] `
            -ArtifactRoot $ArtifactRoot -Hash $Process["${stream}_sha256"]
        if ((Get-Item -LiteralPath $Process["${stream}_path"]).Length -ne $Process["${stream}_bytes"]) {
            throw 'Matrix process capture length mismatch'
        }
    }
}

function Test-ScopedMatrix {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][string] $ManifestPath,
          [switch] $RequireScopedAcceptance)
    $manifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
    $bundle = Split-Path -Parent $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $suite = Get-Content -LiteralPath (Join-Path $Root 'tests/conformance/suite.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 32
    Assert-ScopedMatrixIndex -Manifest $manifest -Contexts $suite.acceptance_contexts
    $scope = Test-ConformanceScope -Root $Root -RequireScopedComplete:$RequireScopedAcceptance
    if ($RequireScopedAcceptance) {
        foreach ($field in @('author','reviewer','artifact','rationale')) {
            if ($null -eq $manifest.review -or [string]::IsNullOrWhiteSpace([string]$manifest.review[$field])) {
                throw 'Matrix requires independent reconciliation review'
            }
        }
        Assert-MatrixReview -Review $manifest.review
        Assert-MatrixReviewBinding -Root $Root -Manifest $manifest
        $head = (& git -C $Root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $head -cne $manifest.revision) { throw 'Matrix is not the final checkout revision' }
        $dirty = @(& git -C $Root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
        if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Matrix acceptance requires a clean final checkout' }
        # API status alone cannot prove a named C regression executed. Replay
        # its independently reviewed witnesses from every context's captures.
        $identity = $manifest.consumer_mapping
        $mappingPath = Resolve-ReviewedFile -Root $Root -Path $identity.path -Sha256 $identity.sha256
        $reviewPath = Resolve-ReviewedFile -Root $Root -Path $identity.review -Sha256 $identity.review_sha256
        $mapping = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        $review = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($review.decision -cne 'accepted-semantic-witness-mapping' -or
            [string]::IsNullOrWhiteSpace($review.author) -or
            [string]::IsNullOrWhiteSpace($review.reviewer) -or $review.author -ceq $review.reviewer -or
            $review.author -cne $mapping.author -or $review.proposal.path -cne $identity.path -or
            $review.proposal.sha256 -cne $identity.sha256) { throw 'Consumer mapping lacks independent review' }
        foreach ($source in $review.source_bindings) {
            [void](Resolve-ReviewedFile -Root $Root -Path $source.path -Sha256 $source.sha256)
        }
        foreach ($case in $mapping.cases) {
            if (@($review.source_bindings | Where-Object {
                $_.path -ceq $case.source -and $_.sha256 -ceq $case.source_sha256
            }).Count -ne 1) { throw 'Reviewed consumer source binding incomplete' }
        }
        $api = @(Read-ConformanceJsonLines -Path (Join-Path $Root 'tests/conformance/scopes/gc-io-events.api.jsonl'))
        if (@($mapping.entries).Count -ne $api.Count) { throw 'Consumer mapping API inventory differs' }
        foreach ($obligation in $api) {
            $matched = @($mapping.entries | Where-Object { $_.id -ceq $obligation.id })
            if ($matched.Count -ne 1) { throw 'Consumer mapping API obligation missing/duplicate' }
            $expected = @($obligation.named_cases | ForEach-Object { $_.source + '#' + $_.id } | Sort-Object -Unique)
            $actual = @($matched[0].cases | Sort-Object -Unique)
            if (($expected -join "`n") -cne ($actual -join "`n")) { throw 'Consumer mapping API cases differ' }
            foreach ($case in $expected) {
                if (@($mapping.cases | Where-Object { ($_.source + '#' + $_.case_id) -ceq $case }).Count -ne 1) {
                    throw 'Consumer mapping case missing/duplicate'
                }
            }
        }
        $contexts = @{}
        $consumerReports = @{}
        foreach ($consumer in $manifest.named_consumers) {
            if ($consumer.context -cnotin $suite.acceptance_contexts -or $contexts.ContainsKey($consumer.context)) {
                throw 'Unknown/duplicate named consumer context'
            }
            $consumerReport = Read-MatrixHashedJson -Path (Join-Path $bundle $consumer.report) -Hash $consumer.sha256
            foreach ($kind in @('gc','io')) {
                $contract = $consumerReport["${kind}_contract"]
                foreach ($name in @("${kind}_api_contract.c", "${kind}_contract.h", 'consumer_allocator.h')) {
                    $source = @($contract.sources | Where-Object { $_.file -ceq "c_api/tests/$name" })
                    if ($source.Count -ne 1) { throw 'Consumer oracle driver source missing/duplicate' }
                    [void](Resolve-ReviewedFile -Root $Root -Path $source[0].file -Sha256 $source[0].sha256)
                }
            }
            $consumerRoot = [IO.Path]::GetFullPath((Join-Path $bundle $consumer.artifact_root))
            $resolve = { param($path,$hash)
                Resolve-MatrixCapture -Original $path -ArtifactRoot $consumerRoot -Hash $hash
            }
            $contexts[$consumer.context] = Test-NamedConsumerEvidence -Report $consumerReport -Mapping $mapping `
                -Revision $manifest.revision -Context $consumer.context -ResolveCapture $resolve
            $consumerReports[$consumer.context] = $consumerReport
        }
        foreach ($context in $suite.acceptance_contexts) {
            if (-not $contexts.ContainsKey($context)) { throw "Missing named consumer context: $context" }
        }
        $identity = $manifest.aunit_mapping
        $mappingPath = Resolve-ReviewedFile -Root $Root -Path $identity.path -Sha256 $identity.sha256
        $reviewPath = Resolve-ReviewedFile -Root $Root -Path $identity.review -Sha256 $identity.review_sha256
        $aunitMapping = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        $aunitReview = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($aunitReview.decision -cne 'accepted-semantic-witness-mapping' -or
            [string]::IsNullOrWhiteSpace($aunitReview.author) -or
            [string]::IsNullOrWhiteSpace($aunitReview.reviewer) -or
            $aunitReview.author -ceq $aunitReview.reviewer -or $aunitReview.author -cne $aunitMapping.author -or
            $aunitReview.proposal.path -cne $identity.path -or $aunitReview.proposal.sha256 -cne $identity.sha256) {
            throw 'AUnit mapping lacks independent review'
        }
        foreach ($binding in $aunitMapping.bindings) {
            [void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)
        }
        foreach ($entry in $aunitMapping.entries) {
            if (@($aunitMapping.bindings | Where-Object {
                $_.path -ceq $entry.case.Split('#')[0] -and $_.sha256 -ceq $entry.source_sha256
            }).Count -ne 1) { throw 'Reviewed AUnit source binding incomplete' }
        }
        $aunitContexts = @{}
        foreach ($unit in $manifest.named_aunit) {
            if ($unit.context -cnotin $suite.acceptance_contexts -or $aunitContexts.ContainsKey($unit.context)) {
                throw 'Unknown/duplicate AUnit context'
            }
            $unitReport = Read-MatrixHashedJson -Path (Join-Path $bundle $unit.report) -Hash $unit.sha256
            $unitRoot = [IO.Path]::GetFullPath((Join-Path $bundle $unit.artifact_root))
            $resolve = {param($path,$hash) Resolve-MatrixCapture -Original $path -ArtifactRoot $unitRoot -Hash $hash}
            $aunitContexts[$unit.context] = Test-NamedAUnitEvidence -Report $unitReport -Mapping $aunitMapping `
                -Revision $manifest.revision -Context $unit.context -ResolveCapture $resolve
            foreach ($library in $unitReport.library_files) {
                if (@($consumerReports[$unit.context].library_files | Where-Object {
                    $_.file -ceq $library.file -and $_.sha256 -ceq $library.sha256
                }).Count -ne 1) { throw 'AUnit and C consumer libraries differ' }
            }
        }
        foreach ($context in $suite.acceptance_contexts) {
            if (-not $aunitContexts.ContainsKey($context)) { throw "Missing AUnit context: $context" }
        }
    }
    $coverage = @{}
    foreach ($file in $scope.Definition.files) {
        $source = @($suite.files | Where-Object { $_.path -ceq $file.path })[0]
        foreach ($record in Read-ConformanceJsonLines -Path (Join-Path $Root "tests/conformance/$($source.coverage_file)")) {
            $coverage[$record.id] = $record
        }
    }
    $records = @()
    foreach ($entry in $manifest.operations) {
        $configuration = $entry.context.Split('/')[0]
        $referenceNativeFacts = $null
        $contract = $null
        if ($RequireScopedAcceptance) {
            $contract = Read-MatrixHashedJson -Path (Join-Path $bundle $entry.contract.path) -Hash $entry.contract.sha256
        }
        foreach ($target in @('c','ada')) {
            $identity = $entry[$target]
            $report = Read-MatrixHashedJson -Path (Join-Path $bundle $identity.report) -Hash $identity.sha256
            $artifacts = [IO.Path]::GetFullPath((Join-Path $bundle $identity.artifact_root))
            $expectedTarget = if ($target -eq 'ada') { 'Ada' } else { 'ReferenceC' }
            if ($RequireScopedAcceptance -and $target -eq 'ada') {
                foreach ($library in $consumerReports[$entry.context].library_files) {
                    $same = @($report.runtime_library_records | Where-Object {
                        [IO.Path]::GetFileName($_.path.Replace('\','/')) -ceq $library.file -and
                        $_.sha256 -ceq $library.sha256
                    })
                    if ($same.Count -ne 1) { throw 'Consumer and file execution libraries differ' }
                }
            }
            if ($RequireScopedAcceptance -and $target -eq 'c') {
                foreach ($kind in @('gc','io')) {
                    foreach ($library in $consumerReports[$entry.context]["${kind}_contract"].reference_library_files) {
                        $same = @($report.reference_library_records | Where-Object {
                            [IO.Path]::GetFileName($_.path.Replace('\','/')) -ceq $library.file -and
                            $_.sha256 -ceq $library.sha256
                        })
                        if ($same.Count -ne 1) { throw 'Consumer and file execution oracle libraries differ' }
                    }
                }
            }
            if ($report.repository_revision -cne $manifest.revision -or $report.repository_dirty -ne $false -or
                $report.reference_revision -cne $suite.reference_revision -or $report.target -cne $expectedTarget -or
                $report.coverage_scope -cne $manifest.scope -or $report.operation -cne "file:$($entry.file)" -or
                $report.acceptance_context -cne $entry.context -or $report.requested_configuration -cne $configuration -or
                $report.host.platform -cne $entry.context.Split('/')[1] -or
                $report.allocator_limit_bytes -ne 2147483648 -or $report.timeout_seconds -ne 900 -or
                $report.process.timeout_seconds -ne 900 -or $report.setup_error -or $report.acceptance_error -or
                $report.configuration_verified -ne $true -or $report.reference_tree_verified -ne $true -or
                $report.status -notin @('passed','completed-with-skips') -or
                $report.execution_disposition -cnotin @('unchanged','ada-internal-equivalent','native-platform-equivalent') -or
                $report.gate_acceptance -ne $false -or $report.fixture_changes.Count -ne 0) {
                throw 'Matrix report identity, policy or immutable-source mismatch'
            }
            $original = @($scope.Definition.files | Where-Object { $_.path -ceq $entry.file })[0]
            $fixture = @($report.fixture_records | Where-Object { $_.path -ceq $entry.file })
            if ($fixture.Count -ne 1 -or $fixture[0].sha256 -cne $original.sha256 -or
                $report.process.executable_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
                $report.process.executable_sha256 -cne $report.launcher_identity.sha256) {
                throw 'Matrix source or executable identity differs'
            }
            $libraries = if ($target -eq 'ada') { @($report.runtime_library_records) } else { @($report.reference_library_records) }
            if ($libraries.Count -eq 0 -or @($libraries | Where-Object { $_.sha256 -cnotmatch '^[0-9a-f]{64}$' }).Count -ne 0) {
                throw 'Matrix lacks measured library identities'
            }
            $expectedConfiguration = $null
            foreach ($probeName in @('configuration_process','child_configuration_process','arg_child_configuration_process')) {
                $probe = $report[$probeName]
                Set-MatrixProcessCaptures -Process $probe -ArtifactRoot $artifacts
                if ($probe.exit_code -ne 0 -or $probe.timed_out -or $probe.capture_exceeded -or
                    $probe.pipe_drain_failed -or $probe.process_tree_kill_error -or $probe.stderr_bytes -ne 0) {
                    throw 'Matrix launcher probe failed'
                }
                $text = [IO.File]::ReadAllText($probe.stdout_path).Trim()
                if ($probeName -eq 'configuration_process') {
                    $expectedConfiguration = $text
                    [void](Test-ConformanceConfiguration -Observed ($text | ConvertFrom-Json -AsHashtable) `
                        -Configuration $configuration -Target $expectedTarget -AllocatorLimitBytes 2147483648)
                    if ($target -eq 'ada') {
                        Assert-ScopedBuildIdentity -Observed ($text | ConvertFrom-Json -AsHashtable) -Context $entry.context
                    }
                } elseif ($text -cne $expectedConfiguration) { throw 'Matrix child configuration differs' }
            }
            Set-MatrixProcessCaptures -Process $report.process -ArtifactRoot $artifacts
            if ([string]::IsNullOrWhiteSpace([string]$report.launcher_probe_run_id) -or
                $report.launcher_probe_run_id -ceq $report.run_id) {
                throw 'Matrix launcher probes require a separate run identity'
            }
            $probeTelemetry = @()
            foreach ($probeRecord in $report.launcher_probe_telemetry) {
                $probePath = Resolve-MatrixCapture -Original $probeRecord.path `
                    -ArtifactRoot $artifacts -Hash $probeRecord.sha256
                $measured = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json -AsHashtable
                if ($measured.process_id -ne [int]([IO.Path]::GetFileNameWithoutExtension($probePath).Split('.')[-1])) {
                    throw 'Matrix launcher probe telemetry filename differs from PID'
                }
                $probeTelemetry += $measured
            }
            Assert-ScopedProbeTelemetry -Telemetry $probeTelemetry -Processes @{
                parent=$report.configuration_process; bare=$report.child_configuration_process;
                arg=$report.arg_child_configuration_process } -RunId $report.launcher_probe_run_id `
                -Configuration $configuration -Target $expectedTarget
            $telemetryPath = Resolve-MatrixCapture -Original $report.allocator_telemetry.path `
                -ArtifactRoot $artifacts -Hash $report.allocator_telemetry.sha256
            $telemetry = Get-Content -LiteralPath $telemetryPath -Raw | ConvertFrom-Json -AsHashtable
            Assert-ScopedProcessCompletion -File $entry.file -Process $report.process -Telemetry $telemetry `
                -RunId $report.run_id -Configuration $configuration -NativeOracle:($target -eq 'c')
            if ($entry.file -eq 'files.lua') {
                $nativeMapping = Assert-NativeBranchReviewBinding -Root $Root -Identity $report.native_branch_review
                if ($nativeMapping.source -cne 'references/lua/testes/files.lua' -or
                    $nativeMapping.counterpart.path -cne 'tests/conformance/platform/files-native-branches.lua') {
                    throw 'Matrix native mapping identifies another source or counterpart'
                }
                $facts = Get-ScopedNativeBranchFacts -Output ([IO.File]::ReadAllText($report.process.stdout_path))
                Assert-NativeBranchWitnesses -Mapping $nativeMapping -Output ([IO.File]::ReadAllText($report.process.stdout_path))
                $encodedFacts = $facts | ConvertTo-Json -Compress
                foreach ($key in $facts.Keys) {
                    if ($report.native_branch_facts[$key] -cne $facts[$key]) {
                        throw 'Matrix recorded native branch facts differ from capture'
                    }
                }
                if ($target -eq 'c') { $referenceNativeFacts = $encodedFacts }
                elseif ($encodedFacts -cne $referenceNativeFacts) {
                    throw 'Matrix C/Ada native branch facts differ'
                }
                $sourcePath = 'tests/conformance/platform/files-native-branches.lua'
                $native = @($report.native_fixture_records | Where-Object { $_.source -ceq $sourcePath })
                $sourceHash = (Get-FileHash (Join-Path $Root $sourcePath)).Hash.ToLowerInvariant()
                if ($native.Count -ne 1 -or $native[0].source_sha256 -cne $sourceHash -or
                    $native[0].artifact_sha256 -cne $sourceHash -or
                    $native[0].disposition -cne 'native-platform-equivalent') {
                    throw 'Matrix native branch counterpart identity differs'
                }
                [void](Resolve-MatrixCapture -Original $native[0].artifact -ArtifactRoot $artifacts -Hash $sourceHash)
                $seenChildren = @{}
                foreach ($child in $report.child_allocator_telemetry) {
                    $path = Resolve-MatrixCapture -Original $child.path -ArtifactRoot $artifacts -Hash $child.sha256
                    $measured = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
                    $pidValue = [int]([IO.Path]::GetFileNameWithoutExtension($path).Split('.')[-1])
                    if ($seenChildren.ContainsKey($pidValue) -or $pidValue -eq $report.process.process_id) {
                        throw 'Matrix child telemetry duplicates a process'
                    }
                    $seenChildren[$pidValue] = $true
                    Assert-ManagedTelemetry -Telemetry $measured -RunId $report.run_id -ProcessId $pidValue `
                        -Configuration $configuration -RequireShutdown:($target -eq 'ada')
                }
                $windows = $entry.context.Split('/')[1] -eq 'windows'
                $expectedChildren = if ($windows) { 4 } else { 2 }
                if (-not $windows -and $configuration -eq 'upstream-test') { $expectedChildren++ }
                if ($target -eq 'ada') { $expectedChildren += 4 }
                if ($seenChildren.Count -ne $expectedChildren) { throw 'Matrix child telemetry incomplete' }
            }
            if ($RequireScopedAcceptance) {
                if ($target -eq 'ada' -and ($report.scoped_operation_acceptance -ne $true -or
                    $report.execution_contract.sha256 -cne $entry.contract.sha256)) {
                    throw 'Matrix operation lacks scoped acceptance for the reviewed contract'
                }
                if ($report.execution_disposition -ne 'unchanged' -and
                    ($report.equivalent.diagnostic_only -ne $false -or $report.equivalent.review_status -cne 'accepted')) {
                    throw 'Matrix contains an unreviewed equivalent'
                }
                if ($report.execution_disposition -ne 'unchanged') {
                    $id = [string]$report.equivalent.id
                    if ($id -cnotmatch '^[a-z0-9-]+$') { throw 'Invalid matrix equivalent identifier' }
                    $mapping = Read-MatrixHashedJson -Path (Join-Path $Root "tests/conformance/equivalents/$id.json") `
                        -Hash $report.equivalent.manifest_sha256
                    Assert-MatrixReview -Review $mapping.review
                    Assert-EquivalentReviewBinding -Root $Root -Specification $mapping `
                        -GeneratedSha256 $report.equivalent.output_sha256
                    if ($mapping.source -cne "references/lua/testes/$($entry.file)" -or
                        $mapping.source_sha256 -cne $original.sha256 -or
                        $mapping.configuration -cnotin @($configuration,'default-and-upstream-test') -or
                        ($mapping.Contains('platform') -and $mapping.platform -cne $report.host.platform)) {
                        throw 'Matrix equivalent mapping identifies a different source or platform'
                    }
                    [void](Resolve-MatrixCapture -Original $report.equivalent.output -ArtifactRoot $artifacts `
                        -Hash $report.equivalent.output_sha256)
                    if ($contract.equivalent_manifest_sha256 -cne $report.equivalent.manifest_sha256 -or
                        $contract.executed_sha256 -cne $report.equivalent.output_sha256 -or
                        $contract.disposition -cne $report.execution_disposition) {
                        throw 'Matrix contract does not identify its equivalent execution'
                    }
                }
                $marker = if ($entry.file -eq 'files.lua') { '' } else { 'OK' }
                $outcome = Get-ConformanceOutcome -Process $report.process -Marker $marker
                [void](Test-ConformanceAcceptance -Process $report.process -Outcome $outcome -Contract $contract `
                    -Operation "file:$($entry.file)" -Context $entry.context -SourceRecords $report.fixture_records `
                    -RunId $report.run_id -Configuration $configuration -AllocatorLimitBytes 2147483648 `
                    -CoverageComplete $scope.ScopeComplete -CoverageRecords $coverage -Telemetry $telemetry)
            }
            $records += [ordered]@{file=$entry.file; context=$entry.context; target=$expectedTarget;
                disposition=$report.execution_disposition; report_sha256=$identity.sha256;
                supplemental_native_equivalents=$(if($entry.file -eq 'files.lua'){@($nativeMapping.branches.id)}else{@()})}
        }
    }
    return [ordered]@{scope=$manifest.scope; revision=$manifest.revision; contexts=$suite.acceptance_contexts.Count;
        operations=$manifest.operations.Count; executions=$records; scoped_acceptance=[bool]$RequireScopedAcceptance;
        full_m3_acceptance=$false}
}

Export-ModuleMember -Function Assert-ScopedMatrixIndex, Test-ScopedMatrix
