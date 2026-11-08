param([Parameter(Mandatory)][string] $OracleRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Native Windows counterpart only' }
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$oracle = (Resolve-Path -LiteralPath $OracleRoot).Path
$report = Join-Path $root ('reports/windows-main-transport/' +
    [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($report)
$utf8 = [Text.UTF8Encoding]::new($false)

function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Save([string] $Path, $Value) {
    $json = (ConvertTo-Json -InputObject $Value -Depth 70).Replace("`r", '')
    [IO.File]::WriteAllText($Path, $json + "`n", $utf8)
}

$fixture = 'tests/conformance/platform/windows-main-cli-transport.lua'
$marks = @('fresh-private-paths', 'actual-version-redirection',
    'empty-explicit-stdin', 'multiline-explicit-stdin', 'native-type-pipe',
    'literal-path-counterpart', 'exact-argv-selected-child',
    'native-set-environment', 'actual-require-literal-name',
    'stdout-stderr-routing', 'actual-child-failure-status',
    'actual-popen-child-identity', 'owned-temp-cleanup')
$expectedOutput = ($marks | ForEach-Object {
    'PASS: windows-main-transport-' + $_ + "`r`n"
}) -join ''
$summary = [ordered]@{
    schema_version = 1
    kind = 'windows-main-transport-native-author-observation'
    author = 'Codex /root/runtime_gaps'
    date = '2026-11-08'
    base_revision = (& git -C $root rev-parse HEAD)
    runtime_acceptance = $false
    coverage_authority = $false
    source_adaptation_authority = $false
    native_applicability_review = 'pending'
    independent_source_review = 'pending'
    transformed_main_emitted = $false
    original_main_executed = $false
    mode_flags = @()
    source_bindings = @()
    counterpart_cases = $marks
    roles = @()
}
foreach ($path in @($fixture, 'scripts/observe-windows-main-transport.ps1',
    'scripts/ConformanceRunner.psm1', 'references/lua/testes/main.lua',
    'references/lua/lua.c', 'references/lua/loslib.c',
    'references/lua/liolib.c', 'references/lua/loadlib.c')) {
    $summary.source_bindings += @(@{path = $path
        sha256 = (Hash (Join-Path $root $path))})
}

$failed = $false
foreach ($mode in @('default', 'upstream-test')) {
    $dir = Join-Path $report $mode
    $runtime = Join-Path $dir 'runtime image'
    $cwd = Join-Path $dir 'disposable cwd'
    [void][IO.Directory]::CreateDirectory($runtime)
    [void][IO.Directory]::CreateDirectory($cwd)

    # Copy each actual oracle image. A space-bearing executable path is part
    # of the input, rather than an untested shell-quoting assumption.
    $artifacts = @()
    foreach ($image in @(
        @{source = "build/conformance/$mode/bin/lua.exe"; name = 'lua.exe'},
        @{source = "build/conformance/$mode/lib/libconformance_lua.dll"
            name = 'libconformance_lua.dll'})) {
        $selected = Join-Path $oracle $image.source
        $copy = Join-Path $runtime $image.name
        $before = Hash $selected
        [IO.File]::Copy($selected, $copy, $false)
        if ((Hash $selected) -cne $before -or (Hash $copy) -cne $before) {
            throw 'Native image changed while being frozen'
        }
        $artifacts += @(@{selected = $selected; frozen = $copy
            sha256 = $before})
    }
    $exe = Join-Path $runtime 'lua.exe'
    $frozenFixture = Join-Path $cwd 'transport.lua'
    [IO.File]::Copy((Join-Path $root $fixture), $frozenFixture, $false)
    $prefix = Join-Path $dir 'transport'
    $run = [guid]::NewGuid().ToString('N')
    $envValues = @{
        LUA_ADA_CONFORMANCE_ALLOCATOR = '2147483648'
        MEMLIMIT = '2147483648'
        LUA_ADA_CONFORMANCE_RUN_ID = $run
        LUA_ADA_CONFORMANCE_TELEMETRY = $prefix + '-allocator'
        PATH = $runtime + [IO.Path]::PathSeparator + $env:PATH
    }
    $process = Invoke-ConformanceProcess -Executable $exe `
        -Arguments @('transport.lua', $exe, $mode) -Directory $cwd `
        -OutputPrefix $prefix -TimeoutSeconds 30 -CaptureLimitBytes 1048576 `
        -Environment $envValues

    # Every ordinary Lua child inherits the run/configuration/limit. The
    # --conformance-config child creates no Lua state, hence no sidecar.
    $sidecars = @()
    $pids = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $dir `
        -Filter 'transport-allocator.*.json')) {
        $data = Get-Content -LiteralPath $file.FullName -Raw |
            ConvertFrom-Json -AsHashtable
        if ($data.run_id -cne $run -or $data.configuration -cne $mode -or
            $data.allocator_limit_bytes -ne 2147483648 -or
            $data.outstanding_bytes -ne 0 -or $data.outstanding_blocks -ne 0 -or
            $data.managed_refusals -ne 0 -or $pids.ContainsKey([long]$data.process_id)) {
            throw 'Native parent/child allocator sidecar mismatch'
        }
        $pids[[long]$data.process_id] = $true
        $sidecars += @(@{path = $file.FullName
            sha256 = (Hash $file.FullName); data = $data})
    }
    foreach ($image in $artifacts) {
        if ((Hash $image.frozen) -cne $image.sha256) {
            throw 'Frozen native image changed during execution'
        }
    }
    $remaining = @(Get-ChildItem -LiteralPath $cwd -File |
        ForEach-Object { $_.Name })
    $ok = $process.exit_code -eq 0 -and $process.stderr_bytes -eq 0 -and
        -not $process.timed_out -and -not $process.capture_exceeded -and
        -not $process.pipe_drain_failed -and -not $process.output_drain_failed -and
        -not $process.input_write_failed -and -not $process.process_tree_kill_error -and
        $null -eq $process.abnormal_exit_kind -and $sidecars.Count -eq 10 -and
        $pids.ContainsKey([long]$process.process_id) -and
        $remaining.Count -eq 1 -and $remaining[0] -ceq 'transport.lua' -and
        [IO.File]::ReadAllText($process.stdout_path) -ceq $expectedOutput
    $entry = @{
        configuration = $mode
        artifacts = $artifacts
        process = $process
        environment = $envValues
        fixture_sha256 = (Hash $frozenFixture)
        sidecars = $sidecars
        counterpart_completed = $ok
        final_cwd_files = $remaining
        native_config_child = 'Actual io.popen --conformance-config checked internally; no Lua-state sidecar is fabricated.'
    }
    $summary.roles += @($entry)
    if (-not $ok) { $failed = $true }
    Save ($prefix + '-process.json') $entry
    "Native $mode counterpart exit=$($process.exit_code) completed=$ok measured_Lua_processes=$($sidecars.Count)"
    Get-Content $process.stdout_path -Tail 5
    Get-Content $process.stderr_path -Tail 5
}
Save (Join-Path $report 'observation.json') $summary
$report
if ($failed) {
    throw 'Native transport needs correction/review; no source authority'
}
