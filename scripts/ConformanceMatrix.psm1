Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')

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
        if ($manifest.review.status -cne 'reviewed' -or $manifest.review.author -ceq $manifest.review.reviewer) {
            throw 'Matrix requires completed independent review'
        }
        $head = (& git -C $Root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $head -cne $manifest.revision) { throw 'Matrix is not the final checkout revision' }
        $dirty = @(& git -C $Root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
        if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Matrix acceptance requires a clean final checkout' }
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
        $contract = $null
        if ($RequireScopedAcceptance) {
            $contract = Read-MatrixHashedJson -Path (Join-Path $bundle $entry.contract.path) -Hash $entry.contract.sha256
        }
        foreach ($target in @('c','ada')) {
            $identity = $entry[$target]
            $report = Read-MatrixHashedJson -Path (Join-Path $bundle $identity.report) -Hash $identity.sha256
            $artifacts = [IO.Path]::GetFullPath((Join-Path $bundle $identity.artifact_root))
            $expectedTarget = if ($target -eq 'ada') { 'Ada' } else { 'ReferenceC' }
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
            $telemetryPath = Resolve-MatrixCapture -Original $report.allocator_telemetry.path `
                -ArtifactRoot $artifacts -Hash $report.allocator_telemetry.sha256
            $telemetry = Get-Content -LiteralPath $telemetryPath -Raw | ConvertFrom-Json -AsHashtable
            Assert-ScopedProcessCompletion -File $entry.file -Process $report.process -Telemetry $telemetry `
                -RunId $report.run_id -Configuration $configuration -NativeOracle:($target -eq 'c')
            if ($entry.file -eq 'files.lua') {
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
                    ($report.equivalent.diagnostic_only -ne $false -or $report.equivalent.review_status -cne 'reviewed')) {
                    throw 'Matrix contains an unreviewed equivalent'
                }
                if ($report.execution_disposition -ne 'unchanged') {
                    $id = [string]$report.equivalent.id
                    if ($id -cnotmatch '^[a-z0-9-]+$') { throw 'Invalid matrix equivalent identifier' }
                    $mapping = Read-MatrixHashedJson -Path (Join-Path $Root "tests/conformance/equivalents/$id.json") `
                        -Hash $report.equivalent.manifest_sha256
                    if ($mapping.review.status -cne 'reviewed' -or
                        [string]::IsNullOrWhiteSpace([string]$mapping.review.author) -or
                        [string]::IsNullOrWhiteSpace([string]$mapping.review.reviewer) -or
                        $mapping.review.author -ceq $mapping.review.reviewer -or
                        [string]::IsNullOrWhiteSpace([string]$mapping.review.artifact)) {
                        throw 'Matrix equivalent mapping lacks independent review'
                    }
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
                disposition=$report.execution_disposition; report_sha256=$identity.sha256}
        }
    }
    return [ordered]@{scope=$manifest.scope; revision=$manifest.revision; contexts=$suite.acceptance_contexts.Count;
        operations=$manifest.operations.Count; executions=$records; scoped_acceptance=[bool]$RequireScopedAcceptance;
        full_m3_acceptance=$false}
}

Export-ModuleMember -Function Assert-ScopedMatrixIndex, Test-ScopedMatrix
