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
    [switch] $RequireAcceptance,
    [ValidateSet('', 'gc-io-events','expanded-t-conformance')][string] $Scope = '',
    [switch] $RequireScopedAcceptance,
    [ValidateSet('','remaining-upstream-compatibility')][string] $TargetPolicy = '',
    [switch] $RequireTargetAcceptance,
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string] $Variant = 'primary',
    [ValidateSet(0,1)][int] $ConstructsBranch = 0,
    [string] $EquivalentManifest = '',
    [string] $TAdaptationManifest = '',
    [string] $FileProtocolManifest = '',
    [string] $NativeApplicability = '',
    [switch] $AllowUnreviewedEquivalent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceFileProtocols.psm1')
$root = Split-Path -Parent $PSScriptRoot
$original = Get-Location
$revision = '7579fc9d7ed90240487251dfb69168f8e64e9294'
$suffix = if ($IsWindows) { '.exe' } else { '' }
if ($Mode -eq 'Suite') { $Mode = 'Aggregate' }
if ($BuildReference -and $Target -ne 'ReferenceC') { throw 'BuildReference requires ReferenceC target' }
if ($RequireAcceptance -and ($Scope -ne '' -or $RequireScopedAcceptance)) {
    throw 'Full M3 acceptance and scoped acceptance are separate commands'
}
if ($RequireScopedAcceptance -and ($Scope -eq '' -or $Target -ne 'Ada')) {
    throw 'Scoped acceptance requires the named scope and actual Ada target'
}
if (($TargetPolicy -ne '' -and ($Scope -ne '' -or $RequireAcceptance -or $RequireScopedAcceptance)) -or
    ($RequireTargetAcceptance -and ($TargetPolicy -eq '' -or $Target -cne 'Ada')) -or
    ($TargetPolicy -eq '' -and $Variant -cne 'primary')) {
    throw 'Full-target policy and acceptance must be selected explicitly and separately from historical modes'
}
if ($TargetPolicy -ne '' -and $Mode -cnotin @('File','Aggregate','Heavy')) {
    throw 'Full-target policy requires File, Aggregate or Heavy mode'
}
if ($FileProtocolManifest -ne '' -and ($TargetPolicy -eq '' -or $Mode -cne 'File' -or
    $null -eq (Get-TargetFileProtocolDefinition -File $File))) {
    throw 'FileProtocolManifest requires a remaining-target File with a completion protocol'
}
if ($TargetPolicy -ne '' -and $Mode -ceq 'File' -and $File -ceq 'constructs.lua') {
    $expectedVariant = if ($ConstructsBranch -eq 1) { 'constructs-branch-1' } else { 'primary' }
    if ($Variant -cnotin @('primary',$expectedVariant)) { throw 'Constructs variant differs from its requested real template' }
    $Variant = $expectedVariant
}
$isolatedLauncher = $Scope -ne '' -or $TargetPolicy -ne ''
$hasProfileWitness = $Scope -ceq 'expanded-t-conformance' -or ($TargetPolicy -ne '' -and $Mode -ceq 'File')
$requiresCliPrerequisites = $TargetPolicy -eq '' -or $Mode -ceq 'Aggregate' -or
    ($Mode -ceq 'File' -and $File -ceq 'main.lua')
$requiresNativeFixtures = $TargetPolicy -eq '' -or $Mode -ceq 'Aggregate' -or
    ($Mode -ceq 'File' -and $File -cin @('attrib.lua','main.lua'))
if ($Scope -ne '') {
    $scopePolicy = Get-ConformanceScopePolicy -Scope $Scope
    if ($Mode -ne 'File' -or $File -cnotin $scopePolicy.Files) {
        throw 'Named scope requires File mode and one of its selected primary files'
    }
}
$acceptanceRequested = $RequireAcceptance -or $RequireScopedAcceptance -or $RequireTargetAcceptance
if ($TargetPolicy -ne '' -and $AllowUnreviewedEquivalent) {
    throw 'Full-target execution never permits unreviewed equivalents'
}
if ($TAdaptationManifest -ne '' -and ($TargetPolicy -eq '' -or $Target -cne 'Ada' -or
    $Configuration -cne 'upstream-test' -or $Mode -cne 'File' -or $EquivalentManifest -ne '')) {
    throw 'T adaptation requires an explicit instrumented Ada File target and cannot combine mappings'
}
if ($TargetPolicy -ne '' -and $EquivalentManifest -ne '' -and $Mode -cne 'File') {
    throw 'Single-file equivalent manifests require full-target File mode'
}
if (($EquivalentManifest -ne '' -and $Scope -eq '' -and $TargetPolicy -eq '') -or
    ($AllowUnreviewedEquivalent -and ($EquivalentManifest -eq '' -or $acceptanceRequested))) {
    throw 'Unreviewed equivalents are scoped observations only, never acceptance'
}
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
        platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        os_description = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        os_architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        process_architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        powershell_version = $PSVersionTable.PSVersion.ToString()
    }
    reference_revision = $revision
    target = $Target
    requested_configuration = $Configuration
    mode = $Mode.ToLowerInvariant()
    operation = if ($Mode -eq 'File') { 'file:' + $File } else { $Mode.ToLowerInvariant() }
    status = 'setup-failed'
    gate_acceptance = $false
    coverage_scope = $Scope
    target_policy = $TargetPolicy
    target_acceptance_requested = [bool]$RequireTargetAcceptance
    target_operation_acceptance = $false
    target_complete = $false
    synthetic_fixture = $false
    variant = $Variant
    excluded_obligations = @()
    excluded_omissions = @()
    exclusion_policy_sha256 = $null
    scoped_acceptance_requested = [bool]$RequireScopedAcceptance
    scoped_operation_acceptance = $false
    scope_complete = $false
    foundation_smoke_passed = $false
    report_only = [bool]$ReportOnly
    acceptance_requested = [bool]$RequireAcceptance
    acceptance_context = $Context
    execution_contract = $null
    coverage_validation = $null
    allocator_telemetry = $null
    child_allocator_telemetry = @()
    acceptance_error = $null
    started_utc = [DateTime]::UtcNow.ToString('o')
    configuration_verified = $false
    reference_tree_verified = $false
    observed_configuration = $null
    configuration_process = $null
    child_configuration_process = $null
    arg_child_configuration_process = $null
    launcher_identity = $null
    launcher_probe_run_id = $null
    launcher_probe_telemetry = @()
    constructs_branch = $(if ($File -ceq 'constructs.lua' -and $hasProfileWitness) { $ConstructsBranch } else { $null })
    execution_disposition = 'unchanged'
    equivalent = $null
    t_adaptation = $null
    file_completion_protocol = $null
    native_applicability = $null
    native_applicability_verified = $false
    repl_preflight_process = $null
    reference_source_records = @()
    harness_source_records = @()
    reference_library_records = @()
    runtime_library_records = @()
    build_processes = @()
    native_fixture_records = @()
    native_branch_facts = $null
    source_profile_facts = $null
    source_condition_results = $null
    native_branch_review = $null
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

function Build-WindowsFileFixtures {
    param([string] $Directory, [string] $LibraryDirectory)
    # These narrow native drivers implement the reviewed platform replacement,
    # not the unrelated upstream loadlib fixture suite. Ada already contains
    # the private native file helpers; only C needs the oracle module opener.
    $cases = @(@{ Source='tests/conformance/platform/windows_process.c';
        Output='native-terminate.exe'; Options=@() })
    if ($Target -eq 'ReferenceC') {
        $cases += @{ Source='tests/c/conformance_platform.c'; Output='conformance_platform.dll';
            Options=@('-shared', '-DLUA_ADA_PLATFORM_MODULE', '-I', (Join-Path $root 'c_api/include/api'),
                '-L', $LibraryDirectory, '-lconformance_lua') }
    }
    foreach ($case in $cases) {
        $source = Join-Path $root $case.Source
        $artifact = Join-Path $Directory $case.Output
        Invoke-BuildProcess (@('exec','--','gcc','-std=c99','-Wall','-Wextra','-Werror','-pedantic',
            $source, '-o', $artifact) + $case.Options)
        $evidence.native_fixture_records += [ordered]@{ source=$case.Source;
            source_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();
            artifact=$artifact;
            artifact_sha256=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant() }
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
        'scripts/ConformanceInventory.psm1', 'scripts/ConformanceScope.psm1',
        'scripts/ManagedTelemetry.psm1', 'scripts/ConformanceReview.psm1',
        'scripts/ConformanceFileProtocols.psm1',
        'scripts/ConformanceTransforms.psm1','scripts/New-ConformanceTTransform.ps1',
        'scripts/New-ConformanceEquivalent.ps1', 'tests/conformance/suite.json')) {
        $evidence.harness_source_records += [ordered]@{
            path = $relative
            sha256 = (Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $suite = Get-Content -LiteralPath (Join-Path $root 'tests/conformance/suite.json') -Raw | ConvertFrom-Json
    if ($suite.schema_version -ne 1 -or $suite.reference_revision -cne $revision) { throw 'Invalid conformance manifest' }
    if ($Scope -ne '') {
        $evidence.coverage_validation = Test-ConformanceScope -Root $root -Scope $Scope
        if ($Context -ne '' -and ($Context -cnotin $suite.acceptance_contexts -or
            -not $Context.StartsWith("$Configuration/$($evidence.host.platform)/"))) {
            throw 'Scoped context does not identify this configuration and host'
        }
    }
    if ($TargetPolicy -ne '') {
        $evidence.coverage_validation = Test-ConformanceInventory -Root $root -TargetPolicy $TargetPolicy
        $policyPath = Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json'
        $evidence.exclusion_policy_sha256 = (Get-FileHash -LiteralPath $policyPath).Hash.ToLowerInvariant()
        if ($Context -cnotin $suite.acceptance_contexts -or
            -not $Context.StartsWith("$Configuration/$($evidence.host.platform)/")) {
            throw 'Full-target context does not identify this configuration and host'
        }
        if ($Mode -ceq 'File' -and $File -cnotin @($suite.files | Where-Object role -CEQ primary | ForEach-Object path)) {
            throw 'Full-target File mode requires one of the 30 scheduled primary sources'
        }
        if ($Target -ceq 'Ada' -and $Configuration -ceq 'upstream-test') {
            $evidence.excluded_obligations = @($evidence.coverage_validation.Exclusions | Where-Object {
                ($Mode -ceq 'Aggregate' -and $_.source -cne 'heavy.lua') -or
                ($Mode -ceq 'Heavy' -and $_.source -ceq 'heavy.lua') -or
                ($Mode -ceq 'File' -and $_.source -ceq $File)
            } | ForEach-Object id | Sort-Object)
            if ($evidence.excluded_obligations.Count -gt 0 -and $TAdaptationManifest -eq '') {
                throw 'Full-target excluded obligations require an independently reviewed exact T transformation'
            }
        }
        if ($RequireTargetAcceptance) {
            if ($evidence.coverage_validation.PendingApiEntries -gt 0) {
                throw 'Full-target global public API coverage remains unresolved'
            }
            $evidence.coverage_validation = Test-ConformanceInventory -Root $root `
                -TargetPolicy $TargetPolicy -RequireComplete
        }
    }
    if ($acceptanceRequested) {
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
    if ($isolatedLauncher) {
        # Both bare lua and arg-selected children use this exact immutable
        # launcher. The source fixture tree remains unchanged and hash-checked.
        $selectedInterpreter = $Interpreter
        $Interpreter = Join-Path $fixtureDirectory "lua$suffix"
        Copy-Item -LiteralPath $selectedInterpreter -Destination $Interpreter
        if ((Get-FileHash -LiteralPath $selectedInterpreter -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath $Interpreter -Algorithm SHA256).Hash) {
            throw 'Scoped child executable copy changed bytes'
        }
        $evidence.launcher_identity = [ordered]@{ original=$selectedInterpreter; copy=$Interpreter;
            sha256=(Get-FileHash -LiteralPath $Interpreter -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $environment = @{
        LUA_ADA_CONFORMANCE_ALLOCATOR = [string]$evidence.allocator_limit_bytes
        MEMLIMIT = [string]$evidence.allocator_limit_bytes
    }
    if ($isolatedLauncher) {
        # Probe states finish before the selected file starts. Retain their
        # independent shutdown records without contaminating the file's child
        # count or allowing probe refusals to stand in for a tested refusal.
        $evidence.launcher_probe_run_id = [Guid]::NewGuid().ToString('N')
        $environment.LUA_ADA_CONFORMANCE_RUN_ID = $evidence.launcher_probe_run_id
        $environment.LUA_ADA_CONFORMANCE_TELEMETRY = Join-Path $runRoot 'probe-allocator'
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
        if ($Scope -eq '' -and $requiresCliPrerequisites) {
        $repl = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-E', '-W', '-i') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'repl-preflight') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.repl_preflight_process = $repl
        if ($repl.exit_code -ne 0 -or $repl.timed_out -or $repl.stderr_bytes -ne 0 -or
            $repl.capture_exceeded -or $repl.pipe_drain_failed -or $repl.process_tree_kill_error) {
            throw "Default C REPL prerequisite failed; see $($repl.stderr_path)"
        }
        }
        if ($Scope -eq '' -and $requiresNativeFixtures) {
            Build-Fixtures -Directory $fixtureDirectory -LibraryDirectory $libraryDirectory
        }
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
        if ($isolatedLauncher -and $Context -ne '') {
            Assert-ScopedBuildIdentity -Observed $observed -Context $Context
        }
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
        if ($Scope -eq '' -and $requiresCliPrerequisites) {
        $repl = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-E', '-W', '-i') `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'repl-preflight') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.repl_preflight_process = $repl
        if ($repl.exit_code -ne 0 -or $repl.timed_out -or $repl.stderr_bytes -ne 0 -or
            $repl.capture_exceeded -or $repl.pipe_drain_failed -or $repl.process_tree_kill_error) {
            throw 'Default Ada REPL prerequisite failed'
        }
        }
        if ($Scope -eq '' -and $requiresNativeFixtures -and $NativeLibraryDirectory -ne '') {
            Build-Fixtures -Directory $fixtureDirectory `
                -LibraryDirectory (Resolve-Path -LiteralPath $NativeLibraryDirectory).Path -LibraryName lua
        }
        elseif ($Scope -eq '' -and $requiresNativeFixtures -and ($RequireAcceptance -or $RequireTargetAcceptance)) {
            throw 'Ada acceptance needs NativeLibraryDirectory for actual upstream C fixture modules'
        }
    }
    if ($isolatedLauncher) {
        $argCode = 'local i=0; while arg[i] do i=i-1 end; local exe=arg[i+1]; '
        $argCode += if ($IsWindows) {
            'local command=''""''..exe..''" --conformance-config"''; '
        } else {
            'local command="''"..exe:gsub("''", "''\"''\"''").."'' --conformance-config"; '
        }
        $argCode += 'local p=assert(io.popen(command,"r")); local s=p:read("a"); assert(p:close()); io.write(s)'
        $argChild = Invoke-ConformanceProcess -Executable $Interpreter -Arguments @('-e', $argCode) `
            -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'arg-child-configuration') `
            -TimeoutSeconds 30 -Environment $environment
        $evidence.arg_child_configuration_process = $argChild
        if ($argChild.exit_code -ne 0 -or $argChild.timed_out -or $argChild.stderr_bytes -ne 0 -or
            $argChild.capture_exceeded -or $argChild.pipe_drain_failed -or $argChild.process_tree_kill_error -or
            [IO.File]::ReadAllText($argChild.stdout_path).Trim() -cne
                [IO.File]::ReadAllText($probe.stdout_path).Trim()) {
            throw 'Arg-selected child does not retain the selected configuration/allocator ceiling'
        }
        $probeTelemetry = @()
        foreach ($sidecar in Get-ChildItem -LiteralPath $runRoot -Filter 'probe-allocator.*.json') {
            $measured = Get-Content -LiteralPath $sidecar.FullName -Raw | ConvertFrom-Json -AsHashtable
            if ($measured.process_id -ne [int]($sidecar.BaseName.Split('.')[-1])) {
                throw 'Scoped launcher probe telemetry filename differs from PID'
            }
            $probeTelemetry += $measured
            $evidence.launcher_probe_telemetry += [ordered]@{ path=$sidecar.FullName;
                sha256=(Get-FileHash -LiteralPath $sidecar.FullName -Algorithm SHA256).Hash.ToLowerInvariant();
                data=$measured }
        }
        Assert-ScopedProbeTelemetry -Telemetry $probeTelemetry `
            -Processes @{parent=$probe; bare=$child; arg=$argChild} `
            -RunId $evidence.launcher_probe_run_id -Configuration $Configuration -Target $Target `
            -LimitBytes $evidence.allocator_limit_bytes
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
    $nativeSetup = ''
    if ($EquivalentManifest -ne '') {
        $mapping = Get-Content -LiteralPath $EquivalentManifest -Raw | ConvertFrom-Json
        if ($mapping.source -cne "references/lua/testes/$File" -or
            $mapping.configuration -notin @($Configuration, 'default-and-upstream-test')) {
            throw 'Equivalent identifies a different source/configuration'
        }
        $hostName = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        if ($mapping.PSObject.Properties['platform'] -and $mapping.platform -cne $hostName) {
            throw 'Equivalent identifies a different native platform'
        }
        $generated = Join-Path $runRoot "equivalent-$File"
        $equivalent = & "$PSScriptRoot/New-ConformanceEquivalent.ps1" -Manifest $EquivalentManifest `
            -Output $generated -AllowUnreviewedDiagnostics:$AllowUnreviewedEquivalent | ConvertFrom-Json -AsHashtable
        $equivalent['manifest_sha256'] = (Get-FileHash -LiteralPath $EquivalentManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        $evidence.equivalent = $equivalent
        $evidence.execution_disposition = $equivalent.disposition
        if ($TargetPolicy -ne '') {
            $reviewedMapping = Get-Content -LiteralPath $EquivalentManifest -Raw | ConvertFrom-Json -AsHashtable -Depth 64
            $replay = Get-ConformanceEquivalentReplay -Root $root -Specification $reviewedMapping
            if ($replay.sha256 -cne $equivalent.output_sha256 -or
                [Convert]::ToBase64String($replay.bytes) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($generated))) {
                throw 'Equivalent producer bytes differ from exact full-target replay'
            }
            $evidence.equivalent.manifest_path = [IO.Path]::GetRelativePath($root,(Resolve-Path $EquivalentManifest).Path).Replace('\','/')
            if ($replay.disposition -ceq 'ada-internal-equivalent' -and $Target -cne 'Ada') {
                throw 'Ada internal equivalents cannot replace the original C oracle'
            }
            if ($replay.disposition -ceq 'native-platform-equivalent') {
                if ($NativeApplicability -ne '') {
                    $evidence.native_applicability = @{path=(Resolve-Path $NativeApplicability).Path;
                        sha256=(Get-FileHash -LiteralPath $NativeApplicability).Hash.ToLowerInvariant()}
                    $nativeProof = Assert-ConformanceNativeApplicability -Root $root -ArtifactRoot $root `
                        -Identity $evidence.native_applicability -Specification $reviewedMapping `
                        -ManifestSha256 $evidence.equivalent.manifest_sha256 -Configuration $Configuration `
                        -Platform $evidence.host.platform -Revision $evidence.repository_revision -ExpectedContext $Context `
                        -RequireRuntimeEvidence:$RequireTargetAcceptance
                    $evidence.native_applicability_verified = $nativeProof.runtime_verified
                } elseif ($RequireTargetAcceptance) {
                    throw 'Native platform acceptance requires matching source-linked original C applicability evidence'
                }
            }
        }
        $arguments = @($generated)
        if ($File -eq 'files.lua' -and $IsWindows -and $mapping.id -ceq 'files-windows-platform') {
            Build-WindowsFileFixtures -Directory $fixtureDirectory -LibraryDirectory $libraryDirectory
            if ($Target -eq 'ReferenceC') {
                $nativeSetup = "; local p=assert(package.loadlib('conformance_platform.dll','luaopen_conformance_platform'))(); " +
                    '_test_failing_stream=p.failing_stream; _test_nonblocking_pair=p.nonblocking_pair'
            }
        }
        if ($File -eq 'files.lua' -and $IsMacOS -and $mapping.id -ceq 'files-macos-platform') {
            # Keep the native failure setup outside the unchanged interpreter.
            # Both targets run the same separately named counterpart before
            # the source-hashed equivalent, within the measured owned state.
            if ($Target -eq 'ReferenceC') {
                $driver = Join-Path $root 'tests/c/conformance_platform.c'
                $module = Join-Path $fixtureDirectory 'conformance_platform.dylib'
                Invoke-BuildProcess @('exec','--','gcc','-std=c99','-Wall','-Wextra','-Werror',
                    '-pedantic','-fPIC','-dynamiclib','-DLUA_ADA_PLATFORM_MODULE',
                    '-I',(Join-Path $root 'c_api/include/api'),$driver,'-o',$module,
                    '-L',$libraryDirectory,'-lconformance_lua','-Wl,-undefined,dynamic_lookup')
                $evidence.native_fixture_records += [ordered]@{source='tests/c/conformance_platform.c';
                    source_sha256=(Get-FileHash $driver).Hash.ToLowerInvariant(); artifact=$module;
                    artifact_sha256=(Get-FileHash $module).Hash.ToLowerInvariant()}
                $nativeSetup = "; local p=assert(package.loadlib('conformance_platform.dylib','luaopen_conformance_platform'))(); _test_failing_stream=p.failing_stream"
            }
            $counterpart = Join-Path $root 'tests/conformance/platform/macos-buffered-failure.lua'
            $counterpartCopy = Join-Path $fixtureDirectory 'macos-buffered-failure.lua'
            Copy-Item -LiteralPath $counterpart -Destination $counterpartCopy
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/platform/macos-buffered-failure.lua';
                source_sha256=(Get-FileHash $counterpart).Hash.ToLowerInvariant(); artifact=$counterpartCopy;
                artifact_sha256=(Get-FileHash $counterpartCopy).Hash.ToLowerInvariant()}
            $nativeSetup += "; dofile('macos-buffered-failure.lua')"
            # Retain actual direct/nested shell statuses before the immutable
            # upstream loop diagnoses its expected-kind mismatch. These are
            # observations only; no dynamic status becomes an accepted value.
            $diagnostic = Join-Path $root 'tests/conformance/platform/macos-shell-diagnostic.lua'
            $diagnosticCopy = Join-Path $fixtureDirectory 'equivalent-macos-shell-diagnostic.lua'
            Copy-Item -LiteralPath $diagnostic -Destination $diagnosticCopy
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/platform/macos-shell-diagnostic.lua';
                source_sha256=(Get-FileHash $diagnostic).Hash.ToLowerInvariant(); artifact=$diagnosticCopy;
                artifact_sha256=(Get-FileHash $diagnosticCopy).Hash.ToLowerInvariant(); diagnostic_only=$true}
            $nativeSetup += "; dofile('equivalent-macos-shell-diagnostic.lua')"
            $counterpart = Join-Path $root 'tests/conformance/platform/macos-shell-status.lua'
            $counterpartCopy = Join-Path $fixtureDirectory 'equivalent-macos-shell-status.lua'
            Copy-Item -LiteralPath $counterpart -Destination $counterpartCopy
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/platform/macos-shell-status.lua';
                source_sha256=(Get-FileHash $counterpart).Hash.ToLowerInvariant(); artifact=$counterpartCopy;
                artifact_sha256=(Get-FileHash $counterpartCopy).Hash.ToLowerInvariant()}
            $nativeSetup += "; dofile('equivalent-macos-shell-status.lua')"
            # The equivalent invokes this counterpart exactly at the original
            # calendar boundary check, preserving the surrounding test order.
            $counterpart = Join-Path $root 'tests/conformance/platform/macos-calendar-boundary.lua'
            $counterpartCopy = Join-Path $fixtureDirectory 'equivalent-macos-calendar-boundary.lua'
            Copy-Item -LiteralPath $counterpart -Destination $counterpartCopy
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/platform/macos-calendar-boundary.lua';
                source_sha256=(Get-FileHash $counterpart).Hash.ToLowerInvariant(); artifact=$counterpartCopy;
                artifact_sha256=(Get-FileHash $counterpartCopy).Hash.ToLowerInvariant()}
        }
    }
    if ($TAdaptationManifest -ne '') {
        $specification = Get-Content -LiteralPath $TAdaptationManifest -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($specification.source -cne "references/lua/testes/$File") { throw 'T transform identifies another primary source' }
        $generated = Join-Path $runRoot "equivalent-t-$File"
        $adapted = & "$PSScriptRoot/New-ConformanceTTransform.ps1" -Manifest $TAdaptationManifest `
            -Output $generated | ConvertFrom-Json -AsHashtable -Depth 32
        if ((@($adapted.excluded_obligations | Sort-Object) -join '|') -cne
            (@($evidence.excluded_obligations | Sort-Object) -join '|')) {
            throw 'T transformation does not replace exactly the approved source obligations'
        }
        $evidence.t_adaptation = $adapted
        $evidence.execution_disposition = 'reviewed-t-adapted'
        $arguments = @($generated)
    }
    if ($isolatedLauncher -and $File -eq 'files.lua') {
        # Upstream's read-only no-buffer example ignores its write result. The
        # separate C/Ada counterpart proves immediate visibility through a
        # second native handle, without adding any unmeasured subprocess.
        $counterpart = Join-Path $root 'tests/conformance/platform/unbuffered-visibility.lua'
        $counterpartCopy = Join-Path $fixtureDirectory 'unbuffered-visibility.lua'
        Copy-Item -LiteralPath $counterpart -Destination $counterpartCopy
        $sourceHash = (Get-FileHash $counterpart -Algorithm SHA256).Hash.ToLowerInvariant()
        $copyHash = (Get-FileHash $counterpartCopy -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -cne $copyHash) { throw 'Unbuffered counterpart copy changed bytes' }
        $evidence.native_fixture_records += [ordered]@{source='tests/conformance/platform/unbuffered-visibility.lua';
            source_sha256=$sourceHash; artifact=$counterpartCopy; artifact_sha256=$copyHash}
        $nativeSetup += "; dofile('unbuffered-visibility.lua')"
        # Host-specific guards need an executed counterpart and explicit facts,
        # not an inferred pass for an inactive original branch. Preserve this
        # input in the artifact bundle separately from unchanged upstream.
        $counterpart = Join-Path $root 'tests/conformance/platform/files-native-branches.lua'
        $mappingPath = 'tests/conformance/reviews/files-native-branches.proposal.json'
        $reviewPath = 'tests/conformance/reviews/files-native-branches.gc-cross-review.json'
        $evidence.native_branch_review = [ordered]@{
            mapping=$mappingPath; mapping_sha256=(Get-FileHash (Join-Path $root $mappingPath)).Hash.ToLowerInvariant();
            review=$reviewPath; review_sha256=(Get-FileHash (Join-Path $root $reviewPath)).Hash.ToLowerInvariant()}
        $nativeMapping = Assert-NativeBranchReviewBinding -Root $root -Identity $evidence.native_branch_review
        if ($nativeMapping.source -cne 'references/lua/testes/files.lua' -or
            $nativeMapping.counterpart.path -cne 'tests/conformance/platform/files-native-branches.lua') {
            throw 'Native branch mapping identifies another source or counterpart'
        }
        $counterpartCopy = Join-Path $fixtureDirectory 'equivalent-files-native-branches.lua'
        Copy-Item -LiteralPath $counterpart -Destination $counterpartCopy
        $sourceHash = (Get-FileHash $counterpart -Algorithm SHA256).Hash.ToLowerInvariant()
        $copyHash = (Get-FileHash $counterpartCopy -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -cne $copyHash) { throw 'Native branch counterpart copy changed bytes' }
        $evidence.native_fixture_records += [ordered]@{source='tests/conformance/platform/files-native-branches.lua';
            source_sha256=$sourceHash; artifact=$counterpartCopy; artifact_sha256=$copyHash;
            disposition='native-platform-equivalent'}
        $nativeSetup += "; dofile('equivalent-files-native-branches.lua')"
    }
    if ($isolatedLauncher) {
        # Enable normal warnings before upstream execution, including close-time
        # finalizers. Otherwise the test handler's initial off state can hide
        # early assertions before a source explicitly enables its warnings.
        $setup = "assert(_soft==nil and _port==nil and _U==nil and _nomsg==nil); warn('@on'); "
        $setup += if ($Configuration -eq 'upstream-test') {
            "assert(type(T)=='table' and type(T.checkmemory)=='function'); T.checkmemory()"
        } else { 'assert(T==nil)' }
        if ($File -eq 'files.lua' -and $Configuration -eq 'upstream-test' -and -not $IsWindows) {
            $setup += "; assert(type(T.nonblock)=='function')"
        }
        if ($hasProfileWitness) {
            $profileWitness = Join-Path $root 'tests/conformance/source-profile-witness.lua'
            $profileCopy = Join-Path $fixtureDirectory 'equivalent-source-profile-witness.lua'
            Copy-Item -LiteralPath $profileWitness -Destination $profileCopy
            $sourceHash = (Get-FileHash $profileWitness).Hash.ToLowerInvariant()
            $copyHash = (Get-FileHash $profileCopy).Hash.ToLowerInvariant()
            if ($sourceHash -cne $copyHash) { throw 'Source profile witness copy changed bytes' }
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/source-profile-witness.lua';
                source_sha256=$sourceHash; artifact=$profileCopy; artifact_sha256=$copyHash}
            $setup += "; dofile('equivalent-source-profile-witness.lua')"
        }
        if ($File -eq 'bitwise.lua' -and $hasProfileWitness) {
            $wrapper = Join-Path $root 'tests/conformance/bitwise-helper-witness.lua'
            $wrapperCopy = Join-Path $runRoot 'equivalent-bitwise-helper-witness.lua'
            Copy-Item -LiteralPath $wrapper -Destination $wrapperCopy
            $sourceHash = (Get-FileHash $wrapper).Hash.ToLowerInvariant()
            $copyHash = (Get-FileHash $wrapperCopy).Hash.ToLowerInvariant()
            if ($sourceHash -cne $copyHash) { throw 'Bitwise helper wrapper copy changed bytes' }
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/bitwise-helper-witness.lua';
                source_sha256=$sourceHash; artifact=$wrapperCopy; artifact_sha256=$copyHash}
            $arguments = @($wrapperCopy)
        }
        if ($File -eq 'constructs.lua' -and $hasProfileWitness) {
            $wrapper = Join-Path $root 'tests/conformance/constructs-seeded.lua'
            $wrapperCopy = Join-Path $runRoot 'equivalent-constructs-seeded.lua'
            Copy-Item -LiteralPath $wrapper -Destination $wrapperCopy
            $sourceHash = (Get-FileHash $wrapper).Hash.ToLowerInvariant()
            $copyHash = (Get-FileHash $wrapperCopy).Hash.ToLowerInvariant()
            if ($sourceHash -cne $copyHash) { throw 'Constructs seeded wrapper copy changed bytes' }
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/constructs-seeded.lua';
                source_sha256=$sourceHash; artifact=$wrapperCopy; artifact_sha256=$copyHash}
            $arguments = @($wrapperCopy, [string]$ConstructsBranch)
        }
        if ($File -eq 'events.lua') {
            $wrapper = Join-Path $root 'tests/conformance/events-return-witness.lua'
            $wrapperCopy = Join-Path $runRoot 'equivalent-events-return-witness.lua'
            Copy-Item -LiteralPath $wrapper -Destination $wrapperCopy
            $sourceHash = (Get-FileHash $wrapper).Hash.ToLowerInvariant()
            $copyHash = (Get-FileHash $wrapperCopy).Hash.ToLowerInvariant()
            if ($sourceHash -cne $copyHash) { throw 'Events return wrapper copy changed bytes' }
            $evidence.native_fixture_records += [ordered]@{source='tests/conformance/events-return-witness.lua';
                source_sha256=$sourceHash; artifact=$wrapperCopy; artifact_sha256=$copyHash}
            $arguments = @($wrapperCopy)
        }
        $arguments = @('-e', ($setup + $nativeSetup)) + $arguments
        if ($Mode -ceq 'File' -and $File -ne 'files.lua') {
            # These three originals deliberately return before OK when T is
            # absent. Preserve that measured omission; the reviewed contract
            # must link its body to instrumented evidence or approved target
            # exclusions rather than inventing a completion marker.
            $marker = if ($TargetPolicy -ne '' -and $Configuration -ceq 'default' -and
                $File -cin @('api.lua','code.lua','memerr.lua')) { '' }
                elseif ($File -ceq 'utf8.lua') { 'ok' } else { 'OK' }
        }
        if ($TargetPolicy -ne '' -and $Mode -ceq 'File' -and
            $null -ne (Get-TargetFileProtocolDefinition -File $File)) {
            $protocolPath = if ($FileProtocolManifest -ne '') { $FileProtocolManifest }
                else { 'tests/conformance/targets/remaining-upstream-compatibility/file-completion.author-proposal.json' }
            $protocol = Read-TargetFileProtocolManifest -Root $root -Path $protocolPath -RequireReview:$RequireTargetAcceptance
            $wrapper = Join-Path $root $protocol.manifest.wrapper.path
            $wrapperCopy = Join-Path $runRoot 'target-file-completion.lua'
            Copy-Item -LiteralPath $wrapper -Destination $wrapperCopy
            $wrapperHash = (Get-FileHash -LiteralPath $wrapperCopy).Hash.ToLowerInvariant()
            if ($wrapperHash -cne $protocol.manifest.wrapper.sha256) { throw 'Target completion wrapper copy changed bytes' }
            # Replace only the selected chunk argument; setup, native fixtures,
            # adapter and source-profile setup stay in the same process.
            $chunk = $arguments[-1]
            $chunkFull = if ([IO.Path]::IsPathRooted($chunk)) { $chunk } else { Join-Path $fixtureDirectory $chunk }
            $definition = Get-TargetFileProtocolDefinition -File $File
            $evidence.file_completion_protocol = [ordered]@{file=$File;entry=$definition.entry;
                manifest_path=$protocol.path;manifest_sha256=$protocol.sha256;wrapper_artifact=$wrapperCopy;
                wrapper_sha256=$wrapperHash;chunk_path=$chunk;
                executed_sha256=(Get-FileHash -LiteralPath $chunkFull).Hash.ToLowerInvariant();
                disposition=$null;terminal_witness=$null;source_completed=$false;
                runtime_acceptance=$false;coverage_authority=$false}
            $arguments = @($arguments[0],$arguments[1],$wrapperCopy,$File,$chunk)
            $marker = 'target file completion ' + $File + ': ' +
                $(if ($Configuration -ceq 'default' -and $definition.t_absent_return) { 'T absent' } else { 'complete' })
        }
    }
    if ($acceptanceRequested -or $isolatedLauncher) {
        $environment.LUA_ADA_CONFORMANCE_RUN_ID = $runId
        $environment.LUA_ADA_CONFORMANCE_TELEMETRY = Join-Path $runRoot 'allocator'
    }
    $evidence.process = Invoke-ConformanceProcess -Executable $Interpreter -Arguments $arguments `
        -Directory $fixtureDirectory -OutputPrefix (Join-Path $runRoot 'execution') `
        -TimeoutSeconds $evidence.timeout_seconds -Environment $environment
    $evidence.outcome = Get-ConformanceOutcome -Process $evidence.process -Marker $marker
    if ($null -ne $evidence.file_completion_protocol) {
        $completed = Assert-TargetFileCompletion -File $File -Configuration $Configuration -Process $evidence.process
        foreach ($field in @('disposition','terminal_witness','source_completed')) {
            $evidence.file_completion_protocol[$field] = $completed[$field]
        }
    }
    if ($hasProfileWitness) {
        $evidence.source_profile_facts = Get-ScopedSourceProfileFacts `
            -Output ([IO.File]::ReadAllText($evidence.process.stdout_path)) -Observed $observed
        $selectedSource = @($suite.files | Where-Object path -CEQ $File)[0]
        $sourceConditions = @(Read-ConformanceJsonLines `
            -Path (Join-Path $root ('tests/conformance/' + $selectedSource.coverage_file)))
        $evidence.source_condition_results = Get-ScopedMeasuredConditionResults `
            -Records $sourceConditions -Facts $evidence.source_profile_facts
    }
    if ($File -ceq 'constructs.lua' -and $hasProfileWitness) {
        $branchOutput = [IO.File]::ReadAllText($evidence.process.stdout_path)
        $pattern = '(?m)^testing short-circuit optimizations \(' + $ConstructsBranch + '\)\r?$'
        if ([regex]::Matches($branchOutput, $pattern).Count -ne 1) {
            throw 'Constructs seeded template branch witness missing or duplicated'
        }
    }
    $evidence.fixture_changes = Test-ConformanceFixtureHashes -Directory $fixtureDirectory -Records $evidence.fixture_records
    $evidence.status = if ($evidence.fixture_changes.Count -gt 0) { 'fixture-source-changed' } else { $evidence.outcome.status }
    if ($isolatedLauncher) {
        $telemetryPath = $environment.LUA_ADA_CONFORMANCE_TELEMETRY + '.' + $evidence.process.process_id + '.json'
        $telemetry = Get-Content -LiteralPath $telemetryPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-ManagedTelemetry -Telemetry $telemetry -RunId $runId -ProcessId $evidence.process.process_id `
            -Configuration $Configuration -LimitBytes $evidence.allocator_limit_bytes -RequireShutdown:($Target -ceq 'Ada')
        if ($Scope -ne '' -or ($Mode -ceq 'File' -and $File -cin (Get-ConformanceScopePolicy -Scope expanded-t-conformance).Files)) {
            Assert-ScopedProcessCompletion -File $File -Process $evidence.process `
                -Telemetry $telemetry -RunId $runId -Configuration $Configuration -Platform $evidence.host.platform -NativeOracle:($Target -eq 'ReferenceC')
        }
        $evidence.allocator_telemetry = [ordered]@{ path=$telemetryPath;
            sha256=(Get-FileHash -LiteralPath $telemetryPath -Algorithm SHA256).Hash.ToLowerInvariant(); data=$telemetry }
        if ($File -eq 'files.lua') {
            $evidence.native_branch_facts = Get-ScopedNativeBranchFacts -Output ([IO.File]::ReadAllText($evidence.process.stdout_path))
            Assert-NativeBranchWitnesses -Mapping $nativeMapping -Output ([IO.File]::ReadAllText($evidence.process.stdout_path))
        }
        if ($File -eq 'files.lua' -or $TargetPolicy -ne '') {
            foreach ($sidecar in Get-ChildItem -LiteralPath $runRoot -Filter 'allocator.*.json') {
                $childId = [int]($sidecar.BaseName.Split('.')[-1])
                if ($childId -eq $evidence.process.process_id) { continue }
                $childTelemetry = Get-Content -LiteralPath $sidecar.FullName -Raw | ConvertFrom-Json -AsHashtable
                Assert-ManagedTelemetry -Telemetry $childTelemetry -RunId $runId -ProcessId $childId `
                    -Configuration $Configuration -LimitBytes $evidence.allocator_limit_bytes -RequireShutdown:($Target -eq 'Ada')
                $evidence.child_allocator_telemetry += [ordered]@{ path=$sidecar.FullName;
                    sha256=(Get-FileHash -LiteralPath $sidecar.FullName -Algorithm SHA256).Hash.ToLowerInvariant();
                    data=$childTelemetry }
            }
            # No setup Lua children share this execution's telemetry prefix.
            # POSIX has two empty commands, four exits, and (with T) a pipe
            # receiver. Windows substitutes two Lua cat counterparts instead.
            # C exits bypass its writer; Ada typed exits always dispose/record.
            if ($File -eq 'files.lua') {
                $expectedChildren = if ($IsWindows) { 4 } else { 2 }
                if (-not $IsWindows -and $Configuration -eq 'upstream-test') { $expectedChildren++ }
                if ($Target -eq 'Ada') { $expectedChildren += 4 }
                if ($evidence.child_allocator_telemetry.Count -ne $expectedChildren) {
                    throw 'Scoped file child allocator telemetry is incomplete'
                }
            }
        }
    }
    $evidence.foundation_smoke_passed = $Target -eq 'ReferenceC' -and $Mode -eq 'Smoke' -and
        $evidence.status -eq 'passed' -and $evidence.configuration_verified -and
        $evidence.process.stderr_bytes -eq 0
    if ($Mode -eq 'Smoke' -and $evidence.status -eq 'passed' -and $evidence.process.stderr_bytes -ne 0) {
        $evidence.status = 'unexpected-smoke-stderr'
    }
    if ($acceptanceRequested) {
        try {
            if ($evidence.repository_dirty -or -not $evidence.configuration_verified -or
                $evidence.fixture_changes.Count -gt 0) {
                throw 'Acceptance requires committed, configuration-verified, unchanged inputs'
            }
            $contract = Get-Content -LiteralPath $AcceptanceContract -Raw | ConvertFrom-Json -AsHashtable
            if ($RequireTargetAcceptance -and $null -ne $evidence.file_completion_protocol) {
                [void](Assert-TargetFileProtocolBinding -Root $root -Report $evidence `
                    -WrapperPath $evidence.file_completion_protocol.wrapper_artifact -Contract $contract -RequireReview)
            }
            if ($EquivalentManifest -ne '' -and
                ($contract.equivalent_manifest_sha256 -cne $evidence.equivalent.manifest_sha256 -or
                 $contract.executed_sha256 -cne $evidence.equivalent.output_sha256 -or
                 $contract.disposition -cne $evidence.execution_disposition)) {
                throw 'Execution contract does not identify the reviewed equivalent'
            }
            if ($TAdaptationManifest -ne '' -and
                ($contract.t_transform_manifest_sha256 -cne $evidence.t_adaptation.manifest_sha256 -or
                 $contract.executed_sha256 -cne $evidence.t_adaptation.output_sha256 -or
                 $contract.exclusion_policy_sha256 -cne $evidence.exclusion_policy_sha256 -or
                 $contract.disposition -cne 'reviewed-t-adapted')) {
                throw 'Execution contract does not identify the exact reviewed T transformation'
            }
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
            if ($RequireScopedAcceptance) {
                if ($evidence.runtime_library_records.Count -eq 0 -or
                    $evidence.process.executable_sha256 -cne $evidence.launcher_identity.sha256) {
                    throw 'Scoped execution requires actual executable/library identities'
                }
                $evidence.coverage_validation = Test-ConformanceScope -Root $root -Scope $Scope -RequireScopedComplete
                $evidence.scope_complete = $evidence.coverage_validation.ScopeComplete
                Assert-ScopedProcessCompletion -File $File -Process $evidence.process `
                    -Telemetry $telemetry -RunId $runId -Configuration $Configuration -Platform $evidence.host.platform
            } elseif ($RequireTargetAcceptance) {
                if ($evidence.runtime_library_records.Count -eq 0 -or
                    $evidence.process.executable_sha256 -cne $evidence.launcher_identity.sha256) {
                    throw 'Full-target execution requires actual executable/library identities'
                }
                $evidence.coverage_validation = Test-ConformanceInventory -Root $root `
                    -TargetPolicy $TargetPolicy -RequireComplete
                $evidence.target_complete = $evidence.coverage_validation.TargetComplete
            } else {
                $evidence.coverage_validation = Test-ConformanceInventory -Root $root -RequireComplete
            }
            $coverageRecords = @{}
            foreach ($source in $suite.files) {
                if ($RequireScopedAcceptance -and $source.path -cnotin (@($evidence.coverage_validation.Definition.files.path) + @($scopePolicy.Helpers))) { continue }
                $coveragePath = Join-Path $root ('tests/conformance/' + $source.coverage_file)
                foreach ($record in (Read-ConformanceJsonLines -Path $coveragePath)) {
                    $coverageRecords[$record.id] = $record
                }
            }
            $operation = if ($Mode -eq 'File') { 'file:' + $File } else { $Mode.ToLowerInvariant() }
            $resolvedExclusions = @{}
            if ($RequireTargetAcceptance) {
                foreach ($exclusion in $evidence.coverage_validation.Exclusions) { $resolvedExclusions[$exclusion.id] = $exclusion }
            }
            $accepted = Test-ConformanceAcceptance -Process $evidence.process -Outcome $evidence.outcome `
                -Contract $contract -Operation $operation -Context $Context `
                -SourceRecords $evidence.fixture_records -RunId $runId -Configuration $Configuration `
                -AllocatorLimitBytes $evidence.allocator_limit_bytes `
                -CoverageComplete $(if ($RequireScopedAcceptance) { $evidence.scope_complete }
                    elseif ($RequireTargetAcceptance) { $evidence.target_complete } else { $evidence.coverage_validation.Complete }) `
                -CoverageRecords $coverageRecords -Telemetry $telemetry `
                -TargetPolicy $(if ($RequireTargetAcceptance) { $TargetPolicy } else { 'strict-upstream' }) `
                -ResolvedExclusions $resolvedExclusions
            if ($RequireScopedAcceptance) {
                $evidence.scoped_operation_acceptance = $accepted.gate_acceptance
            } elseif ($RequireTargetAcceptance) {
                $evidence.target_operation_acceptance = $accepted.gate_acceptance
                $evidence.excluded_omissions = $accepted.excluded_omissions
            } else { $evidence.gate_acceptance = $accepted.gate_acceptance }
        }
        catch {
            $evidence.acceptance_error = $_.Exception.Message
            $evidence.status = 'acceptance-blocked'
        }
    }
}
catch {
    $evidence.setup_error = $_.Exception.Message
    if ($evidence.status -eq 'passed') { $evidence.status = 'verification-failed' }
}
finally {
    Set-Location $original
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Report))
    [IO.File]::WriteAllText($Report, (ConvertTo-Json -InputObject $evidence -Depth 12) + "`n",
        [Text.UTF8Encoding]::new($false))
}
Write-Output "CONFORMANCE OBSERVATION: $($evidence.status); report=$Report; M3 acceptance=$($evidence.gate_acceptance.ToString().ToLowerInvariant())"
if ($evidence.setup_error) { Write-Output "SETUP FAILURE: $($evidence.setup_error)" }
if ($evidence.acceptance_error) { Write-Output "ACCEPTANCE BLOCKED: $($evidence.acceptance_error)" }
if ($RequireScopedAcceptance) {
    Write-Output "SCOPED OPERATION ACCEPTANCE: $($evidence.scoped_operation_acceptance); full M3 acceptance=False"
    if ($evidence.scoped_operation_acceptance) { exit 0 }
    exit 1
}
if ($RequireTargetAcceptance) {
    Write-Output "TARGET OPERATION ACCEPTANCE: $($evidence.target_operation_acceptance); reviewed exclusions=$($evidence.excluded_obligations.Count); full M3 acceptance=False"
    if ($evidence.target_operation_acceptance) { exit 0 }
    exit 1
}
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
