param([Parameter(Mandatory)][string]$OracleRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This observation is Windows-only'}
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$oracle=(Resolve-Path -LiteralPath $OracleRoot).Path
$output=Join-Path $root ('reports/verybig-windows/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($output)
$utf8=[Text.UTF8Encoding]::new($false)
function Hash($path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Save($path,$value){
    $text=(ConvertTo-Json -InputObject $value -Depth 48).Replace([string][char]13,'')+[char]10
    [IO.File]::WriteAllText($path,$text,$utf8)
}
$source=Join-Path $root 'references/lua/testes/verybig.lua'
$counterpart=Join-Path $root 'tests/conformance/platform/windows-verybig-tempfile.lua'
if((Hash $source) -cne '2b6d30c69cbe6974068881108eae297bdedd275b429be8ec614bf5f8ee89707e'){
    throw 'Pinned original verybig source differs'
}
$summary=[ordered]@{schema_version=1;kind='verybig-windows-native-author-observation';
    author='Codex /root/runtime_gaps';platform='windows';repository_revision=(& git -C $root rev-parse HEAD);
    reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';runtime_acceptance=$false;coverage_authority=$false;
    source_adaptation_authority=$false;independent_source_review='pending';native_applicability_review='pending';
    transformed_verybig_emitted=$false;transformed_verybig_executed=$false;
    source=@{path='references/lua/testes/verybig.lua';sha256=(Hash $source)};
    counterpart=@{path='tests/conformance/platform/windows-verybig-tempfile.lua';sha256=(Hash $counterpart)};
    build_input_bindings=@();configurations=@()}
foreach($path in @('experiments/conformance/oracle.gpr','experiments/conformance/reference.gpr',
        'experiments/conformance/c/conformance_cli.c','experiments/conformance/c/allocator_limit.h',
        'experiments/conformance/c/conformance_exports.h','references/lua/loslib.c')){
    $summary.build_input_bindings+=@(@{path=$path;sha256=(Hash (Join-Path $root $path))})
}
$unexpected=$false
foreach($configuration in @('default','upstream-test')){
    $directory=Join-Path $output $configuration
    $frozen=Join-Path $directory 'oracle'
    [void][IO.Directory]::CreateDirectory($frozen)
    $originalExe=Join-Path $oracle "build/conformance/$configuration/bin/lua.exe"
    $originalDll=Join-Path $oracle "build/conformance/$configuration/lib/libconformance_lua.dll"
    $exe=Join-Path $frozen 'lua.exe';$dll=Join-Path $frozen 'libconformance_lua.dll'
    [IO.File]::Copy($originalExe,$exe,$false);[IO.File]::Copy($originalDll,$dll,$false)
    if((Hash $originalExe) -cne (Hash $exe) -or (Hash $originalDll) -cne (Hash $dll)){
        throw 'Frozen oracle bytes differ from selected native artifacts'
    }
    $entry=[ordered]@{configuration=$configuration;artifacts=@(
        @{selected=$originalExe;frozen=$exe;sha256=(Hash $exe)},
        @{selected=$originalDll;frozen=$dll;sha256=(Hash $dll)});
        compiler_flags_provenance='No native rebuild performed. GPR/source hashes are inputs, not a claimed compile-command receipt.';
        processes=@()}
    foreach($role in @('configuration','original','counterpart')){
        $cwd=Join-Path $directory $role;[void][IO.Directory]::CreateDirectory($cwd)
        $prefix=Join-Path $directory $role
        $run=[guid]::NewGuid().ToString('N')
        $environment=@{PATH=$frozen+[IO.Path]::PathSeparator+$env:PATH;
            LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';MEMLIMIT='2147483648';
            LUA_ADA_CONFORMANCE_RUN_ID=$run;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'-allocator'}
        if($role -eq 'configuration'){$arguments=@('--conformance-config')}
        elseif($role -eq 'original'){
            [IO.File]::Copy($source,(Join-Path $cwd 'verybig.lua'),$false)
            $arguments=@('-e',"assert(not _soft and not _port);local r=table.pack(assert(loadfile('verybig.lua'))());assert(r.n==1 and r[1]==10);print('SCALE verybig return10 OK')")
        }else{
            [IO.File]::Copy($counterpart,(Join-Path $cwd 'windows-verybig-tempfile.lua'),$false)
            $arguments=@('-e',"assert(not _soft and not _port);assert(dofile('windows-verybig-tempfile.lua')==10);print('PASS: windows-verybig-tempfile-return')")
        }
        $process=Invoke-ConformanceProcess -Executable $exe -Arguments $arguments -Directory $cwd -OutputPrefix $prefix -TimeoutSeconds 900 -Environment $environment
        $record=[ordered]@{role=$role;process=$process;environment=$environment;telemetry=$null;
            runtime_acceptance=$false;coverage_authority=$false}
        if($role -ne 'configuration'){
            # The native ABI/configuration command creates no Lua state and
            # returns before its telemetry epilogue. Only real Lua workloads
            # have allocator sidecars; never invent a probe shutdown record.
            $telemetryPath=$prefix+'-allocator.'+$process.process_id+'.json'
            $telemetry=Get-Content -LiteralPath $telemetryPath -Raw|ConvertFrom-Json -AsHashtable
            if($telemetry.run_id -cne $run -or $telemetry.process_id -ne $process.process_id -or
                $telemetry.configuration -cne $configuration -or $telemetry.allocator_limit_bytes -ne 2147483648 -or
                $telemetry.outstanding_bytes -ne 0 -or $telemetry.outstanding_blocks -ne 0){
                throw 'Actual native process telemetry identity or balance differs'
            }
            $record.telemetry=@{path=$telemetryPath;sha256=(Hash $telemetryPath);data=$telemetry}
        }
        if($role -eq 'configuration'){
            $config=Get-Content -LiteralPath $process.stdout_path -Raw|ConvertFrom-Json -AsHashtable
            $record.observed_configuration=$config
            $record.expected_observation=($process.exit_code -eq 0 -and -not $process.timed_out -and
                $process.stderr_bytes -eq 0 -and $config.configuration -ceq $configuration -and
                $config.allocator_limit_bytes -eq 2147483648 -and
                $config.test_adapter -eq ($configuration -ceq 'upstream-test'))
        }elseif($role -eq 'original'){
            $errorText=[IO.File]::ReadAllText($process.stderr_path)
            $record.expected_observation=($process.exit_code -ne 0 -and -not $process.timed_out -and
                $errorText.Contains('verybig.lua:142: cannot open file') -and $errorText.Contains('Permission denied'))
            $record.input_sha256=Hash (Join-Path $cwd 'verybig.lua')
            if($record.input_sha256 -cne (Hash $source)){throw 'Original baseline source changed'}
        }else{
            $lines=@([IO.File]::ReadAllLines($process.stdout_path))
            $expected=@('rooted-name','fresh-cwd-name','write-read','text-loadfile','dofile','binary-load','remove','return')|
                ForEach-Object{'PASS: windows-verybig-tempfile-'+$_}
            $record.expected_observation=($process.exit_code -eq 0 -and -not $process.timed_out -and $process.stderr_bytes -eq 0 -and
                ($lines -join '|') -ceq ($expected -join '|'))
            $record.input_sha256=Hash (Join-Path $cwd 'windows-verybig-tempfile.lua')
            if($record.input_sha256 -cne (Hash $counterpart)){throw 'Native counterpart source changed'}
            if(@(Get-ChildItem -LiteralPath $cwd -Force).Count -ne 1){throw 'Counterpart left a generated temporary file'}
        }
        if(-not $record.expected_observation){$unexpected=$true}
        Save ($prefix+'-process.json') $record
        $entry.processes+=@(@{role=$role;record=($prefix+'-process.json');sha256=(Hash ($prefix+'-process.json'));
            expected_observation=$record.expected_observation;exit_code=$process.exit_code})
        Write-Output "$configuration/$role exit=$($process.exit_code) expected=$($record.expected_observation) stdout=$($process.stdout_sha256)"
    }
    foreach($artifact in $entry.artifacts){if((Hash $artifact.frozen) -cne $artifact.sha256){throw 'Frozen oracle artifact changed'}}
    $summary.configurations+=@($entry)
}
Save (Join-Path $output 'observation.json') $summary
Write-Output $output
if($unexpected){throw 'At least one native platform observation differed; no applicability decision is granted'}
