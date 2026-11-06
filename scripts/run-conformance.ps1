param(
    [ValidateSet('ReferenceC', 'Ada')][string] $Target = 'ReferenceC',
    [ValidateSet('default', 'upstream-test')][string] $Configuration = 'default',
    [ValidateSet('Smoke', 'File', 'Aggregate', 'Heavy', 'Suite')][string] $Mode = 'Smoke',
    [string] $File = '',
    [string] $Interpreter = '',
    [string] $Report = '',
    [string] $RuntimeDirectory = '',
    [switch] $BuildReference,
    [switch] $ReportOnly
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
if ($Target -eq 'Ada' -and $Configuration -eq 'upstream-test') {
    throw 'Instrumented Ada configuration is not implemented/verified in M3-01'
}
if ($BuildReference -and $Target -ne 'ReferenceC') { throw 'BuildReference requires ReferenceC target' }
$runRoot = Join-Path $root ('reports/conformance/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runRoot)
if ($Report -eq '') { $Report = Join-Path $runRoot 'report.json' }
$Report = [IO.Path]::GetFullPath($Report)
$evidence = [ordered]@{
    schema_version = 1
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
    started_utc = [DateTime]::UtcNow.ToString('o')
    configuration_verified = $false
    reference_tree_verified = $false
    observed_configuration = $null
    configuration_process = $null
    reference_source_records = @()
    harness_source_records = @()
    reference_library_records = @()
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
    param([string] $Directory, [string] $LibraryDirectory)
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
            '-L', $LibraryDirectory, '-lconformance_lua')
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
        $environment.PATH = $libraryDirectory + [IO.Path]::PathSeparator + $env:PATH
        $environment.LD_LIBRARY_PATH = $libraryDirectory + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $environment.DYLD_LIBRARY_PATH = $libraryDirectory + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
        $probe = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('--conformance-config') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'configuration') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.configuration_process = $probe
        if ($probe.exit_code -ne 0 -or $probe.timed_out -or $probe.stderr_bytes -ne 0) { throw 'Configuration probe failed' }
        $observed = [IO.File]::ReadAllText($probe.stdout_path) | ConvertFrom-Json
        if ($observed.schema_version -ne 1 -or $observed.configuration -cne $Configuration -or
            $observed.lua_release -cne 'Lua 5.5.1' -or
            $observed.integer_bytes -ne 8 -or $observed.number_bytes -ne 8 -or
            $observed.pointer_bytes -ne [IntPtr]::Size -or
            $observed.extra_space_bytes -ne $observed.expected_extra_space_bytes -or
            $observed.allocator_limit_bytes -ne $evidence.allocator_limit_bytes -or
            ($Configuration -eq 'default' -and ($observed.compat_global -ne 1 -or
                $observed.max_stack -ne 1000000 -or $observed.max_c_calls -ne 200 -or
                $observed.extra_space_bytes -ne $observed.pointer_bytes -or
                $observed.aux_buffer_bytes -ne 16 * $observed.pointer_bytes * $observed.number_bytes -or
                $observed.rand32 -or $observed.compat_math)) -or
            ($Configuration -eq 'upstream-test' -and ($observed.compat_global -ne 0 -or
                $observed.max_stack -ne 68000 -or $observed.max_c_calls -ne 180 -or
                $observed.aux_buffer_bytes -ne 23 -or -not $observed.rand32 -or -not $observed.compat_math))) {
            throw 'Observed C configuration does not match requested baseline'
        }
        $evidence.observed_configuration = $observed
        $evidence.configuration_verified = $true
        Build-Fixtures -Directory $fixtureDirectory -LibraryDirectory $libraryDirectory
    }
    elseif ($RuntimeDirectory -ne '') {
        $runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
        $environment.PATH = $runtime + [IO.Path]::PathSeparator + $env:PATH
        $environment.LD_LIBRARY_PATH = $runtime + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $environment.DYLD_LIBRARY_PATH = $runtime + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
    }
    $marker = ''
    $arguments = @()
    if ($Mode -eq 'Smoke') {
        $marker = 'M3 conformance smoke OK'
        $code = "assert(_VERSION=='Lua 5.5'); "
        if ($Target -eq 'ReferenceC') {
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
}
catch { $evidence.setup_error = $_.Exception.Message }
finally {
    Set-Location $original
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Report))
    [IO.File]::WriteAllText($Report, (ConvertTo-Json -InputObject $evidence -Depth 12) + "`n",
        [Text.UTF8Encoding]::new($false))
}
Write-Output "CONFORMANCE OBSERVATION: $($evidence.status); report=$Report; M3 acceptance=false"
if ($evidence.setup_error) { Write-Output "SETUP FAILURE: $($evidence.setup_error)" }
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
