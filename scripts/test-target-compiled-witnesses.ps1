param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetCompiledWitnesses.psm1') -Force
$temporary=Join-Path $root ('reports/compiled-witness-selftests/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0
# All compiler/process records are deliberately fabricated validator fixtures.
# No compiler or executable runs. Their shape is tested independently from the
# final policy's actual source review, image provenance and CI capture origin.
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "COMPILED WITNESS TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
function New-Process([string]$Prefix,[string]$Text,[string[]]$Arguments,[string]$ExecutableSha){
    [IO.File]::WriteAllText(($Prefix+'.stdout'),$Text,$utf8);[IO.File]::WriteAllText(($Prefix+'.stderr'),'',$utf8)
    return @{exit_code=0;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;process_tree_kill_error=$null;abnormal_exit_kind=$null;
        executable_sha256=$ExecutableSha;arguments=$Arguments;stdout_path=($Prefix+'.stdout');stderr_path=($Prefix+'.stderr');
        stdout_sha256=(Get-FileHash ($Prefix+'.stdout')).Hash.ToLowerInvariant();stderr_sha256=(Get-FileHash ($Prefix+'.stderr')).Hash.ToLowerInvariant();
        stdout_bytes=(Get-Item ($Prefix+'.stdout')).Length;stderr_bytes=0}
}
function New-Fixture{
    $directory=Join-Path $temporary ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
    $source=Join-Path $directory 'probe.c';[IO.File]::WriteAllText($source,'/* synthetic source binding, never compiled */',$utf8)
    $relative=[IO.Path]::GetRelativePath($root,$source).Replace('\','/')
    $sourceIdentity=@{path=$relative;sha256=(Get-FileHash $source).Hash.ToLowerInvariant()}
    $artifact=Join-Path $directory 'fake-executable';[IO.File]::WriteAllText($artifact,'synthetic non-executable bytes',$utf8)
    $artifactHash=(Get-FileHash $artifact).Hash.ToLowerInvariant()
    $args=@('-std=c99','-Werror',('{root}/'+$relative))
    $case=@{id='synthetic-header';contexts=@('default/windows/validation/static');source=$sourceIdentity;source_bindings=@($sourceIdentity);
        compile_arguments=$args;execution_arguments=@();required_stdout_line='synthetic header observation'}
    $report=@{schema_version=1;kind='target-compiled-context-observations';context='default/windows/validation/static';revision=('a'*40);
        source_root=$root;repository_dirty=$false;synthetic_fixture=$false;compiler_sha256=('1'*64);
        cases=@(@{id=$case.id;source_bindings=@($sourceIdentity);compile=(New-Process (Join-Path $directory 'compile') '' @($args|ForEach-Object{$_.Replace('{root}',$root)}) ('1'*64));
            execution=(New-Process (Join-Path $directory 'execution') "synthetic header observation`n" @() $artifactHash);
            artifact=@{path=$artifact;sha256=$artifactHash}})}
    return @{report=$report;mapping=@{kind='target-compiled-witness-mapping';cases=@($case)}}
}
function Replay([Collections.IDictionary]$Fixture){Test-TargetCompiledWitnesses -Root $root -Mapping $Fixture.mapping -Report $Fixture.report `
    -ArtifactRoot $root -Context default/windows/validation/static -Revision ('a'*40) -CompilerSha256 ('1'*64)}
Case 'complete synthetic record exercises exact source compiler arguments and result binding without execution'{
    $r=Replay (New-Fixture);Assert-True ($r.Count -eq 1 -and -not $r['synthetic-header'].runtime_acceptance) 'Fixture gained target acceptance'
}
Case 'synthetic report label dirty state wrong context revision and compiler all reject'{
    foreach($field in @('synthetic_fixture','repository_dirty','context','revision','compiler_sha256')){
        $f=New-Fixture;$f.report[$field]=if($field -cin @('synthetic_fixture','repository_dirty')){$true}else{'wrong'}
        Reject {Replay $f} 'matching context/revision'
    }
}
Case 'missing duplicate and unknown compiled cases cannot close the catalogue'{
    $f=New-Fixture;$f.report.cases=@();Reject {Replay $f} 'case set is incomplete'
    $f=New-Fixture;$f.report.cases[0].id='invented';Reject {Replay $f} 'identity missing'
}
Case 'compiler timeout failed exit and unreviewed stderr cannot be called compiled evidence'{
    foreach($change in @('timeout','exit','stderr')){
        $f=New-Fixture;$p=$f.report.cases[0].compile
        if($change -ceq 'timeout'){$p.timed_out=$true}elseif($change -ceq 'exit'){$p.exit_code=1}else{
            [IO.File]::WriteAllText($p.stderr_path,'warning disguised as success',$utf8);$p.stderr_sha256=(Get-FileHash $p.stderr_path).Hash.ToLowerInvariant();$p.stderr_bytes=(Get-Item $p.stderr_path).Length
        }
        Reject {Replay $f} 'finish cleanly|unreviewed compiler'
    }
}
Case 'changed source capture bytes arguments and executable cannot reuse metadata'{
    $f=New-Fixture;$f.report.cases[0].source_bindings=@(@{path=$f.mapping.cases[0].source.path;sha256=('0'*64)});Reject {Replay $f} 'different original'
    $f=New-Fixture;[IO.File]::AppendAllText($f.report.cases[0].execution.stdout_path,'changed',$utf8);Reject {Replay $f} 'capture path/hash/length'
    $f=New-Fixture;$f.report.cases[0].compile.arguments+=@('-w');Reject {Replay $f} 'reviewed compiler/execution arguments'
    $f=New-Fixture;[IO.File]::AppendAllText($f.report.cases[0].artifact.path,'changed',$utf8);Reject {Replay $f} 'executable/compiler identity'
}
Case 'a compiler success marker cannot replace the exact executed declaration assertions'{
    $f=New-Fixture;$p=$f.report.cases[0].execution
    [IO.File]::WriteAllText($p.stdout_path,"different line`n",$utf8);$p.stdout_sha256=(Get-FileHash $p.stdout_path).Hash.ToLowerInvariant();$p.stdout_bytes=(Get-Item $p.stdout_path).Length
    Reject {Replay $f} 'exact observed assertion line'
}
Write-Output "PASS: $script:Cases compiled witness validator regressions; fabricated process fixtures only, no compiler/runtime/API acceptance"
