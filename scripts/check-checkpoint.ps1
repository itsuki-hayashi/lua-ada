param([Parameter(Mandatory)][string]$Context,[switch]$PlanOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CheckpointPlan.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
$plan=Get-CheckpointPlan -Root $root
$matches=@($plan.contexts|Where-Object context -CEQ $Context)
if($matches.Count -ne 1){throw 'Unknown bounded checkpoint context'}
$selected=$matches[0];$type=$selected.library_type;$configuration=$selected.configuration
$platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
$prefix=if($configuration -ceq 'upstream-test'){'upstream-test/'}else{''}
$suffix=if($selected.platform -ceq 'windows'){'.exe'}else{''}
$runtime=Join-Path $root "lib/${prefix}validation/$type"
$bin=Join-Path $root "tests/bin/$prefix$type"
$cli=Join-Path $root "cli/bin/$prefix$type/lua_ada$suffix"
$oracle=Join-Path $root "build/conformance/$configuration/bin/lua$suffix"
$oracleLibrary=Join-Path $root "build/conformance/$configuration/lib"
$steps=@('source-guards','runtime-build','tests-build','cli-build','core-c-sdk-native',
    'aunit','syntax-api','configuration','frontend-opcodes','canonical-compiler-runtime',
    'abi','layout','output-policy','batch-cli-79-plus-2','debug-console-lua','readline',
    'readline-signatures','debug-console-c4','binary-cli','lifecycle','allocator-ceiling','launcher-isolation')
if($configuration -ceq 'upstream-test'){$steps+=@('real-t-adapter','managed-telemetry','native-allocator-observer')}
if($PlanOnly){
    @{context=$Context;steps=$steps;batch_cli_source_cases=79;batch_cli_package_probes=2;
        full_cli_processes=112;full_cli_gate='deferred-backend-protocol';full_target_contexts=26;
        runtime_build_requested=$false;runtime_acceptance=$false;coverage_authority=$false}|ConvertTo-Json -Depth 16
    exit 0
}
if($selected.platform -cne $platform){throw 'Checkpoint identifies another host'}
$directory=Join-Path $root ('reports/checkpoint/'+$selected.id+'-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$records=@();$passed=$false;$saved=@{}
foreach($name in @('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH','LUA_ADA_CONFIGURATION','LUA_ADA_ABI_RUNTIME_ARCHIVE','LUA_ADA_TASKING_RUNTIME_ARCHIVE','LUA_ADA_RUNTIME_LIBRARY_DIR')){
    $saved[$name]=[Environment]::GetEnvironmentVariable($name)
}
function Invoke-Step([string]$Name,[string[]]$Arguments){
    $process=Invoke-ConformanceProcess -Executable (Get-Command alr -ErrorAction Stop).Source -Arguments $Arguments -Directory $root `
        -OutputPrefix (Join-Path $directory $Name) -TimeoutSeconds 3600
    $script:records+=@{name=$Name;process=$process}
    foreach($stream in @('stdout','stderr')){Write-Output ([IO.File]::ReadAllText($process[$stream+'_path']))}
    if($process.exit_code -ne 0 -or $process.timed_out -or $process.capture_exceeded -or $process.pipe_drain_failed -or
        $process.process_tree_kill_error -or $process.abnormal_exit_kind){throw "Checkpoint gate failed: $Name"}
}
function Invoke-Check([string]$Name,[string]$Script,[string[]]$Arguments=@()){
    Invoke-Step $Name (@('exec','--','pwsh','-NoProfile','-File',(Join-Path $PSScriptRoot $Script))+$Arguments)
}
try{
    Test-ConformanceReferenceTree -Root $root
    $env:LUA_ADA_CONFIGURATION=$configuration
    Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1')
    $support=Get-SelectedAdaRuntime
    if($IsMacOS){
        $env:LUA_ADA_ABI_RUNTIME_ARCHIVE=$support.CoreArchive
        $env:LUA_ADA_TASKING_RUNTIME_ARCHIVE=$support.TaskingArchive
        $env:LUA_ADA_RUNTIME_LIBRARY_DIR=$support.Directory
    }
    foreach($guard in @('check-documentation.ps1','test-pe-unwind.ps1','test-aunit-launch.ps1','test-aunit-evidence.ps1',
        'test-foreign-contract-evidence.ps1','test-configured-fixture-selection.ps1','test-cli-batch-protocol.ps1',
        'test-native-module-linkage.ps1','test-native-lua-fixture-evidence.ps1','test-file-consumer-io.ps1')){
        Invoke-Check ([IO.Path]::GetFileNameWithoutExtension($guard)) $guard
    }
    Invoke-Step runtime-build @('-n','build','--validation','--',"-XLUA_ADA_LIBRARY_TYPE=$type","-XLUA_ADA_CONFIGURATION=$configuration",'-XLUA_ADA_PREBUILT=false')
    foreach($crate in @('tests','cli')){
        Invoke-Step ($crate+'-build') @('-n','-C',$crate,'build','--validation','--profiles=lua_ada=validation','--',
            "-XLUA_ADA_LIBRARY_TYPE=$type","-XLUA_ADA_CONFIGURATION=$configuration",'-XLUA_ADA_PREBUILT=true')
    }
    # These are the actual selected SAL and compiler support directories for
    # every subsequent child. Nothing points to an ambient sibling profile.
    $selectedPath=& alr exec -- pwsh -NoProfile -Command '$env:PATH'
    if($LASTEXITCODE -ne 0){throw 'Cannot identify selected compiler environment'}
    $env:PATH=$runtime+[IO.Path]::PathSeparator+($selectedPath-join '').Trim()
    $env:LD_LIBRARY_PATH=$runtime+[IO.Path]::PathSeparator+$support.Directory+[IO.Path]::PathSeparator+$saved.LD_LIBRARY_PATH
    $env:DYLD_LIBRARY_PATH=$runtime+[IO.Path]::PathSeparator+$support.Directory+[IO.Path]::PathSeparator+$saved.DYLD_LIBRARY_PATH
    Invoke-Check core-c-sdk-native check-core-image.ps1 @('-Configuration',$configuration,'-Profile','validation','-LibraryType',$type,
        '-UseExistingRuntime','-TargetPolicy','remaining-upstream-compatibility')
    Invoke-Check aunit check-aunit-evidence.ps1 @('-Executable',"$bin/test_runner$suffix",'-Configuration',$configuration,'-Profile','validation','-LibraryType',$type)
    Invoke-Step syntax-api @('exec','--',"$bin/syntax_consumer$suffix")
    Invoke-Check configuration check-runtime-configuration.ps1 @('-Probe',"$bin/lua-configuration_probe$suffix",'-Configuration',$configuration,'-RuntimeDirectory',$runtime)
    Invoke-Check frontend-opcodes check-frontend.ps1 @('-Probe',"$bin/lexer_probe$suffix",'-OpcodeProbe',"$bin/lua-opcode_probe$suffix")
    Invoke-Check canonical-compiler-runtime check-canonical-compiler.ps1 @('-Probe',"$bin/lua-canonical_compiler_probe$suffix",'-RuntimeProbe',"$bin/lua-canonical_runtime_probe$suffix",
        '-ReferenceInterpreter',$oracle,'-Configuration',$configuration,'-RuntimeDirectory',$runtime)
    Invoke-Check abi check-abi.ps1
    Invoke-Check layout check-layout.ps1 @('-AdaProbe',"$bin/lua-codec_layout_probe$suffix")
    Invoke-Check output-policy check-output-policy.ps1 @('-Consumer',"$bin/output_consumer$suffix",'-Interpreter',$cli)
    Invoke-Check batch-cli check-cli.ps1 @('-Interpreter',$cli,'-BatchProtocol','-Configuration',$configuration,'-Profile','validation','-LibraryType',$type,
        '-RuntimeDirectory',$runtime,'-Report',(Join-Path $directory 'batch-cli.json'))
    Invoke-Check debug-console-lua check-debug-console.ps1 @('-Interpreter',$cli,'-ReferenceInterpreter',$oracle,'-ReferenceLibraryDirectory',$oracleLibrary,
        '-RuntimeDirectory',$runtime,'-Configuration',$configuration,'-OutputDirectory',(Join-Path $directory 'console-lua'))
    Invoke-Check readline check-cli-readline.ps1 @('-Interpreter',$cli,'-ReferenceInterpreter',$oracle,'-ReferenceLibraryDirectory',$oracleLibrary,
        '-RuntimeDirectory',$runtime,'-Configuration',$configuration,'-OutputDirectory',(Join-Path $directory 'readline'))
    $compilerOutput=& alr exec -- pwsh -NoProfile -Command '(Get-Command gcc -ErrorAction Stop).Source'
    if($LASTEXITCODE -ne 0){throw 'Cannot identify selected C compiler'}
    $compiler=($compilerOutput-join '').Trim()
    Invoke-Check readline-signatures test-cli-readline-portability.ps1 @('-Compiler',$compiler)
    Invoke-Check debug-console-c4 check-debug-console-c.ps1 @('-Interpreter',$oracle,'-AdaConsumer',
        (Join-Path $root "build/c-api/bin/${prefix}validation/$type/builtin_api_contract$suffix"),'-Compiler',$compiler,
        '-ReferenceLibrary',$oracleLibrary,'-AdaRuntimeDirectory',$runtime,'-Configuration',$configuration,'-OutputDirectory',(Join-Path $directory 'console-c'))
    Invoke-Check binary-cli check-binary-cli.ps1 @('-Interpreter',$cli,'-ReferenceInterpreter',$oracle,'-RuntimeDirectory',$runtime)
    Invoke-Check lifecycle check-lifecycle.ps1 @('-Interpreter',$cli)
    Invoke-Check allocator-ceiling test-conformance-allocator-ceiling.ps1 @('-Interpreter',"$bin/conformance_runner$suffix",'-Configuration',$configuration,
        '-OutputDirectory',(Join-Path $directory 'allocator-ceiling'))
    Invoke-Check launcher-isolation test-conformance-launcher.ps1 @('-Interpreter',"$bin/conformance_runner$suffix",'-ReferenceInterpreter',$oracle,
        '-ReferenceLibraryDirectory',$oracleLibrary,'-Configuration',$configuration)
    if($configuration -ceq 'upstream-test'){
        Invoke-Check real-t-adapter check-conformance-adapter.ps1 @('-Interpreter',"$bin/conformance_runner$suffix")
        Invoke-Check managed-telemetry check-conformance-telemetry.ps1 @('-Interpreter',"$bin/conformance_runner$suffix",'-Configuration',$configuration)
        Invoke-Check native-allocator-observer test-native-allocator-observer.ps1 @('-Compiler',$compiler,'-LibraryDirectory',$oracleLibrary,
            '-OutputDirectory',(Join-Path $directory 'native-allocator-observer'))
    }
    $passed=$true
}finally{
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
    $report=@{schema_version=1;kind='bounded-progress-checkpoint';context=$Context;checkpoint_passed=$passed;
        repository_revision=(&git -C $root rev-parse HEAD).Trim();
        repository_dirty=(@(&git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal).Count -ne 0);processes=$records;
        batch_cli_source_cases=79;batch_cli_package_probes=2;full_cli112='deferred';full_target26='deferred';
        runtime_acceptance=$false;coverage_authority=$false}
    [IO.File]::WriteAllText((Join-Path $directory 'result.json'),(ConvertTo-Json -InputObject $report -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
}
Write-Output "PASS: bounded checkpoint $Context; full112CLI/full26target acceptance remains deferred; $directory"
