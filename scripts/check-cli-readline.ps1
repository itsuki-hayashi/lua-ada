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
    $OutputDirectory=Join-Path $root ('reports/cli-readline/'+[guid]::NewGuid().ToString('N'))
}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Readline output must be a fresh directory'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$setup="_PROMPT='P';_PROMPT2='C'"
$cases=@(
    @{name='basic';input="print(17)`n"},
    @{name='empty-eof';input=''},
    @{name='unterminated-final-line';input='print(19)'},
    @{name='empty-line';input="`nprint(23)`n"},
    @{name='fixed-buffer-boundary';input=('--'+(' '*1100))+"`nprint(29)`n"},
    @{name='embedded-nul';input="print(31)`0print(37)`nprint(41)`n"},
    @{name='multiline';input="function f()`nreturn 43`nend`nprint(f())`n"},
    @{name='dynamic-prompt';input="_PROMPT='Q'`nprint(47)`n"},
    @{name='crlf';input="print(53)`r`nprint(59)`r`n"},
    @{name='invalid-utf8-comment';bytes=([byte[]]@(45,45,255,254,10)+[Text.Encoding]::ASCII.GetBytes("print(61)`n"))},
    @{name='missing-library-warnings-off';input="print(67)`n";library='missing-readline-library-that-does-not-exist'},
    @{name='missing-library-warnings-on';input="print(71)`n";library='missing-readline-library-that-does-not-exist';warnings=$true},
    @{name='ignored-library-override';input="print(73)`n";library='missing-readline-library-that-does-not-exist';ignore=$true;warnings=$true}
)
if($IsWindows){$cases+=@{name='native-text-ctrl-z';input="`u{001a}print(79)`n"}}
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
        if($case.ContainsKey('bytes')){[byte[]]$bytes=$case.bytes}
        else{[byte[]]$bytes=[Text.Encoding]::UTF8.GetBytes($case.input)}
        [IO.File]::WriteAllBytes($inputPath,[byte[]]$bytes)
        # A copied oracle must resolve the shared library beside that exact
        # image. POSIX dynamic loaders do not search the executable's PATH.
        $loader=if($IsWindows){'PATH'}elseif($IsMacOS){'DYLD_LIBRARY_PATH'}else{'LD_LIBRARY_PATH'}
        $environment=@{}
        $environment[$loader]=$image+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($loader)
        if($case.ContainsKey('library')){$environment.LUA_READLINELIB=$case.library}
        $arguments=@('-i')
        if($case.ContainsKey('warnings')){$arguments+='-W'}
        if($case.ContainsKey('ignore')){$arguments+='-E'}
        $caseSetup=$setup
        if($Configuration -ceq 'upstream-test' -and $IsLinux -and $case.name -ceq 'missing-library-warnings-on'){
            # The pinned T observer aborts unexpected enabled warnings. This
            # case intentionally requests one; the independent review permits
            # printing it, while retaining the real failure/-W/raw comparison.
            $review='tests/conformance/targets/remaining-upstream-compatibility/reviews/readline-expected-warning.feature-review.md'
            $reviewHash='a7a0bce436101ff9835008929fdb6923b4940c4833eec14faa10459db4194944'
            if((Get-FileHash -LiteralPath (Join-Path $root $review)).Hash.ToLowerInvariant() -cne $reviewHash){
                throw 'Expected readline warning requires its exact independent feature review'
            }
            $caseSetup="if T then warn('@allow')end;"+$caseSetup
        }
        $arguments+=@('-e',$caseSetup)
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
$report=@{schema_version=1;kind='cli-readline-process-regressions';configuration=$Configuration;
    synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
    repository_revision=(&git -C $root rev-parse HEAD).Trim();
    repository_dirty=(@(&git -C $root status --porcelain=v1 --untracked-files=normal).Count -ne 0);
    source=@{path='scripts/check-cli-readline.ps1';sha256=(Get-FileHash $PSCommandPath).Hash.ToLowerInvariant()};
    processes=$rows;comparison_failures=$failures;
    limitations=@('Product CLI observations do not supply measured Ada allocator telemetry or final context acceptance.',
        'Native backend selection is exercised on the actual host; this is not a TTY observation.',
        'References remain unchanged; each exact raw comparison uses the same-host original C CLI.')}
if($Configuration -ceq 'upstream-test' -and $IsLinux){
    $report['expected_warning_review']=@{path=$review;sha256=$reviewHash;case='missing-library-warnings-on';
        setup_prefix="if T then warn('@allow')end;";runtime_acceptance=$false;coverage_authority=$false}
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'result.json'),
    ($report|ConvertTo-Json -Depth 32).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
if($failures.Count){throw "CLI readline differs in $($failures.Count) cases; $OutputDirectory"}
Write-Output "PASS:$($cases.Count) paired native readline/fallback cases; $OutputDirectory"
