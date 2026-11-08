param(
    [Parameter(Mandatory)][string]$Interpreter,
    [Parameter(Mandatory)][string]$ReferenceInterpreter,
    [Parameter(Mandatory)][string]$ReferenceLibraryDirectory,
    [string]$RuntimeDirectory='',
    [ValidateSet('default','upstream-test')][string]$Configuration='default',
    [string]$OutputDirectory=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetHostCampaignContracts.psm1')
$platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
if($OutputDirectory -eq ''){
    $OutputDirectory=Join-Path $root ('reports/cli-readline/'+[guid]::NewGuid().ToString('N'))
}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Readline output must be a fresh directory'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$cases=@(Get-TargetHostCampaignCases -Kind readline -Platform $platform)
$rows=@()
foreach($role in @('native','ada')){
    $source=if($role -ceq 'native'){$ReferenceInterpreter}else{$Interpreter}
    $source=(Resolve-Path -LiteralPath $source).Path
    $image=Join-Path $OutputDirectory ($role+'/image')
    [void][IO.Directory]::CreateDirectory($image)
    Copy-Item -LiteralPath $source -Destination $image
    $libraries=if($role -ceq 'native'){$ReferenceLibraryDirectory}else{$RuntimeDirectory}
    if($libraries -ne ''){
        Get-ChildItem -LiteralPath $libraries -File |
            Where-Object Name -Match '\.(dll|dylib|so(?:\..+)?)$' |
            Copy-Item -Destination $image
    }
    $exe=Join-Path $image ([IO.Path]::GetFileName($source))
    foreach($case in $cases){
        $directory=Join-Path $OutputDirectory ($role+'/'+$case.name)
        [void][IO.Directory]::CreateDirectory($directory)
        $inputPath=Join-Path $directory 'input'
        [byte[]]$bytes=Get-TargetHostCampaignInputBytes -Kind readline -Case $case
        [IO.File]::WriteAllBytes($inputPath,[byte[]]$bytes)
        # A copied oracle must resolve the shared library beside that exact
        # image. POSIX dynamic loaders do not search the executable's PATH.
        $loader=if($IsWindows){'PATH'}elseif($IsMacOS){'DYLD_LIBRARY_PATH'}else{'LD_LIBRARY_PATH'}
        $environment=@{}
        $environment[$loader]=$image+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($loader)
        if($case.ContainsKey('library')){$environment.LUA_READLINELIB=$case.library}
        $arguments=@(Get-TargetHostCampaignArguments -Kind readline -Case $case)
        $process=Invoke-ConformanceProcess -Executable $exe -Arguments $arguments `
            -Directory $directory -OutputPrefix (Join-Path $directory 'process') `
            -TimeoutSeconds 30 -StandardInputPath $inputPath -Environment $environment
        $rows+=@{role=$role;name=$case.name;environment=$environment;process=$process;
            images=@(Get-ChildItem $image -File|ForEach-Object{
                @{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})}
    }
}
$failures=@()
foreach($case in $cases){
    $native=@($rows|Where-Object{$_.role -ceq 'native' -and $_.name -ceq $case.name})[0].process
    $ada=@($rows|Where-Object{$_.role -ceq 'ada' -and $_.name -ceq $case.name})[0].process
    $errors=@()
    foreach($p in @($native,$ada)){
        if($p.exit_code -ne 0 -or $p.timed_out -or $p.capture_exceeded -or
            $p.pipe_drain_failed -or $p.abnormal_exit_kind){$errors+='process did not complete cleanly'}
    }
    foreach($stream in @('stdout','stderr')){
        if([Convert]::ToBase64String([IO.File]::ReadAllBytes($native[$stream+'_path'])) -cne
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($ada[$stream+'_path']))){$errors+="$stream differs"}
    }
    if($errors.Count){$failures+=@{name=$case.name;errors=$errors}}
    else{Write-Output "CLI READLINE PASS: $($case.name)"}
}
$report=@{schema_version=2;kind='cli-readline-process-regressions';configuration=$Configuration;
    output_directory=$OutputDirectory;
    platform=$platform;source_repository_root=$root;
        reference_revision=(&git -C (Join-Path $root 'references/lua') rev-parse HEAD).Trim();
        source_bindings=@(Get-TargetHostCampaignSourcePaths -Kind readline|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}});
        synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
    repository_revision=(&git -C $root rev-parse HEAD).Trim();
    repository_dirty=(@(&git -C $root status --porcelain=v1 --untracked-files=normal).Count -ne 0);
    source=@{path='scripts/check-cli-readline.ps1';sha256=(Get-FileHash $PSCommandPath).Hash.ToLowerInvariant()};
    processes=$rows;comparison_failures=$failures;
    limitations=@('Product CLI observations do not supply measured Ada allocator telemetry or final context acceptance.',
        'Native backend selection is exercised on the actual host; this is not a TTY observation.',
        'References remain unchanged; each exact raw comparison uses the same-host original C CLI.')}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'result.json'),
    ($report|ConvertTo-Json -Depth 32).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
if($failures.Count){throw "CLI readline differs in $($failures.Count) cases; $OutputDirectory"}
Write-Output "PASS:$($cases.Count) paired native readline/fallback cases; $OutputDirectory"
