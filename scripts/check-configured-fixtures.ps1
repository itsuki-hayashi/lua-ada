param(
    [Parameter(Mandatory)][string]$Interpreter,
    [Parameter(Mandatory)][string]$ReferenceInterpreter,
    [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string]$Configuration,
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [Parameter(Mandatory)][string]$ReferenceLibraryDirectory,
    [ValidateSet('development','validation','release')][string]$Profile='validation',
    [ValidateSet('static','static-pic','relocatable')][string]$LibraryType='static',
    [string]$Report=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConfiguredFixtureEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
& (Join-Path $PSScriptRoot 'test-configured-fixture-selection.ps1')
if($Report -eq ''){$Report=Join-Path $root ('reports/core-image/configured-'+[guid]::NewGuid().ToString('N')+'/result.json')}
$Report=[IO.Path]::GetFullPath($Report)
if(-not ([IO.Path]::GetRelativePath($root,$Report).Replace('\','/')).StartsWith('reports/',[StringComparison]::Ordinal) -or
    (Test-Path -LiteralPath $Report)){throw 'Configured fixture report must be a new first-party observation under reports'}
$directory=Split-Path -Parent $Report;[void][IO.Directory]::CreateDirectory($directory)
$revision=(&git -C $root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Configured fixture source revision is unknown'}
$dirty=@(&git -C $root status --porcelain=v1 --untracked-files=normal).Count -ne 0
$audit=Get-ConfiguredFixtureAudit -Root $root
$raw=[ordered]@{schema_version=1;kind='configured-fixture-observations';configuration=$Configuration;
    repository_root=$root;platform=$(if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'});profile=$Profile;library_type=$LibraryType;
    repository_revision=$revision;repository_dirty=$dirty;reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
    runtime_acceptance=$false;coverage_authority=$false;synthetic_fixture=$false;
    fixture_selection_audit=$audit;
    fixture_selection_audit_sha256=(Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $audit -Depth 12 -Compress))));
    source_bindings=@(Get-ConfiguredFixtureSources $Configuration|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}});
    runtimes=@();processes=@()}
$raw.context=$Configuration+'/'+$raw.platform+'/'+$Profile+'/'+$(if($LibraryType -ceq 'relocatable'){'shared'}else{$LibraryType})
$definitions=@(Get-ConfiguredFixtureDefinitions $Configuration)
try{
    foreach($role in @('ReferenceC','Ada')){
        $exe=(Resolve-Path -LiteralPath $(if($role -ceq 'Ada'){$Interpreter}else{$ReferenceInterpreter})).Path
        $runtime=(Resolve-Path -LiteralPath $(if($role -ceq 'Ada'){$RuntimeDirectory}else{$ReferenceLibraryDirectory})).Path
        $libraries=@(Get-ChildItem -LiteralPath $runtime -File|Where-Object{$_.Name -cmatch '\.(?:a|dll|dylib|so(?:\.[0-9.]+)?)$'}|
            ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
        $raw.runtimes+=@{role=$role;executable=$exe;executable_sha256=(Get-FileHash $exe).Hash.ToLowerInvariant();library_files=$libraries}
        $environment=@{PATH=($runtime+[IO.Path]::PathSeparator+$env:PATH);
            LD_LIBRARY_PATH=($runtime+[IO.Path]::PathSeparator+$env:LD_LIBRARY_PATH);
            DYLD_LIBRARY_PATH=($runtime+[IO.Path]::PathSeparator+$env:DYLD_LIBRARY_PATH);
            LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';MEMLIMIT='2147483648'}
        # Configuration is measured before either fixture is allowed to run.
        # Wrong-role or T-absent binaries cannot borrow their neighbour's probe.
        $p=Invoke-ConformanceProcess -Executable $exe -Arguments @('--conformance-config') -Directory $root `
            -OutputPrefix (Join-Path $directory ($role+'-configuration')) -TimeoutSeconds 60 -Environment $environment
        $raw.processes+=@{role=$role;operation='configuration';process=$p}
        if($p.exit_code -ne 0 -or $p.stderr_bytes -ne 0 -or $p.timed_out -or $p.abnormal_exit_kind){throw 'Configured fixture measured handshake failed'}
        [void](Test-ConformanceConfiguration -Observed (Get-Content $p.stdout_path -Raw|ConvertFrom-Json -AsHashtable) `
            -Configuration $Configuration -Target $role -AllocatorLimitBytes 2147483648)
        foreach($definition in $definitions){
            if($role -cnotin @(Get-ConfiguredFixtureRoles $definition)){continue}
            $fixtureInput=Join-Path $root $definition.source
            $binary=$definition.Contains('execution') -and $definition.execution -ceq 'native-dumped-chunk'
            if($binary){
                if($role -ceq 'ReferenceC'){
                    $run=[guid]::NewGuid().ToString('N');$prefix=Join-Path $directory ('ReferenceC-produce-'+$definition.id)
                    $environment.LUA_ADA_CONFORMANCE_TELEMETRY=$prefix;$environment.LUA_ADA_CONFORMANCE_RUN_ID=$run
                    $chunkPath=$prefix+'.luac'
                    $p=Invoke-ConformanceProcess -Executable $exe -Arguments (Get-ConfiguredFixtureProducerArguments -Root $root -Definition $definition -Output $chunkPath) `
                        -Directory $root -OutputPrefix $prefix -TimeoutSeconds 900 -Environment $environment
                    $row=@{role=$role;operation=('produce-'+$definition.id);process=$p;telemetry=@{path=($prefix+'.'+$p.process_id+'.json');run_id=$run;sha256=$null}}
                    $raw.processes+=$row
                    if(Test-Path -LiteralPath $row.telemetry.path){$row.telemetry.sha256=(Get-FileHash $row.telemetry.path).Hash.ToLowerInvariant()}
                    if($p.exit_code -ne 0 -or $p.stderr_bytes -ne 0 -or $p.timed_out -or $p.abnormal_exit_kind){throw "Configured fixture native producer failed: $($definition.id); see $directory"}
                    $row.output_chunk=@{path=$chunkPath;sha256=(Get-FileHash $chunkPath).Hash.ToLowerInvariant();bytes=(Get-Item $chunkPath).Length}
                }
                $produced=@($raw.processes|Where-Object{$_.role -ceq 'ReferenceC' -and $_.operation -ceq ('produce-'+$definition.id)})
                if($produced.Count -ne 1){throw 'Configured fixture requires its actual native chunk producer first'}
                $fixtureInput=$produced[0].output_chunk.path
            }
            $run=[guid]::NewGuid().ToString('N');$prefix=Join-Path $directory ($role+'-'+$definition.id)
            $environment.LUA_ADA_CONFORMANCE_TELEMETRY=$prefix;$environment.LUA_ADA_CONFORMANCE_RUN_ID=$run
            $p=Invoke-ConformanceProcess -Executable $exe -Arguments (Get-ConfiguredFixtureArguments -Root $root -Definition $definition -FixtureInput $fixtureInput) `
                -Directory $root -OutputPrefix $prefix -TimeoutSeconds 900 -Environment $environment
            $row=@{role=$role;operation=$definition.id;process=$p;telemetry=@{path=($prefix+'.'+$p.process_id+'.json');run_id=$run;sha256=$null}}
            if($binary){$row.input_chunk=@{path=$fixtureInput;sha256=$produced[0].output_chunk.sha256;bytes=$produced[0].output_chunk.bytes}}
            $raw.processes+=$row
            if(Test-Path -LiteralPath $row.telemetry.path){$row.telemetry.sha256=(Get-FileHash $row.telemetry.path).Hash.ToLowerInvariant()}
            if($p.exit_code -ne 0 -or $p.stderr_bytes -ne 0 -or $p.timed_out -or $p.abnormal_exit_kind){throw "Configured fixture actual execution failed: $role/$($definition.id); see $directory"}
        }
    }
    $observed=Assert-ConfiguredFixtureReport -Root $root -Report $raw -Configuration $Configuration -Interpreter (Resolve-Path $Interpreter).Path
    Write-Output "PASS: actual configured $Configuration fixture pair ($($observed.operations -join ', ')); runtime acceptance=False"
}finally{
    [IO.File]::WriteAllText($Report,(ConvertTo-Json -InputObject $raw -Depth 32).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
}
& (Join-Path $PSScriptRoot 'test-configured-fixtures.ps1') -Report $Report
