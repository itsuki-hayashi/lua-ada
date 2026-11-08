param([Parameter(Mandatory)][string] $ArtifactsRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$selectedRoot = (Resolve-Path -LiteralPath $ArtifactsRoot).Path
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$utf8 = [Text.UTF8Encoding]::new($false)
$output = Join-Path $root ('reports/cli-arg-lifecycle/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($output)
$casePath = Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/cli-arg-lifecycle.author-cases.json'
$cases = Get-Content -LiteralPath $casePath -Raw | ConvertFrom-Json -AsHashtable -Depth 100

function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Save([string] $Path, $Value) {
    $json = (ConvertTo-Json -InputObject $Value -Depth 80).Replace([string][char]13, '') + [char]10
    [IO.File]::WriteAllText($Path, $json, $utf8)
}

function Freeze([string] $Source, [string] $Target) {
    $before = Hash $Source
    [IO.File]::Copy($Source, $Target, $false)
    if ((Hash $Source) -cne $before -or (Hash $Target) -cne $before) {
        throw 'Selected artifact changed while being frozen'
    }
    return @{selected = $Source; frozen = $Target; sha256 = $before}
}

$summary = [ordered]@{
    schema_version = 1; kind = 'cli-arg-lifecycle-author-observation'
    author = 'Codex /root/runtime_gaps'; date = '2026-11-08'
    source_snapshot_revision = (& git -C $root rev-parse HEAD)
    selected_artifact_repository_revision = (& git -C $selectedRoot rev-parse HEAD)
    runtime_acceptance = $false; coverage_authority = $false
    source_adaptation_authority = $false; independent_feature_review = 'pending'
    transformed_main_emitted = $false; original_main_executed = $false
    modes = @(); source_bindings = @(); roles = @()
    compiler_flags_provenance = 'Existing artifacts only; source/GPR hashes are not compile-command receipts.'
    limits = @{per_process_timeout_seconds = 30; capture_limit_bytes = 1048576;
        conformance_allocator_limit_bytes = 2147483648; product_cli_allocator_ceiling_measured = $false}
}
foreach ($path in @(
    'references/lua/testes/main.lua', 'references/lua/lua.c', 'references/lua/lauxlib.c',
    'scripts/ConformanceRunner.psm1', 'scripts/observe-cli-arg-lifecycle.ps1',
    'tests/conformance/targets/remaining-upstream-compatibility/cli-arg-lifecycle.author-cases.json',
    'tests/conformance/platform/cli-dynamic-arg.lua',
    'tests/conformance/platform/cli-dynamic-arg-refused-entry.lua',
    'cli/shared/lua_cli.adb', 'src/lua-sessions.adb',
    'cli/shared/lua-sessions-cli.ads', 'cli/shared/lua-sessions-cli.adb',
    'experiments/conformance/oracle.gpr', 'experiments/conformance/reference.gpr')) {
    $summary.source_bindings += @(@{path = $path; sha256 = (Hash (Join-Path $root $path))})
}

# Native roles deliberately run first. Their observed positive/error outcomes
# establish the controls before any current Ada mismatch is classified. The
# six roles all receive the same exact setup argument and selected script.
$roles = @()
foreach ($kind in @('ReferenceC', 'AdaConformance', 'AdaProduct')) {
    foreach ($configuration in @('default', 'upstream-test')) {
        $roles += @(@{kind = $kind; configuration = $configuration})
    }
}
$nativeUnexpected = $false
foreach ($role in $roles) {
    if ($role.kind -cne 'ReferenceC' -and $nativeUnexpected) {
        Save (Join-Path $output 'observation.json') $summary
        throw "Native expectations need review before Ada comparison: $output"
    }
    $directory = Join-Path $output ($role.kind + '-' + $role.configuration)
    $frozen = Join-Path $directory 'frozen'
    [void][IO.Directory]::CreateDirectory($frozen)
    $exe = Join-Path $frozen 'lua.exe'
    $artifacts = @()
    if ($role.kind -ceq 'ReferenceC') {
        $artifacts += @(Freeze (Join-Path $selectedRoot "build/conformance/$($role.configuration)/bin/lua.exe") $exe)
        $artifacts += @(Freeze (Join-Path $selectedRoot "build/conformance/$($role.configuration)/lib/libconformance_lua.dll") `
            (Join-Path $frozen 'libconformance_lua.dll'))
    }
    else {
        $mode = if ($role.configuration -ceq 'upstream-test') { 'upstream-test/' } else { '' }
        $selected = if ($role.kind -ceq 'AdaConformance') {
            Join-Path $selectedRoot ("tests/bin/${mode}static/conformance_runner.exe")
        } else { Join-Path $selectedRoot ("cli/bin/${mode}static/lua_ada.exe") }
        $artifacts += @(Freeze $selected $exe)
    }
    $entry = [ordered]@{
        implementation = $role.kind; configuration_label = $role.configuration
        artifacts = $artifacts; configuration_process = $null
        configuration_data = $null; cases = @(); passes_native_contract = 0
        fails_native_contract = 0; omitted_T_cases = @(); telemetry_required = ($role.kind -cne 'AdaProduct')
        product_configuration_note = 'Product CLI has no conformance configuration command; build-path label is not an adapter claim. Actual _VERSION/type(T) are separately captured.'
    }
    $prefix = Join-Path $directory 'configuration'
    $environment = @{PATH = $frozen + [IO.Path]::PathSeparator + $env:PATH;
        LUA_ADA_CONFORMANCE_ALLOCATOR = '2147483648'; MEMLIMIT = '2147483648';
        LUA_ADA_CONFORMANCE_RUN_ID = [guid]::NewGuid().ToString('N');
        LUA_ADA_CONFORMANCE_TELEMETRY = $prefix + '-allocator'}
    $configArgs = if ($role.kind -ceq 'AdaProduct') {
        @('-e', 'print(_VERSION,type(T))')
    } else { @('--conformance-config') }
    $config = Invoke-ConformanceProcess -Executable $exe -Arguments $configArgs -Directory $frozen `
        -OutputPrefix $prefix -TimeoutSeconds 30 -CaptureLimitBytes 1048576 -Environment $environment
    if ($config.exit_code -ne 0 -or $config.stderr_bytes -ne 0 -or $config.timed_out -or
        $config.capture_exceeded -or $config.pipe_drain_failed -or $config.process_tree_kill_error) {
        throw 'Selected configuration probe failed'
    }
    $entry.configuration_process = $config
    if ($role.kind -ceq 'AdaProduct') {
        $probe = [IO.File]::ReadAllText($config.stdout_path)
        if ($probe -cne ("Lua 5.5`tnil" + [Environment]::NewLine)) { throw 'Unexpected product CLI capabilities' }
        $entry.configuration_data = @{lua_version = 'Lua 5.5'; test_adapter = $false;
            source = 'actual user-level _VERSION/type(T) probe; no conformance metadata'}
    }
    else {
        $data = Get-Content -LiteralPath $config.stdout_path -Raw | ConvertFrom-Json -AsHashtable
        if ($data.configuration -cne $role.configuration -or
            $data.test_adapter -ne ($role.configuration -ceq 'upstream-test') -or
            $data.allocator_limit_bytes -ne 2147483648) { throw 'Selected image configuration mismatch' }
        $entry.configuration_data = $data
        # Native configuration prints before constructing any Lua state. Ada
        # currently closes a real probe state; preserve a sidecar if present,
        # never synthesize one or credit the native no-state path as cleanup.
        $configTelemetry = $prefix + '-allocator.' + $config.process_id + '.json'
        if (Test-Path -LiteralPath $configTelemetry) {
            $entry.configuration_data.telemetry = @{path = $configTelemetry; sha256 = (Hash $configTelemetry)}
        }
    }
    foreach ($case in $cases.cases) {
        $needsT = $case.ContainsKey('requires_real_T') -and $case.requires_real_T
        if ($needsT -and ($role.configuration -cne 'upstream-test' -or $role.kind -ceq 'AdaProduct')) {
            # An ordinary/product role supplies no T fault-body credit.
            $entry.omitted_T_cases += @($case.id)
            continue
        }
        $cwd = Join-Path $directory $case.id
        [void][IO.Directory]::CreateDirectory($cwd)
        $name = if ($case.ContainsKey('selected_name')) { $case.selected_name } else { $cases.selected_name }
        $scriptFile = Join-Path $cwd $name
        $sourceIdentity = $null
        if ($case.create_selected_source) {
            if ($case.ContainsKey('source_text')) {
                [IO.File]::WriteAllText($scriptFile, $case.source_text, $utf8)
            } else {
                [IO.File]::Copy((Join-Path $root $case.script), $scriptFile, $false)
            }
            $sourceIdentity = Hash $scriptFile
        }
        [IO.File]::WriteAllText((Join-Path $cwd 'wrong-script.lua'), $cases.wrong_script, $utf8)
        $arguments = @('-e', $case.setup, $name) + @($case.script_arguments)
        $prefix = Join-Path $directory ($case.id + '-result')
        $run = [guid]::NewGuid().ToString('N')
        $environment = @{PATH = $frozen + [IO.Path]::PathSeparator + $env:PATH;
            LUA_ADA_CONFORMANCE_ALLOCATOR = '2147483648'; MEMLIMIT = '2147483648';
            LUA_ADA_CONFORMANCE_RUN_ID = $run; LUA_ADA_CONFORMANCE_TELEMETRY = $prefix + '-allocator'}
        $process = Invoke-ConformanceProcess -Executable $exe -Arguments $arguments -Directory $cwd `
            -OutputPrefix $prefix -TimeoutSeconds 30 -CaptureLimitBytes 1048576 -Environment $environment
        $stdout = [IO.File]::ReadAllText($process.stdout_path)
        $stderr = [IO.File]::ReadAllText($process.stderr_path)
        $transport = (-not $process.timed_out -and -not $process.capture_exceeded -and
            -not $process.pipe_drain_failed -and -not $process.process_tree_kill_error -and
            -not $process.abnormal_exit_kind)
        $contractMatches = if ($case.expected.kind -ceq 'script-completed') {
            $transport -and $process.exit_code -eq 0 -and $stderr -ceq '' -and
            $stdout.EndsWith($case.expected.stdout_suffix, [StringComparison]::Ordinal) -and
            (-not $case.expected.ContainsKey('stdout_contains') -or $stdout.Contains($case.expected.stdout_contains))
        } elseif ($case.expected.kind -ceq 'typed-exit') {
            $transport -and $process.exit_code -eq $case.expected.exit_code -and
            $stdout -ceq $case.expected.stdout -and $stderr -ceq $case.expected.stderr
        } else {
            $transport -and $process.exit_code -ne 0 -and $stdout -ceq '' -and
            $stderr.Contains($case.expected.stderr_contains)
        }
        $record = [ordered]@{id = $case.id; process = $process; environment = $environment;
            expected_native_contract = $case.expected; matches_native_contract = [bool]$contractMatches;
            setup_utf8_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($case.setup))).ToLowerInvariant();
            selected_script_sha256 = $sourceIdentity; selected_script_created = $case.create_selected_source;
            requires_real_T = $needsT; telemetry = $null; telemetry_unavailable_reason = $null;
            runtime_acceptance = $false; coverage_authority = $false}
        $nativeExit = $role.kind -ceq 'ReferenceC' -and $case.expected.kind -ceq 'typed-exit' -and
            $process.exit_code -eq $case.expected.exit_code
        if ($entry.telemetry_required -and -not $nativeExit) {
            $path = $prefix + '-allocator.' + $process.process_id + '.json'
            $telemetry = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            if ($telemetry.run_id -cne $run -or $telemetry.process_id -ne $process.process_id -or
                $telemetry.configuration -cne $role.configuration -or
                $telemetry.allocator_limit_bytes -ne 2147483648 -or
                $telemetry.outstanding_bytes -ne 0 -or $telemetry.outstanding_blocks -ne 0) {
                throw 'Measured CLI case telemetry identity/balance differs'
            }
            if ($role.kind -ceq 'AdaConformance' -and
                ($telemetry.shutdown_complete -ne $true -or $telemetry.accounting_fault -ne $false)) {
                throw 'Measured Ada shutdown/accounting differs'
            }
            $record.telemetry = @{path = $path; sha256 = (Hash $path); data = $telemetry}
        }
        if ($nativeExit) {
            $record.telemetry_unavailable_reason = 'Native os.exit bypasses conformance main-return telemetry; no balance inferred.'
        }
        if ($case.ContainsKey('requires_managed_refusal') -and $case.requires_managed_refusal -and
            $record.telemetry -and $record.telemetry.data.managed_refusals -lt 1) {
            $contractMatches = $false
            $record.matches_native_contract = $false
        }
        if ($case.create_selected_source) {
            $expectedBytes = if ($case.ContainsKey('source_text')) { $utf8.GetBytes($case.source_text) }
                else { [IO.File]::ReadAllBytes((Join-Path $root $case.script)) }
            $expectedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedBytes)).ToLowerInvariant()
            if ((Hash $scriptFile) -cne $expectedHash) { throw 'Selected source changed bytes' }
        } elseif (Test-Path -LiteralPath $scriptFile) { throw 'Missing-script control unexpectedly created its file' }
        Save ($prefix + '-process.json') $record
        $entry.cases += @(@{id = $case.id; record_path = $prefix + '-process.json';
            record_sha256 = (Hash ($prefix + '-process.json')); matches_native_contract = [bool]$contractMatches;
            exit_code = $process.exit_code; stdout_sha256 = $process.stdout_sha256;
            stderr_sha256 = $process.stderr_sha256})
        if ($contractMatches) { $entry.passes_native_contract++ } else { $entry.fails_native_contract++ }
        if ($role.kind -ceq 'ReferenceC' -and -not $contractMatches) { $nativeUnexpected = $true }
        Write-Output "$($role.kind)/$($role.configuration)/$($case.id): native-contract=$contractMatches exit=$($process.exit_code)"
    }
    foreach ($artifact in $artifacts) {
        if ((Hash $artifact.frozen) -cne $artifact.sha256) { throw 'Frozen CLI artifact changed' }
    }
    $summary.roles += @($entry)
    Save (Join-Path $output 'observation.json') $summary
}
Write-Output $output
if ($nativeUnexpected) { throw 'Native contract expectations differ; retain diagnostic, no positive claim' }
