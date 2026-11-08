param(
    [Parameter(Mandatory)][string]$Compiler,
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [string]$OutputDirectory=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$compilerPath=(Resolve-Path -LiteralPath $Compiler).Path
$libraryPath=(Resolve-Path -LiteralPath $LibraryDirectory).Path
if($OutputDirectory -eq ''){
    $OutputDirectory=Join-Path $root ('reports/native-allocator-observer/'+[guid]::NewGuid().ToString('N'))
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$suffix=if($IsWindows){'.exe'}else{''}
$exe=Join-Path $OutputDirectory ('allocator_observer_probe'+$suffix)
$arguments=@('-std=c99','-Wall','-Wextra','-Werror','-pedantic')
if($IsWindows){$arguments+='-DLUA_BUILD_AS_DLL'}
$arguments+='-DLUA_USER_H=<ltests.h>'
if($IsWindows){
    # Only Windows needs explicit imported-data declarations. Forcing this
    # header on POSIX also reads system headers before the probe's GNU feature
    # selection, hiding dladdr/Dl_info in a strict C99 build.
    $arguments+=@('-include',(Join-Path $root 'experiments/conformance/c/conformance_exports.h'))
}
$arguments+=@(
    ('-I'+(Join-Path $root 'references/lua')),
    (Join-Path $root 'experiments/conformance/c/allocator_observer_probe.c'),
    ('-L'+$libraryPath),'-lconformance_lua','-o',$exe)
if(-not $IsWindows){
    # Resolve the real shared data address through the GOT. A non-PIC Linux
    # executable may otherwise create a copy relocation for l_memcontrol.
    $arguments+='-fPIC'
}
if($IsLinux){$arguments+='-ldl'}
$build=Invoke-ConformanceProcess -Executable $compilerPath -Arguments $arguments -Directory $root `
    -OutputPrefix (Join-Path $OutputDirectory 'compile') -TimeoutSeconds 120
if($build.exit_code -ne 0 -or $build.stderr_bytes -ne 0 -or $build.timed_out -or
    $build.capture_exceeded -or $build.pipe_drain_failed -or $build.abnormal_exit_kind){
    throw 'Strict native allocator observer compilation failed'
}
$environment=@{LUA_ADA_CONFORMANCE_ALLOCATOR='67108864';MEMLIMIT='2147483648'}
$loader=if($IsWindows){'PATH'}elseif($IsMacOS){'DYLD_LIBRARY_PATH'}else{'LD_LIBRARY_PATH'}
$environment[$loader]=$libraryPath+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($loader)
$run=Invoke-ConformanceProcess -Executable $exe -Arguments @() -Directory $root `
    -OutputPrefix (Join-Path $OutputDirectory 'execute') -TimeoutSeconds 120 -Environment $environment
$expected=@(
    'real debug allocator identity',
    'fail-next leaves the old block intact',
    'count refusal before backing allocation',
    'byte refusal before backing allocation',
    'backing refusal counted once in both views',
    'successful growth and free are not refusals',
    'original teardown and zero ownership')
$stdout=[IO.File]::ReadAllText($run.stdout_path).Replace("`r`n","`n")
$lines=$stdout.Split("`n")
if($lines[0] -cnotmatch '^ALLOCATOR OBSERVER RUNTIME: (.+)$'){
    throw 'Actual native allocator observer did not identify its loaded runtime'
}
$loadedPath=(Resolve-Path -LiteralPath $Matches[1]).Path
$loadedDirectory=Split-Path -Parent $loadedPath
$pathComparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
if(-not [string]::Equals($loadedDirectory,$libraryPath,$pathComparison)){
    throw 'Actual native allocator observer loaded a different runtime directory'
}
$expectedRuntime=if($IsWindows){'libconformance_lua.dll'}elseif($IsMacOS){'libconformance_lua.dylib'}else{'libconformance_lua.so'}
if(-not [string]::Equals([IO.Path]::GetFileName($loadedPath),$expectedRuntime,$pathComparison)){
    throw 'Actual native allocator observer loaded an unexpected runtime image'
}
$loadedHash=(Get-FileHash -LiteralPath $loadedPath).Hash.ToLowerInvariant()
$stdout=($lines|Select-Object -Skip 1)-join "`n"
if($run.exit_code -ne 0 -or $run.stderr_bytes -ne 0 -or $run.timed_out -or
    $run.capture_exceeded -or $run.pipe_drain_failed -or $run.abnormal_exit_kind -or
    $stdout -cne (($expected|ForEach-Object{'ALLOCATOR OBSERVER PASS: '+$_}) -join "`n")+"`n"){
    throw 'Actual native allocator observer protocol failed'
}
$sources=@('experiments/conformance/c/allocator_observer_probe.c',
    'experiments/conformance/c/bounded_ltests.c','experiments/conformance/c/conformance_cli.c',
    'experiments/conformance/c/allocator_limit.h','experiments/conformance/c/conformance_exports.h',
    'references/lua/ltests.c','references/lua/ltests.h','references/lua/lua.h')
$result=@{schema_version=1;kind='native-allocator-observer-regressions';
    compiler=@{path=$compilerPath;sha256=(Get-FileHash $compilerPath).Hash.ToLowerInvariant()};
    library_directory=$libraryPath;compile=$build;process=$run;
    sources=@($sources|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}});
    libraries=@(Get-ChildItem -LiteralPath $libraryPath -File|ForEach-Object{@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}});
    loaded_runtime=@{path=$loadedPath;sha256=$loadedHash;identity_source='OS mapping of actual l_memcontrol data address'};
    runtime_acceptance=$false;coverage_authority=$false;loaded_runtime_linkage_verified=$true;
    scope='Actual observer unit protocol; final frozen-image linkage and whole-target acceptance remain separate.'}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'result.json'),
    ($result|ConvertTo-Json -Depth 32).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "PASS:7 actual native allocator observer regressions; $OutputDirectory"
