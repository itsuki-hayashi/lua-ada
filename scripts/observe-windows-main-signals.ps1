param(
    [Parameter(Mandatory)][string] $OracleRoot,
    [Parameter(Mandatory)][string] $Compiler
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Native Windows console evidence only' }
$root = Split-Path -Parent $PSScriptRoot
$oracle = (Resolve-Path -LiteralPath $OracleRoot).Path
$gcc = (Resolve-Path -LiteralPath $Compiler).Path
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$dir = Join-Path $root ('reports/windows-main-signals/' +
    [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
$utf8 = [Text.UTF8Encoding]::new($false)

function Hash([string] $Path) {
    (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Save([string] $Path, $Value) {
    $text = (ConvertTo-Json -InputObject $Value -Depth 100).Replace("`r", '')
    [IO.File]::WriteAllText($Path, $text + "`n", $utf8)
}
function Freeze([string] $Selected, [string] $Frozen) {
    $before = Hash $Selected
    [IO.File]::Copy($Selected, $Frozen, $false)
    if ((Hash $Selected) -cne $before -or (Hash $Frozen) -cne $before) {
        throw 'Selected artifact changed during freeze'
    }
    @{selected = $Selected; frozen = $Frozen; sha256 = $before}
}
function Normal-Process($Process) {
    $Process.exit_code -eq 0 -and $Process.stderr_bytes -eq 0 -and
        -not $Process.timed_out -and -not $Process.capture_exceeded -and
        -not $Process.pipe_drain_failed -and -not $Process.output_drain_failed -and
        -not $Process.input_write_failed -and -not $Process.process_tree_kill_error -and
        $null -eq $Process.abnormal_exit_kind
}
function Read-PeSubsystem([string] $Path) {
    # Read fixed headers, not an input-sized executable copy. The optional
    # header's subsystem field has the same offset in PE32 and PE32+.
    $stream = [IO.File]::OpenRead($Path)
    try {
        $dos = [byte[]]::new(64)
        if ($stream.Read($dos, 0, 64) -ne 64 -or $dos[0] -ne 77 -or $dos[1] -ne 90) {
            throw 'Selected native executable lacks a DOS header'
        }
        $offset = [BitConverter]::ToUInt32($dos, 60)
        if ($offset -lt 64 -or $offset -gt $stream.Length - 96) {
            throw 'Selected native executable has an invalid PE offset'
        }
        $stream.Position = $offset
        $pe = [byte[]]::new(96)
        if ($stream.Read($pe, 0, 96) -ne 96 -or
            [BitConverter]::ToUInt32($pe, 0) -ne 17744 -or
            [BitConverter]::ToUInt16($pe, 20) -lt 70) {
            throw 'Selected native executable lacks the expected PE header'
        }
        $magic = [BitConverter]::ToUInt16($pe, 24)
        if ($magic -ne 267 -and $magic -ne 523) { throw 'Unknown PE optional header' }
        @{machine = [BitConverter]::ToUInt16($pe, 4)
            optional_header_magic = $magic
            subsystem = [BitConverter]::ToUInt16($pe, 92)}
    } finally { $stream.Dispose() }
}

$source = 'experiments/conformance/c/windows_signal_broker.c'
$fixtures = @{
    protected = 'tests/conformance/platform/windows-main-sigint-protected.lua'
    search = 'tests/conformance/platform/windows-main-sigint-search.lua'
}
$summary = [ordered]@{
    schema_version = 1
    kind = 'windows-main-real-sigint-native-author-observation'
    author = 'Codex /root/runtime_gaps'
    date = '2026-11-08'
    base_revision = (& git -C $root rev-parse HEAD)
    source_approval = $false
    adaptation_approval = $false
    native_applicability_approval = $false
    runtime_acceptance = $false
    coverage_authority = $false
    transformed_source_emitted = $false
    original_main_executed = $false
    production_signal_implementation = $false
    source_mappings = @()
    source_exclusions = @()
    mode_flags = @()
    review = 'pending-independent-review'
    source_bindings = @()
    original_payloads = @()
    build = $null
    roles = @()
    completed = $false
}
foreach ($path in @($source, $fixtures.protected, $fixtures.search,
    'scripts/observe-windows-main-signals.ps1', 'scripts/ConformanceRunner.psm1',
    'references/lua/testes/main.lua', 'references/lua/lua.c')) {
    $summary.source_bindings += @(@{path = $path
        sha256 = (Hash (Join-Path $root $path))})
}
$main = [IO.File]::ReadAllText((Join-Path $root 'references/lua/testes/main.lua'))
foreach ($kind in @('protected', 'search')) {
    $payload = [IO.File]::ReadAllText((Join-Path $root $fixtures[$kind])).TrimEnd("`n")
    $offset = $main.IndexOf($payload, [StringComparison]::Ordinal)
    if ($offset -lt 0 -or $main.IndexOf($payload, $offset + 1,
        [StringComparison]::Ordinal) -ge 0) { throw 'Not the unique original workload' }
    $summary.original_payloads += @(@{kind = $kind; text = $payload
        original_byte_offset = $utf8.GetByteCount($main.Substring(0, $offset))
        original_byte_length = $utf8.GetByteCount($payload)})
}

# The compiler runs directly. This does not select an Alire toolchain, modify
# generated configuration, or link either reference or production Lua code.
$broker = Join-Path $dir 'windows_signal_broker.exe'
$sourceSnapshot = Join-Path $dir 'broker-source.c'
[IO.File]::Copy((Join-Path $root $source), $sourceSnapshot, $false)
$compileArguments = @('-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
    '-municode', '-o', $broker, $sourceSnapshot)
$compile = Invoke-ConformanceProcess -Executable $gcc -Arguments $compileArguments `
    -Directory $root -OutputPrefix (Join-Path $dir compile) `
    -TimeoutSeconds 30 -CaptureLimitBytes 1048576
$summary.build = @{compiler = $gcc; compiler_sha256 = (Hash $gcc)
    source_sha256 = (Hash (Join-Path $root $source)); process = $compile
    source_snapshot = $sourceSnapshot; arguments = $compileArguments}
if ((Hash $sourceSnapshot) -cne $summary.build.source_sha256) {
    throw 'Broker source changed while being frozen'
}
if (-not (Normal-Process $compile)) {
    Save (Join-Path $dir observation.json) $summary
    throw "Standalone broker compilation failed: $dir"
}
$summary.build.broker_sha256 = Hash $broker
$failed = $false

:configurations foreach ($mode in @('default', 'upstream-test')) {
    $modeDir = Join-Path $dir $mode
    $runtime = Join-Path $modeDir 'runtime image'
    $cwd = Join-Path $modeDir 'disposable cwd'
    [void][IO.Directory]::CreateDirectory($runtime)
    [void][IO.Directory]::CreateDirectory($cwd)
    $images = @(
        (Freeze (Join-Path $oracle "build/conformance/$mode/bin/lua.exe") `
            (Join-Path $runtime 'lua.exe')),
        (Freeze (Join-Path $oracle "build/conformance/$mode/lib/libconformance_lua.dll") `
            (Join-Path $runtime 'libconformance_lua.dll'))
    )
    $exe = Join-Path $runtime 'lua.exe'
    $images[0].pe_header = Read-PeSubsystem $exe
    if ($images[0].pe_header.subsystem -ne 3) {
        $summary.pe_input_failure = $images[0]
        Save (Join-Path $dir observation.json) $summary
        throw 'Actual selected native executable is not Windows CUI'
    }
    $config = Invoke-ConformanceProcess -Executable $exe `
        -Arguments @('--conformance-config') -Directory $cwd `
        -OutputPrefix (Join-Path $modeDir config) -TimeoutSeconds 5 `
        -CaptureLimitBytes 1048576 `
        -Environment @{LUA_ADA_CONFORMANCE_ALLOCATOR = '2147483648'}
    $identity = Get-Content -LiteralPath $config.stdout_path -Raw |
        ConvertFrom-Json -AsHashtable
    if (-not (Normal-Process $config) -or $identity.configuration -cne $mode -or
        $identity.allocator_limit_bytes -ne 2147483648) {
        throw 'Native configuration probe failed before signal tests'
    }
    foreach ($kind in @('protected', 'search')) {
        $prefix = Join-Path $modeDir $kind
        $run = [guid]::NewGuid().ToString('N')
        $envValues = @{
            LUA_ADA_CONFORMANCE_ALLOCATOR = '2147483648'
            MEMLIMIT = '2147483648'
            LUA_ADA_CONFORMANCE_RUN_ID = $run
            LUA_ADA_CONFORMANCE_TELEMETRY = $prefix + '-allocator'
            PATH = $runtime + [IO.Path]::PathSeparator + $env:PATH
        }
        $fixture = Join-Path $cwd ($kind + '.lua')
        [IO.File]::Copy((Join-Path $root $fixtures[$kind]), $fixture, $false)
        $childOut = $prefix + '-child.stdout'
        $childErr = $prefix + '-child.stderr'
        $eventPath = $prefix + '-events.jsonl'
        $arguments = @($exe, $fixture, $cwd, $childOut, $childErr, $eventPath, $kind)
        $process = Invoke-ConformanceProcess -Executable $broker `
            -Arguments $arguments -Directory $cwd -OutputPrefix $prefix `
            -TimeoutSeconds 30 -CaptureLimitBytes 1048576 -Environment $envValues
        $events = @(Get-Content -LiteralPath $eventPath | ForEach-Object {
            ConvertFrom-Json -InputObject $_ -AsHashtable
        })
        $created = @($events | Where-Object event -CEQ 'create-child-new-console-hidden')
        $requests = @($events | Where-Object event -CEQ 'request-real-ctrl-c-group-zero')
        $exitEvents = @($events | Where-Object event -CEQ 'child-exited')
        $final = @($events | Where-Object event -CEQ 'final-result')
        $forced = @($events | Where-Object event -CEQ 'failed-probe-timeout-cleanup-only')
        $normal = Normal-Process $process
        $ok = $normal -and $created.Count -eq 1 -and $created[0].ok -and
            $exitEvents.Count -eq 1 -and $final.Count -eq 1 -and $final[0].ok -and
            $forced.Count -eq 0 -and @($requests | Where-Object ok -EQ $false).Count -eq 0
        $sidecars = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $modeDir `
            -Filter ($kind + '-allocator.*.json'))) {
            $data = Get-Content -LiteralPath $file.FullName -Raw |
                ConvertFrom-Json -AsHashtable
            if ($data.run_id -cne $run -or $data.configuration -cne $mode -or
                $data.process_id -ne $created[0].child_pid -or
                $data.allocator_limit_bytes -ne 2147483648 -or
                $data.outstanding_bytes -ne 0 -or $data.outstanding_blocks -ne 0) {
                $ok = $false
            }
            $sidecars += @(@{path = $file.FullName
                sha256 = (Hash $file.FullName); data = $data})
        }
        if ($kind -ceq 'protected') {
            $ok = $ok -and $requests.Count -eq 1 -and $exitEvents[0].value -eq 0 -and
                [IO.File]::ReadAllText($childOut) -ceq "12`r`n42`r`n" -and
                (Get-Item -LiteralPath $childErr).Length -eq 0 -and $sidecars.Count -eq 1
        } else {
            $ok = $ok -and $requests.Count -ge 2 -and $exitEvents[0].value -ne 0 -and
                [IO.File]::ReadAllText($childOut) -ceq "15`r`n" -and
                (Get-Item -LiteralPath $childErr).Length -eq 0
        }
        foreach ($image in $images) {
            if ((Hash $image.frozen) -cne $image.sha256) { $ok = $false }
        }
        $role = @{configuration = $mode; kind = $kind; process = $process
            artifacts = $images; config_process = $config; config = $identity
            environment = $envValues; events_path = $eventPath
            events_sha256 = (Hash $eventPath); events = $events
            child_stdout = @{path = $childOut; sha256 = (Hash $childOut)}
            child_stderr = @{path = $childErr; sha256 = (Hash $childErr)}
            fixture = @{path = $fixture; sha256 = (Hash $fixture)}
            sidecars = $sidecars; completed = $ok
            forced_cleanup = $forced.Count -ne 0
            telemetry_limit = 'Abrupt default-signal death may bypass normal-return Lua telemetry; absent sidecars are not invented or called balanced shutdown.'}
        $summary.roles += @($role)
        Save ($prefix + '-result.json') $role
        "Native $mode $kind broker_exit=$($process.exit_code) requests=$($requests.Count) completed=$ok"
        if (-not $ok) {
            $failed = $true
            break configurations
        }
    }
}
$summary.completed = -not $failed -and $summary.roles.Count -eq 4
Save (Join-Path $dir observation.json) $summary
$dir
if (-not $summary.completed) {
    throw 'Bounded native console probe failed; inspect raw evidence before alternatives'
}
