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
if($OutputDirectory -eq ''){
    $OutputDirectory=Join-Path $root ('reports/debug-console/'+[guid]::NewGuid().ToString('N'))
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$ordinary="require('debug').debug();print('AFTER')"
$cases=@(
    @{name='write-and-continue';setup=$ordinary;input="io.stderr:write(1000)`ncont`n"},
    @{name='discard-results';setup=$ordinary;input="return 123,'discard'`ncont`n"},
    @{name='syntax-error-recovery';setup=$ordinary;input="local =`nio.stderr:write('RECOVERED')`ncont`n"},
    @{name='error-object-conversion';setup=$ordinary;input="error(setmetatable({},{__tostring=function()return 'OBJECT ERROR'end}))`nio.stderr:write('RECOVERED')`ncont`n"},
    @{name='command-environment';setup="local console_local=99;_G.console_global=17;require('debug').debug();assert(console_global==18);print('AFTER')";input="assert(console_local==nil);console_global=console_global+1`ncont`n"},
    @{name='eof';setup=$ordinary;input=''},
    @{name='partial-final-command';setup=$ordinary;input="io.stderr:write('E')"},
    @{name='embedded-nul';setup=$ordinary;input="io.stderr:write('N')`0ignored`ncont`n"},
    @{name='fixed-buffer-boundary';setup=$ordinary;input=(('--'+('x'*247))*3)+"`nio.stderr:write('B')`ncont`n"},
    @{name='numeric-error-conversion';setup=$ordinary;input="error(setmetatable({},{__tostring=function()return 17 end}))`ncont`n"},
    @{name='conversion-error-escapes';setup="local ok,e=pcall(require('debug').debug);assert(not ok and e=='CONVERT');print('AFTER')";input="error(setmetatable({},{__tostring=function()error('CONVERT',0)end}))`n"},
    @{name='command-cannot-yield';setup="local c=coroutine.create(require('debug').debug);assert(coroutine.resume(c));assert(coroutine.status(c)=='dead');print('AFTER')";input="coroutine.yield('escape')`ncont`n"},
    @{name='initial-argument-release';setup="_G.watch=setmetatable({},{__mode='v'});require('debug').debug((function()local t={}watch[1]=t;return t end)());assert(watch[1]==nil);print('AFTER')";input="collectgarbage();assert(watch[1]~=nil)`ncollectgarbage();assert(watch[1]==nil)`ncont`n"},
    @{name='binary-error-bytes';setup=$ordinary;input="error(string.char(255,254),0)`ncont`n"}
)
if($IsWindows){
    $cases+=@(
        @{name='native-text-crlf';setup=$ordinary;input="io.stderr:write('R')`r`ncont`r`n"},
        @{name='native-text-ctrl-z';setup=$ordinary;input="`u{001a}ignored`n"}
    )
}
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
        [IO.File]::WriteAllText($inputPath,$case.input,[Text.UTF8Encoding]::new($false))
        $loader=if($IsWindows){'PATH'}elseif($IsMacOS){'DYLD_LIBRARY_PATH'}else{'LD_LIBRARY_PATH'}
        $environment=@{}
        $environment[$loader]=$image+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($loader)
        $process=Invoke-ConformanceProcess -Executable $exe -Arguments @('-e',$case.setup) `
            -Directory $directory -OutputPrefix (Join-Path $directory 'process') `
            -TimeoutSeconds 30 -StandardInputPath $inputPath -Environment $environment
        $rows+=@{role=$role;name=$case.name;setup=$case.setup;environment=$environment;
            process=$process;images=@(Get-ChildItem $image -File|ForEach-Object{
                @{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})}
    }
}
$report=@{schema_version=1;kind='debug-console-process-regressions';configuration=$Configuration;
    synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
    repository_revision=(& git -C $root rev-parse HEAD).Trim();
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
