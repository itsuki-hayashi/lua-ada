param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$packet = Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/cli-dynamic-arg.author-observation.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
$casePacket = Get-Content (Join-Path $root $packet.cases_path) -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
$script:checks = 0
$script:identities = 0

function Require([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Verify-Bytes([string] $Path, [string] $Expected) {
    Require ((Hash $Path) -ceq $Expected) "Evidence bytes changed: $Path"
    $script:identities++
}

Require ($packet.kind -ceq 'cli-dynamic-arg-author-observation' -and
    $packet.runtime_acceptance -eq $false -and $packet.coverage_authority -eq $false -and
    $packet.source_adaptation_authority -eq $false -and
    $packet.independent_feature_review -ceq 'pending' -and
    $packet.actual_implementation_changes -eq $false) 'Author evidence acquired authority'
Require ($packet.transformed_main_emitted -eq $false -and
    $packet.original_main_executed -eq $false -and @($packet.modes).Count -eq 0) 'Unexpected original/adapted execution'
Require ($packet.roles.Count -eq 6 -and $casePacket.cases.Count -eq 21 -and
    $packet.new_lua_case_processes -eq 126 -and $packet.new_configuration_processes -eq 6 -and
    $packet.measured_workload_sidecars -eq 84) 'Unexpected campaign shape'
Require ($packet.planned_design.status -ceq 'pending-root-review') 'Proposed design is not pending'
Verify-Bytes (Join-Path $packet.evidence_repository_root $packet.raw_summary.path) $packet.raw_summary.sha256
foreach ($source in $packet.source_bindings) {
    Verify-Bytes (Join-Path $root $source.path) $source.sha256
}
foreach ($source in $packet.design_source_bindings) {
    Verify-Bytes (Join-Path $root $source.path) $source.sha256
}

$seenRoles = @{}
$processes = 0
$sidecars = 0
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($role in $packet.roles) {
    $key = $role.implementation + '/' + $role.configuration_label
    Require (-not $seenRoles.ContainsKey($key)) 'Duplicate image role'
    $seenRoles[$key] = $true
    Require ($role.implementation -cin @('ReferenceC', 'AdaConformance', 'AdaProduct') -and
        $role.configuration_label -cin @('default', 'upstream-test')) 'Unknown image role'
    foreach ($artifact in $role.artifacts) { Verify-Bytes $artifact.frozen $artifact.sha256 }
    $config = $role.configuration_process
    Verify-Bytes $config.stdout_path $config.stdout_sha256
    Verify-Bytes $config.stderr_path $config.stderr_sha256
    Require ($config.exit_code -eq 0 -and $config.stderr_bytes -eq 0 -and
        -not $config.timed_out -and -not $config.pipe_drain_failed -and
        -not $config.capture_exceeded -and -not $config.process_tree_kill_error) 'Configuration capture failed'
    if ($role.implementation -ceq 'AdaProduct') {
        Require ($role.configuration_data.test_adapter -eq $false -and
            $role.configuration_data.lua_version -ceq 'Lua 5.5' -and
            $role.telemetry_required -eq $false) 'Product CLI gained unmeasured adapter/allocator claims'
    }
    else {
        Require ($role.configuration_data.configuration -ceq $role.configuration_label -and
            $role.configuration_data.test_adapter -eq ($role.configuration_label -ceq 'upstream-test') -and
            $role.configuration_data.allocator_limit_bytes -eq 2147483648) 'Measured configuration differs'
        if ($role.configuration_data.ContainsKey('telemetry')) {
            Verify-Bytes $role.configuration_data.telemetry.path $role.configuration_data.telemetry.sha256
        }
    }
    Require ($role.cases.Count -eq 21) 'Role omitted a case'
    $passCount = 0
    $failCount = 0
    foreach ($index in 0..20) {
        $expected = $casePacket.cases[$index]
        $row = $role.cases[$index]
        Require ($row.id -ceq $expected.id) 'Case reordered/renamed'
        Verify-Bytes $row.record_path $row.record_sha256
        $record = Get-Content -LiteralPath $row.record_path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        Require ($record.id -ceq $expected.id -and $record.runtime_acceptance -eq $false -and
            $record.coverage_authority -eq $false) 'Case identity or authority differs'
        $process = $record.process
        $processes++
        Require ($process.timeout_seconds -eq 30 -and $process.capture_limit_bytes -eq 1048576 -and
            -not $process.timed_out -and -not $process.capture_exceeded -and
            -not $process.pipe_drain_failed -and -not $process.process_tree_kill_error -and
            -not $process.abnormal_exit_kind) 'Case transport failed'
        Verify-Bytes $process.stdout_path $process.stdout_sha256
        Verify-Bytes $process.stderr_path $process.stderr_sha256
        Require ($process.executable_sha256 -ceq $role.artifacts[0].sha256) 'Wrong actual executable'
        $argv = @('-e', $expected.setup, $casePacket.selected_name) + @($expected.script_arguments)
        Require (($process.arguments | ConvertTo-Json -Compress) -ceq
            ($argv | ConvertTo-Json -Compress)) 'Actual argv bytes/values differ'
        $setupHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            $utf8.GetBytes($expected.setup))).ToLowerInvariant()
        Require ($record.setup_utf8_sha256 -ceq $setupHash) 'Actual -e setup identity differs'
        $scriptPath = Join-Path $process.working_directory $casePacket.selected_name
        Verify-Bytes $scriptPath $record.selected_script_sha256
        Require ($record.selected_script_sha256 -ceq (Hash (Join-Path $root $casePacket.script))) 'Shared selected script differs'
        $wrong = [IO.File]::ReadAllText((Join-Path $process.working_directory 'wrong-script.lua'))
        Require ($wrong -ceq $casePacket.wrong_script) 'Retarget sentinel changed'
        $stdout = [IO.File]::ReadAllText($process.stdout_path)
        $stderr = [IO.File]::ReadAllText($process.stderr_path)
        $contractMatches = if ($expected.expected.kind -ceq 'script-completed') {
            $process.exit_code -eq 0 -and $stdout -ceq $expected.expected.stdout -and $stderr -ceq ''
        }
        else { $process.exit_code -ne 0 -and $stdout -ceq '' -and $stderr.Contains($expected.expected.stderr_contains) }
        Require ($record.matches_native_contract -eq $contractMatches -and
            $row.matches_native_contract -eq $contractMatches) 'Outcome classification differs from raw capture'
        if ($contractMatches) { $passCount++ } else { $failCount++ }
        if ($role.telemetry_required) {
            $sidecars++
            $telemetry = $record.telemetry
            Verify-Bytes $telemetry.path $telemetry.sha256
            $actual = Get-Content -LiteralPath $telemetry.path -Raw | ConvertFrom-Json -AsHashtable
            Require ($actual.process_id -eq $process.process_id -and
                $actual.run_id -ceq $record.environment.LUA_ADA_CONFORMANCE_RUN_ID -and
                $actual.configuration -ceq $role.configuration_label -and
                $actual.allocator_limit_bytes -eq 2147483648 -and
                $actual.outstanding_bytes -eq 0 -and $actual.outstanding_blocks -eq 0) 'Sidecar identity/balance differs'
            if ($role.implementation -ceq 'AdaConformance') {
                Require ($actual.shutdown_complete -eq $true -and $actual.accounting_fault -eq $false) 'Ada cleanup not completed'
            }
        }
        else { Require ($null -eq $record.telemetry) 'Invented product allocator measurement' }
    }
    Require ($role.passes_native_contract -eq $passCount -and
        $role.fails_native_contract -eq $failCount) 'Role total differs'
    if ($role.implementation -ceq 'ReferenceC') {
        Require ($passCount -eq 21 -and $failCount -eq 0) 'Native controls were not all established'
    }
    else { Require ($passCount -eq 3 -and $failCount -eq 18) 'Dated Ada diagnostic no longer matches its retained records' }
}
Require ($processes -eq 126 -and $sidecars -eq 84) 'Omitted raw process/sidecar'
Write-Output "PASS: frozen CLI argument evidence: $processes cases, 6 configuration probes, $sidecars measured workload sidecars"
Write-Output "PASS: $script:identities actual source/image/input/capture/record identities; $script:checks integrity checks"
Write-Output 'This reads dated observations only; current Ada mismatch and pending design remain unresolved.'
