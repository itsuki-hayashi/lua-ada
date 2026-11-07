param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('development', 'validation', 'release')]
    [string] $Profile = 'validation',
    [ValidateSet('default', 'upstream-test')]
    [string] $Configuration = 'default',
    [switch] $UseExistingRuntime
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$savedPath = $env:PATH
$savedLdPath = $env:LD_LIBRARY_PATH
$savedDyldPath = $env:DYLD_LIBRARY_PATH
$savedArchive = $env:LUA_ADA_ABI_RUNTIME_ARCHIVE
$savedTaskingArchive = $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE
$savedRuntimeDirectory = $env:LUA_ADA_RUNTIME_LIBRARY_DIR
$configurationPart = if ($Configuration -eq 'default') { '' } else { 'upstream-test/' }
$reportDirectory = Join-Path $projectRoot ('reports/core-image/' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $reportDirectory -Force
$records = [Collections.Generic.List[object]]::new()
$scenarios = @("-XLUA_ADA_LIBRARY_TYPE=$LibraryType",
    "-XLUA_ADA_CONFIGURATION=$Configuration")
Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PEUnwind.psm1') -Force

function Invoke-Build {
    param([string[]] $Arguments)
    & alr @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Core-image build failed: $($Arguments -join ' ')" }
}

function Invoke-Consumer {
    param([string] $Name, [string] $Executable, [string] $Marker)
    $unwind = $null
    if ($IsWindows) {
        # The final image, rather than an intermediate object or successful
        # linker exit, must contain disjoint x64 RUNTIME_FUNCTION intervals.
        # Preserve the structural evidence beside the actual process capture.
        $unwind = Test-PEUnwindTable -Path $Executable
        $unwind | ConvertTo-Json | Set-Content -LiteralPath (
            Join-Path $reportDirectory "$Name.unwind.json") -Encoding utf8
        Write-Output "PASS: $Name PE unwind table ($($unwind.Entries) entries)"
    }
    # Redirect both pipes before waiting so even an unexpected diagnostic flood
    # cannot deadlock the driver. Empty stderr is part of this consumer contract.
    $start = [Diagnostics.ProcessStartInfo]::new('alr')
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('exec', '--', $Executable)) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "Cannot start $Name consumer" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(60000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $reportDirectory "$Name.stdout"), $stdout)
    [IO.File]::WriteAllText((Join-Path $reportDirectory "$Name.stderr"), $stderr)
    $record = [ordered]@{ name = $Name; executable = $Executable;
        executable_sha256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant();
        stdout = (Join-Path $reportDirectory "$Name.stdout");
        stdout_sha256 = (Get-FileHash -LiteralPath (Join-Path $reportDirectory "$Name.stdout") -Algorithm SHA256).Hash.ToLowerInvariant();
        stderr = (Join-Path $reportDirectory "$Name.stderr");
        stderr_sha256 = (Get-FileHash -LiteralPath (Join-Path $reportDirectory "$Name.stderr") -Algorithm SHA256).Hash.ToLowerInvariant();
        exit_code = $process.ExitCode; timed_out = $timedOut;
        profile = $Profile; library_type = $LibraryType;
        configuration = $Configuration;
        pe_unwind_entries = $(if ($null -eq $unwind) { $null } else { $unwind.Entries }) }
    $records.Add($record)
    if ($timedOut -or $process.ExitCode -ne 0 -or $stderr.Length -ne 0 -or
        -not $stdout.Contains($Marker)) {
        # Captures must also be visible in the job log when a build fails
        # before later campaigns. Do not hide the actual loader/assertion
        # diagnostic behind a report path that CI may not yet have uploaded.
        [Console]::Error.WriteLine("Core-image child $Name exited $($process.ExitCode); timed_out=$timedOut")
        [Console]::Error.WriteLine("--- captured stdout ---`n$stdout")
        [Console]::Error.WriteLine("--- captured stderr ---`n$stderr")
        throw "Core-image consumer failed: $Name; see $reportDirectory"
    }
    Write-Output "PASS: $Name ($Profile/$LibraryType/$Configuration)"
    $process.Dispose()
}

try {
    Set-Location $projectRoot
    # Bind captured cases to the source tree that produced this campaign.
    # Dirty runs remain useful diagnostics but cannot supply final acceptance.
    $repositoryRevision = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify consumer source revision' }
    $repositoryChanges = @(& git -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect consumer source state' }
    $referenceRevision = (& git -C references/lua rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify consumer reference revision' }
    $adaRuntimeDirectory = ''
    if ($IsMacOS) {
        $runtime = Get-SelectedAdaRuntime
        $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $runtime.CoreArchive
        $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $runtime.TaskingArchive
        $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $runtime.Directory
        $adaRuntimeDirectory = $runtime.Directory + [IO.Path]::PathSeparator
    }
    # Select the requested generated profile through Alire, never by editing
    # generated configuration. All subsequent projects import this same root.
    $runtimeDirectory = Join-Path $projectRoot "lib/$configurationPart$Profile/$LibraryType"
    if (-not $UseExistingRuntime) {
        Invoke-Build (@('-n', 'build', "--$Profile", '--', '-XLUA_ADA_PREBUILT=false') + $scenarios)
    }
    $imageName = if ($LibraryType -ne 'relocatable') { 'liblua.a' }
        elseif ($IsWindows) { 'liblua.dll' } elseif ($IsMacOS) { 'liblua.dylib' } else { 'liblua.so' }
    $imagePath = Join-Path $runtimeDirectory $imageName
    $inputHash = (Get-FileHash -LiteralPath $imagePath).Hash
    # The consumers import the already compiled SAL. A fresh gprlib bind would
    # give the C cases another archive/shared object even at the same revision.
    $consumerScenarios = $scenarios + @('-XLUA_ADA_PREBUILT=true')
    Invoke-Build (@('exec', '--', 'gprbuild', '-P', 'c_api/consumer.gpr', '-p') + $consumerScenarios)
    Invoke-Build (@('exec', '--', 'gprbuild', '-P', 'c_api/image_consumer.gpr', '-p') + $consumerScenarios)
    if ((Get-FileHash -LiteralPath $imagePath).Hash -cne $inputHash) {
        throw 'Consumer build changed the selected runtime image'
    }
    $env:PATH = $runtimeDirectory + [IO.Path]::PathSeparator + $savedPath
    $env:LD_LIBRARY_PATH = $runtimeDirectory + [IO.Path]::PathSeparator + $savedLdPath
    $env:DYLD_LIBRARY_PATH = $runtimeDirectory + [IO.Path]::PathSeparator + $adaRuntimeDirectory + $savedDyldPath
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    if ($IsWindows -and $LibraryType -eq 'relocatable') {
        # The callback code lives in the DLL for shared consumers, so checking
        # only the small importing executable would miss the broken metadata.
        $images = @(Get-ChildItem -LiteralPath $runtimeDirectory -File |
            Where-Object { $_.Name -match '^(lib)?lua\.dll$' })
        if ($images.Count -ne 1) { throw 'Selected lua DLL is absent or ambiguous' }
        $dllUnwind = Test-PEUnwindTable -Path $images[0].FullName
        $dllUnwind | ConvertTo-Json | Set-Content -LiteralPath (
            Join-Path $reportDirectory 'library.unwind.json') -Encoding utf8
        Write-Output "PASS: shared lua PE unwind table ($($dllUnwind.Entries) entries)"
    }
    Invoke-Consumer 'c-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/c_api_consumer$suffix") 'PASS: real Ada C API bootstrap consumer'
    Invoke-Consumer 'gc-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/gc_api_contract$suffix") 'PASS: public GC contract'
    Invoke-Consumer 'io-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/io_api_contract$suffix") 'PASS: public IO/OS contract'
    Invoke-Consumer 'foreign-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/foreign_api_contract$suffix") 'PASS: public foreign contract'
    # Compile the identical public-header contract against the isolated pinned
    # C library. No reference object is linked into either Ada consumer.
    Invoke-Build @('exec', '--', 'gprbuild', '-P', 'experiments/conformance/reference.gpr', '-p', "-XLUA_CONFORMANCE_CONFIGURATION=$Configuration")
    $referenceDirectory = Join-Path $projectRoot "build/conformance/$Configuration/lib"
    $referenceConsumer = Join-Path $reportDirectory "gc-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/gc_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceConsumer)
    $referenceIOConsumer = Join-Path $reportDirectory "io-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/io_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceIOConsumer)
    $adaExecutionPath = $env:PATH
    $referenceForeignConsumer = Join-Path $reportDirectory "foreign-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/foreign_api_contract.c'),
        (Join-Path $projectRoot 'tests/c/foreign_continuation_contract.c'),
        (Join-Path $projectRoot 'tests/c/foreign_hook_contract.c'),
        (Join-Path $projectRoot 'tests/c/math_reopen_contract.c'),
        (Join-Path $projectRoot 'tests/c/library_opener_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceForeignConsumer)
    $adaExecutionLdPath = $env:LD_LIBRARY_PATH
    $adaExecutionDyldPath = $env:DYLD_LIBRARY_PATH
    try {
        $env:PATH = $referenceDirectory + [IO.Path]::PathSeparator + $env:PATH
        $env:LD_LIBRARY_PATH = $referenceDirectory + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $env:DYLD_LIBRARY_PATH = $referenceDirectory + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
        Invoke-Consumer 'gc-oracle' $referenceConsumer 'PASS: public GC contract'
        Invoke-Consumer 'io-oracle' $referenceIOConsumer 'PASS: public IO/OS contract'
        Invoke-Consumer 'foreign-oracle' $referenceForeignConsumer 'PASS: public foreign contract'
    } finally {
        $env:PATH = $adaExecutionPath
        $env:LD_LIBRARY_PATH = $adaExecutionLdPath
        $env:DYLD_LIBRARY_PATH = $adaExecutionDyldPath
    }
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'gc-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'gc-oracle.stdout'))) {
        throw 'C/Ada public GC contract output differs'
    }
    Write-Output 'PASS: identical public GC contract against C and Ada'
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'io-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'io-oracle.stdout'))) {
        throw 'C/Ada public IO/OS contract output differs'
    }
    Write-Output 'PASS: identical public IO/OS contract against C and Ada'
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'foreign-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'foreign-oracle.stdout'))) {
        throw 'C/Ada public foreign contract output differs'
    }
    Write-Output 'PASS: identical public foreign contract against C and Ada'
    $referenceLibraries = @(Get-ChildItem -LiteralPath $referenceDirectory -File |
        Where-Object { $_.Name -match '^libconformance_lua\.(dll|so(\.[0-9.]+)?|dylib)$' } |
        ForEach-Object { [ordered]@{ file=$_.Name;
            sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
    if ($referenceLibraries.Count -eq 0) { throw 'Reference GC library hash is missing' }
    $contractSources = @(foreach ($name in @('gc_api_contract.c', 'gc_contract.h', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $ioContractSources = @(foreach ($name in @('io_api_contract.c', 'io_contract.h', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $foreignContractSources = @(foreach ($name in @('c_api/tests/foreign_api_contract.c',
        'tests/c/foreign_continuation_contract.c', 'tests/c/foreign_hook_contract.c',
        'tests/c/math_reopen_contract.c', 'tests/c/library_opener_contract.c')) {
        [ordered]@{ file=$name;
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    Invoke-Consumer 'mixed' (Join-Path $projectRoot "build/c-api/image/bin/$configurationPart$Profile/$LibraryType/lua-core_image_check$suffix") 'CORE IMAGE ADA+C OK'
    Invoke-Consumer 'c-startup' (Join-Path $projectRoot "build/c-api/image/bin/$configurationPart$Profile/$LibraryType/c_image_client$suffix") 'CORE IMAGE C STARTUP OK'
    # Old ignored products can remain after the library rename. Hash only the
    # selected lua image, never stale lua_ada archives or unrelated ALI files.
    $libraries = @(Get-ChildItem -LiteralPath $runtimeDirectory -File |
        Where-Object { $_.Name -match '^(lib)?lua(\.dll(\.a)?|\.a|\.so(\.[0-9.]+)?|\.dylib)$' } |
        ForEach-Object {
        [ordered]@{ file = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    if ($libraries.Count -eq 0) { throw 'Selected root lua image is absent' }
    if ((Get-FileHash -LiteralPath $imagePath).Hash -cne $inputHash) {
        throw 'Consumer execution changed the selected runtime image'
    }
    [ordered]@{ profile = $Profile; library_type = $LibraryType;
        repository_revision = $repositoryRevision;
        repository_dirty = ($repositoryChanges.Count -ne 0);
        platform = $(if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' });
        reference_revision = $referenceRevision;
        consumer_sources = @(@(foreach ($name in @('c_api_consumer.c', 'gc_contract.h', 'io_contract.h', 'consumer_allocator.h')) {
            [ordered]@{ file="c_api/tests/$name";
                sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
        }) + $foreignContractSources);
        configuration = $Configuration; consumers = $records.ToArray();
        library_files = $libraries;
        gc_contract = [ordered]@{ matching_output=$true; sources=$contractSources;
            reference_library_files=$referenceLibraries };
        io_contract = [ordered]@{ matching_output=$true; sources=$ioContractSources;
            reference_library_files=$referenceLibraries };
        foreign_contract = [ordered]@{ matching_output=$true; sources=$foreignContractSources;
            reference_library_files=$referenceLibraries } } | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $reportDirectory 'result.json') -Encoding utf8
    Write-Output 'PASS: one production interpreter image; Ada/C state, pool, allocator and startup checks'
}
finally {
    # Even a failed run retains which processes actually ran. A missing result
    # file is a failed/incomplete campaign, never a successful skipped consumer.
    $records.ToArray() | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $reportDirectory 'processes.json') -Encoding utf8
    Set-Location $originalLocation
    $env:PATH = $savedPath
    $env:LD_LIBRARY_PATH = $savedLdPath
    $env:DYLD_LIBRARY_PATH = $savedDyldPath
    $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $savedArchive
    $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE = $savedTaskingArchive
    $env:LUA_ADA_RUNTIME_LIBRARY_DIR = $savedRuntimeDirectory
}
exit 0
