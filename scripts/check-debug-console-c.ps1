param(
    [Parameter(Mandatory)][string]$Interpreter,
    [Parameter(Mandatory)][string]$AdaConsumer,
    [Parameter(Mandatory)][string]$Compiler,
    [Parameter(Mandatory)][string]$ReferenceLibrary,
    [ValidateSet('default','upstream-test')][string]$Configuration='default',
    [string]$AdaRuntimeDirectory='',
    [string]$OutputDirectory=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$referenceRevision=(& git -C (Join-Path $root 'references/lua') rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $referenceRevision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294'){
    throw 'Debug console C campaign requires the pinned native source tree'
}
$revision=(& git -C $root rev-parse HEAD).Trim()
$changes=@(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if($LASTEXITCODE -ne 0){throw 'Cannot identify debug console C campaign source state'}
$compilerPath=(Resolve-Path -LiteralPath $Compiler).Path
$referenceDirectory=(Resolve-Path -LiteralPath $ReferenceLibrary).Path
if(-not (Test-Path -LiteralPath $referenceDirectory -PathType Container)){
    throw 'ReferenceLibrary must identify the selected native library directory'
}
if($OutputDirectory -eq ''){
    $OutputDirectory=Join-Path $root ('reports/debug-console-c/'+[guid]::NewGuid().ToString('N'))
}
if(Test-Path -LiteralPath $OutputDirectory){
    throw 'Debug console C output directory must be new; preserve previous observations'
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$sourceRoot=Join-Path $OutputDirectory 'sources'
$sourceNames=@('c_api/tests/builtin_api_contract.c','c_api/tests/consumer_allocator.h',
    'tests/c/argument_registry_callbacks.h','references/lua/lua.h',
    'references/lua/lauxlib.h','references/lua/lualib.h','references/lua/luaconf.h')
if($Configuration -ceq 'upstream-test'){$sourceNames+='references/lua/ltests.h'}
$sources=@(foreach($relative in $sourceNames){
    $from=Join-Path $root $relative
    $to=Join-Path $sourceRoot $relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
    [IO.File]::Copy($from,$to)
    @{path=$relative;sha256=(Get-FileHash -LiteralPath $from).Hash.ToLowerInvariant();
        snapshot_path=$to;snapshot_sha256=(Get-FileHash -LiteralPath $to).Hash.ToLowerInvariant()}
})
if(@($sources|Where-Object { $_.sha256 -cne $_.snapshot_sha256 }).Count){
    throw 'Debug console C source changed during its byte snapshot'
}
$modes=@('host','host-close','callback-close','callback-error')
$sourceText=[IO.File]::ReadAllText((Join-Path $sourceRoot 'c_api/tests/builtin_api_contract.c'))
foreach($mode in $modes){
    if(-not $sourceText.Contains('"--debug-console-'+$mode+'"',[StringComparison]::Ordinal)){
        throw "The actual selected C source lacks its debug console mode: $mode"
    }
}
$images=@()
function Copy-ImageFile([string]$From,[string]$To){
    $hash=(Get-FileHash -LiteralPath $From).Hash.ToLowerInvariant()
    if(Test-Path -LiteralPath $To){
        if((Get-FileHash -LiteralPath $To).Hash.ToLowerInvariant() -cne $hash){
            throw 'Debug console image dependency basename collision'
        }
    }else{[IO.File]::Copy($From,$To)}
    if((Get-FileHash -LiteralPath $To).Hash.ToLowerInvariant() -cne $hash){
        throw 'Debug console image changed during its byte snapshot'
    }
    $script:images+=@{source_path=$From;path=$To;sha256=$hash;bytes=(Get-Item -LiteralPath $To).Length}
}
function Copy-Libraries([string]$Directory,[string]$Destination){
    if($Directory -eq ''){return}
    foreach($file in Get-ChildItem -LiteralPath $Directory -File|
        Where-Object Name -Match '\.(?:dll|dylib|so(?:\.[0-9.]+)*|a)$'){
        Copy-ImageFile $file.FullName (Join-Path $Destination $file.Name)
    }
}
$nativeImage=Join-Path $OutputDirectory 'native/image'
$adaImage=Join-Path $OutputDirectory 'ada/image'
foreach($directory in @($nativeImage,$adaImage)){
    [void][IO.Directory]::CreateDirectory($directory)
}
$nativeInterpreter=Join-Path $nativeImage ([IO.Path]::GetFileName($Interpreter))
$adaExecutable=Join-Path $adaImage ([IO.Path]::GetFileName($AdaConsumer))
Copy-ImageFile (Resolve-Path -LiteralPath $Interpreter).Path $nativeInterpreter
Copy-ImageFile (Resolve-Path -LiteralPath $AdaConsumer).Path $adaExecutable
Copy-Libraries $referenceDirectory $nativeImage
Copy-Libraries $AdaRuntimeDirectory $adaImage
# Selected compiler support libraries are frozen too. No ambient PATH folder
# supplies a substitute named dependency. The loader still retains its normal
# system search tail, while these exact image files have first precedence.
foreach($directory in @($nativeImage,$adaImage)){
    Copy-Libraries (Split-Path -Parent $compilerPath) $directory
}
$suffix=if($IsWindows){'.exe'}else{''}
$nativeExecutable=Join-Path $nativeImage ('builtin_api_contract'+$suffix)
$compileArguments=@('-std=c99','-Wall','-Wextra','-Werror','-pedantic')
if($Configuration -ceq 'upstream-test'){
    # Use the real pinned test header's luaL_newstate macro so native T gets
    # debug_realloc/l_memcontrol, rather than the ordinary SDK constructor.
    # Ada remains its separately built public SDK consumer; no C private
    # interpreter header or debug allocator is linked into the Ada runtime.
    $compileArguments+='-DLUA_USER_H=<ltests.h>'
}
if($IsWindows){$compileArguments+='-DLUA_BUILD_AS_DLL'}
elseif($IsMacOS){$compileArguments+='-DLUA_USE_MACOSX'}
else{$compileArguments+='-DLUA_USE_LINUX'}
if(-not $IsWindows){
    # The actual T constructor takes &l_memcontrol from the shared oracle.
    # Resolve data through the GOT, avoiding an executable copy relocation.
    $compileArguments+='-fPIC'
}
$compileArguments+=@(('-I'+(Join-Path $sourceRoot 'references/lua')),
    (Join-Path $sourceRoot 'c_api/tests/builtin_api_contract.c'),
    ('-L'+$nativeImage),'-lconformance_lua','-lm','-o',$nativeExecutable)
$loader=if($IsWindows){'PATH'}elseif($IsMacOS){'DYLD_LIBRARY_PATH'}else{'LD_LIBRARY_PATH'}
function Environment-For([string]$Directory){
    $environment=@{}
    $environment[$loader]=$Directory+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($loader)
    return $environment
}
function Assert-Completed($Process,[string]$Name){
    if($Process.exit_code -ne 0 -or $Process.timed_out -or $Process.capture_exceeded -or
        $Process.pipe_drain_failed -or $Process.process_tree_kill_error -or $Process.abnormal_exit_kind){
        throw "Debug console C operation failed: $Name; $OutputDirectory"
    }
}
$processes=@();$compile=$null;$probe=$null;$comparisonComplete=$false
try{
    $compile=Invoke-ConformanceProcess -Executable $compilerPath -Arguments $compileArguments -Directory $root `
        -OutputPrefix (Join-Path $OutputDirectory 'compile') -TimeoutSeconds 120
    Assert-Completed $compile 'strict same-source native compilation'
    if($compile.stderr_bytes -ne 0){throw 'Debug console C strict compilation emitted diagnostics'}
    $images+=@{source_path=$nativeExecutable;path=$nativeExecutable;
        sha256=(Get-FileHash $nativeExecutable).Hash.ToLowerInvariant();bytes=(Get-Item $nativeExecutable).Length}
    $condition=if($Configuration -ceq 'upstream-test'){
        "type(T)=='table' and type(T.totalmem)=='function'"
    }else{'T==nil'}
    $probeCode="assert($condition);io.write('DEBUG CONSOLE C CONFIG $Configuration\n')"
    $probe=Invoke-ConformanceProcess -Executable $nativeInterpreter -Arguments @('-e',$probeCode) -Directory $root `
        -OutputPrefix (Join-Path $OutputDirectory 'native-config') -TimeoutSeconds 30 -Environment (Environment-For $nativeImage)
    Assert-Completed $probe 'actual native configuration probe'
    $newline=if($IsWindows){"`r`n"}else{"`n"}
    $expectedProbe=[Text.Encoding]::ASCII.GetBytes("DEBUG CONSOLE C CONFIG $Configuration"+$newline)
    if($probe.stderr_bytes -ne 0 -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($probe.stdout_path)) -cne
        [Convert]::ToBase64String($expectedProbe)){
        throw 'Debug console C actual oracle configuration differs'
    }
    # The first command must see the initial C-slot object alive. C db_debug's
    # actual lua_settop(L,0) after that command closes/removes its final root;
    # the second collection must reclaim it. A throwing closer exits after
    # the first command and is caught by the real outer C lua_pcall instead.
    $inputBytes=[Text.UTF8Encoding]::new($false).GetBytes(
        "collectgarbage();assert(watch[1]~=nil)`ncollectgarbage();assert(watch[1]==nil)`ncont`n")
    foreach($mode in $modes){
        foreach($role in @('native','ada')){
            $directory=Join-Path $OutputDirectory ($role+'/'+$mode)
            [void][IO.Directory]::CreateDirectory($directory)
            $stdin=Join-Path $directory 'stdin'
            [IO.File]::WriteAllBytes($stdin,$inputBytes)
            $executable=if($role -ceq 'native'){$nativeExecutable}else{$adaExecutable}
            $image=if($role -ceq 'native'){$nativeImage}else{$adaImage}
            $process=Invoke-ConformanceProcess -Executable $executable -Arguments @('--debug-console-'+$mode) `
                -Directory $directory -OutputPrefix (Join-Path $directory 'process') -TimeoutSeconds 30 `
                -StandardInputPath $stdin -Environment (Environment-For $image)
            $processes+=@{role=$role;mode=$mode;process=$process;stdin=@{path=$stdin;
                sha256=(Get-FileHash $stdin).Hash.ToLowerInvariant();bytes=$inputBytes.Length}}
        }
    }
    foreach($mode in $modes){
        $pair=@($processes|Where-Object mode -CEQ $mode)
        foreach($row in $pair){
            Assert-Completed $row.process ($row.role+'/'+$mode)
            $input=$row.process.standard_input
            if($input.sha256 -cne $row.stdin.sha256 -or $input.bytes -ne $inputBytes.Length -or
                -not $input.write_completed -or -not $input.eof_sent -or -not $input.close_requested){
                throw "Debug console C captured input delivery differs: $($row.role)/$mode"
            }
            $expected=[Text.Encoding]::ASCII.GetBytes("PASS: builtin-debug-console-$mode"+$newline+
                'PASS: public builtin contract'+$newline)
            if([Convert]::ToBase64String([IO.File]::ReadAllBytes($row.process.stdout_path)) -cne
                [Convert]::ToBase64String($expected)){
                throw "Debug console C named completion differs: $($row.role)/$mode"
            }
        }
        foreach($stream in @('stdout','stderr')){
            $left=[IO.File]::ReadAllBytes($pair[0].process[$stream+'_path'])
            $right=[IO.File]::ReadAllBytes($pair[1].process[$stream+'_path'])
            if([Convert]::ToBase64String($left) -cne [Convert]::ToBase64String($right)){
                throw "Debug console C raw $stream differs: $mode"
            }
        }
        Write-Output "DEBUG CONSOLE C PASS: $mode"
    }
    $comparisonComplete=$true
}finally{
    # Failure observations survive too. Console modes use luaL_newstate on
    # both sides, including native T's required debug allocator. The consumer
    # intentionally does not report its otherwise unused custom counts as a
    # console allocator/cleanup witness, and this report invents none.
    $result=@{schema_version=1;kind='debug-console-c-process-regressions';configuration=$Configuration;
        repository_revision=$revision;repository_dirty=($changes.Count -ne 0);reference_revision=$referenceRevision;
        synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
        comparison_complete=$comparisonComplete;source_repository_root=$root;sources=$sources;
        harness_sources=@(foreach($file in @('scripts/check-debug-console-c.ps1','scripts/ConformanceRunner.psm1')){
            @{path=$file;sha256=(Get-FileHash (Join-Path $root $file)).Hash.ToLowerInvariant()}});
        compiler=@{path=$compilerPath;sha256=(Get-FileHash $compilerPath).Hash.ToLowerInvariant()};
        native_header_role=$(if($Configuration -ceq 'upstream-test'){'pinned-native-private-test-header'}else{'pinned-native-public-sdk'});
        ada_consumer_source_build_verified=$false;
        compile=$compile;configuration_probe=$probe;images=$images;processes=$processes;
        scope='Four actual same-source C direct-console protocols; no allocator-balance or final-context acceptance authority.'}
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'result.json'),
        ($result|ConvertTo-Json -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
}
Write-Output "PASS:4 actual paired C debug console cases; $OutputDirectory"
