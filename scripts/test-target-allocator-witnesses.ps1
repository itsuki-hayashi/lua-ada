Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetAllocatorWitnesses.psm1') -Force
$temporary=Join-Path $root ('reports/target-allocator-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8=[Text.UTF8Encoding]::new($false)
$revision=(&git -C $root rev-parse HEAD).Trim()
# Construct explicit non-execution schema fixtures. No developer-local dated
# report, Lua executable or compiler is required by this portable regression.
# The validator's positive fixture path is reachable only with AllowSynthetic;
# the final image consumer never selects that switch.
$samples=Join-Path $temporary 'synthetic-schema-inputs'
[void][IO.Directory]::CreateDirectory($samples)
function Sample-Process([string]$Name,[string[]]$Arguments,[string]$Output,[string]$ErrorText='',[int]$Exit=0){
    $out=Join-Path $samples ($Name+'.stdout');$err=Join-Path $samples ($Name+'.stderr')
    [IO.File]::WriteAllText($out,$Output,$utf8);[IO.File]::WriteAllText($err,$ErrorText,$utf8)
    return @{executable=(Join-Path $samples 'synthetic-tool.exe');executable_sha256=('a'*64);process_id=1000+$script:sampleIndex;
        working_directory=$root;arguments=@($Arguments);started_utc=[DateTimeOffset]::UtcNow;elapsed_milliseconds=1;
        exit_code=$Exit;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;process_tree_kill_error=$null;abnormal_exit_kind=$null;
        stdout_path=$out;stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();stdout_bytes=$utf8.GetByteCount($Output);
        stderr_path=$err;stderr_sha256=(Get-FileHash $err).Hash.ToLowerInvariant();stderr_bytes=$utf8.GetByteCount($ErrorText)}
}
$script:sampleIndex=0
$module=Get-Module TargetAllocatorWitnesses
$operations=@(& $module {Get-TawCeilingOperations})
$observations=@()
foreach($operation in $operations){
    $script:sampleIndex++
    $invalid=$operation.Contains('invalid');$out='';$errorText='';$exit=0
    if($invalid){$errorText='SYNTHETIC invalid conformance allocator ceiling';$exit=1}
    elseif($operation.Contains('stdout')){$out=$operation.stdout}
    else{
        $out=@{schema_version=1;implementation='Lua Ada';lua_release='Lua 5.5.1';configuration='default';test_adapter=$false;
            runtime_build_profile='validation';launcher_build_profile='validation';launcher_library_type='static';
            integer_bytes=8;number_bytes=8;pointer_bytes=8;extra_space_bytes=8;expected_extra_space_bytes=8;
            max_stack=1000000;max_c_calls=200;aux_buffer_bytes=1024;compat_global=1;rand32=$false;compat_math=$false;
            allocator_accounting='managed-provider-raw-bytes';allocator_limit_bytes=$operation.limit}|ConvertTo-Json
    }
    $p=Sample-Process $operation.name $operation.arguments $out $errorText $exit
    $run=[guid]::NewGuid().ToString('N')
    $environment=@{LUA_ADA_CONFORMANCE_RUN_ID=$run;LUA_ADA_CONFORMANCE_TELEMETRY=(Join-Path $samples ($operation.name+'.telemetry'))}
    if($null -ne $operation.selection){$environment.LUA_ADA_CONFORMANCE_ALLOCATOR=$operation.selection}
    $row=@{name=$operation.name;process=$p;environment=$environment}
    if(-not $invalid){
        $s=@{schema_version=1;run_id=$run;process_id=$p.process_id;configuration='default';allocator_limit_bytes=$operation.limit;
            outstanding_bytes=0;outstanding_blocks=0;peak_managed_bytes=512;provider_refusals=0;
            managed_refusals=$(if($operation.Contains('refusal')){1}else{0});shutdown_complete=$true;accounting_fault=$false}
        $path=Join-Path $samples ($operation.name+'.telemetry.'+$p.process_id+'.json')
        [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $s),$utf8)
        $row.telemetry=@{path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant();observed=$s}
    }
    $observations+=$row
}
$ceilingSample=Join-Path $samples 'ceiling.json'
[IO.File]::WriteAllText($ceilingSample,(@{schema_version=1;kind='conformance-allocator-ceiling-regressions';configuration='default';
    executable=@{path=(Join-Path $samples 'synthetic-tool.exe');sha256=('a'*64)};runtime_acceptance=$false;coverage_authority=$false;
    observations=$observations}|ConvertTo-Json -Depth 100),$utf8)
$compile=Sample-Process 'compile' @() ''; $process=Sample-Process 'execute' @() ''
$sources=@('experiments/conformance/c/allocator_observer_probe.c','experiments/conformance/c/bounded_ltests.c',
    'experiments/conformance/c/conformance_cli.c','experiments/conformance/c/allocator_limit.h',
    'experiments/conformance/c/conformance_exports.h','references/lua/ltests.c','references/lua/ltests.h','references/lua/lua.h')
$nativeSample=Join-Path $samples 'native.json'
[IO.File]::WriteAllText($nativeSample,(@{schema_version=1;kind='native-allocator-observer-regressions';
    compiler=@{path=$compile.executable;sha256=$compile.executable_sha256};compile=$compile;process=$process;
    loaded_runtime=@{path='synthetic-placeholder';sha256=('b'*64)};library_directory=$samples;loaded_runtime_linkage_verified=$true;
    runtime_acceptance=$false;coverage_authority=$false;
    sources=@($sources|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}})}|
    ConvertTo-Json -Depth 100),$utf8)
$script:cases=0
function Clone($Value){ConvertTo-Json -InputObject $Value -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100}
function New-Fixture([string]$Kind){
    $configuration=if($Kind -ceq 'ada-ceiling'){'default'}else{'upstream-test'}
    $context="$configuration/windows/validation/static"
    $payload=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($payload)
    $script:files=@()
    function Artifact([string]$Relative,[byte[]]$Bytes){
        $path=Join-Path $payload $Relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllBytes($path,$Bytes)
        $hash=(Get-FileHash $path).Hash.ToLowerInvariant()
        $script:files=@($script:files|Where-Object path -CNE $Relative)+@(@{path=$Relative;sha256=$hash;bytes=$Bytes.Length;unix_mode=0})
        return @{path=($root.Replace('\','/')+'/'+$Relative);sha256=$hash}
    }
    function Text-Artifact([string]$Relative,[string]$Text){Artifact $Relative ($utf8.GetBytes($Text))}
    function Capture($Process,[string]$Relative){
        foreach($stream in @('stdout','stderr')){
            $id=Artifact ($Relative+'.'+$stream) ([IO.File]::ReadAllBytes($Process[$stream+'_path']))
            $Process[$stream+'_path']=$id.path;$Process[$stream+'_sha256']=$id.sha256
        }
        $Process.working_directory=$root
    }
    $base='reports/target-builds/'+$context.Replace('/','-')+'/synthetic-'+$Kind
    $rawBase=$base+'/raw'
    $originalRaw=$root.Replace('\','/')+'/'+$rawBase
    $library=if($Kind -ceq 'ada-ceiling'){'lib/validation/static'}else{'build/conformance/upstream-test/lib'}
    $libName=if($Kind -ceq 'ada-ceiling'){'liblua.a'}else{'libconformance_lua.dll'}
    $lib=Text-Artifact ($library+'/'+$libName) 'SYNTHETIC library fixture, never a runtime'
    $selected=@{library_directory=($root.Replace('\','/')+'/'+$library);library_files=@($lib)}
    if($Kind -ceq 'ada-ceiling'){
        $raw=Get-Content $ceilingSample -Raw|ConvertFrom-Json -AsHashtable -Depth 100
        $exe=Text-Artifact 'tests/bin/static/allocator-synthetic.exe' 'SYNTHETIC executable, never executed'
        $selected.executable=$exe;$raw.executable=$exe
        foreach($row in $raw.observations){
            Capture $row.process ($rawBase+'/'+$row.name)
            $row.process.executable=$exe.path;$row.process.executable_sha256=$exe.sha256
            $row.environment.LUA_ADA_CONFORMANCE_TELEMETRY=$originalRaw+'/'+$row.name+'.telemetry'
            if($row.Contains('telemetry')){
                $id=Artifact ($rawBase+'/'+$row.name+'.telemetry.'+$row.process.process_id+'.json') ([IO.File]::ReadAllBytes($row.telemetry.path))
                $row.telemetry.path=$id.path;$row.telemetry.sha256=$id.sha256
            }
        }
        $children=@($raw.observations.process)
        $producerArguments=@('-NoProfile','-File',($root.Replace('\','/')+'/scripts/test-conformance-allocator-ceiling.ps1'),
            '-Interpreter',$exe.path,'-Configuration','default','-OutputDirectory',$originalRaw)
    }else{
        $raw=Get-Content $nativeSample -Raw|ConvertFrom-Json -AsHashtable -Depth 100
        Capture $raw.compile ($rawBase+'/compile');Capture $raw.process ($rawBase+'/execute')
        $exe=Text-Artifact ($rawBase+'/allocator_observer_probe.exe') 'SYNTHETIC native probe, never executed'
        $raw.process.executable=$exe.path;$raw.process.executable_sha256=$exe.sha256
        $raw.library_directory=$selected.library_directory
        $raw.loaded_runtime.path=$lib.path;$raw.loaded_runtime.sha256=$lib.sha256
        $runText='ALLOCATOR OBSERVER RUNTIME: '+$lib.path+"`r`n"+
            ((@('real debug allocator identity','fail-next leaves the old block intact','count refusal before backing allocation',
            'byte refusal before backing allocation','backing refusal counted once in both views',
            'successful growth and free are not refusals','original teardown and zero ownership')|
            ForEach-Object{'ALLOCATOR OBSERVER PASS: '+$_})-join "`r`n")+"`r`n"
        $out=Text-Artifact ($rawBase+'/execute.stdout') $runText
        $raw.process.stdout_path=$out.path;$raw.process.stdout_sha256=$out.sha256;$raw.process.stdout_bytes=$utf8.GetByteCount($runText)
        $raw.compile.arguments=@('-std=c99','-Wall','-Wextra','-Werror','-pedantic','-DLUA_BUILD_AS_DLL',
            '-DLUA_USER_H=<ltests.h>','-include',($root.Replace('\','/')+'/experiments/conformance/c/conformance_exports.h'),
            ('-I'+$root.Replace('\','/')+'/references/lua'),($root.Replace('\','/')+'/experiments/conformance/c/allocator_observer_probe.c'),
            ('-L'+$selected.library_directory),'-lconformance_lua','-o',$exe.path)
        $children=@($raw.compile,$raw.process)
        $producerArguments=@('-NoProfile','-File',($root.Replace('\','/')+'/scripts/test-native-allocator-observer.ps1'),
            '-Compiler',$raw.compiler.path.Replace('\','/'),'-LibraryDirectory',$selected.library_directory,'-OutputDirectory',$originalRaw)
    }
    $rawIdentity=Text-Artifact ($rawBase+'/result.json') (ConvertTo-Json -InputObject $raw -Depth 100)
    $begin=@($children|ForEach-Object{[DateTimeOffset]$_.started_utc}|Sort-Object)[0].AddSeconds(-1)
    $end=@($children|ForEach-Object{[DateTimeOffset]$_.started_utc}|Sort-Object)[-1].AddSeconds(5)
    $parentOut=Text-Artifact ($base+'/producer.stdout') 'SYNTHETIC parent fixture'
    $parentErr=Artifact ($base+'/producer.stderr') ([byte[]]::new(0))
    $parent=@{executable=(Get-Command pwsh).Source;executable_sha256=(Get-FileHash (Get-Command pwsh).Source).Hash.ToLowerInvariant();
        process_id=123456;working_directory=$root;arguments=$producerArguments;started_utc=$begin;elapsed_milliseconds=[long]($end-$begin).TotalMilliseconds;
        exit_code=0;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;process_tree_kill_error=$null;abnormal_exit_kind=$null;
        stdout_path=$parentOut.path;stdout_sha256=$parentOut.sha256;stdout_bytes=$utf8.GetByteCount('SYNTHETIC parent fixture');
        stderr_path=$parentErr.path;stderr_sha256=$parentErr.sha256;stderr_bytes=0}
    $w=@{schema_version=1;kind='target-context-allocator-witness';target='remaining-upstream-compatibility';witness_kind=$Kind;
        context=$context;repository_revision=$revision;reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        source_repository_root=$root;synthetic_fixture=$true;repository_dirty=$false;runtime_acceptance=$false;coverage_authority=$false;
        producer_report=$rawIdentity;producer_process=$parent;selected_runtime=$selected;
        source_bindings=@(Get-TargetAllocatorSourcePaths $Kind $configuration|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}})}
    $image=@{context=$context;revision=$revision;files=$script:files;toolchain=@{pwsh_sha256=$parent.executable_sha256};paths=@{}}
    if($Kind -ceq 'ada-ceiling'){$image.paths.ada_runtime=$library;$image.paths.ada_launcher='tests/bin/static/allocator-synthetic.exe'}
    else{$w.compiler=$raw.compiler;$image.paths.c_runtime=$library;$image.toolchain.compiler_sha256=$raw.compiler.sha256}
    return @{root=$payload;witness=$w;image=$image;raw=$raw;raw_relative=($rawBase+'/result.json')}
}
function Case([string]$Kind,[string]$Name,[scriptblock]$Change,[string]$Expected='',[switch]$Actual,[switch]$External){
    $f=New-Fixture $Kind;& $Change $f
    $failure=$null;$value=$null
    try{$value=Assert-TargetAllocatorWitness -Root $root -Witness $f.witness -ArtifactRoot $f.root -Context $f.image.context `
        -Revision $revision -Image $f.image -AllowSynthetic:(-not $Actual) -AllowExternalInput:$External}catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){
        throw "Allocator fixture failed: $Name; $failure; expected $Expected"
    }
    if($Expected -eq '' -and (-not $value.diagnostic_only -or $value.runtime_acceptance -or $value.coverage_authority)){throw 'Synthetic binding fixture gained authority'}
    $script:cases++;Write-Output "ALLOCATOR WITNESS GUARD PASS: $Name"
}
function Save-Raw($Fixture){
    $path=Join-Path $Fixture.root $Fixture.raw_relative
    [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $Fixture.raw -Depth 100),$utf8)
    $hash=(Get-FileHash $path).Hash.ToLowerInvariant()
    $Fixture.witness.producer_report.sha256=$hash
    $entry=@($Fixture.image.files|Where-Object path -CEQ $Fixture.raw_relative)[0]
    $entry.sha256=$hash;$entry.bytes=(Get-Item $path).Length
}
function Rewrite-Artifact($Fixture,[string]$OriginalPath,[string]$Text){
    $relative=$OriginalPath.Replace('\','/').Substring($root.Replace('\','/').Length+1)
    $path=Join-Path $Fixture.root $relative
    [IO.File]::WriteAllText($path,$Text,$utf8)
    $hash=(Get-FileHash $path).Hash.ToLowerInvariant()
    $entry=@($Fixture.image.files|Where-Object path -CEQ $relative)[0]
    $entry.sha256=$hash;$entry.bytes=(Get-Item $path).Length
    return @{sha256=$hash;bytes=$entry.bytes}
}
function External-Input($Fixture,[string]$Change=''){
    $files=@($Fixture.witness.selected_runtime.library_files)
    if($Fixture.witness.witness_kind -ceq 'ada-ceiling'){$files+=@($Fixture.witness.selected_runtime.executable)}
    $value=@{schema_version=1;kind='target-allocator-external-input-snapshot';context=$Fixture.image.context;
        repository_revision=('b'*40);repository_dirty=$true;source_build_provenance_verified=$false;
        synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;files=$files}
    if($Change -ceq 'missing-product'){$value.files=@($files|Select-Object -SkipLast 1)}
    if($Change -ceq 'invent-build-provenance'){$value.source_build_provenance_verified=$true}
    $relative=$Fixture.raw_relative.Replace('/raw/result.json','/external-input.json')
    $path=Join-Path $Fixture.root $relative
    [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $value -Depth 64),$utf8)
    $Fixture.witness.external_input_snapshot=@{path=($root.Replace('\','/')+'/'+$relative);sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
}
Case ada-ceiling 'thirteen synthetic source-bound rows exercise only binding validation' {}
Case native-observer 'seven synthetic native rows exercise only source/toolchain/OS-path binding' {}
Case native-observer 'Windows OS path casing retains raw bytes and identifies the same module' {param($f)
    $p=$f.raw.process;$relative=$p.stdout_path.Replace('\','/').Substring($root.Replace('\','/').Length+1)
    $text=[IO.File]::ReadAllText((Join-Path $f.root $relative)).Replace($f.raw.loaded_runtime.path,$f.raw.loaded_runtime.path.ToUpperInvariant())
    $id=Rewrite-Artifact $f $p.stdout_path $text;$p.stdout_sha256=$id.sha256;$p.stdout_bytes=$id.bytes;Save-Raw $f
}
Case ada-ceiling 'final consumer rejects a labelled synthetic report' {} 'actual clean observations' -Actual
Case ada-ceiling 'external observations remain explicitly rejected by the final reader' {param($f)External-Input $f} 'cannot supply final context build provenance'
Case ada-ceiling 'explicit external observation mode retains only unverified provenance' {param($f)External-Input $f} -External
Case ada-ceiling 'external observations cannot invent a verified source build' {param($f)External-Input $f invent-build-provenance} 'unverified provenance' -External
Case ada-ceiling 'external input snapshot must retain every selected product' {param($f)External-Input $f missing-product} 'absent from its immutable input snapshot' -External
Case ada-ceiling 'revision drift cannot reuse raw observations' {param($f)$f.witness.repository_revision='0'*40} 'revision context or role'
Case ada-ceiling 'another selected context cannot inherit the report' {param($f)$f.witness.context='upstream-test/windows/validation/static'} 'revision context or role'
Case ada-ceiling 'source hash drift requires new observations' {param($f)$f.witness.source_bindings[0].sha256='0'*64} 'source binding is stale'
Case ada-ceiling 'raw report bytes remain immutable' {param($f)[IO.File]::AppendAllText((Join-Path $f.root $f.raw_relative),' ')} 'artifact hash'
Case ada-ceiling 'a selected runtime cannot disappear behind its launcher' {param($f)$f.witness.selected_runtime.library_files=@()} 'missing or duplicate'
Case ada-ceiling 'another frozen launcher cannot supply the ceiling checks' {param($f)$f.image.paths.ada_launcher='tests/bin/other.exe'} 'different frozen Ada launcher'
Case native-observer 'another frozen compiler cannot inherit probe execution' {param($f)$f.image.toolchain.compiler_sha256='0'*64} 'frozen toolchain'
Case native-observer 'wrong actual runtime DLL bytes are rejected' {param($f)
    $p=Join-Path $f.root ($f.image.paths.c_runtime+'/libconformance_lua.dll');[IO.File]::AppendAllText($p,'other')
} 'artifact hash'
Case ada-ceiling 'raw children must belong to the recorded producer window' {param($f)$f.witness.producer_process.started_utc=[DateTimeOffset]::UtcNow.AddYears(1)} 'predates its actual producer'
Case ada-ceiling 'an unlisted raw artifact cannot enter a frozen context' {param($f)$f.image.files=@($f.image.files|Where-Object path -CNE ($f.raw_relative))} 'absent from its exact frozen image'
Case ada-ceiling 'a successful summary cannot replace all thirteen physical children' {param($f)$f.raw.observations=@($f.raw.observations|Select-Object -SkipLast 1);Save-Raw $f} 'thirteen operations'
Case ada-ceiling 'relabelled ordinary capacity cannot become the 64MiB request' {param($f)$f.raw.observations[2].environment.LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';Save-Raw $f} 'selected environment'
Case ada-ceiling 'distinct cases cannot reuse a prior allocator run id' {param($f)$f.raw.observations[1].environment.LUA_ADA_CONFORMANCE_RUN_ID=$f.raw.observations[0].environment.LUA_ADA_CONFORMANCE_RUN_ID;Save-Raw $f} 'unique run identity'
Case ada-ceiling 'a rehashed sidecar cannot change the actual child PID' {param($f)
    $row=$f.raw.observations[0];$s=Clone $row.telemetry.observed;$s.process_id++
    $id=Rewrite-Artifact $f $row.telemetry.path (ConvertTo-Json -InputObject $s)
    $row.telemetry.sha256=$id.sha256;Save-Raw $f
} 'process/run/configuration identity'
Case ada-ceiling 'zero exit cannot hide outstanding allocator ownership' {param($f)
    $row=$f.raw.observations[0];$s=Clone $row.telemetry.observed;$s.outstanding_bytes=1
    $id=Rewrite-Artifact $f $row.telemetry.path (ConvertTo-Json -InputObject $s)
    $row.telemetry.sha256=$id.sha256;Save-Raw $f
} 'ceiling or ownership'
Case ada-ceiling 'an error marker alone cannot invent a real allocator refusal' {param($f)
    $row=@($f.raw.observations|Where-Object name -CEQ actual-heavy-refusal)[0];$s=Clone $row.telemetry.observed
    $s.managed_refusals=0;$s.provider_refusals=0
    $id=Rewrite-Artifact $f $row.telemetry.path (ConvertTo-Json -InputObject $s)
    $row.telemetry.sha256=$id.sha256;Save-Raw $f
} 'actual managed or provider refusal'
Case ada-ceiling 'same executable must measure the selected build profile' {param($f)
    $p=$f.raw.observations[0].process;$relative=$p.stdout_path.Replace('\','/').Substring($root.Replace('\','/').Length+1)
    $c=Get-Content (Join-Path $f.root $relative) -Raw|ConvertFrom-Json -AsHashtable;$c.runtime_build_profile='release'
    $id=Rewrite-Artifact $f $p.stdout_path (ConvertTo-Json -InputObject $c)
    $p.stdout_sha256=$id.sha256;$p.stdout_bytes=$id.bytes;Save-Raw $f
} 'measured profile or library type'
Case native-observer 'compiler flags cannot disable the actual C assertions' {param($f)$f.raw.compile.arguments+='-DNDEBUG';Save-Raw $f} 'exact arguments'
Case native-observer 'rehashing six success lines cannot replace seven actual C operations' {param($f)
    $p=$f.raw.process;$relative=$p.stdout_path.Replace('\','/').Substring($root.Replace('\','/').Length+1)
    $text=[IO.File]::ReadAllText((Join-Path $f.root $relative)).Replace("ALLOCATOR OBSERVER PASS: backing refusal counted once in both views`r`n",'')
    $id=Rewrite-Artifact $f $p.stdout_path $text;$p.stdout_sha256=$id.sha256;$p.stdout_bytes=$id.bytes;Save-Raw $f
} 'complete seven-case protocol'
Case native-observer 'same basename from another actually mapped DLL is rejected' {param($f)
    $p=$f.raw.process;$old=$f.raw.loaded_runtime.path;$f.raw.loaded_runtime.path=$old.Replace('/upstream-test/','/default/')
    $relative=$p.stdout_path.Replace('\','/').Substring($root.Replace('\','/').Length+1)
    $id=Rewrite-Artifact $f $p.stdout_path ([IO.File]::ReadAllText((Join-Path $f.root $relative)).Replace($old,$f.raw.loaded_runtime.path))
    $p.stdout_sha256=$id.sha256;$p.stdout_bytes=$id.bytes;Save-Raw $f
} 'actually loaded another runtime'
Case ada-ceiling 'another producer tool cannot inherit the frozen observation' {param($f)$f.image.toolchain.pwsh_sha256='0'*64} 'frozen observation toolchain'
Case ada-ceiling 'numeric identities must be actual integral JSON measurements' {param($f)$f.raw.observations[0].process.process_id=[double]1.5;Save-Raw $f} 'integer differs'
$module=Get-Module TargetAllocatorWitnesses
foreach($entry in @(@{origin='D:\repo';path='D:\repo\reports\target-builds\one\result.json';expected='reports/target-builds/one/result.json'},
    @{origin='/home/runner/repo';path='/home/runner/repo/reports/target-builds/one/result.json';expected='reports/target-builds/one/result.json'})){
    $actual=& $module {param($o,$p)Get-TawRelative $o $p} $entry.origin $entry.path
    if($actual -cne $entry.expected){throw 'Cross-platform original-path parsing depends on the verifier host'}
    $script:cases++
}
Write-Output "PASS:$script:cases allocator witness regressions; all fixtures synthetic; no compiler/Lua execution or acceptance"
