param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$packet = Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/cli-typed-arguments.current.author-observation.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
$checks = 0
function Check([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
Check ($packet.new_evidence -eq $true -and $packet.runtime_acceptance -eq $false -and
    $packet.coverage_authority -eq $false -and $packet.source_adaptation_authority -eq $false -and
    $packet.original_main_executed -eq $false) 'Unexpected authority/original-source claim'
foreach ($binding in $packet.new_current_source_bindings) {
    Check ((Hash (Join-Path $root $binding.path)) -ceq $binding.sha256) "Current source drift: $($binding.path)"
}
$caseCount = 0
$sidecarCount = 0
foreach ($campaign in $packet.campaigns) {
    $path = Join-Path $root ($campaign.directory + '/observation.json')
    Check ((Hash $path) -ceq $campaign.raw_summary_sha256) 'Fresh raw summary drift'
    foreach ($role in $campaign.roles) {
        foreach ($artifact in $role.artifacts) {
            Check ((Hash $artifact.frozen) -ceq $artifact.sha256) 'Frozen executable/DLL changed'
        }
        Check ($role.fails_native_contract -eq 0) 'Current component still differs'
        foreach ($row in $role.cases) {
            $caseCount++
            Check ((Hash $row.record_path) -ceq $row.record_sha256) 'Actual case record changed'
            $record = Get-Content -LiteralPath $row.record_path -Raw |
                ConvertFrom-Json -AsHashtable -Depth 100
            $process = $record.process
            Check ($record.matches_native_contract -eq $true -and
                -not $process.timed_out -and -not $process.capture_exceeded -and
                -not $process.pipe_drain_failed -and -not $process.process_tree_kill_error -and
                -not $process.abnormal_exit_kind) 'Component process did not satisfy contract'
            Check ((Hash $process.stdout_path) -ceq $process.stdout_sha256 -and
                (Hash $process.stderr_path) -ceq $process.stderr_sha256) 'Raw process capture changed'
            if ($record.telemetry) {
                $sidecarCount++
                Check ((Hash $record.telemetry.path) -ceq $record.telemetry.sha256) 'Sidecar changed'
                $actual = Get-Content -LiteralPath $record.telemetry.path -Raw |
                    ConvertFrom-Json -AsHashtable
                Check ($actual.process_id -eq $process.process_id -and
                    $actual.run_id -ceq $record.environment.LUA_ADA_CONFORMANCE_RUN_ID -and
                    $actual.configuration -ceq $role.configuration_label -and
                    $actual.allocator_limit_bytes -eq 2147483648 -and
                    $actual.outstanding_bytes -eq 0 -and $actual.outstanding_blocks -eq 0) 'Sidecar identity/balance differs'
            }
            elseif ($role.implementation -ceq 'ReferenceC') {
                Check ($record.ContainsKey('telemetry_unavailable_reason') -and
                    $record.telemetry_unavailable_reason.Contains('bypasses')) 'Unexplained native sidecar absence'
            }
            else { Check ($role.implementation -ceq 'AdaProduct') 'Missing measured Ada sidecar' }
        }
    }
}
Check ($caseCount -eq 166 -and $sidecarCount -eq 110) 'Current campaign omitted a case or sidecar'
Write-Output "PASS: fresh CLI argument component: $caseCount cases, $sidecarCount normal-return sidecars, $checks integrity checks"
Write-Output 'Dated baseline packets stay unchanged; this grants no original main.lua or full-target authority.'
