param([Parameter(Mandatory)][string]$Context,[Parameter(Mandatory)][string]$Compiler,
    [string]$RuntimeSupportDirectory='',
    [string]$ExternalInputs='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetAllocatorWitnesses.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$plan=Get-TargetContextPlan -Root $root
$selected=@($plan.contexts|Where-Object context -CEQ $Context)
if($selected.Count -ne 1){throw 'Unknown allocator context'}
$selected=$selected[0]
$hostPlatform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
if($selected.platform -cne $hostPlatform){throw 'Allocator collector identifies another host'}
$compilerPath=(Resolve-Path -LiteralPath $Compiler).Path
$prefix=if($selected.configuration -ceq 'upstream-test'){'upstream-test/'}else{''}
$suffix=if($IsWindows){'.exe'}else{''}
$executable=Join-Path $root "tests/bin/$prefix$($selected.library_type)/conformance_runner$suffix"
$adaRuntime=Join-Path $root "lib/$prefix$($selected.profile)/$($selected.library_type)"
$nativeRuntime=Join-Path $root "build/conformance/$($selected.configuration)/lib"
$external=$null
if($ExternalInputs -ne ''){
    # Development replay uses immutable copies instead of replacing generated
    # products. The witness keeps this separate input identity and the final
    # context reader refuses it, regardless of its successful process results.
    $inputPath=(Resolve-Path -LiteralPath $ExternalInputs).Path
    $inputs=Get-Content -LiteralPath $inputPath -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    if($inputs.kind -cne 'target-allocator-external-input-snapshot' -or $inputs.context -cne $Context){
        throw 'External allocator inputs identify another context'
    }
    $executable=$inputs.input_paths.ada_launcher
    $adaRuntime=$inputs.input_paths.ada_runtime
    $nativeRuntime=$inputs.input_paths.c_runtime
    $external=@{path=$inputPath;sha256=(Get-FileHash -LiteralPath $inputPath).Hash.ToLowerInvariant()}
}
$directory=Join-Path $root ('reports/target-builds/'+$selected.id+'/allocator-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$witnesses=@()
foreach($kind in @('ada-ceiling','native-observer')){
    if($kind -ceq 'native-observer' -and $selected.configuration -cne 'upstream-test'){continue}
    $output=Join-Path $directory $kind
    [void][IO.Directory]::CreateDirectory($output)
    $raw=Join-Path $output 'raw'
    $runtime=if($kind -ceq 'ada-ceiling'){$adaRuntime}else{$nativeRuntime}
    $environment=@{}
    $search=@($runtime)
    if($RuntimeSupportDirectory -ne ''){$search+=$RuntimeSupportDirectory}
    $search+=Split-Path -Parent $compilerPath
    foreach($name in @('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH')){
        $environment[$name]=($search -join [IO.Path]::PathSeparator)+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($name)
    }
    $scriptName=if($kind -ceq 'ada-ceiling'){'test-conformance-allocator-ceiling.ps1'}else{'test-native-allocator-observer.ps1'}
    $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot $scriptName))
    if($kind -ceq 'ada-ceiling'){$arguments+=@('-Interpreter',$executable,'-Configuration',$selected.configuration)}
    else{$arguments+=@('-Compiler',$compilerPath,'-LibraryDirectory',$runtime)}
    $arguments+=@('-OutputDirectory',$raw)
    $process=Invoke-ConformanceProcess -Executable (Get-Command pwsh -ErrorAction Stop).Source -Arguments $arguments `
        -Directory $root -OutputPrefix (Join-Path $output 'producer') -TimeoutSeconds 600 -Environment $environment
    foreach($stream in @('stdout','stderr')){Write-Output ([IO.File]::ReadAllText($process[$stream+'_path']))}
    if($process.exit_code -ne 0 -or $process.timed_out -or $process.capture_exceeded -or $process.pipe_drain_failed -or
        $process.process_tree_kill_error -or $process.abnormal_exit_kind){throw "Actual allocator producer failed: $kind"}
    $parameters=@{Root=$root;Context=$Context;Kind=$kind;ProducerReport=(Join-Path $raw 'result.json');
        ProducerProcess=$process;RuntimeDirectory=$runtime;Compiler=$compilerPath;Output=(Join-Path $output 'witness.json')}
    if($kind -ceq 'ada-ceiling'){$parameters.Executable=$executable}
    if($null -ne $external){$parameters.ExternalInputSnapshot=$external}
    $witnesses+=New-TargetAllocatorWitness @parameters
}
$index=@{schema_version=1;kind='target-context-allocator-index';context=$Context;
    repository_revision=(& git -C $root rev-parse HEAD).Trim();witnesses=$witnesses;
    runtime_acceptance=$false;coverage_authority=$false}
if($null -ne $external){$index.external_input_snapshot=$external;$index.source_build_provenance_verified=$false}
$path=Join-Path $directory 'index.json'
[IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $index -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "OBSERVED: actual allocator context reports=$($witnesses.Count); target acceptance=False; index=$path"
return @{index=$path;witnesses=$witnesses;runtime_acceptance=$false;coverage_authority=$false}
