param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('development', 'validation', 'release')]
    [string] $Profile = 'validation',
    [ValidateSet('default', 'upstream-test')]
    [string] $Configuration = 'default',
    [switch] $UseExistingRuntime,
    [ValidateSet('','remaining-upstream-compatibility')][string] $TargetPolicy = ''
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
    param([string] $Name, [string] $Executable, [string] $Marker,
        [string[]] $ConsumerArguments = @())
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
    foreach ($argument in $ConsumerArguments) { $start.ArgumentList.Add($argument) }
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
        arguments = $ConsumerArguments;
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
    # A dependency build in tests/ can generate the requested root profile
    # without selecting the root crate's own remembered profile. Select that
    # profile explicitly even when importing an existing SAL. Alire's generation
    # stop precedes all compiler/linker/binder work; never edit generated files.
    $runtimeDirectory = Join-Path $projectRoot "lib/$configurationPart$Profile/$LibraryType"
    $imageName = if ($LibraryType -ne 'relocatable') { 'liblua.a' }
        elseif ($IsWindows) { 'liblua.dll' } elseif ($IsMacOS) { 'liblua.dylib' } else { 'liblua.so' }
    $imagePath = Join-Path $runtimeDirectory $imageName
    if ($UseExistingRuntime) {
        # Capture before generation as well as before the consumer campaign:
        # configuration selection must preserve the exact prebuilt image too.
        $inputHash = (Get-FileHash -LiteralPath $imagePath).Hash
        Invoke-Build @('-n', 'build', "--$Profile", '--stop-after=generation')
        if ((Get-FileHash -LiteralPath $imagePath).Hash -cne $inputHash) {
            throw 'Profile generation changed the selected runtime image'
        }
    } else {
        Invoke-Build (@('-n', 'build', "--$Profile", '--', '-XLUA_ADA_PREBUILT=false') + $scenarios)
        $inputHash = (Get-FileHash -LiteralPath $imagePath).Hash
    }
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
    Invoke-Consumer 'load-dump-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/load_dump_api_contract$suffix") 'PASS: public reader/writer contract'
    Invoke-Consumer 'debug-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/debug_api_contract$suffix") 'PASS: public debug contract'
    Invoke-Consumer 'builtin-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/builtin_api_contract$suffix") 'PASS: public builtin contract'
    # The pinned T lock instrumentation itself aborts deallocator API reentry.
    # Keep that observed native limit explicit: ownership/refusal still run in
    # both configurations; ordinary C/Ada reentry is paired in default only.
    $externalArguments = $(if ($Configuration -eq 'upstream-test') {
        @('--ownership-only')
    } else { @() })
    Invoke-Consumer 'external-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/external_string_contract$suffix") 'PASS: public external string contract' $externalArguments
    Invoke-Consumer 'conversion-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/conversion_api_contract$suffix") 'PASS: public numeric conversion contract'
    if($TargetPolicy -ne ''){
        Invoke-Consumer 'format-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/format_api_contract$suffix") 'PASS: public formatting contract'
    }
    Invoke-Consumer 'operator-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/operator_api_contract$suffix") 'PASS: public C operator contract'
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
    $referenceLoadDumpConsumer = Join-Path $reportDirectory "load-dump-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/load_dump_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceLoadDumpConsumer)
    $adaExecutionLdPath = $env:LD_LIBRARY_PATH
    $referenceDebugConsumer = Join-Path $reportDirectory "debug-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/debug_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceDebugConsumer)
    $adaExecutionDyldPath = $env:DYLD_LIBRARY_PATH
    $referenceBuiltinConsumer = Join-Path $reportDirectory "builtin-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/builtin_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceBuiltinConsumer)
    $referenceExternalConsumer = Join-Path $reportDirectory "external-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/external_string_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceExternalConsumer)
    $referenceConversionConsumer = Join-Path $reportDirectory "conversion-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/conversion_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceConversionConsumer)
    $referenceFormatConsumer=$null
    if($TargetPolicy -ne ''){
        $referenceFormatConsumer=Join-Path $reportDirectory "format-oracle$suffix"
        Invoke-Build @('exec','--','gcc','-std=c99','-Wall','-Wextra','-Werror','-pedantic',
            '-I',(Join-Path $projectRoot 'c_api/include/api'),(Join-Path $projectRoot 'c_api/tests/format_api_contract.c'),
            '-L',$referenceDirectory,'-lconformance_lua','-lm','-o',$referenceFormatConsumer)
    }
    $referenceOperatorConsumer = Join-Path $reportDirectory "operator-oracle$suffix"
    Invoke-Build @('exec', '--', 'gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-pedantic',
        '-I', (Join-Path $projectRoot 'c_api/include/api'),
        (Join-Path $projectRoot 'c_api/tests/operator_api_contract.c'),
        '-L', $referenceDirectory, '-lconformance_lua', '-lm', '-o', $referenceOperatorConsumer)
    try {
        $env:PATH = $referenceDirectory + [IO.Path]::PathSeparator + $env:PATH
        $env:LD_LIBRARY_PATH = $referenceDirectory + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
        $env:DYLD_LIBRARY_PATH = $referenceDirectory + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
        Invoke-Consumer 'gc-oracle' $referenceConsumer 'PASS: public GC contract'
        Invoke-Consumer 'io-oracle' $referenceIOConsumer 'PASS: public IO/OS contract'
        Invoke-Consumer 'foreign-oracle' $referenceForeignConsumer 'PASS: public foreign contract'
        Invoke-Consumer 'load-dump-oracle' $referenceLoadDumpConsumer 'PASS: public reader/writer contract'
        Invoke-Consumer 'debug-oracle' $referenceDebugConsumer 'PASS: public debug contract'
        Invoke-Consumer 'builtin-oracle' $referenceBuiltinConsumer 'PASS: public builtin contract'
        Invoke-Consumer 'external-oracle' $referenceExternalConsumer 'PASS: public external string contract' $externalArguments
        Invoke-Consumer 'conversion-oracle' $referenceConversionConsumer 'PASS: public numeric conversion contract'
        if($TargetPolicy -ne ''){Invoke-Consumer 'format-oracle' $referenceFormatConsumer 'PASS: public formatting contract'}
        Invoke-Consumer 'operator-oracle' $referenceOperatorConsumer 'PASS: public C operator contract'
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
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'load-dump-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'load-dump-oracle.stdout'))) {
        throw 'C/Ada public reader/writer contract output differs'
    }
    Write-Output 'PASS: identical public reader/writer contract against C and Ada'
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'debug-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'debug-oracle.stdout'))) {
        throw 'C/Ada public debug contract output differs'
    }
    Write-Output 'PASS: identical public debug contract against C and Ada'
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'builtin-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'builtin-oracle.stdout'))) {
        throw 'C/Ada public builtin contract output differs'
    }
    Write-Output 'PASS: identical public builtin contract against C and Ada'
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'external-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'external-oracle.stdout'))) {
        throw 'C/Ada public external string contract output differs'
    }
    Write-Output 'PASS: identical scoped external string contract against C and Ada'
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'conversion-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'conversion-oracle.stdout'))) {
        throw 'C/Ada public numeric conversion contract output differs'
    }
    Write-Output 'PASS: identical public numeric conversion contract against C and Ada'
    if($TargetPolicy -ne ''){
        if([IO.File]::ReadAllText((Join-Path $reportDirectory 'format-api.stdout')) -cne
            [IO.File]::ReadAllText((Join-Path $reportDirectory 'format-oracle.stdout'))){throw 'C/Ada public formatting contract output differs'}
        Write-Output 'PASS: identical public formatting contract against C and Ada'
    }
    if ([IO.File]::ReadAllText((Join-Path $reportDirectory 'operator-api.stdout')) -cne
        [IO.File]::ReadAllText((Join-Path $reportDirectory 'operator-oracle.stdout'))) {
        throw 'C/Ada public operator contract output differs'
    }
    Write-Output 'PASS: identical public C operator contract against C and Ada'
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
    $loadDumpContractSources = @(foreach ($name in @('load_dump_api_contract.c',
        'load_dump_contract.h', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $debugContractSources = @(foreach ($name in @('debug_api_contract.c', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $builtinContractSources = @(foreach ($name in @('builtin_api_contract.c', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $externalContractSources = @(foreach ($name in @('external_string_contract.c', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $conversionContractSources = @(foreach ($name in @('conversion_api_contract.c', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $formatSources=@()
    if($TargetPolicy -ne ''){
        $formatSources=@(foreach($name in @('format_api_contract.c','consumer_allocator.h')){
            @{file="c_api/tests/$name";sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name")).Hash.ToLowerInvariant()}
        })
    }
    $operatorContractSources = @(foreach ($name in @('operator_api_contract.c', 'consumer_allocator.h')) {
        [ordered]@{ file="c_api/tests/$name";
            sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
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
    $consumerSourceNames=@('c_api_consumer.c', 'gc_contract.h', 'io_contract.h', 'load_dump_contract.h', 'consumer_allocator.h')
    if($TargetPolicy -ne ''){$consumerSourceNames+='format_api_contract.c'}
    [ordered]@{ profile = $Profile; library_type = $LibraryType;
        repository_revision = $repositoryRevision;
        repository_dirty = ($repositoryChanges.Count -ne 0);
        platform = $(if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' });
        reference_revision = $referenceRevision;
        consumer_sources = @(@(foreach ($name in $consumerSourceNames) {
            [ordered]@{ file="c_api/tests/$name";
                sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot "c_api/tests/$name") -Algorithm SHA256).Hash.ToLowerInvariant() }
        }) + $foreignContractSources + $debugContractSources + $builtinContractSources + $externalContractSources + $conversionContractSources + $operatorContractSources);
        configuration = $Configuration; consumers = $records.ToArray();
        library_files = $libraries;
        gc_contract = [ordered]@{ matching_output=$true; sources=$contractSources;
            reference_library_files=$referenceLibraries };
        io_contract = [ordered]@{ matching_output=$true; sources=$ioContractSources;
            reference_library_files=$referenceLibraries };
        foreign_contract = [ordered]@{ matching_output=$true; sources=$foreignContractSources;
            reference_library_files=$referenceLibraries };
        load_dump_contract = [ordered]@{ matching_output=$true; sources=$loadDumpContractSources;
            reference_library_files=$referenceLibraries };
        debug_contract = [ordered]@{ matching_output=$true; sources=$debugContractSources;
            reference_library_files=$referenceLibraries };
        builtin_contract = [ordered]@{ matching_output=$true; sources=$builtinContractSources;
            reference_library_files=$referenceLibraries };
        external_contract = [ordered]@{ matching_output=$true; sources=$externalContractSources;
            matched_cases=$(if ($Configuration -eq 'upstream-test') { 13 } else { 18 });
            skipped_reentry_cases=$(if ($Configuration -eq 'upstream-test') { 5 } else { 0 });
            reference_library_files=$referenceLibraries };
        conversion_contract = [ordered]@{ matching_output=$true; sources=$conversionContractSources;
            reference_library_files=$referenceLibraries };
        format_contract=$(if($TargetPolicy -ne ''){@{matching_output=$true;sources=$formatSources;reference_library_files=$referenceLibraries}}else{$null});
        operator_contract = [ordered]@{ matching_output=$true; sources=$operatorContractSources;
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
