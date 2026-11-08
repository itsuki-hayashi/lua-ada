Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConsumerEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'AUnitEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'ScopedWarnings.psm1')

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
    if ($Manifest.schema_version -ne 1 -or $Manifest.scope -cnotin @('gc-io-events','expanded-t-conformance') -or
        $Manifest.revision -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid scoped matrix identity' }
    $files = (Get-ConformanceScopePolicy -Scope $Manifest.scope).Files
    $seen = @{}
    foreach ($entry in $Manifest.operations) {
        if ($entry.file -cnotin $files -or $entry.context -cnotin $Contexts) {
            throw 'Unknown scoped matrix file/context'
        }
        $key = $entry.context + '/' + $entry.file
        if ($seen.ContainsKey($key)) { throw "Duplicate scoped matrix operation: $key" }
        $seen[$key] = $true
        if ($Manifest.scope -ceq 'expanded-t-conformance' -and $entry.file -ceq 'constructs.lua') {
            if (-not $entry.Contains('supplemental') -or @($entry.supplemental).Count -ne 1 -or
                $entry.supplemental[0].variant -cne 'constructs-branch-1') {
                throw 'Constructs requires its second seeded template execution'
            }
            foreach ($target in @('ada','c')) {
                $identity=$entry.supplemental[0][$target]
                if ($null -eq $identity -or [string]::IsNullOrWhiteSpace([string]$identity.report) -or
                    [string]::IsNullOrWhiteSpace([string]$identity.artifact_root) -or
                    $identity.sha256 -cnotmatch '^[0-9a-f]{64}$') {
                    throw 'Constructs supplemental report identity missing'
                }
            }
        } elseif ($entry.Contains('supplemental') -and @($entry.supplemental).Count -gt 0) {
            throw 'Unexpected supplemental matrix execution'
        }
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
    if($Manifest.scope -ceq 'expanded-t-conformance') {
        $warnings=@{}
        foreach($identity in $Manifest.warning_regressions) {
            if($identity.context -cnotin $Contexts -or $warnings.ContainsKey($identity.context) -or
                [string]::IsNullOrWhiteSpace([string]$identity.report) -or
                [string]::IsNullOrWhiteSpace([string]$identity.artifact_root) -or
                $identity.sha256 -cnotmatch '^[0-9a-f]{64}$') {
                throw 'Unknown, duplicate or incomplete warning regression identity'
            }
            $warnings[$identity.context]=$true
        }
        foreach($context in $Contexts) {
            if(-not $warnings.ContainsKey($context)) { throw "Missing warning regression context: $context" }
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

function Test-MatrixWarningEvidence {
    param([string] $Root,[Collections.IDictionary] $Manifest,[string] $Bundle)
    $results=@()
    foreach($identity in $Manifest.warning_regressions) {
        $report=Read-MatrixHashedJson -Path (Join-Path $Bundle $identity.report) -Hash $identity.sha256
        $parts=$identity.context.Split('/')
        if($report.schema_version -ne 1 -or $report.scope -cne $Manifest.scope -or
            $report.context -cne $identity.context -or $report.configuration -cne $parts[0] -or
            $report.repository_revision -cne $Manifest.revision -or $report.repository_dirty -ne $false -or
            @($report.repository_status).Count -ne 0) { throw 'Warning index revision or context differs' }
        $requiredSources=@(Get-ScopedWarningSources | Sort-Object)
        if((@($report.source_records.path | Sort-Object) -join '|') -cne ($requiredSources -join '|')) {
            throw 'Warning source binding set differs'
        }
        foreach($source in $report.source_records) {
            [void](Resolve-ReviewedFile -Root $Root -Path $source.path -Sha256 $source.sha256)
        }
        $expected=@(Get-ScopedWarningCases -Configuration $parts[0])
        if(@($report.cases).Count -ne 2*$expected.Count) { throw 'Warning case set incomplete' }
        $artifactRoot=[IO.Path]::GetFullPath((Join-Path $Bundle $identity.artifact_root))
        $seen=@{}
        $fileEntry=@($Manifest.operations | Where-Object { $_.context -ceq $identity.context -and $_.file -ceq 'events.lua' })
        if($fileEntry.Count -ne 1) { throw 'Warning runtime counterpart missing' }
        if(@($report.library_records | Where-Object { $_.target -cnotin @('Ada','ReferenceC') }).Count) {
            throw 'Unknown warning library target'
        }
        foreach($target in @('Ada','ReferenceC')) {
            $key=if($target -ceq 'Ada'){'ada'}else{'c'}
            $fileReport=Read-MatrixHashedJson -Path (Join-Path $Bundle $fileEntry[0][$key].report) -Hash $fileEntry[0][$key].sha256
            # The main matrix separately binds these exact file runtimes to
            # named C/AUnit consumers. Requiring the complete library set here
            # keeps warning behavior in that same runtime/oracle identity.
            $libraries=if($target -ceq 'Ada'){@($fileReport.runtime_library_records)}else{@($fileReport.reference_library_records)}
            $actual=@($report.library_records | Where-Object target -CEQ $target | ForEach-Object {
                [IO.Path]::GetFileName($_.path.Replace('\','/'))+'#'+$_.sha256
            } | Sort-Object)
            $wanted=@($libraries | ForEach-Object {
                [IO.Path]::GetFileName($_.path.Replace('\','/'))+'#'+$_.sha256
            } | Sort-Object)
            if($wanted.Count -eq 0 -or ($actual -join '|') -cne ($wanted -join '|')) {
                throw 'Warning and file runtime libraries differ'
            }
            foreach($case in $expected) {
                $matches=@($report.cases | Where-Object { $_.target -ceq $target -and $_.name -ceq $case.name })
                $caseKey=$target+'/'+$case.name
                if($matches.Count -ne 1 -or $seen.ContainsKey($caseKey) -or
                    $matches[0].expected_rejection -isnot [bool] -or
                    $matches[0].expected_rejection -ne $case.reject) { throw 'Warning case identity or rejection claim differs' }
                $seen[$caseKey]=$true
                $process=$matches[0].process
                if($process.executable_sha256 -cne $fileReport.launcher_identity.sha256) {
                    throw 'Warning and file executable identities differ'
                }
                Set-MatrixProcessCaptures -Process $process -ArtifactRoot $artifactRoot
                Assert-ScopedWarningProcess -Process $process -Case $case -Target $target `
                    -Configuration $parts[0] -Platform $parts[1]
            }
        }
        $results+=@{context=$identity.context;sha256=$identity.sha256;cases=$seen.Count}
    }
    return $results
}

function Test-MatrixNamedEvidence {
    param([string] $Root, [Collections.IDictionary] $Manifest,
          [string] $Bundle, [Collections.IDictionary] $Suite)
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
    $api = @(Read-ConformanceJsonLines -Path (Join-Path $Root "tests/conformance/scopes/$($manifest.scope).api.jsonl"))
    if (@($mapping.entries).Count -ne $api.Count) { throw 'Consumer mapping API inventory differs' }
    $aunitApiCases = @{}
    foreach ($obligation in $api) {
        $matched = @($mapping.entries | Where-Object { $_.id -ceq $obligation.id })
        if ($matched.Count -ne 1) { throw 'Consumer mapping API obligation missing/duplicate' }
        $expected = @(if ($obligation.Contains('named_cases')) {
            $obligation.named_cases | ForEach-Object { $_.source + '#' + $_.id } | Sort-Object -Unique
        })
        $actual = @($matched[0].cases | Sort-Object -Unique)
        if (($expected -join "`n") -cne ($actual -join "`n")) { throw 'Consumer mapping API cases differ' }
        foreach ($case in $expected) {
            if (@($mapping.cases | Where-Object { ($_.source + '#' + $_.case_id) -ceq $case }).Count -ne 1) {
                throw 'Consumer mapping case missing/duplicate'
            }
        }
        if ($manifest.scope -ceq 'expanded-t-conformance') {
            $unitCases = @(if ($obligation.Contains('named_aunit_cases')) {
                $obligation.named_aunit_cases | ForEach-Object { $_.source + '#' + $_.id }
            })
            if (($expected.Count + $unitCases.Count) -eq 0) { throw 'Scoped API has no named runtime witness' }
            if ($unitCases.Count -ne @($unitCases | Sort-Object -Unique).Count) {
                throw 'Scoped API has duplicate named AUnit witnesses'
            }
            $aunitApiCases[$obligation.id] = $unitCases
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
        if ($manifest.scope -ceq 'expanded-t-conformance') {
            if (-not $consumerReport.Contains('foreign_contract')) { throw 'Expanded foreign contract missing' }
            $foreignSources=@('c_api/tests/foreign_api_contract.c',
                'tests/c/foreign_continuation_contract.c','tests/c/foreign_hook_contract.c',
                'tests/c/math_reopen_contract.c','tests/c/library_opener_contract.c')
            if (@($consumerReport.foreign_contract.sources).Count -ne $foreignSources.Count) {
                throw 'Expanded foreign contract source set differs'
            }
            foreach ($name in $foreignSources) {
                $source=@($consumerReport.foreign_contract.sources | Where-Object file -CEQ $name)
                if ($source.Count -ne 1) { throw 'Expanded foreign contract source missing/duplicate' }
                [void](Resolve-ReviewedFile -Root $Root -Path $source[0].file -Sha256 $source[0].sha256)
            }
        }
        $consumerRoot = [IO.Path]::GetFullPath((Join-Path $bundle $consumer.artifact_root))
        $resolve = { param($path,$hash)
            Resolve-MatrixCapture -Original $path -ArtifactRoot $consumerRoot -Hash $hash
        }
        $contexts[$consumer.context] = Test-NamedConsumerEvidence -Report $consumerReport -Mapping $mapping `
            -Revision $manifest.revision -Context $consumer.context -ResolveCapture $resolve `
            -RequireForeignContract:($manifest.scope -ceq 'expanded-t-conformance')
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
    if ($manifest.scope -ceq 'expanded-t-conformance' -and
        (-not $aunitMapping.Contains('expected_stderr') -or
         $aunitMapping.expected_stderr -cne "Lua warning: error in __gc ([string `"file-abort-test`"]:1: ordinary failure)`n")) {
        throw 'Expanded AUnit warning mapping differs from its source regression'
    }
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
    foreach ($apiId in $aunitApiCases.Keys) {
        foreach ($case in $aunitApiCases[$apiId]) {
            if (@($aunitMapping.entries | Where-Object { $_.case -ceq $case }).Count -ne 1) {
                throw "Scoped API named AUnit witness missing/duplicate: $apiId/$case"
            }
        }
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
    return $consumerReports
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
    $scope = Test-ConformanceScope -Root $Root -Scope $manifest.scope -RequireScopedComplete:$RequireScopedAcceptance
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
        $consumerReports = Test-MatrixNamedEvidence -Root $Root -Manifest $manifest -Bundle $bundle -Suite $suite
    }
    $coverage = @{}
    $coverageByFile = @{}
    $scopeHelpers = @(if ($scope.Definition.Contains('helpers')) { $scope.Definition.helpers })
    foreach ($file in (@($scope.Definition.files) + $scopeHelpers)) {
        $source = @($suite.files | Where-Object { $_.path -ceq $file.path })[0]
        $fileRecords=@(Read-ConformanceJsonLines -Path (Join-Path $Root "tests/conformance/$($source.coverage_file)"))
        $coverageByFile[$file.path]=$fileRecords
        foreach ($record in $fileRecords) {
            $coverage[$record.id] = $record
        }
    }
    $records = @()
    $executionEntries = @($manifest.operations)
    if ($manifest.scope -ceq 'expanded-t-conformance') {
        foreach ($primary in $manifest.operations | Where-Object file -CEQ 'constructs.lua') {
            $extra=$primary.supplemental[0]
            $expanded=@{file=$primary.file; context=$primary.context; c=$extra.c; ada=$extra.ada;
                variant=$extra.variant}
            if ($RequireScopedAcceptance) { $expanded.contract=$primary.contract }
            $executionEntries += $expanded
        }
    }
    foreach ($entry in $executionEntries) {
        $configuration = $entry.context.Split('/')[0]
        $referenceNativeFacts = $null
        $referenceSourceFacts = $null
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
                $contractKinds=@('gc','io')
                if ($manifest.scope -ceq 'expanded-t-conformance') { $contractKinds += 'foreign' }
                foreach ($kind in $contractKinds) {
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
                -RunId $report.run_id -Configuration $configuration -Platform $report.host.platform -NativeOracle:($target -eq 'c')
            if ($manifest.scope -ceq 'expanded-t-conformance') {
                $facts = Get-ScopedSourceProfileFacts -Output ([IO.File]::ReadAllText($report.process.stdout_path)) `
                    -Observed $report.observed_configuration
                if (-not $report.Contains('source_profile_facts') -or $null -eq $report.source_profile_facts -or
                    $report.source_profile_facts.Count -ne $facts.Count) {
                    throw 'Matrix source profile fact record missing'
                }
                foreach ($name in $facts.Keys) {
                    if ($report.source_profile_facts[$name] -cne $facts[$name]) {
                        throw 'Matrix captured source profile facts differ'
                    }
                    if ($target -eq 'ada' -and $facts[$name] -cne $referenceSourceFacts[$name]) {
                        throw 'Matrix C/Ada source profile applicability differs'
                    }
                }
                if ($target -eq 'c') { $referenceSourceFacts=$facts }
                $conditions=Get-ScopedMeasuredConditionResults -Records $coverageByFile[$entry.file] -Facts $facts
                if (-not $report.Contains('source_condition_results') -or $null -eq $report.source_condition_results -or
                    (@($conditions.Keys | Sort-Object) -join '|') -cne
                    (@($report.source_condition_results.Keys | Sort-Object) -join '|')) {
                    throw 'Matrix measured source condition set differs'
                }
                foreach ($id in $conditions.Keys) {
                    if ($report.source_condition_results[$id] -isnot [bool] -or
                        $report.source_condition_results[$id] -ne $conditions[$id]) {
                        throw 'Matrix measured source condition result differs'
                    }
                }
                $wrapperPath='tests/conformance/source-profile-witness.lua'
                $wrapper=@($report.native_fixture_records | Where-Object source -CEQ $wrapperPath)
                $hash=(Get-FileHash (Join-Path $Root $wrapperPath)).Hash.ToLowerInvariant()
                if ($wrapper.Count -ne 1 -or $wrapper[0].source_sha256 -cne $hash -or
                    $wrapper[0].artifact_sha256 -cne $hash) { throw 'Matrix source profile witness differs' }
                [void](Resolve-MatrixCapture -Original $wrapper[0].artifact -ArtifactRoot $artifacts -Hash $hash)
            }
            if ($manifest.scope -ceq 'expanded-t-conformance' -and $entry.file -ceq 'bitwise.lua') {
                $wrapperPath='tests/conformance/bitwise-helper-witness.lua'
                $wrapper=@($report.native_fixture_records | Where-Object source -CEQ $wrapperPath)
                $hash=(Get-FileHash (Join-Path $Root $wrapperPath)).Hash.ToLowerInvariant()
                if ($wrapper.Count -ne 1 -or $wrapper[0].source_sha256 -cne $hash -or
                    $wrapper[0].artifact_sha256 -cne $hash) { throw 'Matrix bitwise helper wrapper differs' }
                [void](Resolve-MatrixCapture -Original $wrapper[0].artifact -ArtifactRoot $artifacts -Hash $hash)
            }
            if ($manifest.scope -ceq 'expanded-t-conformance' -and $entry.file -ceq 'constructs.lua') {
                $branch=if($entry.Contains('variant')){1}else{0}
                $stdout=[IO.File]::ReadAllText($report.process.stdout_path)
                $pattern='(?m)^testing short-circuit optimizations \('+$branch+'\)\r?$'
                if (-not $report.Contains('constructs_branch') -or $report.constructs_branch -ne $branch -or
                    [regex]::Matches($stdout,$pattern).Count -ne 1) {
                    throw 'Matrix constructs template branch differs'
                }
                $wrapperPath='tests/conformance/constructs-seeded.lua'
                $wrapper=@($report.native_fixture_records | Where-Object source -CEQ $wrapperPath)
                $hash=(Get-FileHash (Join-Path $Root $wrapperPath)).Hash.ToLowerInvariant()
                if ($wrapper.Count -ne 1 -or $wrapper[0].source_sha256 -cne $hash -or
                    $wrapper[0].artifact_sha256 -cne $hash) { throw 'Matrix constructs wrapper differs' }
                [void](Resolve-MatrixCapture -Original $wrapper[0].artifact -ArtifactRoot $artifacts -Hash $hash)
            }
            if ($entry.file -eq 'events.lua') {
                $wrapperPath = 'tests/conformance/events-return-witness.lua'
                $wrapper = @($report.native_fixture_records | Where-Object { $_.source -ceq $wrapperPath })
                $hash = (Get-FileHash (Join-Path $Root $wrapperPath)).Hash.ToLowerInvariant()
                if ($wrapper.Count -ne 1 -or $wrapper[0].source_sha256 -cne $hash -or
                    $wrapper[0].artifact_sha256 -cne $hash) { throw 'Matrix events return wrapper differs' }
                [void](Resolve-MatrixCapture -Original $wrapper[0].artifact -ArtifactRoot $artifacts -Hash $hash)
            }
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
                $marker = if ($entry.file -eq 'files.lua') { '' } elseif ($entry.file -ceq 'utf8.lua') { 'ok' } else { 'OK' }
                $outcome = Get-ConformanceOutcome -Process $report.process -Marker $marker
                [void](Test-ConformanceAcceptance -Process $report.process -Outcome $outcome -Contract $contract `
                    -Operation "file:$($entry.file)" -Context $entry.context -SourceRecords $report.fixture_records `
                    -RunId $report.run_id -Configuration $configuration -AllocatorLimitBytes 2147483648 `
                    -CoverageComplete $scope.ScopeComplete -CoverageRecords $coverage -Telemetry $telemetry)
            }
            $records += [ordered]@{file=$entry.file; context=$entry.context; target=$expectedTarget;
                variant=$(if($entry.Contains('variant')){$entry.variant}else{'primary'});
                disposition=$report.execution_disposition; report_sha256=$identity.sha256;
                supplemental_native_equivalents=$(if($entry.file -eq 'files.lua'){@($nativeMapping.branches.id)}else{@()})}
        }
    }
    $warningResults=if($manifest.scope -ceq 'expanded-t-conformance') {
        @(Test-MatrixWarningEvidence -Root $Root -Manifest $manifest -Bundle $bundle)
    } else { @() }
    return [ordered]@{scope=$manifest.scope; revision=$manifest.revision; contexts=$suite.acceptance_contexts.Count;
        operations=$manifest.operations.Count; executions=$records; scoped_acceptance=[bool]$RequireScopedAcceptance;
        warning_regressions=$warningResults;full_m3_acceptance=$false}
}

function Test-RetainedMatrixWitnesses {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][Collections.IDictionary] $Manifest,
          [Parameter(Mandatory)][string] $Bundle,
          [Parameter(Mandatory)][Collections.IDictionary] $Suite,
          [Collections.IDictionary] $TargetWitnessPolicy = $null,
          [Collections.IDictionary] $TargetBuildWitnesses = @{})
    # Full-target reconciliation reuses the actual named C/AUnit and warning
    # protocols from the retained expanded scope. Exposing this replay avoids
    # weakening them to a set of successful primary-file process exits.
    if ($Manifest.scope -cne 'expanded-t-conformance') { throw 'Unknown retained matrix witness scope' }
    $seenWarnings = @{}
    foreach ($identity in $Manifest.warning_regressions) {
        if ($identity.context -cnotin $Suite.acceptance_contexts -or $seenWarnings.ContainsKey($identity.context)) {
            throw 'Unknown or duplicate retained warning context'
        }
        $seenWarnings[$identity.context] = $true
    }
    foreach ($context in $Suite.acceptance_contexts) {
        if (-not $seenWarnings.ContainsKey($context)) { throw "Missing retained warning context: $context" }
    }
    if($null -eq $TargetWitnessPolicy){
        $consumers = Test-MatrixNamedEvidence -Root $Root -Manifest $Manifest -Bundle $Bundle -Suite $Suite
    }else{
        if($TargetWitnessPolicy.source_reviewed -ne $true){throw 'Retained target witnesses need independently reviewed current-source catalogues'}
        $consumers=@{}
        foreach($context in $Suite.acceptance_contexts){
            if(-not $TargetBuildWitnesses.Contains($context) -or $TargetBuildWitnesses[$context].build_witnesses_verified -ne $true){
                throw 'Retained target actual named build evidence is missing'
            }
            $consumers[$context]=$TargetBuildWitnesses[$context].consumer_report
        }
    }
    $warnings = @(Test-MatrixWarningEvidence -Root $Root -Manifest $Manifest -Bundle $Bundle)
    return @{consumers=$consumers;warnings=$warnings}
}

Export-ModuleMember -Function Assert-ScopedMatrixIndex, Test-ScopedMatrix, Test-RetainedMatrixWitnesses
