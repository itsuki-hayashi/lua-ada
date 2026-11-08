param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root ('tests/conformance/targets/' +
    'remaining-upstream-compatibility/main-windows-signals.author-observation.json')
$packet = Get-Content -LiteralPath $path -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
$script:checks = 0
$controlCExit = [Convert]::ToUInt32('C000013A', 16)
function Require([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Same-Json($Left, $Right) {
    (ConvertTo-Json -InputObject $Left -Compress -Depth 100) -ceq
        (ConvertTo-Json -InputObject $Right -Compress -Depth 100)
}
function Read-Observation($Record) {
    Require ((Hash (Join-Path $root $Record.path)) -ceq $Record.sha256) 'Raw observation changed'
    $raw = Get-Content -LiteralPath (Join-Path $root $Record.path) -Raw |
        ConvertFrom-Json -AsHashtable -Depth 100
    Require (Same-Json $raw $Record.data) 'Embedded raw observation changed'
    $raw
}
function Check-Document($Document) {
    Require ($Document.schema_version -eq 1 -and
        $Document.kind -ceq 'windows-main-real-sigint-author-observation' -and
        $Document.author_only -is [bool] -and $Document.author_only -eq $true -and
        $Document.independent_review -ceq 'pending') 'Unexpected author schema'
    foreach ($field in @('source_approval', 'adaptation_approval',
        'native_applicability_approval', 'runtime_acceptance', 'coverage_authority',
        'source_adaptation_authority', 'production_signal_implementation',
        'transformed_source_emitted', 'original_main_executed',
        'complete_native_positive_gate')) {
        Require ($Document[$field] -is [bool] -and
            $Document[$field] -eq $false) "Authority/gate changed: $field"
    }
    foreach ($field in @('source_mappings', 'source_exclusions', 'mode_flags')) {
        Require (@($Document[$field]).Count -eq 0) "Source policy introduced: $field"
    }
    $contract = $Document.broker_contract
    Require ($contract.test_only -eq $true -and $contract.new_child_console -eq $true -and
        $contract.hidden_SW_HIDE -eq $true -and $contract.event -ceq 'CTRL_C_EVENT' -and
        $contract.group_id -eq 0 -and $contract.console_members_exact -eq 2 -and
        $contract.attach_after_actual_readiness -eq $true -and
        $contract.attach_retry_error -eq 6 -and $contract.attach_retry_max_ms -eq 2000 -and
        $contract.child_deadline_ms -eq 25000 -and $contract.outer_deadline_seconds -eq 30 -and
        $contract.capture_limit_bytes -eq 1048576 -and
        $contract.expected_search_exit_status -eq $controlCExit -and
        $contract.checked_cleanup_required -eq $true -and
        $contract.terminate_cleanup_is_failure -eq $true) 'Broker contract changed'
    $paths = @('experiments/conformance/c/windows_signal_broker.c',
        'tests/conformance/platform/windows-main-sigint-protected.lua',
        'tests/conformance/platform/windows-main-sigint-search.lua',
        'scripts/observe-windows-main-signals.ps1', 'scripts/ConformanceRunner.psm1',
        'references/lua/testes/main.lua', 'references/lua/lua.c',
        'references/lua/ltests.c')
    Require (@($Document.source_bindings).Count -eq 8) 'Source binding count changed'
    foreach ($source in $paths) {
        $binding = @($Document.source_bindings | Where-Object path -CEQ $source)
        Require ($binding.Count -eq 1 -and
            $binding[0].sha256 -ceq (Hash (Join-Path $root $source))) "Stale binding: $source"
    }
    $ranges = @(
        @('main-signal-transport', 'references/lua/testes/main.lua', 550, 567),
        @('main-protected-interrupt', 'references/lua/testes/main.lua', 570, 578),
        @('main-native-search', 'references/lua/testes/main.lua', 581, 597),
        @('native-stop-hook', 'references/lua/lua.c', 70, 74),
        @('native-first-signal', 'references/lua/lua.c', 83, 87),
        @('native-cli-signal-scope', 'references/lua/lua.c', 161, 171),
        @('test-final-memory-check', 'references/lua/ltests.c', 2225, 2228),
        @('test-atexit-registration', 'references/lua/ltests.c', 2231, 2241))
    Require (@($Document.source_anchors).Count -eq 8) 'Anchor count changed'
    foreach ($range in $ranges) {
        $anchors = @($Document.source_anchors | Where-Object id -CEQ $range[0])
        Require ($anchors.Count -eq 1) 'Missing/duplicate anchor'
        $anchor = $anchors[0]
        $bytes = [IO.File]::ReadAllBytes((Join-Path $root $range[1]))
        $starts = [Collections.Generic.List[int]]::new()
        $starts.Add(0)
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 10) { $starts.Add($i + 1) }
        }
        $start = $starts[$range[2] - 1]
        $end = $starts[$range[3]]
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [byte[]]$bytes[$start..($end - 1)])).ToLowerInvariant()
        Require ($anchor.path -ceq $range[1] -and $anchor.first_line -eq $range[2] -and
            $anchor.last_line -eq $range[3] -and $anchor.byte_offset -eq $start -and
            $anchor.byte_length -eq $end - $start -and $anchor.sha256 -ceq $hash) 'Anchor changed'
    }
    $raw = Read-Observation $Document.current_observation
    Require ($raw.completed -eq $false -and @($raw.roles).Count -eq 4 -and
        @($Document.results).Count -eq 4) 'Four-role failure gate changed'
    Require ($raw.build.process.exit_code -eq 0 -and $raw.build.process.stderr_bytes -eq 0 -and
        (Hash $raw.build.source_snapshot) -ceq $raw.build.source_sha256 -and
        (Hash $raw.build.process.executable) -ceq $raw.build.compiler_sha256 -and
        (Hash $raw.roles[0].process.executable) -ceq $raw.build.broker_sha256) 'Build identity changed'
    $expectedCounts = @(1, 2, 1, 5)
    $normalCount = 0
    $abruptCount = 0
    for ($index = 0; $index -lt 4; $index++) {
        $role = $raw.roles[$index]
        $result = $Document.results[$index]
        $mode = if ($index -lt 2) { 'default' } else { 'upstream-test' }
        $kind = if ($index % 2 -eq 0) { 'protected' } else { 'search' }
        $wanted = $index -ne 3
        Require ($role.configuration -ceq $mode -and $role.kind -ceq $kind -and
            $role.completed -eq $wanted -and $result.configuration -ceq $mode -and
            $result.kind -ceq $kind -and $result.strict_pass -eq $wanted -and
            $result.request_count -eq $expectedCounts[$index]) 'Observed role relabelled'
        Require ($result.classification -ceq $(if ($wanted) {
                'PASS-authored-native-control'
            } else { 'FAIL-native-T-abrupt-teardown-assertion' })) 'Strict failure classification changed'
        Require ($role.process.exit_code -eq $(if ($wanted) { 0 } else { 1 }) -and
            $role.process.elapsed_milliseconds -lt 30000 -and
            $role.process.stderr_bytes -eq 0 -and $role.forced_cleanup -eq $false) 'Broker result changed'
        foreach ($flag in @('timed_out', 'capture_exceeded', 'pipe_drain_failed',
            'output_drain_failed', 'input_write_failed')) {
            Require ($role.process[$flag] -eq $false) "Broker process failure: $flag"
        }
        Require ($null -eq $role.process.abnormal_exit_kind -and
            -not $role.process.process_tree_kill_error) 'Broker did not finish cleanly'
        Require ($role.artifacts[0].pe_header.subsystem -eq 3 -and
            $role.artifacts[0].pe_header.machine -eq 34404 -and
            $role.config.configuration -ceq $mode -and
            $role.config.allocator_limit_bytes -eq 2147483648) 'Native CUI/config identity changed'
        foreach ($artifact in $role.artifacts) {
            Require ((Hash $artifact.frozen) -ceq $artifact.sha256) 'Native frozen image changed'
        }
        Require ((Hash $role.events_path) -ceq $role.events_sha256 -and
            (Hash $role.child_stdout.path) -ceq $role.child_stdout.sha256 -and
            (Hash $role.child_stderr.path) -ceq $role.child_stderr.sha256) 'Raw child evidence changed'
        $events = @(Get-Content -LiteralPath $role.events_path | ForEach-Object {
            ConvertFrom-Json -InputObject $_ -AsHashtable
        })
        Require (Same-Json $events $role.events) 'Embedded event trace changed'
        $created = @($events | Where-Object event -CEQ 'create-child-new-console-hidden')
        $ready = @($events | Where-Object event -CEQ 'actual-stdout-readiness')
        $exited = @($events | Where-Object event -CEQ 'child-exited')
        $final = @($events | Where-Object event -CEQ 'final-result')
        $cleanup = @($events | Where-Object event -CEQ 'cleanup-complete')
        $requests = @($events | Where-Object event -CEQ 'request-real-ctrl-c-group-zero')
        Require ($created.Count -eq 1 -and $ready.Count -eq 1 -and
            $exited.Count -eq 1 -and $final.Count -eq 1 -and
            $requests.Count -eq $expectedCounts[$index] -and $final[0].ok -eq $wanted -and
            @($events | Where-Object event -CEQ 'failed-probe-timeout-cleanup-only').Count -eq 0) 'Event outcomes changed'
        Require ($cleanup.Count -eq 1 -and $cleanup[0].ok -and
            $cleanup[0].value -eq 9 -and
            @($events | Where-Object {
                $_.event -in @('close-owned-handle-failed',
                    'detach-child-console-failed', 'free-attribute-storage-failed')
            }).Count -eq 0) 'Checked cleanup failed'
        $previous = 0
        $number = 0
        for ($j = 0; $j -lt $events.Count; $j++) {
            $event = $events[$j]
            Require ($event.broker_pid -eq $role.process.process_id -and
                $event.child_pid -eq $created[0].child_pid -and
                $event.elapsed_ms -ge $previous -and $event.elapsed_ms -lt 25000) 'PID/timestamp changed'
            $previous = $event.elapsed_ms
            if ($event.event -ceq 'attach-child-console-attempt') {
                Require ($event.elapsed_ms -ge $ready[0].elapsed_ms -and
                    $event.value -le 2000 -and ($event.ok -or $event.win32_error -eq 6)) 'Attachment policy changed'
            }
            if ($event.event -ceq 'request-real-ctrl-c-group-zero') {
                $number++
                Require ($j -ge 3 -and $event.ok -and $event.value -eq $number -and
                    $events[$j - 1].event -ceq 'console-membership' -and
                    $events[$j - 1].ok -and $events[$j - 1].value -eq 2 -and
                    $events[$j - 2].event -ceq 'console-member' -and
                    $events[$j - 3].event -ceq 'console-member') 'Signal isolation guard missing'
                $ids = @($events[$j - 2].value, $events[$j - 3].value)
                Require ($ids -contains $role.process.process_id -and
                    $ids -contains $created[0].child_pid) 'Wrong console members'
            }
        }
        if ($kind -ceq 'protected') {
            $normalCount++
            Require ([IO.File]::ReadAllText($role.child_stdout.path) -ceq "12`r`n42`r`n" -and
                (Get-Item -LiteralPath $role.child_stderr.path).Length -eq 0 -and
                $exited[0].value -eq 0 -and $result.actual_exit_code -eq 0 -and
                $result.normal_return_telemetry -eq $true -and
                $result.abrupt_missing_telemetry -eq $false -and
                $result.accounting_claim -ceq 'actual-normal-return-balanced' -and
                @($role.sidecars).Count -eq 1) 'Protected signal/normal closure changed'
            $sidecar = $role.sidecars[0]
            Require ((Hash $sidecar.path) -ceq $sidecar.sha256 -and
                $sidecar.data.process_id -eq $created[0].child_pid -and
                $sidecar.data.run_id -ceq $role.environment.LUA_ADA_CONFORMANCE_RUN_ID -and
                $sidecar.data.configuration -ceq $mode -and
                $sidecar.data.allocator_limit_bytes -eq 2147483648 -and
                $sidecar.data.outstanding_bytes -eq 0 -and
                $sidecar.data.outstanding_blocks -eq 0) 'Actual normal telemetry changed'
        } else {
            $abruptCount++
            Require ([IO.File]::ReadAllText($role.child_stdout.path) -ceq "15`r`n" -and
                $exited[0].value -eq $controlCExit -and
                $result.actual_exit_code -eq $controlCExit -and
                $result.normal_return_telemetry -eq $false -and
                $result.abrupt_missing_telemetry -eq $true -and
                $result.accounting_claim -ceq 'unavailable-no-normal-return-telemetry' -and
                @($role.sidecars).Count -eq 0) 'Abrupt death/absent telemetry changed'
            if ($mode -ceq 'default') {
                Require ((Get-Item -LiteralPath $role.child_stderr.path).Length -eq 0) 'Default search stderr changed'
            } else {
                Require ([IO.File]::ReadAllText($role.child_stderr.path).Contains(
                    'Assertion failed: l_memcontrol.numblocks == 0') -and
                    [IO.File]::ReadAllText($role.child_stderr.path).Contains(
                    'ltests.c, line 2226')) 'Native T failure hidden'
            }
        }
    }
    Require ($normalCount -eq 2 -and $abruptCount -eq 2) 'Shutdown accounting classes changed'
    $initial = Read-Observation $Document.initial_failure
    Require ($initial.completed -eq $false -and $initial.roles.Count -eq 1 -and
        $initial.roles[0].completed -eq $false -and
        $initial.roles[0].forced_cleanup -eq $true -and
        @($initial.roles[0].events | Where-Object {
            $_.event -ceq 'request-real-ctrl-c-group-zero'
        }).Count -eq 0 -and
        @($initial.roles[0].events | Where-Object {
            $_.event -ceq 'attach-child-console'
        })[0].win32_error -eq 6) 'Initial console failure lost'
    Require ((Hash (Join-Path $root $Document.initial_failure.frozen_source.path)) -ceq
        $initial.build.source_sha256 -and
        $Document.initial_failure.frozen_source.sha256 -ceq $initial.build.source_sha256) 'Initial exact broker source lost'
    Require ((Hash (Join-Path $root $Document.initial_failure.frozen_observer.path)) -ceq
        $Document.initial_failure.frozen_observer.sha256) 'Initial exact observer lost'
    $prior = $Document.previous_author_packet
    Require ((Hash (Join-Path $root $prior.path)) -ceq $prior.sha256) 'Prior author packet changed'
    $old = Get-Content -LiteralPath (Join-Path $root $prior.path) -Raw |
        ConvertFrom-Json -AsHashtable -Depth 100
    Require ($old.complete_native_positive_gate -eq $false -and
        $old.results.Count -eq 4 -and $old.results[3].strict_pass -eq $false -and
        $old.results[3].request_count -eq 5 -and
        $old.current_observation.data.completed -eq $false -and
        (Hash (Join-Path $root $old.current_observation.path)) -ceq
        $old.current_observation.sha256) 'Previous four observations relabelled/lost'
    Require ((Hash $old.current_observation.data.build.source_snapshot) -ceq
        $old.current_observation.data.build.source_sha256 -and
        (Hash (Join-Path $root $prior.frozen_observer.path)) -ceq
        $prior.frozen_observer.sha256) 'Previous broker/observer source lost'
}

Check-Document $packet
$positive = $script:checks
function Must-Reject([string] $Name, [scriptblock] $Mutation) {
    $copy = ConvertFrom-Json -AsHashtable -Depth 100 -InputObject (
        ConvertTo-Json -InputObject $packet -Depth 100)
    & $Mutation $copy
    $failed = $false
    try { Check-Document $copy } catch { $failed = $true }
    Require $failed "Rejected mutation was accepted: $Name"
}
Must-Reject gate-pass { param($p) $p.complete_native_positive_gate = $true }
Must-Reject T-clean { param($p) $p.results[3].strict_pass = $true }
Must-Reject source-approval { param($p) $p.source_approval = $true }
Must-Reject missing-author { param($p) $p.Remove('author_only') }
Must-Reject source-map { param($p) $p.source_mappings = @(@{line = 550}) }
Must-Reject exclusion { param($p) $p.source_exclusions = @(@{line = 582}) }
Must-Reject skip { param($p) $p.mode_flags = @('_port') }
Must-Reject production { param($p) $p.production_signal_implementation = $true }
Must-Reject group-target { param($p) $p.broker_contract.group_id = 1 }
Must-Reject cleanup-pass { param($p) $p.broker_contract.terminate_cleanup_is_failure = $false }
Must-Reject missing-T { param($p) $p.current_observation.data.roles = @($p.current_observation.data.roles[0]) }
Must-Reject absent-as-balanced { param($p) $p.results[3].accounting_claim = 'actual-normal-return-balanced' }
Must-Reject source-drift { param($p) $p.source_bindings[0].sha256 = '0' * 64 }
Must-Reject payload-drift { param($p) $p.source_anchors[1].byte_length-- }
Must-Reject count-refresh { param($p) $p.results[3].request_count = 2 }
Must-Reject initial-failure-erasure { param($p) $p.initial_failure.data.completed = $true }
Must-Reject unexpected-access-violation {
    param($p) $p.results[1].actual_exit_code = [Convert]::ToUInt32('C0000005', 16)
}
Must-Reject loosened-exit-contract {
    param($p) $p.broker_contract.expected_search_exit_status = 1
}
Must-Reject unchecked-cleanup {
    param($p) $p.broker_contract.checked_cleanup_required = $false
}
"Windows real signals: $positive integrity checks and 19 rejection controls passed; native T search remains FAIL, no source/runtime authority"
