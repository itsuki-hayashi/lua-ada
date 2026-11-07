Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceMatrix.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')

function Assert-TargetMatrixIndex {
    param([Parameter(Mandatory)][Collections.IDictionary] $Manifest,
          [Parameter(Mandatory)][Collections.IDictionary] $Suite)
    if ($Manifest.schema_version -ne 1 -or $Manifest.kind -cne 'full-target-matrix' -or
        $Manifest.target -cne 'remaining-upstream-compatibility' -or
        $Manifest.reference_revision -cne $Suite.reference_revision -or
        $Manifest.revision -cnotmatch '^[0-9a-f]{40}$' -or
        $Manifest.synthetic_fixture -isnot [bool]) { throw 'Invalid full-target matrix identity' }
    $primaries = @($Suite.files | Where-Object role -CEQ 'primary' | ForEach-Object { 'file:' + $_.path })
    if ($primaries.Count -ne 30 -or @($Suite.acceptance_contexts).Count -ne 26) {
        throw 'Full-target matrix requires the pinned 30-primary/26-context suite'
    }
    $operations = $primaries + @('aggregate','heavy')
    $seen = @{}
    foreach ($entry in (@($Manifest.operations) + @($Manifest.supplemental))) {
        $supplemental = $entry.Contains('variant')
        if ($entry.operation -cnotin $operations -or $entry.context -cnotin $Suite.acceptance_contexts -or
            ($supplemental -and ($entry.variant -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
                $entry.variant -ceq 'primary'))) { throw 'Unknown full-target operation, context or variant' }
        $variant = if ($supplemental) { $entry.variant } else { 'primary' }
        $key = $entry.context + '/' + $entry.operation + '/' + $variant
        if ($seen.ContainsKey($key)) { throw 'Duplicate full-target matrix operation' }
        $seen[$key] = $true
        if ($entry.comparison -cnotin @('exact','reviewed-semantic')) { throw 'Unknown full-target comparison policy' }
        foreach ($target in @('c','ada')) {
            $identity = $entry[$target]
            if ($null -eq $identity -or [string]::IsNullOrWhiteSpace([string]$identity.report) -or
                [string]::IsNullOrWhiteSpace([string]$identity.artifact_root) -or
                $identity.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "Missing full-target $target report identity" }
        }
        if ($null -eq $entry.contract -or [string]::IsNullOrWhiteSpace([string]$entry.contract.path) -or
            $entry.contract.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing full-target execution contract identity' }
    }
    foreach ($entry in $Manifest.operations) {
        if ($entry.Contains('variant')) { throw 'Primary matrix operations cannot contain supplemental variants' }
    }
    foreach ($entry in $Manifest.supplemental) {
        if (-not $entry.Contains('variant')) { throw 'Supplemental matrix operations require a distinct variant' }
    }
    foreach ($context in $Suite.acceptance_contexts) {
        foreach ($operation in $operations) {
            if (-not $seen.ContainsKey("$context/$operation/primary")) {
                throw "Incomplete full-target matrix: $context/$operation"
            }
        }
        # The retained source audit requires both real constructs templates.
        # A collection containing only one random choice is incomplete even
        # when its primary process and every unrelated file passed.
        if (-not $seen.ContainsKey("$context/file:constructs.lua/constructs-branch-1")) {
            throw "Missing required constructs supplement: $context"
        }
    }
}

function Resolve-TargetBundlePath {
    param([string] $Root, [string] $Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative)) {
        throw 'Target bundle path must be relative'
    }
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $path = [IO.Path]::GetFullPath((Join-Path $fullRoot $Relative))
    $within = [IO.Path]::GetRelativePath($fullRoot,$path)
    if ($within -eq '..' -or $within.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        [IO.Path]::IsPathRooted($within)) { throw 'Target bundle path escapes its root' }
    return $path
}

function Read-TargetHashedJson {
    param([string] $Root, [Collections.IDictionary] $Identity, [string] $PathField = 'path')
    $path = Resolve-TargetBundlePath -Root $Root -Relative $Identity[$PathField]
    if ($Identity.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Identity.sha256) {
        throw 'Full-target JSON artifact hash differs'
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
}

function Resolve-TargetCapture {
    param([string] $Root, [string] $Original, [string] $Sha256)
    $normalized = $Original.Replace('\','/')
    $offset = $normalized.LastIndexOf('/reports/',[StringComparison]::Ordinal)
    if ($offset -lt 0) { throw 'Target capture is outside the reports subtree' }
    $path = Resolve-TargetBundlePath -Root $Root -Relative $normalized.Substring($offset + 1)
    if ($Sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Sha256) {
        throw 'Target capture hash differs'
    }
    return $path
}

function Set-TargetProcessCaptures {
    param([Collections.IDictionary] $Process, [string] $ArtifactRoot)
    foreach ($stream in @('stdout','stderr')) {
        $Process["${stream}_path"] = Resolve-TargetCapture -Root $ArtifactRoot `
            -Original $Process["${stream}_path"] -Sha256 $Process["${stream}_sha256"]
        if ((Get-Item -LiteralPath $Process["${stream}_path"]).Length -ne $Process["${stream}_bytes"]) {
            throw 'Target capture byte length differs'
        }
    }
    if ($Process.exit_code -ne 0 -or $Process.timed_out -ne $false -or
        $Process.capture_exceeded -ne $false -or $Process.pipe_drain_failed -ne $false -or
        $Process.process_tree_kill_error -or $Process.abnormal_exit_kind) {
        throw 'Full-target process did not complete cleanly'
    }
}

function Get-TargetOperationExclusions {
    param([string] $Operation, [string] $Configuration, [string] $Target,
          [AllowEmptyCollection()][object[]] $Exclusions)
    if ($Target -ceq 'ReferenceC' -or $Configuration -ceq 'default') { return }
    foreach ($entry in $Exclusions) {
        if (($Operation -ceq 'aggregate' -and $entry.source -cne 'heavy.lua') -or
            ($Operation -ceq 'heavy' -and $entry.source -ceq 'heavy.lua') -or
            $Operation -ceq ('file:' + $entry.source)) { $entry.id }
    }
}

function Test-TargetMatrixReport {
    param([Parameter(Mandatory)][Collections.IDictionary] $Report,
          [Parameter(Mandatory)][Collections.IDictionary] $Entry,
          [Parameter(Mandatory)][Collections.IDictionary] $Suite,
          [Parameter(Mandatory)][string] $Revision,
          [Parameter(Mandatory)][string] $ArtifactRoot,
          [Parameter(Mandatory)][ValidateSet('ReferenceC','Ada')][string] $Target,
          [Parameter(Mandatory)][string] $ExclusionPolicySha256,
          [AllowEmptyCollection()][object[]] $Exclusions = @())
    $parts = $Entry.context.Split('/')
    $heavy = $Entry.operation -ceq 'heavy'
    $limit = if ($heavy) { 67108864L } else { 2147483648L }
    $timeout = if ($heavy) { 600 } elseif ($Entry.operation -ceq 'aggregate') { 3600 } else { 900 }
    if ($Report.repository_revision -cne $Revision -or $Report.repository_dirty -ne $false -or
        @($Report.repository_status).Count -ne 0 -or $Report.reference_revision -cne $Suite.reference_revision -or
        $Report.target -cne $Target -or $Report.target_policy -cne 'remaining-upstream-compatibility' -or
        $Report.coverage_scope -cne '' -or $Report.operation -cne $Entry.operation -or
        $Report.acceptance_context -cne $Entry.context -or $Report.requested_configuration -cne $parts[0] -or
        $Report.host.platform -cne $parts[1] -or $Report.allocator_limit_bytes -ne $limit -or
        $Report.timeout_seconds -ne $timeout -or $Report.process.timeout_seconds -ne $timeout -or
        $Report.configuration_verified -ne $true -or $Report.reference_tree_verified -ne $true -or
        $Report.setup_error -or $Report.acceptance_error -or @($Report.fixture_changes).Count -ne 0 -or
        $Report.gate_acceptance -ne $false -or $Report.scoped_operation_acceptance -ne $false -or
        $Report.status -cnotin @('passed','completed-with-skips') -or
        $Report.execution_disposition -cnotin @('unchanged','ada-internal-equivalent','native-platform-equivalent','reviewed-t-adapted') -or
        $Report.synthetic_fixture -isnot [bool]) { throw 'Full-target report revision, identity or policy differs' }
    $variant = if ($Entry.Contains('variant')) { $Entry.variant } else { 'primary' }
    if ($Report.variant -cne $variant) { throw 'Full-target report variant differs' }
    foreach ($source in $Suite.files) {
        $matches = @($Report.fixture_records | Where-Object path -CEQ $source.path)
        if ($matches.Count -ne 1 -or $matches[0].sha256 -cne $source.sha256) {
            throw 'Full-target original source identity differs'
        }
    }
    if ($Report.process.executable_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Report.process.executable_sha256 -cne $Report.launcher_identity.sha256) {
        throw 'Full-target executable identity differs'
    }
    $libraries = if ($Target -ceq 'Ada') { @($Report.runtime_library_records) } else { @($Report.reference_library_records) }
    $images = @{}
    foreach ($library in $libraries) {
        $name = [IO.Path]::GetFileName($library.path.Replace('\','/'))
        if ([string]::IsNullOrWhiteSpace($name) -or $images.ContainsKey($name) -or
            $library.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Full-target library identities missing or duplicated' }
        $images[$name] = $library.sha256
    }
    if ($images.Count -eq 0) { throw 'Full-target library identity missing' }
    $probeText = $null
    foreach ($name in @('configuration_process','child_configuration_process','arg_child_configuration_process')) {
        $probe = $Report[$name]
        Set-TargetProcessCaptures -Process $probe -ArtifactRoot $ArtifactRoot
        if ($probe.stderr_bytes -ne 0) { throw 'Full-target configuration probe has stderr' }
        $actual = [IO.File]::ReadAllText($probe.stdout_path).Trim()
        if ($name -ceq 'configuration_process') {
            $probeText = $actual
            $observed = $actual | ConvertFrom-Json -AsHashtable
            [void](Test-ConformanceConfiguration -Observed $observed -Configuration $parts[0] `
                -Target $Target -AllocatorLimitBytes $limit)
            if ($Target -ceq 'Ada') { Assert-ScopedBuildIdentity -Observed $observed -Context $Entry.context }
            foreach ($field in $observed.Keys) {
                if (-not $Report.observed_configuration.Contains($field) -or
                    $Report.observed_configuration[$field] -cne $observed[$field]) {
                    throw 'Full-target recorded configuration differs from actual probe'
                }
            }
        } elseif ($actual -cne $probeText) { throw 'Full-target child configuration differs' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Report.launcher_probe_run_id) -or
        $Report.launcher_probe_run_id -ceq $Report.run_id) { throw 'Full-target probe run identity is not distinct' }
    $probeTelemetry = @()
    foreach ($identity in $Report.launcher_probe_telemetry) {
        $path = Resolve-TargetCapture -Root $ArtifactRoot -Original $identity.path -Sha256 $identity.sha256
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        if ($data.process_id -ne [int]([IO.Path]::GetFileNameWithoutExtension($path).Split('.')[-1])) {
            throw 'Full-target probe telemetry PID differs'
        }
        $probeTelemetry += $data
    }
    Assert-ScopedProbeTelemetry -Telemetry $probeTelemetry -Processes @{
        parent=$Report.configuration_process;bare=$Report.child_configuration_process;arg=$Report.arg_child_configuration_process
    } -RunId $Report.launcher_probe_run_id -Configuration $parts[0] -Target $Target -LimitBytes $limit
    Set-TargetProcessCaptures -Process $Report.process -ArtifactRoot $ArtifactRoot
    if ($Entry.operation -ceq 'file:constructs.lua' -and
        $variant -cin @('primary','constructs-branch-1')) {
        $branch = if ($variant -ceq 'constructs-branch-1') { 1 } else { 0 }
        if ($Report.constructs_branch -ne $branch -or
            [regex]::Matches([IO.File]::ReadAllText($Report.process.stdout_path),
                '(?m)^testing short-circuit optimizations \(' + $branch + '\)\r?$').Count -ne 1) {
            throw 'Full-target constructs supplemental branch witness differs'
        }
    }
    $path = Resolve-TargetCapture -Root $ArtifactRoot -Original $Report.allocator_telemetry.path `
        -Sha256 $Report.allocator_telemetry.sha256
    $telemetry = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    Assert-ManagedTelemetry -Telemetry $telemetry -RunId $Report.run_id -ProcessId $Report.process.process_id `
        -Configuration $parts[0] -LimitBytes $limit -RequireShutdown:($Target -ceq 'Ada')
    if ($heavy -and ($telemetry.managed_refusals -lt 1 -or
        [IO.File]::ReadAllText($Report.process.stdout_path) -cnotmatch '(?im)^expected error:\s+.*not enough memory')) {
        throw 'Full-target heavy operation lacks its own caught allocator refusal'
    }
    $excludedIds = @(Get-TargetOperationExclusions -Operation $Entry.operation -Configuration $parts[0] `
        -Target $Target -Exclusions $Exclusions | Sort-Object)
    if ((@($Report.excluded_obligations | Sort-Object) -join '|') -cne ($excludedIds -join '|') -or
        @($Report.excluded_obligations).Count -ne $excludedIds.Count -or
        $Report.exclusion_policy_sha256 -cne $ExclusionPolicySha256) {
        throw 'Full-target report excluded obligation set or policy hash differs'
    }
    if (($excludedIds.Count -gt 0) -ne ($Report.execution_disposition -ceq 'reviewed-t-adapted')) {
        throw 'Full-target exclusions and adapted execution disposition differ'
    }
    return @{report=$Report;telemetry=$telemetry;images=$images;
        executable_sha256=$Report.process.executable_sha256;excluded_obligations=$excludedIds}
}

function Assert-TargetMatrixCoverage {
    param([Parameter(Mandatory)][object] $Inventory, [switch] $RequireComplete)
    if ($Inventory.PendingApiEntries -ne 0) { throw 'Full-target global public API coverage remains unresolved' }
    if ($Inventory.RequiredPendingSourceAnchors -ne 0) { throw 'Full-target source coverage remains unresolved' }
    if ($RequireComplete -and -not $Inventory.TargetComplete) { throw 'Full-target reviewed coverage is incomplete' }
}

function Assert-TargetMatrixReview {
    param([string] $Root, [Collections.IDictionary] $Manifest, [Collections.IDictionary] $Suite)
    $review = $Manifest.review
    if ($null -eq $review -or $review.status -cne 'accepted' -or
        [string]::IsNullOrWhiteSpace([string]$review.author) -or
        [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer) {
        throw 'Full-target matrix requires accepted independent reconciliation'
    }
    $path = Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($approval.schema_version -ne 1 -or $approval.kind -cne 'full-target-matrix-approval' -or
        $approval.target -cne $Manifest.target -or $approval.revision -cne $Manifest.revision -or
        $approval.reference_revision -cne $Suite.reference_revision -or $approval.decision -cne 'accepted' -or
        $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer) {
        throw 'Full-target matrix approval identity differs'
    }
    foreach ($name in @('exclusion_policy','retained_evidence')) {
        if ($approval[$name].path -cne $Manifest[$name].path -or
            $approval[$name].sha256 -cne $Manifest[$name].sha256) { throw 'Full-target reviewed policy or retained evidence differs' }
    }
    $entries = @($Manifest.operations) + @($Manifest.supplemental)
    if (@($approval.operations).Count -ne $entries.Count) { throw 'Full-target approved operation count differs' }
    $seen = @{}
    foreach ($entry in $entries) {
        $variant = if ($entry.Contains('variant')) { $entry.variant } else { 'primary' }
        $matched = @($approval.operations | Where-Object {
            $_.operation -ceq $entry.operation -and $_.context -ceq $entry.context -and $_.variant -ceq $variant
        })
        $key = $entry.context + '/' + $entry.operation + '/' + $variant
        if ($matched.Count -ne 1 -or $seen.ContainsKey($key) -or $matched[0].decision -cne 'accepted' -or
            $matched[0].c_report_sha256 -cne $entry.c.sha256 -or
            $matched[0].ada_report_sha256 -cne $entry.ada.sha256 -or
            $matched[0].contract_sha256 -cne $entry.contract.sha256 -or
            $matched[0].comparison -cne $entry.comparison) { throw 'Full-target approved operation binding differs' }
        $seen[$key] = $true
    }
    $expectedPaths = @('tests/conformance/suite.json','tests/conformance/c-api.jsonl') +
        @($Suite.files | ForEach-Object { 'tests/conformance/' + $_.coverage_file })
    if (@($approval.inventory_files).Count -ne $expectedPaths.Count) { throw 'Full-target approved inventory set differs' }
    foreach ($relative in $expectedPaths) {
        $matched = @($approval.inventory_files | Where-Object path -CEQ $relative)
        if ($matched.Count -ne 1) { throw 'Full-target approved inventory binding missing or duplicated' }
        [void](Resolve-ReviewedFile -Root $Root -Path $relative -Sha256 $matched[0].sha256)
    }
    $narrative = $approval.review_evidence
    $path = Resolve-ReviewedFile -Root $Root -Path $narrative.path -Sha256 $narrative.sha256
    $decision = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    if ($decision.reviewer -cne $review.reviewer -or $decision.decision -cne 'accepted' -or
        $decision.target -cne $Manifest.target -or $decision.revision -cne $Manifest.revision) {
        throw 'Full-target independent reconciliation narrative differs'
    }
}

function Test-FullTargetMatrix {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][string] $ManifestPath,
          [ValidateSet('remaining-upstream-compatibility')][string] $TargetPolicy = 'remaining-upstream-compatibility',
          [switch] $RequireTargetAcceptance)
    $manifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
    $bundle = Split-Path -Parent $manifestPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $suite = Get-Content -LiteralPath (Join-Path $Root 'tests/conformance/suite.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 32
    Assert-TargetMatrixIndex -Manifest $manifest -Suite $suite
    if ($manifest.target -cne $TargetPolicy -or
        $manifest.exclusion_policy.path -cne 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json') {
        throw 'Full-target matrix selects another exclusion policy'
    }
    [void](Resolve-ReviewedFile -Root $Root -Path $manifest.exclusion_policy.path -Sha256 $manifest.exclusion_policy.sha256)
    $inventory = Test-ConformanceInventory -Root $Root -TargetPolicy $TargetPolicy
    $retained = $null
    if ($RequireTargetAcceptance) {
        if ($manifest.synthetic_fixture) { throw 'Synthetic fixture matrix cannot establish target acceptance' }
        Assert-TargetMatrixCoverage -Inventory $inventory
        $inventory = Test-ConformanceInventory -Root $Root -TargetPolicy $TargetPolicy -RequireComplete
        Assert-TargetMatrixCoverage -Inventory $inventory -RequireComplete
        $head = (& git -C $Root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $head -cne $manifest.revision) { throw 'Full-target matrix is not current checkout revision' }
        $dirty = @(& git -C $Root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
        if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Full-target acceptance requires a clean checkout' }
        Assert-TargetMatrixReview -Root $Root -Manifest $manifest -Suite $suite
        $retainedIndex = Read-TargetHashedJson -Root $bundle -Identity $manifest.retained_evidence
        if ($retainedIndex.revision -cne $manifest.revision) { throw 'Retained witnesses have another revision' }
        $retained = Test-RetainedMatrixWitnesses -Root $Root -Manifest $retainedIndex -Bundle $bundle -Suite $suite
    }
    $coverage = @{}
    foreach ($source in $suite.files) {
        foreach ($record in (Read-ConformanceJsonLines (Join-Path $Root ('tests/conformance/' + $source.coverage_file)))) {
            $coverage[$record.id] = $record
        }
    }
    $executions = @(); $contextImages = @{}
    foreach ($entry in (@($manifest.operations) + @($manifest.supplemental))) {
        $contract = Read-TargetHashedJson -Root $bundle -Identity $entry.contract
        $pair = @{}
        foreach ($target in @('c','ada')) {
            $expectedTarget = if ($target -ceq 'ada') { 'Ada' } else { 'ReferenceC' }
            $identity = $entry[$target]
            $report = Read-TargetHashedJson -Root $bundle -Identity $identity -PathField report
            $artifacts = Resolve-TargetBundlePath -Root $bundle -Relative $identity.artifact_root
            $observed = Test-TargetMatrixReport -Report $report -Entry $entry -Suite $suite `
                -Revision $manifest.revision -ArtifactRoot $artifacts -Target $expectedTarget `
                -ExclusionPolicySha256 $manifest.exclusion_policy.sha256 -Exclusions $inventory.Exclusions
            $imageKey = $entry.context + '/' + $target
            $signature = $observed.executable_sha256 + '|' + (@($observed.images.Keys | Sort-Object |
                ForEach-Object { $_ + ':' + $observed.images[$_] }) -join '|')
            if ($contextImages.ContainsKey($imageKey) -and $contextImages[$imageKey] -cne $signature) {
                throw 'Full-target operations do not share their context runtime image'
            }
            $contextImages[$imageKey] = $signature
            if ($RequireTargetAcceptance) {
                if ($report.synthetic_fixture -or $report.report_only -ne $false -or
                    ($target -ceq 'ada' -and ($report.target_operation_acceptance -ne $true -or
                        $report.execution_contract.sha256 -cne $entry.contract.sha256))) {
                    throw 'Full-target operation lacks actual accepted execution evidence'
                }
                foreach ($library in $retained.consumers[$entry.context].library_files) {
                    if ($target -ceq 'ada' -and (-not $observed.images.ContainsKey($library.file) -or
                        $observed.images[$library.file] -cne $library.sha256)) {
                        throw 'Retained witnesses and full-target runtime images differ'
                    }
                }
                if ($target -ceq 'c') {
                    foreach ($kind in @('gc','io','foreign')) {
                        foreach ($library in $retained.consumers[$entry.context]["${kind}_contract"].reference_library_files) {
                            if (-not $observed.images.ContainsKey($library.file) -or
                                $observed.images[$library.file] -cne $library.sha256) {
                                throw 'Retained witnesses and full-target C oracle images differ'
                            }
                        }
                    }
                }
                # Source adaptation needs a separate exact-byte replay. Until
                # that producer/verifier exists, reject it explicitly rather
                # than turn an exclusion decision into execution authority.
                if ($report.execution_disposition -cne 'unchanged') {
                    throw 'Full-target adapted execution replay is not implemented'
                }
                $outcome = Get-ConformanceOutcome -Process $report.process -Marker $contract.completion_marker
                [void](Test-ConformanceAcceptance -Process $report.process -Outcome $outcome -Contract $contract `
                    -Operation $entry.operation -Context $entry.context -SourceRecords $report.fixture_records `
                    -RunId $report.run_id -Configuration $report.requested_configuration `
                    -AllocatorLimitBytes $report.allocator_limit_bytes -CoverageComplete $inventory.TargetComplete `
                    -CoverageRecords $coverage -Telemetry $observed.telemetry)
            }
            $pair[$target] = $report
            $executions += @{operation=$entry.operation;context=$entry.context;target=$expectedTarget;
                variant=$report.variant;report_sha256=$identity.sha256;disposition=$report.execution_disposition;
                excluded_obligations=$observed.excluded_obligations;synthetic_fixture=$report.synthetic_fixture}
        }
        if ($entry.comparison -ceq 'exact' -and
            ($pair.c.process.stdout_sha256 -cne $pair.ada.process.stdout_sha256 -or
             $pair.c.process.stderr_sha256 -cne $pair.ada.process.stderr_sha256)) {
            throw 'Full-target exact C/Ada output differs'
        }
    }
    return @{target=$TargetPolicy;revision=$manifest.revision;contexts=@($suite.acceptance_contexts).Count;
        operations=@($manifest.operations).Count;supplemental_operations=@($manifest.supplemental).Count;
        executions=$executions;target_acceptance=[bool]$RequireTargetAcceptance;
        excluded_obligations=@($inventory.Exclusions);excluded_obligation_count=$inventory.ExcludedSourceObligations;
        pending_source_obligations=$inventory.RequiredPendingSourceAnchors;pending_api_entries=$inventory.PendingApiEntries;
        original_suite_unchanged_pass=([bool]$RequireTargetAcceptance -and $inventory.Complete -and
            @($executions | Where-Object disposition -CNE 'unchanged').Count -eq 0);
        full_m3_acceptance=$false;synthetic_fixture=$manifest.synthetic_fixture}
}

Export-ModuleMember -Function Assert-TargetMatrixIndex, Assert-TargetMatrixCoverage,
    Test-TargetMatrixReport, Test-FullTargetMatrix
