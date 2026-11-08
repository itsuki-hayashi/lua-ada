Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetHostCampaignContracts.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetHostCampaignEvidence.psm1')
$temporary=Join-Path $root ('reports/host-campaign-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8=[Text.UTF8Encoding]::new($false);$revision=(&git -C $root rev-parse HEAD).Trim();$script:count=0
# These transport objects and tiny fake images are deliberately synthetic.
# No compiler, interpreter, C consumer or original upstream file is executed.
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function New-Fixture([string]$Kind){
    $payload=Join-Path $temporary ([guid]::NewGuid().ToString('N'));$script:files=@()
    $base='reports/target-builds/default-windows-validation-static/host-synthetic'
    $original=$root.Replace('\','/')+'/'+$base
    function File([string]$Relative,[byte[]]$Bytes){
        $path=Join-Path $payload $Relative;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllBytes($path,$Bytes);$hash=Hash $path
        $script:files+=@{path=$Relative;sha256=$hash;bytes=$Bytes.Length}
        return @{path=($root.Replace('\','/')+'/'+$Relative);sha256=$hash;bytes=$Bytes.Length}
    }
    function Text([string]$Relative,[string]$Value){File $Relative ($utf8.GetBytes($Value))}
    function Process([string]$Exe,[string]$Hash,[string[]]$Arguments,[string]$Relative,[string]$Stdout,[byte[]]$InputBytes,[string]$SourceName='stdin'){
        $out=Text ($Relative+'.stdout') $Stdout;$err=File ($Relative+'.stderr') ([byte[]]::new(0))
        $p=@{executable=$Exe;executable_sha256=$Hash;process_id=1000+$script:files.Count;arguments=@($Arguments);
            working_directory=($root.Replace('\','/')+'/'+($Relative.Substring(0,$Relative.LastIndexOf('/'))));
            started_utc=[DateTimeOffset]::UtcNow.ToString('o');elapsed_milliseconds=1;timeout_seconds=30;
            exit_code=0;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;abnormal_exit_kind=$null;process_tree_kill_error=$null;
            stdout_path=$out.path;stdout_sha256=$out.sha256;stdout_bytes=$out.bytes;
            stderr_path=$err.path;stderr_sha256=$err.sha256;stderr_bytes=0}
        if($null -ne $InputBytes){
            $snapshotInput=File ($Relative+'.stdin') $InputBytes
            $source=File ($Relative.Substring(0,$Relative.LastIndexOf('/'))+'/'+$SourceName) $InputBytes
            $p.standard_input=@{path=$snapshotInput.path;source_path=$source.path;sha256=$snapshotInput.sha256;bytes=$InputBytes.Length;
                write_completed=$true;eof_sent=$true;close_requested=$true}
        }
        return $p
    }
    $cliAda=Text 'cli/bin/static/lua_ada.exe' 'SYNTHETIC Ada CLI';$cliNative=Text 'build/conformance/default/bin/lua.exe' 'SYNTHETIC native CLI'
    $runtimeAda=Text 'lib/validation/relocatable/liblua.dll' 'SYNTHETIC Ada DLL';$runtimeNative=Text 'build/conformance/default/lib/libconformance_lua.dll' 'SYNTHETIC native DLL'
    $builtinAda=Text 'build/c-api/bin/validation/relocatable/builtin_api_contract.exe' 'SYNTHETIC Ada builtin consumer'
    $kindName=switch($Kind){'console-lua'{'debug-console-process-regressions'}'console-c'{'debug-console-c-process-regressions'}'readline'{'cli-readline-process-regressions'}}
    $report=@{schema_version=2;kind=$kindName;configuration='default';platform='windows';repository_revision=$revision;repository_dirty=$false;
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        source_repository_root=$root;output_directory=$original;processes=@();source_bindings=@(Get-TargetHostCampaignSourcePaths $Kind|
            ForEach-Object{@{path=$_;sha256=(Hash (Join-Path $root $_))}})}
    if($Kind -ceq 'readline'){$report.comparison_failures=@()}
    if($Kind -cne 'console-c'){
        $producer=if($Kind -ceq 'readline'){'scripts/check-cli-readline.ps1'}else{'scripts/check-debug-console.ps1'}
        $report.source=@{path=$producer;sha256=(Hash (Join-Path $root $producer))}
    }
    $images=@{}
    foreach($role in @('native','ada')){
        $selected=if($role -ceq 'native'){$cliNative}else{$cliAda}
        if($Kind -ceq 'console-c'){$selected=if($role -ceq 'native'){@{path='builtin_api_contract.exe';sha256='';bytes=0}}else{$builtinAda}}
        $name=if($Kind -ceq 'console-c'){'builtin_api_contract.exe'}elseif($role -ceq 'native'){'lua.exe'}else{'lua_ada.exe'}
        $body=if($Kind -ceq 'console-c' -and $role -ceq 'native'){'SYNTHETIC compiled native consumer'}else{
            [IO.File]::ReadAllText((Join-Path $payload ($selected.path.Replace('\','/').Substring($root.Replace('\','/').Length+1))))}
        $exe=Text ($base+'/'+$role+'/image/'+$name) $body
        $runtime=if($role -ceq 'native'){$runtimeNative}else{$runtimeAda}
        $libName=if($role -ceq 'native'){'libconformance_lua.dll'}else{'liblua.dll'}
        $dll=File ($base+'/'+$role+'/image/'+$libName) ([IO.File]::ReadAllBytes((Join-Path $payload ($runtime.path.Replace('\','/').Substring($root.Replace('\','/').Length+1)))))
        $images[$role]=@{exe=$exe;dll=$dll}
    }
    $cases=@(Get-TargetHostCampaignCases $Kind windows)
    $order=@();if($Kind -ceq 'console-c'){foreach($case in $cases){foreach($role in @('native','ada')){$order+=@{role=$role;case=$case}}}}
    else{foreach($role in @('native','ada')){foreach($case in $cases){$order+=@{role=$role;case=$case}}}}
    foreach($item in $order){
        $case=$item.case;$role=$item.role;$exe=$images[$role].exe
        $out=if($Kind -ceq 'console-lua'){"AFTER`r`n"}elseif($Kind -ceq 'console-c'){
            "PASS: builtin-debug-console-$($case.name)`r`nPASS: public builtin contract`r`n"}else{"Lua 5.5.1 SYNTHETIC banner`r`nSYNTHETIC paired output`r`n"}
        $sourceName=if($Kind -ceq 'readline'){'input'}else{'stdin'}
        $p=Process $exe.path $exe.sha256 (Get-TargetHostCampaignArguments $Kind $case) ($base+'/'+$role+'/'+$case.name+'/process') $out (Get-TargetHostCampaignInputBytes $Kind $case) $sourceName
        $row=@{role=$role;process=$p;images=@(@{name=[IO.Path]::GetFileName($exe.path);sha256=$exe.sha256},
            @{name=[IO.Path]::GetFileName($images[$role].dll.path);sha256=$images[$role].dll.sha256})}
        if($Kind -ceq 'console-c'){$row.mode=$case.name;$row.stdin=@{path=$p.standard_input.source_path;sha256=$p.standard_input.sha256;bytes=$p.standard_input.bytes}}else{$row.name=$case.name}
        if($Kind -ceq 'console-lua'){$row.setup=$case.setup}
        if($Kind -cne 'console-c'){$row.environment=@{PATH=($original+'/'+$role+'/image;SYNTHETIC inherited tail')}}
        if($Kind -ceq 'readline' -and $case.Contains('library')){$row.environment.LUA_READLINELIB=$case.library}
        $report.processes+=$row
    }
    $toolchain=@{compiler_sha256=('a'*64)}
    if($Kind -ceq 'console-c'){
        $report.comparison_complete=$true;$report.native_header_role='pinned-native-public-sdk';$report.ada_consumer_source_build_verified=$false
        $report.sources=@(foreach($path in @('c_api/tests/builtin_api_contract.c','c_api/tests/consumer_allocator.h','tests/c/argument_registry_callbacks.h',
            'references/lua/lua.h','references/lua/lauxlib.h','references/lua/lualib.h','references/lua/luaconf.h')){
            $snapshot=File ($base+'/sources/'+$path) ([IO.File]::ReadAllBytes((Join-Path $root $path)))
            @{path=$path;sha256=$snapshot.sha256;snapshot_path=$snapshot.path;snapshot_sha256=$snapshot.sha256}})
        $report.images=@();foreach($role in @('native','ada')){foreach($file in @($images[$role].exe,$images[$role].dll)){$report.images+=@{path=$file.path;sha256=$file.sha256}}}
        $oracle=Text ($base+'/native/image/lua.exe') 'SYNTHETIC native CLI';$report.images+=@{path=$oracle.path;sha256=$oracle.sha256}
        $report.compiler=@{path='C:/SYNTHETIC/compiler.exe';sha256=$toolchain.compiler_sha256}
        $arguments=Get-TargetHostConsoleCompileArguments default windows ($original+'/sources') ($original+'/native/image') $images.native.exe.path
        $report.compile=Process $report.compiler.path $report.compiler.sha256 $arguments ($base+'/compile') '' $null
        $report.compile.working_directory=$root;$report.compile.timeout_seconds=120
        $code="assert(T==nil);io.write('DEBUG CONSOLE C CONFIG default\n')"
        $report.configuration_probe=Process $oracle.path $oracle.sha256 @('-e',$code) ($base+'/native-config') "DEBUG CONSOLE C CONFIG default`r`n" $null
        $report.configuration_probe.working_directory=$root
    }
    $image=@{context='default/windows/validation/shared';revision=$revision;files=$script:files;toolchain=$toolchain;
        paths=@{ada_cli='cli/bin/static/lua_ada.exe';c_oracle='build/conformance/default/bin/lua.exe';ada_runtime='lib/validation/relocatable';c_runtime='build/conformance/default/lib'}}
    return @{root=$payload;report=$report;image=$image;consumer=@{consumers=@(@{name='builtin-api';executable_sha256=$builtinAda.sha256})}}
}
function Case([string]$Kind,[string]$Name,[scriptblock]$Mutation,[string]$Expected='',[switch]$Actual){
    $f=New-Fixture $Kind;&$Mutation $f;$errorText=$null;$value=$null
    try{$value=Assert-TargetHostCampaignReport -Root $root -Report $f.report -ArtifactRoot $f.root -Context $f.image.context -Revision $revision `
        -Image $f.image -ConsumerReport $f.consumer -AllowSynthetic:(-not $Actual)}catch{$errorText=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $errorText) -or ($Expected -ne '' -and ($null -eq $errorText -or $errorText -notmatch $Expected))){throw "Host campaign test $Name failed: $errorText; expected $Expected"}
    if($Expected -eq '' -and ($value.runtime_acceptance -or $value.coverage_authority -or -not $value.diagnostic_only)){throw 'Synthetic transport gained acceptance'}
    $script:count++;Write-Output "HOST CAMPAIGN GUARD PASS: $Name"
}
Case console-lua 'all sixteen paired Lua console inputs survive strict binding' {}
Case console-c 'all four separate C modes retain source compiler configuration and image bindings' {}
Case readline 'all fourteen paired readline inputs retain raw bytes and backend overrides' {}
Case console-lua 'synthetic transport cannot supply actual final evidence' {} 'actual clean observations' -Actual
Case readline 'dated schema1 reports cannot inherit the new source contract' {param($f)$f.report.schema_version=1} 'schema revision configuration'
Case console-lua 'actual labels cannot hide a dirty harness checkout' {param($f)$f.report.synthetic_fixture=$false;$f.report.repository_dirty=$true} 'actual clean observations' -Actual
Case console-lua 'missing mandatory case cannot borrow the remaining pairs' {param($f)$f.report.processes=@($f.report.processes|Select-Object -SkipLast 1)} 'every mandatory actual paired operation'
Case console-lua 'duplicate role cannot replace its Ada counterpart' {param($f)$f.report.processes[-1].role='native'} 'order role or case'
Case console-lua 'modified actual command input is rejected even after rehashing' {param($f)$f.report.processes[0].process.standard_input.sha256='0'*64} 'actual input bytes'
Case console-lua 'failed stdin delivery cannot become a passing console process' {param($f)$f.report.processes[0].process.standard_input.write_completed=$false} 'delivery did not complete'
Case console-lua 'setup and exact arguments stay bound to retained operation' {param($f)$f.report.processes[0].process.arguments=@('-e','print("AFTER")')} 'exact arguments'
Case console-lua 'another frozen CLI cannot supply actual console observations' {param($f)$f.image.files[0].sha256='0'*64} 'another frozen CLI'
Case readline 'missing backend override is a distinct failed operation' {param($f)[void]$f.report.processes[10].environment.Remove('LUA_READLINELIB')} 'backend environment'
Case readline 'retained comparison failures block final interpretation' {param($f)$f.report.comparison_failures=@(@{name='basic';errors=@('stdout differs')})} 'comparison failures'
Case readline 'another image cannot replace the actual loader prefix' {param($f)$f.report.processes[0].environment.PATH='C:/other/image;tail'} 'loader image prefix'
Case console-lua 'a producer hash cannot contradict the required source identity' {param($f)$f.report.source.sha256='0'*64} 'producer source identity'
Case readline 'configuration and actual platform cannot be relabelled' {param($f)$f.report.configuration='upstream-test'} 'configuration or platform'
Case console-c 'strict compile cannot append disabled assertions' {param($f)$f.report.compile.arguments+='-DNDEBUG'} 'exact arguments'
Case console-c 'wrong private header role cannot masquerade as the selected SDK' {param($f)$f.report.native_header_role='pinned-native-private-test-header'} 'header role'
Case console-c 'another prebuilt Ada consumer cannot supply these four invocations' {param($f)$f.consumer.consumers[0].executable_sha256='0'*64} 'different built Ada consumer'
Case console-c 'missing source snapshot preserves its exact obligation' {param($f)$f.report.sources=@($f.report.sources|Select-Object -SkipLast 1)} 'snapshot set'
Case console-c 'missing actual native configuration probe is rejected' {param($f)$f.report.configuration_probe.arguments=@()} 'exact arguments'
Case console-c 'a duplicate input receipt cannot contradict actual delivered bytes' {param($f)$f.report.processes[0].stdin.sha256='0'*64} 'input receipt contradicts'
Case console-c 'another case input path cannot replace its exact source identity' {param($f)$f.report.processes[0].process.standard_input.source_path=$f.report.processes[2].process.standard_input.source_path} 'actual input bytes or snapshot path'
Case console-lua 'wrong actual operation timeout remains a failure' {param($f)$f.report.processes[0].process.timeout_seconds=600} 'timeout or elapsed'
Case console-lua 'raw artifacts cannot disappear from the frozen image' {param($f)$f.image.files=@($f.image.files|Where-Object{$_.path -notmatch '/native/write-and-continue/process.stdout$'})} 'absent from the exact frozen image'
Write-Output "PASS:$script:count host campaign regressions; synthetic objects only; no compiler/Lua execution or acceptance"
