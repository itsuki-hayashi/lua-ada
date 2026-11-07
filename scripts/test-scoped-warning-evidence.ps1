param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module "$PSScriptRoot/ConformanceMatrix.psm1" -Force
Import-Module "$PSScriptRoot/ScopedWarnings.psm1" -Force
$module=Get-Module ConformanceMatrix
$directory=Join-Path $root ('reports/warning-evidence-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$count=0
function Save([string] $Path,$Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 64 -Compress)+"`n")
    return (Get-FileHash $Path).Hash.ToLowerInvariant()
}
function Capture([string] $Path,[string] $Text) {
    [IO.File]::WriteAllText($Path,$Text)
    return @{path=$Path;bytes=(Get-Item $Path).Length;sha256=(Get-FileHash $Path).Hash.ToLowerInvariant()}
}
function New-Fixture([string] $Configuration='upstream-test',[string] $Platform='windows') {
    $id=[guid]::NewGuid().ToString('N')
    $bundle=Join-Path $directory $id
    $captureRoot=Join-Path $bundle 'reports/warnings'
    [void][IO.Directory]::CreateDirectory($captureRoot)
    $context="$Configuration/$Platform/validation/static"
    $index=@{schema_version=1;scope='expanded-t-conformance';context=$context;configuration=$Configuration;
        repository_revision=('a'*40);repository_dirty=$false;repository_status=@();
        source_records=@(Get-ScopedWarningSources | ForEach-Object {
            @{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}
        });library_records=@();cases=@()}
    $operation=@{file='events.lua';context=$context}
    $newline=if($Platform -ceq 'windows'){"`r`n"}else{"`n"}
    foreach($target in @('Ada','ReferenceC')) {
        $targetKey=if($target -ceq 'Ada'){'ada'}else{'c'}
        $library=@{path="/fixture/$target/libfixture.a";sha256=('2'*64)}
        $index.library_records+=@{target=$target;path=$library.path;sha256=$library.sha256}
        $fileReport=@{launcher_identity=@{sha256=('1'*64)};
            runtime_library_records=@($library);reference_library_records=@($library)}
        $filePath=Join-Path $captureRoot "$target-events.json"
        $operation[$targetKey]=@{report=[IO.Path]::GetRelativePath($bundle,$filePath);
            sha256=(Save $filePath $fileReport);artifact_root='.'}
        foreach($case in Get-ScopedWarningCases -Configuration $Configuration) {
            $stdout=if($Configuration -ceq 'upstream-test' -and $case.name -ceq 'normal-warning'){''}else{"OK$newline"}
            $stderr='';$code=0
            if($case.reject) {
                $payload=if($case.name -ceq 'normal-warning'){'scoped unexpected warning'}else{
                    $location=if($target -ceq 'Ada'){'[string "(command line)"]'}else{'(command line)'}
                    "error in __gc ($($location):1: scoped shutdown assertion)"
                }
                if($Configuration -ceq 'default'){$stderr="Lua warning: $payload$newline"}
                elseif($target -ceq 'ReferenceC'){$code=1;$stderr="Unexpected warning in test mode: $payload$($newline)aborting...$newline"}
                else{
                    $stderr="T warning failure: unexpected warning: $payload$newline"
                    if($Platform -ceq 'windows'){$code=3}
                    elseif($Platform -ceq 'linux'){$code=134}
                    else{$code=1;$stderr+="`nExecution of /fixture/runner terminated by unhandled exception`nraised PROGRAM_ERROR : unhandled signal`nLoad address: 0x123`nCall stack traceback locations:`n0x456 0x789`n"}
                }
            }
            $prefix=Join-Path $captureRoot "$target-$($case.name)"
            $out=Capture "$prefix.stdout" $stdout
            $err=Capture "$prefix.stderr" $stderr
            $process=@{executable='/fixture/runner';executable_sha256=('1'*64);arguments=@('-e',$case.source);
                exit_code=$code;timeout_seconds=30;timed_out=$false;capture_exceeded=$false;
                pipe_drain_failed=$false;process_tree_kill_error=$null;
                stdout_path=$out.path;stdout_bytes=$out.bytes;stdout_sha256=$out.sha256;
                stderr_path=$err.path;stderr_bytes=$err.bytes;stderr_sha256=$err.sha256}
            $index.cases+=@{name=$case.name;target=$target;expected_rejection=$case.reject;process=$process}
        }
    }
    $path=Join-Path $captureRoot 'index.json'
    $manifest=@{scope='expanded-t-conformance';revision=('a'*40);operations=@($operation);
        warning_regressions=@(@{context=$context;report='reports/warnings/index.json';sha256='';artifact_root='.'})}
    return @{bundle=$bundle;path=$path;index=$index;manifest=$manifest}
}
function Check($Fixture) {
    $Fixture.manifest.warning_regressions[0].sha256=Save $Fixture.path $Fixture.index
    return & $module {param($r,$m,$b) Test-MatrixWarningEvidence -Root $r -Manifest $m -Bundle $b} $root $Fixture.manifest $Fixture.bundle
}
function Case([string] $Name,[scriptblock] $Mutate,[string] $Expected='',
        [string] $Configuration='upstream-test',[string] $Platform='windows') {
    $fixture=New-Fixture $Configuration $Platform
    $failure=$null
    try { & $Mutate $fixture; Check $fixture | Out-Null } catch {$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))) {
        throw "Warning evidence case failed ($Name): $failure; expected $Expected"
    }
    $script:count++
    Write-Output "WARNING EVIDENCE PASS: $Name"
}
function Rewrite-Stream($Process,[string] $Stream,[string] $Text) {
    $record=Capture $Process["${Stream}_path"] $Text
    $Process["${Stream}_bytes"]=$record.bytes;$Process["${Stream}_sha256"]=$record.sha256
}
Case 'six default cases retain actual payload and successful return' {} '' default
Case 'eight T cases distinguish rejection,shutdown and stored control' {}
Case 'Linux abort transport is separately verified' {} '' upstream-test linux
Case 'Linux normal warning preserves converted signal diagnostics' {param($f)
    $p=$f.index.cases[0].process;$p.exit_code=1
    Rewrite-Stream $p stderr ([IO.File]::ReadAllText($p.stderr_path)+"(command line):1: internal Ada check: unhandled signal`n")
} '' upstream-test linux
Case 'Linux shutdown warning preserves outer signal diagnostics' {param($f)
    $p=$f.index.cases[1].process;$p.exit_code=1
    Rewrite-Stream $p stderr ([IO.File]::ReadAllText($p.stderr_path)+"lua_ada: unhandled signal`n")
} '' upstream-test linux
Case 'Darwin signal transport retains measured executable and trace structure' {} '' upstream-test macos
Case 'missing required stored T control rejected' {param($f) $f.index.cases=@($f.index.cases | Select-Object -Skip 1)} 'case set incomplete'
Case 'duplicate named case rejected' {param($f) $f.index.cases[1]=$f.index.cases[0]} 'case identity'
Case 'untrusted expected rejection flag cannot waive warning checks' {param($f) $f.index.cases[0].expected_rejection=$false} 'rejection claim'
Case 'dirty warning checkout rejected' {param($f) $f.index.repository_dirty=$true} 'revision or context'
Case 'old warning revision rejected' {param($f) $f.index.repository_revision='b'*40} 'revision or context'
Case 'warning configuration mismatch rejected' {param($f) $f.index.configuration='default'} 'revision or context'
Case 'warning source bytes must still match current script' {param($f) $f.index.source_records[0].sha256='f'*64} 'hash differs'
Case 'warning runtime libraries cannot differ from file runtime' {param($f) $f.index.library_records[0].sha256='f'*64} 'runtime libraries differ'
Case 'warning executable cannot differ from file launcher' {param($f) $f.index.cases[0].process.executable_sha256='f'*64} 'executable identities differ'
Case 'warning script cannot be replaced while retaining named case' {param($f) $f.index.cases[0].process.arguments[1]='print("OK")'} 'setup or completion'
Case 'warning crash without expected abort status rejected' {param($f) $f.index.cases[0].process.exit_code=139} 'abort transport'
Case 'shutdown requires completion before finalizer rejection' {param($f) Rewrite-Stream $f.index.cases[1].process stdout ''} 'completion phase'
Case 'correct warning plus unrelated error rejected' {param($f)
    $p=$f.index.cases[0].process;Rewrite-Stream $p stderr ([IO.File]::ReadAllText($p.stderr_path)+"unrelated failure`r`n")
} 'abort transport'
Case 'control cannot hide a warning in stderr' {param($f) Rewrite-Stream $f.index.cases[2].process stderr "unexpected`r`n"} 'empty stderr'
Case 'altered capture bytes reject without rehashing' {param($f) [IO.File]::AppendAllText($f.index.cases[0].process.stderr_path,'x')} 'capture hash mismatch'
Write-Output "PASS: $count warning evidence regressions; synthetic fixtures grant no runtime acceptance"
