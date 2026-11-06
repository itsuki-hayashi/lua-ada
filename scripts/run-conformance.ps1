param(
    [ValidateSet('ReferenceC', 'Ada')][string] $Target = 'ReferenceC',
    [ValidateSet('default', 'upstream-test')][string] $Configuration = 'default',
    [ValidateSet('Smoke', 'File', 'Aggregate', 'Heavy', 'Suite')][string] $Mode = 'Smoke',
    [string] $File = '',
    [string] $Interpreter = '',
    [string] $Report = '',
    [string] $RuntimeDirectory = '',
    [string] $NativeLibraryDirectory = '',
    [string] $AcceptanceContract = '',
    [string] $Context = '',
    [switch] $BuildReference,
    [switch] $ReportOnly,
    [switch] $RequireAcceptance
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$original = Get-Location
$revision = '7579fc9d7ed90240487251dfb69168f8e64e9294'
$suffix = if ($IsWindows) { '.exe' } else { '' }
if ($Mode -eq 'Suite') { $Mode = 'Aggregate' }
if ($BuildReference -and $Target -ne 'ReferenceC') { throw 'BuildReference requires ReferenceC target' }
$runId = [Guid]::NewGuid().ToString('N')
$runRoot = Join-Path $root ('reports/conformance/' + $runId)
[void][IO.Directory]::CreateDirectory($runRoot)
if ($Report -eq '') { $Report = Join-Path $runRoot 'report.json' }
$Report = [IO.Path]::GetFullPath($Report)
$evidence = [ordered]@{
    schema_version = 1
    run_id = $runId
    repository_revision = $null
    repository_dirty = $null
    repository_status = @()
    host = [ordered]@{
        os_description = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        os_architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        process_architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        powershell_version = $PSVersionTable.PSVersion.ToString()
    }
    reference_revision = $revision
    target = $Target
    requested_configuration = $Configuration
    mode = $Mode.ToLowerInvariant()
    status = 'setup-failed'
    gate_acceptance = $false
    foundation_smoke_passed = $false
    report_only = [bool]$ReportOnly
    acceptance_requested = [bool]$RequireAcceptance
    acceptance_context = $Context
    execution_contract = $null
    coverage_validation = $null
    allocator_telemetry = $null
    acceptance_error = $null
    started_utc = [DateTime]::UtcNow.ToString('o')
    configuration_verified = $false
    reference_tree_verified = $false
    observed_configuration = $null
    configuration_process = $null
    child_configuration_process = $null
    repl_preflight_process = $null
    reference_source_records = @()
    harness_source_records = @()
    reference_library_records = @()
    runtime_library_records = @()
    build_processes = @()
    native_fixture_records = @()
    allocator_limit_bytes = if ($Mode -eq 'Heavy') { 67108864L } else { 2147483648L }
    timeout_seconds = if ($Mode -eq 'Aggregate') { 3600 } elseif ($Mode -eq 'Heavy') { 600 } else { 900 }
    fixture_records = @()
    fixture_changes = @()
    process = $null
    outcome = $null
    setup_error = $null
}

function Invoke-BuildProcess {
    param([string[]] $BuildArguments)
    # Keep compiler output and its exact argument vector alongside execution
    # evidence. In particular, a fixture link failure is a setup failure, not
    # a Lua-platform equivalent or an unexplained skipped test.
    $alire = (Get-Command alr -ErrorAction Stop).Source
    $build = Invoke-ConformanceProcess -Executable $alire -Arguments $BuildArguments `
        -Directory $root -OutputPrefix (Join-Path $runRoot ('build-' + $evidence.build_processes.Count)) `
        -TimeoutSeconds 900
    $evidence.build_processes += $build
    if ($build.exit_code -ne 0 -or $build.timed_out -or $build.capture_exceeded -or
        $build.pipe_drain_failed -or $build.process_tree_kill_error) {
        # Preserve the raw captures as artifacts, and expose a readable copy
        # of failed compiler diagnostics directly in the CI job log as well.
        Write-Output ([IO.File]::ReadAllText($build.stdout_path))
        Write-Output ([IO.File]::ReadAllText($build.stderr_path))
        throw "Conformance build failed; see $($build.stderr_path)"
    }
}

function Build-Fixtures {
    param([string] $Directory, [string] $LibraryDirectory,
          [string] $LibraryName = 'conformance_lua')
    # Match the upstream fixture filenames even on Windows: LoadLibrary can
    # load a PE DLL with an explicit .so suffix. Sources remain byte-identical.
    $include = Join-Path $root 'references/lua'
    $exports = Join-Path $root 'experiments/conformance/c/module_exports.h'
    $common = @('-std=c99', '-O2', '-I', $include, '-include', $exports)
    if ($Configuration -eq 'upstream-test') { $common += '-DLUA_USER_H=<ltests.h>' }
    if (-not $IsWindows) { $common += '-fPIC' }
    $shared = if ($IsMacOS) { '-dynamiclib' } else { '-shared' }
    $cases = @(
        @{ Name='lib1'; Source='lib1.c' },
        @{ Name='lib11'; Source='lib11.c' },
        @{ Name='lib2'; Source='lib2.c' },
        @{ Name='lib21'; Source='lib21.c' },
        @{ Name='lib2-v2'; Source='lib22.c' }
    )
    foreach ($case in $cases) {
        $args = $common + @($shared, (Join-Path $Directory ('libs/' + $case.Source)),
            '-o', (Join-Path $Directory ('libs/' + $case.Name + '.so')),
            '-L', $LibraryDirectory, ('-l' + $LibraryName))
        if ($IsWindows -and $case.Name -in @('lib1', 'lib2')) {
            $args += '-Wl,--out-implib,' + (Join-Path $Directory ('libs/' + $case.Name + '.a'))
        }
        if ($IsWindows -and $case.Name -eq 'lib11') { $args += Join-Path $Directory 'libs/lib1.a' }
        if ($IsWindows -and $case.Name -eq 'lib21') { $args += Join-Path $Directory 'libs/lib2.a' }
        if ($IsMacOS) { $args += @('-Wl,-undefined,dynamic_lookup') }
        Invoke-BuildProcess (@('exec', '--', 'gcc') + $args)
        $artifact = Join-Path $Directory ('libs/' + $case.Name + '.so')
        $source = Join-Path $Directory ('libs/' + $case.Source)
        $evidence.native_fixture_records += [ordered]@{
            source = 'libs/' + $case.Source
            source_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
            artifact = $artifact
            artifact_sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

try {
    Set-Location $root
    $evidence.repository_revision = (& git -c core.fsmonitor=false rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine first-party repository revision' }
    # HEAD identifies committed inputs only. Record staged, unstaged and
    # untracked first-party changes separately so a local experimental run
    # cannot masquerade as evidence for that committed revision. Submodule
    # contents have their own stricter immutable-reference witness below.
    $evidence.repository_status = @(& git -c core.fsmonitor=false status --porcelain=v1 `
        --untracked-files=normal --ignore-submodules=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine first-party repository worktree status' }
    $evidence.repository_dirty = $evidence.repository_status.Count -gt 0
    # A header-only check misses modified VM/parser sources and staged edits.
    # The shared witness checks the entire pinned tracked tree and rejects
    # untracked/ignored source inputs before any build or fixture execution.
    Test-ConformanceReferenceTree -Root $root
    $evidence.reference_tree_verified = $true
    $referenceRoot = Join-Path $root 'references/lua'
    foreach ($source in Get-ChildItem -LiteralPath $referenceRoot -File -Recurse |
        Where-Object { $_.Extension -in @('.c', '.h') } | Sort-Object FullName) {
        $evidence.reference_source_records += [ordered]@{
            path = [IO.Path]::GetRelativePath($referenceRoot, $source.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    foreach ($source in Get-ChildItem -LiteralPath (Join-Path $root 'experiments/conformance') -File -Recurse |
        Where-Object { $_.Extension -in @('.c', '.h', '.gpr') } | Sort-Object FullName) {
        $evidence.harness_source_records += [ordered]@{
            path = [IO.Path]::GetRelativePath($root, $source.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    foreach ($relative in @('scripts/run-conformance.ps1', 'scripts/ConformanceRunner.psm1',
        'scripts/ConformanceInventory.psm1', 'tests/conformance/suite.json')) {
        $evidence.harness_source_records += [ordered]@{
            path = $relative
            sha256 = (Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $suite = Get-Content -LiteralPath (Join-Path $root 'tests/conformance/suite.json') -Raw | ConvertFrom-Json
    if ($suite.schema_version -ne 1 -or $suite.reference_revision -cne $revision) { throw 'Invalid conformance manifest' }
    if ($RequireAcceptance) {
        # Observation mode remains useful during implementation. Final mode is
        # deliberately opt-in and cannot be softened by ReportOnly or an absent
        # per-operation review contract.
        if ($ReportOnly) { throw 'RequireAcceptance cannot be combined with ReportOnly' }
        $hostName = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        if ($Context -notin $suite.acceptance_contexts -or
            -not $Context.StartsWith("$Configuration/$hostName/")) {
            throw 'Acceptance context does not identify this configuration and host'
        }
        if ($AcceptanceContract -eq '' -or -not (Test-Path -LiteralPath $AcceptanceContract -PathType Leaf)) {
            throw 'RequireAcceptance needs an independently reviewed execution contract'
        }
        $evidence.execution_contract = [ordered]@{
            path = [IO.Path]::GetFullPath($AcceptanceContract)
            sha256 = (Get-FileHash -LiteralPath $AcceptanceContract -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    if ($Mode -eq 'File') {
        if ($File -notin @($suite.files.path)) { throw 'File must name one of the pinned 34 Lua sources' }
        if ($File -in @('all.lua', 'heavy.lua')) { throw 'Use Aggregate or Heavy for this file' }
    }
    elseif ($File -ne '') { throw 'File is only valid in File mode' }
    if ($BuildReference) {
        Invoke-BuildProcess @('exec', '--', 'gprbuild', '-P', 'experiments/conformance/oracle.gpr',
            "-XLUA_CONFORMANCE_CONFIGURATION=$Configuration")
    }
    $libraryDirectory = Join-Path $root "build/conformance/$Configuration/lib"
    if ($Interpreter -eq '') {
        if ($Target -ne 'ReferenceC') { throw 'Ada observation requires an explicit Interpreter' }
        $Interpreter = Join-Path $root "build/conformance/$Configuration/bin/lua$suffix"
    }
    $Interpreter = (Resolve-Path -LiteralPath $Interpreter).Path
    $fixtureDirectory = Join-Path $runRoot 'fixtures'
    $evidence.fixture_records = Copy-ConformanceFixtures -Source (Join-Path $root 'references/lua/testes') -Destination $fixtureDirectory
    foreach ($item in $suite.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $fixtureDirectory $item.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.sha256) {
            throw "Manifest source hash mismatch: $($item.path)"
        }
    }
    $environment = @{
        LUA_ADA_CONFORMANCE_ALLOCATOR = [string]$evidence.allocator_limit_bytes
        MEMLIMIT = [string]$evidence.allocator_limit_bytes
    }
    if ($Target -eq 'ReferenceC') {
        if (-not (Test-Path -LiteralPath $libraryDirectory)) { throw 'Build the conformance C library first' }
        foreach ($library in Get-ChildItem -LiteralPath $libraryDirectory -File | Sort-Object Name) {
            $evidence.reference_library_records += [ordered]@{
                path = $library.FullName
                sha256 = (Get-FileHash -LiteralPath $library.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        # Some unchanged tests launch bare 'lua' through io.popen. Select this
        # profile's executable before any ambient installation, and retain its
        # shared-library directory for Windows loader resolution as well.
        $interpreterDirectory = Split-Path -Parent $Interpreter
        $environment.PATH = $interpreterDirectory + [IO.Path]::PathSeparator +
            $libraryDirectory + [IO.Path]::PathSeparator + $env:PATH
        $environment.LD_LIBRARY_PATH = $libraryDirectory + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $environment.DYLD_LIBRARY_PATH = $libraryDirectory + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
        $probe = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('--conformance-config') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'configuration') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.configuration_process = $probe
        if ($probe.exit_code -ne 0 -or $probe.timed_out -or $probe.stderr_bytes -ne 0) { throw 'Configuration probe failed' }
        $observed = [IO.File]::ReadAllText($probe.stdout_path) | ConvertFrom-Json -AsHashtable
        [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration `
            -Target $Target -AllocatorLimitBytes $evidence.allocator_limit_bytes)
        $evidence.observed_configuration = $observed
        $evidence.configuration_verified = $true
        # Exercise shell PATH lookup from inside C Lua itself. Merely checking
        # the parent process would miss a missing or wrong-profile bare 'lua'
        # in files.lua's subprocesses. Identical probe records also verify the
        # allocator ceiling inherited by that independently initialized child.
        $childCode = 'local p=assert(io.popen("lua --conformance-config", "r")); ' +
            'local s=p:read("a"); assert(p:close()); io.write(s)'
        $child = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-e', $childCode) `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'child-configuration') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.child_configuration_process = $child
        if ($child.exit_code -ne 0 -or $child.timed_out -or $child.stderr_bytes -ne 0 -or
            $child.capture_exceeded -or $child.pipe_drain_failed -or $child.process_tree_kill_error -or
            [IO.File]::ReadAllText($child.stdout_path).Trim() -cne
                [IO.File]::ReadAllText($probe.stdout_path).Trim()) {
            throw "Bare lua child configuration differs from selected C profile; see $($child.stderr_path)"
        }
        # Lua 5.5.1's CLI tests expect its default readline facility to work.
        # A missing host library must fail setup, rather than masquerade as a
        # native-platform difference when main.lua enables warnings with -E.
        # Closed stdin makes this a bounded REPL initialization/cleanup probe.
        $repl = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-E', '-W', '-i') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'repl-preflight') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.repl_preflight_process = $repl
        if ($repl.exit_code -ne 0 -or $repl.timed_out -or $repl.stderr_bytes -ne 0 -or
            $repl.capture_exceeded -or $repl.pipe_drain_failed -or $repl.process_tree_kill_error) {
            throw "Default C REPL prerequisite failed; see $($repl.stderr_path)"
        }
        Build-Fixtures -Directory $fixtureDirectory -LibraryDirectory $libraryDirectory
    }
    else {
        # The Ada conformance launcher is a test-only executable over the real
        # library/CLI. Both profiles use the same measured handshake as C;
        # removing the former blanket rejection does not pretend the adapter
        # exists before that launcher actually reports and exercises it.
        $directories = @((Split-Path -Parent $Interpreter))
        if ($RuntimeDirectory -ne '') {
            $directories += (Resolve-Path -LiteralPath $RuntimeDirectory).Path
        }
        if ($NativeLibraryDirectory -ne '') {
            $directories += (Resolve-Path -LiteralPath $NativeLibraryDirectory).Path
        }
        $prefix = ($directories | Select-Object -Unique) -join [IO.Path]::PathSeparator
        $environment.PATH = $prefix + [IO.Path]::PathSeparator + $env:PATH
        $environment.LD_LIBRARY_PATH = $prefix + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $environment.DYLD_LIBRARY_PATH = $prefix + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
        foreach ($directory in ($directories | Select-Object -Unique)) {
            foreach ($library in Get-ChildItem -LiteralPath $directory -File |
                Where-Object { $_.Extension -in @('.dll','.so','.dylib','.a') } | Sort-Object Name) {
                $evidence.runtime_library_records += [ordered]@{
                    path=$library.FullName
                    sha256=(Get-FileHash -LiteralPath $library.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        }
        $probe = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('--conformance-config') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'configuration') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.configuration_process = $probe
        if ($probe.exit_code -ne 0 -or $probe.timed_out -or $probe.stderr_bytes -ne 0 -or
            $probe.capture_exceeded -or $probe.pipe_drain_failed -or $probe.process_tree_kill_error) {
            throw 'Ada conformance configuration provider is unavailable or failed'
        }
        $observed = [IO.File]::ReadAllText($probe.stdout_path) | ConvertFrom-Json -AsHashtable
        [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration `
            -Target Ada -AllocatorLimitBytes $evidence.allocator_limit_bytes)
        $evidence.observed_configuration = $observed
        $evidence.configuration_verified = $true
        $childCode = 'local p=assert(io.popen("lua --conformance-config", "r")); ' +
            'local s=p:read("a"); assert(p:close()); io.write(s)'
        $child = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-e', $childCode) `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'child-configuration') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.child_configuration_process = $child
        if ($child.exit_code -ne 0 -or $child.timed_out -or $child.stderr_bytes -ne 0 -or
            $child.capture_exceeded -or $child.pipe_drain_failed -or $child.process_tree_kill_error -or
            [IO.File]::ReadAllText($child.stdout_path).Trim() -cne
                [IO.File]::ReadAllText($probe.stdout_path).Trim()) {
            throw 'Bare lua child does not retain the selected Ada configuration/allocator ceiling'
        }
        $repl = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-E', '-W', '-i') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'repl-preflight') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.repl_preflight_process = $repl
        if ($repl.exit_code -ne 0 -or $repl.timed_out -or $repl.stderr_bytes -ne 0 -or
            $repl.capture_exceeded -or $repl.pipe_drain_failed -or $repl.process_tree_kill_error) {
            throw 'Default Ada REPL prerequisite failed'
        }
        if ($NativeLibraryDirectory -ne '') {
            Build-Fixtures -Directory $fixtureDirectory `
                -LibraryDirectory (Resolve-Path -LiteralPath $NativeLibraryDirectory).Path -LibraryName lua
        }
        elseif ($RequireAcceptance) {
            throw 'Ada acceptance needs NativeLibraryDirectory for actual upstream C fixture modules'
        }
    }
    $marker = ''
    $arguments = @()
    if ($Mode -eq 'Smoke') {
        $marker = 'M3 conformance smoke OK'
        $code = "assert(_VERSION=='Lua 5.5'); "
        if ($Target -eq 'ReferenceC' -or $RequireAcceptance) {
            $code += if ($Configuration -eq 'default') { "assert(rawget(_G,'T')==nil); " }
                     else { "assert(type(T)=='table'); T.checkmemory(); " }
            $code += "assert(type(debug.getinfo)=='function' and type(string.dump)=='function'); " +
                "local f=assert(package.loadlib('libs/lib1.so','luaopen_lib1_sub')); " +
                "local m=f('lib1.sub','fixture'); assert(m.id(7)==7); "
        }
        $code += "print('$marker')"
        $arguments = @('-e', $code)
    }
    elseif ($Mode -eq 'Aggregate') { $arguments = @('all.lua'); $marker = 'final OK !!!' }
    elseif ($Mode -eq 'Heavy') { $arguments = @('heavy.lua'); $marker = 'OK' }
    else {
        $arguments = @($File)
        if ($File -eq 'utf8.lua') { $marker = 'ok' }
        elseif ($File -in @('tpack.lua', 'bitwise.lua')) { $marker = 'OK' }
    }
    if ($RequireAcceptance) {
        $environment.LUA_ADA_CONFORMANCE_RUN_ID = $runId
        $environment.LUA_ADA_CONFORMANCE_TELEMETRY = Join-Path $runRoot 'allocator'
    }
    $evidence.process = Invoke-ConformanceProcess -Executable $Interpreter -Arguments $arguments `
        -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'execution') `
        -TimeoutSeconds $evidence.timeout_seconds -Environment $environment
    $evidence.outcome = Get-ConformanceOutcome -Process $evidence.process -Marker $marker
    $evidence.fixture_changes = Test-ConformanceFixtureHashes -Directory $fixtureDirectory -Records $evidence.fixture_records
    $evidence.status = if ($evidence.fixture_changes.Count -gt 0) { 'fixture-source-changed' } else { $evidence.outcome.status }
    $evidence.foundation_smoke_passed = $Target -eq 'ReferenceC' -and $Mode -eq 'Smoke' -and
        $evidence.status -eq 'passed' -and $evidence.configuration_verified -and
        $evidence.process.stderr_bytes -eq 0
    if ($Mode -eq 'Smoke' -and $evidence.status -eq 'passed' -and $evidence.process.stderr_bytes -ne 0) {
        $evidence.status = 'unexpected-smoke-stderr'
    }
    if ($RequireAcceptance) {
        try {
            if ($evidence.repository_dirty -or -not $evidence.configuration_verified -or
                $evidence.fixture_changes.Count -gt 0) {
                throw 'Acceptance requires committed, configuration-verified, unchanged inputs'
            }
            $contract = Get-Content -LiteralPath $AcceptanceContract -Raw | ConvertFrom-Json -AsHashtable
            $telemetryPath = $environment.LUA_ADA_CONFORMANCE_TELEMETRY +
                '.' + $evidence.process.process_id + '.json'
            if (-not (Test-Path -LiteralPath $telemetryPath -PathType Leaf)) {
                throw 'Managed-allocation telemetry is missing for the executed process'
            }
            $telemetry = Get-Content -LiteralPath $telemetryPath -Raw | ConvertFrom-Json -AsHashtable
            $evidence.allocator_telemetry = [ordered]@{
                path=$telemetryPath
                sha256=(Get-FileHash -LiteralPath $telemetryPath -Algorithm SHA256).Hash.ToLowerInvariant()
                data=$telemetry
            }
            $evidence.coverage_validation = Test-ConformanceInventory -Root $root -RequireComplete
            $coverageRecords = @{}
            foreach ($source in $suite.files) {
                $coveragePath = Join-Path $root ('tests/conformance/' + $source.coverage_file)
                foreach ($record in (Read-ConformanceJsonLines -Path $coveragePath)) {
                    $coverageRecords[$record.id] = $record
                }
            }
            $operation = if ($Mode -eq 'File') { 'file:' + $File } else { $Mode.ToLowerInvariant() }
            $accepted = Test-ConformanceAcceptance -Process $evidence.process -Outcome $evidence.outcome `
                -Contract $contract -Operation $operation -Context $Context `
                -SourceRecords $evidence.fixture_records -RunId $runId -Configuration $Configuration `
                -AllocatorLimitBytes $evidence.allocator_limit_bytes `
                -CoverageComplete $evidence.coverage_validation.Complete `
                -CoverageRecords $coverageRecords -Telemetry $telemetry
            $evidence.gate_acceptance = $accepted.gate_acceptance
        }
        catch {
            $evidence.acceptance_error = $_.Exception.Message
            $evidence.status = 'acceptance-blocked'
        }
    }
}
catch { $evidence.setup_error = $_.Exception.Message }
finally {
    Set-Location $original
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Report))
    [IO.File]::WriteAllText($Report, (ConvertTo-Json -InputObject $evidence -Depth 12) + "`n",
        [Text.UTF8Encoding]::new($false))
}
Write-Output "CONFORMANCE OBSERVATION: $($evidence.status); report=$Report; M3 acceptance=$($evidence.gate_acceptance.ToString().ToLowerInvariant())"
if ($evidence.setup_error) { Write-Output "SETUP FAILURE: $($evidence.setup_error)" }
if ($evidence.acceptance_error) { Write-Output "ACCEPTANCE BLOCKED: $($evidence.acceptance_error)" }
if ($RequireAcceptance) {
    if ($evidence.gate_acceptance) { exit 0 }
    exit 1
}
if ($ReportOnly) {
    if ($evidence.setup_error -or $null -eq $evidence.process) {
        Write-Output 'REPORT ONLY does not suppress harness setup failures'
        exit 1
    }
    if ($evidence.status -in @('timed-out', 'output-limit', 'capture-failed',
        'abnormal-exit', 'fixture-source-changed', 'resource-exhausted')) {
        Write-Output 'REPORT ONLY does not suppress resource, crash, timeout, capture, or fixture-integrity failures'
        exit 1
    }
    Write-Output 'REPORT ONLY: collection succeeded; execution/coverage may have failed'
    exit 0
}
if ($evidence.status -eq 'passed') { exit 0 }
exit 1
