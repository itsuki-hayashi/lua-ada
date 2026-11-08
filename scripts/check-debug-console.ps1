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
    $OutputDirectory=Join-Path $root ('reports/debug-console/'+[guid]::NewGuid().ToString('N'))
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$cases=@(Get-TargetHostCampaignCases -Kind console-lua -Platform $platform)
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
        $inputPath=Join-Path $directory 'stdin'
        [IO.File]::WriteAllBytes($inputPath,(Get-TargetHostCampaignInputBytes -Kind console-lua -Case $case))
        $loader=if($IsWindows){'PATH'}elseif($IsMacOS){'DYLD_LIBRARY_PATH'}else{'LD_LIBRARY_PATH'}
        $environment=@{}
        $environment[$loader]=$image+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($loader)
        $process=Invoke-ConformanceProcess -Executable $exe -Arguments (Get-TargetHostCampaignArguments -Kind console-lua -Case $case) `
            -Directory $directory -OutputPrefix (Join-Path $directory 'process') `
            -TimeoutSeconds 30 -StandardInputPath $inputPath -Environment $environment
        $rows+=@{role=$role;name=$case.name;setup=$case.setup;environment=$environment;
            process=$process;images=@(Get-ChildItem $image -File|ForEach-Object{
                @{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})}
    }
}
$report=@{schema_version=2;kind='debug-console-process-regressions';configuration=$Configuration;
    output_directory=$OutputDirectory;
    platform=$platform;source_repository_root=$root;
        reference_revision=(&git -C (Join-Path $root 'references/lua') rev-parse HEAD).Trim();
        source_bindings=@(Get-TargetHostCampaignSourcePaths -Kind console-lua|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}});
        synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
    repository_revision=(& git -C $root rev-parse HEAD).Trim();
    repository_dirty=(@(&git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal).Count -ne 0);
    source=@{path='scripts/check-debug-console.ps1';sha256=(Get-FileHash $PSCommandPath).Hash.ToLowerInvariant()};
    processes=$rows}
# Preserve failures as observations too. Product CLI runs have no measured
# allocator sidecar; this report never invents one or claims matrix acceptance.
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'result.json'),
    ($report|ConvertTo-Json -Depth 32).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
foreach($case in $cases){
    $native=@($rows|Where-Object{ $_.role -ceq 'native' -and $_.name -ceq $case.name })[0].process
    $ada=@($rows|Where-Object{ $_.role -ceq 'ada' -and $_.name -ceq $case.name })[0].process
    foreach($p in @($native,$ada)){
        if($p.exit_code -ne 0 -or $p.timed_out -or $p.capture_exceeded -or
            $p.pipe_drain_failed -or $p.abnormal_exit_kind -or
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($p.stdout_path)) -cne
                [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(
                    $(if($IsWindows){"AFTER`r`n"}else{"AFTER`n"})))){
            throw "Debug console operation failed: $($case.name); $OutputDirectory"
        }
    }
    foreach($stream in @('stdout','stderr')){
        $left=[Convert]::ToBase64String([IO.File]::ReadAllBytes($native[$stream+'_path']))
        $right=[Convert]::ToBase64String([IO.File]::ReadAllBytes($ada[$stream+'_path']))
        if($left -cne $right){throw "Debug console $stream differs: $($case.name); $OutputDirectory"}
    }
    Write-Output "DEBUG CONSOLE PASS: $($case.name)"
}
Write-Output "PASS:$($cases.Count) actual paired debug console cases; $OutputDirectory"
