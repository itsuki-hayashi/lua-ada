param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$packetPath = Join-Path $root ('tests/conformance/targets/' +
    'remaining-upstream-compatibility/main-windows-transport.author-proposal.json')
$packet = Get-Content -LiteralPath $packetPath -Raw |
    ConvertFrom-Json -AsHashtable -Depth 100
$script:checks = 0

function Require([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}

function ByteHash([byte[]] $Bytes) {
    [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Check-Document($Document) {
    # This is an author packet checker. Passing it cannot install a source
    # mapping or convert thirteen authored controls into main.lua coverage.
    Require ($Document.schema_version -eq 1 -and
        $Document.kind -ceq 'windows-main-transport-author-proposal' -and
        $Document.platform -ceq 'windows' -and
        $Document.author_only -eq $true) 'Unexpected proposal schema'
    foreach ($field in @('source_approval', 'adaptation_approval',
        'native_applicability_approval', 'runtime_acceptance',
        'coverage_authority', 'policy_installation',
        'transformed_source_emitted', 'original_main_executed')) {
        Require ($Document[$field] -is [bool] -and
            $Document[$field] -eq $false) "Unexpected authority: $field"
    }
    Require ($Document.actual_new_builds -eq 0) 'New build attributed to probes'
    Require ($Document.review.status -ceq 'pending-independent-review' -and
        $null -eq $Document.review.reviewer -and
        $null -eq $Document.review.artifact) 'Review status changed'
    foreach ($field in @('source_mappings', 'source_exclusions', 'mode_flags')) {
        Require (@($Document[$field]).Count -eq 0) "Unexpected source policy: $field"
    }
    $bindingPaths = @('tests/conformance/platform/windows-main-cli-transport.lua',
        'scripts/observe-windows-main-transport.ps1',
        'scripts/ConformanceRunner.psm1', 'references/lua/testes/main.lua',
        'references/lua/lua.c', 'references/lua/loslib.c',
        'references/lua/liolib.c', 'references/lua/loadlib.c')
    Require (@($Document.source_bindings).Count -eq 8) 'Binding count changed'
    foreach ($path in $bindingPaths) {
        $binding = @($Document.source_bindings | Where-Object path -CEQ $path)
        Require ($binding.Count -eq 1 -and
            $binding[0].sha256 -ceq (Hash (Join-Path $root $path))) "Stale binding: $path"
    }

    $main = [IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/main.lua'))
    $starts = [Collections.Generic.List[int]]::new()
    $starts.Add(0)
    for ($i = 0; $i -lt $main.Length; $i++) {
        if ($main[$i] -eq 10) { $starts.Add($i + 1) }
    }
    $ranges = @(@('temporary-names', 18, 20), @('shell-helpers', 64, 77),
        @('stdin', 86, 102), @('environment', 134, 173),
        @('empty-environment', 186, 190), @('readline', 200, 213),
        @('library-path-literal', 238, 246), @('executable-literal', 256, 267),
        @('repl-console-shell', 279, 285), @('t-constructor', 521, 523),
        @('signals', 550, 598))
    Require (@($Document.source_anchors).Count -eq 11) 'Anchor count changed'
    foreach ($range in $ranges) {
        $anchor = @($Document.source_anchors | Where-Object id -CEQ $range[0])
        Require ($anchor.Count -eq 1) 'Duplicate/missing source anchor'
        $start = $starts[$range[1] - 1]
        $end = $starts[$range[2]]
        Require ($anchor[0].first_line -eq $range[1] -and
            $anchor[0].last_line -eq $range[2] -and
            $anchor[0].byte_offset -eq $start -and
            $anchor[0].byte_length -eq $end - $start -and
            $anchor[0].sha256 -ceq (ByteHash $main[$start..($end - 1)])) 'Source anchor changed'
    }
    $gates = @('original-or-approved-whole-main', 'all-shell-command-forms',
        'empty-environment', 'readline-applicability-and-warning', 'true-terminal',
        'first-real-SIGINT-caught', 'second-real-SIGINT-terminates-native-search',
        'T-constructor-refusal', 'all-main-child-image-and-module-protocols')
    Require (($Document.unproved_gates -join '|') -ceq ($gates -join '|')) 'Pending gates changed'
    $marks = @('fresh-private-paths', 'actual-version-redirection',
        'empty-explicit-stdin', 'multiline-explicit-stdin', 'native-type-pipe',
        'literal-path-counterpart', 'exact-argv-selected-child',
        'native-set-environment', 'actual-require-literal-name',
        'stdout-stderr-routing', 'actual-child-failure-status',
        'actual-popen-child-identity', 'owned-temp-cleanup')
    Require (($Document.counterpart_cases -join '|') -ceq ($marks -join '|')) 'Case set changed'
    $expected = ($marks | ForEach-Object {
        'PASS: windows-main-transport-' + $_ + "`r`n"
    }) -join ''
    $positive = $Document.positive_observation
    Require ((Hash (Join-Path $root $positive.path)) -ceq $positive.sha256) 'Raw positive observation changed'
    $raw = Get-Content -LiteralPath (Join-Path $root $positive.path) -Raw |
        ConvertFrom-Json -AsHashtable -Depth 100
    Require ((ConvertTo-Json -InputObject $raw -Compress -Depth 100) -ceq
        (ConvertTo-Json -InputObject $positive.data -Compress -Depth 100)) 'Embedded observation changed'
    Require (@($positive.data.roles).Count -eq 2) 'Missing native configuration'
    foreach ($mode in @('default', 'upstream-test')) {
        $roles = @($positive.data.roles | Where-Object configuration -CEQ $mode)
        Require ($roles.Count -eq 1) 'Duplicate/missing native role'
        $role = $roles[0]
        $process = $role.process
        Require ($role.counterpart_completed -eq $true -and
            $process.exit_code -eq 0 -and $process.stderr_bytes -eq 0 -and
            $null -eq $process.abnormal_exit_kind) 'Native counterpart did not complete'
        foreach ($flag in @('timed_out', 'capture_exceeded', 'pipe_drain_failed',
            'output_drain_failed', 'input_write_failed')) {
            Require ($process[$flag] -eq $false) "Native process failure: $flag"
        }
        Require (-not $process.process_tree_kill_error) 'Native tree cleanup failed'
        Require ([IO.File]::ReadAllText($process.stdout_path) -ceq $expected -and
            (Hash $process.stdout_path) -ceq $process.stdout_sha256 -and
            (Hash $process.stderr_path) -ceq $process.stderr_sha256) 'Raw output changed'
        Require (@($role.artifacts).Count -eq 2) 'Missing executable/DLL identity'
        foreach ($image in $role.artifacts) {
            Require ((Hash $image.frozen) -ceq $image.sha256) 'Frozen native image changed'
        }
        Require (@($role.sidecars).Count -eq 10) 'Not ten actual measured Lua processes'
        $pids = @{}
        foreach ($sidecar in $role.sidecars) {
            Require ((Hash $sidecar.path) -ceq $sidecar.sha256) 'Raw sidecar changed'
            $data = $sidecar.data
            Require ($data.configuration -ceq $mode -and
                $data.run_id -ceq $role.environment.LUA_ADA_CONFORMANCE_RUN_ID -and
                $data.allocator_limit_bytes -eq 2147483648 -and
                $data.managed_refusals -eq 0 -and $data.outstanding_bytes -eq 0 -and
                $data.outstanding_blocks -eq 0 -and
                -not $pids.ContainsKey([long]$data.process_id)) 'Allocator identity/cleanup changed'
            $pids[[long]$data.process_id] = $true
        }
        Require ($pids.ContainsKey([long]$process.process_id)) 'Parent sidecar missing'
        Require (@($role.final_cwd_files).Count -eq 1 -and
            $role.final_cwd_files[0] -ceq 'transport.lua') 'Temporary files retained'
    }
    Require (@($Document.diagnostic_attempts).Count -eq 3) 'Diagnostic attempts lost'
    foreach ($attempt in $Document.diagnostic_attempts) {
        Require ((Hash (Join-Path $root $attempt.path)) -ceq $attempt.sha256) 'Raw diagnostic changed'
        Require (@($attempt.roles).Count -eq 2 -and
            @($attempt.roles | Where-Object exit_code -NE 1).Count -eq 0) 'Failed attempt relabelled'
    }
}

Check-Document $packet
$positiveChecks = $script:checks
function Must-Reject([string] $Name, [scriptblock] $Mutation) {
    $copy = ConvertFrom-Json -AsHashtable -Depth 100 -InputObject (
        ConvertTo-Json -InputObject $packet -Depth 100)
    & $Mutation $copy
    $rejected = $false
    try { Check-Document $copy } catch { $rejected = $true }
    Require $rejected "Negative control accepted: $Name"
}
Must-Reject approval { param($p) $p.source_approval = $true }
Must-Reject missing-author-label { param($p) $p.Remove('author_only') }
Must-Reject emitted-source { param($p) $p.transformed_source_emitted = $true }
Must-Reject omitted-T { param($p) $p.positive_observation.data.roles = @($p.positive_observation.data.roles[0]) }
Must-Reject added-skip { param($p) $p.mode_flags = @('_port') }
Must-Reject policy-map { param($p) $p.source_mappings = @(@{line = 18}) }
Must-Reject dropped-gate { param($p) $p.unproved_gates = @($p.unproved_gates[0]) }
Must-Reject source-drift { param($p) $p.source_bindings[0].sha256 = '0' * 64 }
Must-Reject anchor-drift { param($p) $p.source_anchors[0].byte_offset++ }
Must-Reject renamed-case { param($p) $p.counterpart_cases[0] = 'other' }
Must-Reject forged-review { param($p) $p.review.reviewer = 'author' }
Must-Reject embedded-output { param($p) $p.positive_observation.data.roles[0].process.exit_code = 1 }
Must-Reject diagnostic-pass { param($p) $p.diagnostic_attempts[0].roles[0].exit_code = 0 }
Must-Reject new-build { param($p) $p.actual_new_builds = 1 }
"Windows main transport: $positiveChecks positive checks and 14 rejection controls passed; author-only, no source authority"
