param(
    [Parameter(Mandatory)][string]$Interpreter,
    [switch]$NativeProtocol,[switch]$PromptProtocol,[switch]$BatchProtocol,
    [ValidateSet('Ada','ReferenceC')][string]$RuntimeRole='Ada',
    [ValidateSet('default','upstream-test')][string]$Configuration='default',
    [ValidateSet('development','validation','release')][string]$Profile='validation',
    [ValidateSet('static','static-pic','relocatable')][string]$LibraryType='static',
    [string]$Report='', [string]$RuntimeDirectory='',
    [switch]$CollectAllObservations,[switch]$DevelopmentObservation
)
$ErrorActionPreference='Stop'
if(($CollectAllObservations -or $DevelopmentObservation) -and
    (-not $CollectAllObservations -or -not $DevelopmentObservation -or
     $RuntimeRole -cne 'ReferenceC' -or -not $PromptProtocol -or $NativeProtocol -or $BatchProtocol)){
    throw 'CollectAllObservations requires explicit development-only native prompt observation'
}
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'CliFixtureEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'CliFixtureCases.psm1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$executable = (Resolve-Path -LiteralPath $Interpreter).Path
$fixtureRoot = Join-Path $projectRoot ('reports/core-image/'+[Guid]::NewGuid().ToString('N')+'/cli-fixtures')
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$newline = [Environment]::NewLine

# Every fixture is authored here rather than copied from upstream. File
# preamble handling is a loader behavior, distinct from source evaluation.
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'arguments.lua'),
    'print(arg[1],arg[2]); print(...)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot '-script.lua'), 'print(42)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'empty.lua'), '', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'source-name.lua'),
    'local d=debug.getinfo(1,"S"); print(d.source,d.short_src)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'shebang.lua'),
    "#!/usr/bin/env lua`nprint(42)", $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'bom.lua'),
    "#!/usr/bin/env lua`nprint(42)", [Text.UTF8Encoding]::new($true))

[IO.File]::WriteAllText((Join-Path $fixtureRoot 'cli_lib.lua'),
    "return { tag = 'lib' }", $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'cli_init.lua'),
    "init_ran = 'file'", $utf8)
$banner = 'Lua 5.5.1  Copyright (C) 1994-2026 Lua.org, PUC-Rio'

[IO.File]::WriteAllText((Join-Path $fixtureRoot 'large-source.lua'),
    ('--[[' + ('a' * 1000001) + ']] print(42)'), $utf8)
[IO.File]::Copy((Join-Path $projectRoot 'tests/lua/cli_prompt_controls.lua'),
    (Join-Path $fixtureRoot 'prompt-controls.lua'))
if((Get-FileHash (Join-Path $projectRoot 'tests/lua/cli_prompt_controls.lua')).Hash -cne
    (Get-FileHash (Join-Path $fixtureRoot 'prompt-controls.lua')).Hash){
    throw 'Prompt callback fixture copy changed bytes'
}

if(@($NativeProtocol,$PromptProtocol,$BatchProtocol|Where-Object{$_}).Count -gt 1){throw 'Choose one explicit CLI protocol subset'}
$mode=if($BatchProtocol){'batch'}elseif($PromptProtocol){'prompt'}elseif($NativeProtocol){'native'}else{'full'}
$platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
if($RuntimeDirectory -eq ''){
    $part=if($Configuration -ceq 'upstream-test'){'upstream-test/'}else{''}
    $RuntimeDirectory=Join-Path $projectRoot "lib/$part$Profile/$LibraryType"
}
$RuntimeDirectory=(Resolve-Path $RuntimeDirectory).Path
if($Report -eq ''){$Report=Join-Path $fixtureRoot 'result.json'}
$Report=[IO.Path]::GetFullPath($Report)
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Report))
$revision=(&git -C $projectRoot rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Cannot identify CLI observation source'}
$changes=@(&git -C $projectRoot -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if($LASTEXITCODE -ne 0){throw 'Cannot identify CLI observation source state'}
$raw=@{schema_version=1;kind='cli-fixture-observations';mode=$mode;runtime_role=$RuntimeRole;synthetic_fixture=$false;
    runtime_acceptance=$false;coverage_authority=$false;repository_revision=$revision;repository_dirty=($changes.Count -ne 0);
    context=($Configuration+'/'+$platform+'/'+$Profile+'/'+$(if($LibraryType -ceq 'relocatable'){'shared'}else{$LibraryType}));
    platform=$platform;executable=$executable;executable_sha256=(Get-FileHash $executable).Hash.ToLowerInvariant();
    runtime_directory=$RuntimeDirectory;
    library_files=@(Get-ChildItem $RuntimeDirectory -File|Where-Object{$_.Name -cmatch '\.(?:a|dll|dylib|so(?:\.[0-9.]+)?)$'}|
        ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}});
    working_directory=$fixtureRoot;source_repository_root=$projectRoot;
    source_bindings=@(Get-CliFixtureSources|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $projectRoot $_)).Hash.ToLowerInvariant()}});
    fixture_files=@(Get-ChildItem $fixtureRoot -File|ForEach-Object{@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}});
    processes=@()}
if($CollectAllObservations){
    $raw['development_observation']=$true
    $raw['contract_failures']=@()
}

function Invoke-Case {
    param([hashtable]$Case,[switch]$ConfigurationProbe)
    # Freeze input and both output byte streams for every child. The shared
    # reader rechecks the original contract against these physical captures.
    $prefix=Join-Path $fixtureRoot ('captures/'+$(if($ConfigurationProbe){'configuration'}else{[string]$raw.processes.Count}))
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $prefix))
    $inputPath=$prefix+'.input'
    [IO.File]::WriteAllText($inputPath,$(if($Case.Contains('Input')){$Case.Input}else{''}),$utf8)
    $environment=if($Case.Contains('Env')){$Case.Env}else{@{}}
    $processEnvironment=@{}
    foreach($name in $environment.Keys){$processEnvironment[$name]=$environment[$name]}
    foreach($name in @('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH')){
        $processEnvironment[$name]=$RuntimeDirectory+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($name)
    }
    $process=Invoke-ConformanceProcess -Executable $executable -Arguments @($Case.Args) -Directory $fixtureRoot `
        -OutputPrefix $prefix -TimeoutSeconds 30 -Environment $processEnvironment -StandardInputPath $inputPath `
        -ObserveEarlyInputClose:($Case.Contains('InputMayCloseEarly') -and $Case.InputMayCloseEarly)
    $diagnostic=$RuntimeRole -ceq 'ReferenceC' -and $Configuration -ceq 'upstream-test' -and
        $mode -ceq 'prompt' -and $Case.Title -ceq 'REPL prompt typed exit without close retains status'
    $collect=$CollectAllObservations -and -not $ConfigurationProbe -and $Case.Title.StartsWith('REPL ',[StringComparison]::Ordinal)
    $unreviewedDiagnostic=$diagnostic -and $platform -cne 'windows'
    $row=@{title=$Case.Title;environment=$environment;process=$process;
        observation_disposition=$(if($diagnostic){'observed-native-test-teardown-diagnostic'}else{'clean-operation'});
        passing_execution_evidence=(-not $diagnostic)}
    if($diagnostic -and -not $unreviewedDiagnostic){
        $row['feature_review']=Assert-CliNativeTestExitDirection -Root $projectRoot
    }
    if($ConfigurationProbe){$raw['configuration_probe']=$row}else{$raw.processes+=,$row}
    try{
        if($unreviewedDiagnostic){throw 'Native T no-close diagnostic requires fresh platform applicability review'}
        $output=Assert-CliCaseCapture -Case $Case -Row $row -Executable $executable `
            -ExecutableHash $raw.executable_sha256 -Directory $fixtureRoot -NativeTestDiagnostic:$diagnostic
        if($collect){$row['contract_match']=$true}
    }catch{
        if(-not $collect){throw}
        $row['contract_match']=$false
        $row['contract_error']=$_.Exception.Message
        $raw.contract_failures+=@{title=$Case.Title;message=$_.Exception.Message;
            stdout_sha256=$process.stdout_sha256;stderr_sha256=$process.stderr_sha256;exit_code=$process.exit_code}
        # Preserve the original stream even when a platform backend violates
        # the current comparison contract. This return value supplies no pass.
        $output=[IO.File]::ReadAllText($process.stdout_path)
    }finally{
        if($collect){
            # The normal validator above evaluated a provisional contract
            # row. Serialize only an observation label; no collected process
            # is promoted to passing evidence by this development campaign.
            $row.passing_execution_evidence=$false
            $row.observation_disposition=if($unreviewedDiagnostic){'unreviewed-native-test-teardown-observation'}else{'development-only-observation'}
        }
    }
    if($collect){
        Write-Host "CLI COLLECTED: $($Case.Title); contract_match=$($row.contract_match); passing evidence=False"
        return $output
    }
    if($diagnostic){Write-Host "CLI OBSERVED DIAGNOSTIC: $($Case.Title) (no passing or cleanup evidence)"}
    else{Write-Host "CLI PASS: $($Case.Title)"}
    return $output
}

try{
    if($RuntimeRole -ceq 'ReferenceC'){$null=Invoke-Case (Get-CliConfigurationCase $Configuration) -ConfigurationProbe}
    $probes=@(Get-CliProbeCases)
    $defaultPath=Invoke-Case $probes[0]
    $defaultCPath=Invoke-Case $probes[1]
    $definitions=Get-CliCaseDefinitions -DefaultPackagePath $defaultPath `
        -DefaultPackageCPath $defaultCPath -Platform $platform -Mode $mode
    foreach($case in $definitions.cases){$null=Invoke-Case $case}
    if($CollectAllObservations){
        Write-Output "COLLECTED: CLI native prompt processes; contract_failures=$($raw.contract_failures.Count); development-only, strict pair remains unaccepted"
    }else{
        $observed=Assert-CliFixtureReport -Root $projectRoot -Report $raw -Interpreter $executable -Mode $mode
        Write-Output "OBSERVED: CLI $mode ($($observed.clean_operations.Count) clean operations/$($observed.native_test_diagnostics.Count) native test diagnostics); runtime acceptance=False"
    }
}finally{
    [IO.File]::WriteAllText($Report,(ConvertTo-Json -InputObject $raw -Depth 32).Replace("`r`n","`n")+"`n",$utf8)
}
exit 0
