param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'FileConsumerIO.psm1') -Force
$directory=Join-Path $root ('reports/file-io-selftests/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0;$script:Serial=0
# Every executable, Lua chunk and process below is deliberately fabricated.
# These fixtures test replay guards only; no C compiler or Lua process runs.
# The explicit AllowSynthetic switch is confined to these primitive tests.
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "FILE IO FIXTURE PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64)}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
function Artifact([string]$Name,[byte[]]$Bytes){
    $script:Serial++;$path=Join-Path $directory ($script:Serial.ToString()+'-'+$Name)
    [IO.File]::WriteAllBytes($path,$Bytes)
    return @{path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant();bytes=$Bytes.Length}
}
$context='default/windows/validation/static'
$drivers=@{};$hashes=@{}
foreach($implementation in @('Ada','ReferenceC')){
    $drivers[$implementation]=Artifact ($implementation+'-NOT-EXECUTABLE.bin') ($utf8.GetBytes('synthetic driver '+$implementation))
    $hashes[$implementation]=$drivers[$implementation].sha256
}
function Process([string]$Implementation,[string]$Argument,[byte[]]$Bytes){
    $out=Artifact 'stdout' $Bytes;$err=Artifact 'stderr' ([byte[]]@())
    return @{executable=$drivers[$Implementation].path;executable_sha256=$hashes[$Implementation];arguments=@($Argument);working_directory=$root;
        exit_code=0;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;process_tree_kill_error=$null;abnormal_exit_kind=$null;
        stdout_path=$out.path;stdout_sha256=$out.sha256;stdout_bytes=$out.bytes;stderr_path=$err.path;stderr_sha256=$err.sha256;stderr_bytes=0}
}
$text=Artifact 'source.lua' ($utf8.GetBytes("return 17, 'input\0payload', true`n"))
$producers=@();$consumers=@()
foreach($implementation in @('Ada','ReferenceC')){
    $producers+=@{implementation=$implementation;process=(Process $implementation '--emit-stdin-chunk' ([byte[]](27,76,117,97,255,0)+$utf8.GetBytes('SYNTHETIC-NOT-LOADABLE-'+$implementation)))}
}
foreach($implementation in @('Ada','ReferenceC')){
    foreach($selection in @(@{kind='text';producer=$null})+@($producers|ForEach-Object{@{kind='binary';producer=$_.implementation}})){
        $inputRecord=if($selection.kind -ceq 'text'){$text}else{
            $p=@($producers|Where-Object implementation -CEQ $selection.producer)[0].process
            @{path=$p.stdout_path;sha256=$p.stdout_sha256;bytes=$p.stdout_bytes}
        }
        $p=Process $implementation ('--stdin-'+$selection.kind) ($utf8.GetBytes("PASS: public loadfile stdin`n"))
        $snapshot=Artifact 'stdin' ([IO.File]::ReadAllBytes($inputRecord.path))
        $p.standard_input=@{source_path=$inputRecord.path;path=$snapshot.path;sha256=$snapshot.sha256;bytes=$snapshot.bytes;
            byte_limit=1048576;write_completed=$true;eof_sent=$true}
        $consumers+=@{implementation=$implementation;input_kind=$selection.kind;producer=$selection.producer;process=$p}
    }
}
$baseline=@{schema_version=1;kind='public-file-stdin-observations';context=$context;source_root=$root;synthetic_fixture=$true;
    drivers=$drivers;text_input=$text;producers=$producers;consumers=$consumers;runtime_acceptance=$false;coverage_authority=$false}
$resolve={param($Path,$Hash)
    if((Get-FileHash $Path).Hash.ToLowerInvariant() -cne $Hash){throw 'Synthetic capture hash mismatch'}
    return $Path
}
function Replay($Value){Test-FileConsumerIO -Observation $Value -Context $context -DriverHashes $hashes -ResolveCapture $resolve -AllowSynthetic}
Case 'complete explicitly synthetic fixture exercises both text readers and all four binary paths'{
    $value=Replay $baseline
    Assert-True ($value.named_outputs.Count -eq 2 -and -not $value.runtime_acceptance -and -not $value.coverage_authority) 'Fixture acquired runtime authority'
}
Case 'actual consumer rejects labelled synthetic observations and wrong context'{
    Reject {Test-FileConsumerIO -Observation $baseline -Context $context -DriverHashes $hashes -ResolveCapture $resolve} 'actual matching context'
    $r=Clone $baseline;$r.context='upstream-test/windows/validation/static';Reject {Replay $r} 'actual matching context'
}
Case 'neither missing producer nor duplicated counterparty can replace the required matrix'{
    $r=Clone $baseline;$r.producers=@($r.producers[0]);Reject {Replay $r} 'two dump producers'
    $r=Clone $baseline;$r.producers[1]=Clone $r.producers[0];Reject {Replay $r} 'producer is missing or duplicated'
    $r=Clone $baseline;$r.consumers=@($r.consumers|Select-Object -Skip 1);Reject {Replay $r} 'all six consumers'
    $r=Clone $baseline;$r.consumers[5]=Clone $r.consumers[4];Reject {Replay $r} 'consumer is duplicated'
}
Case 'a rehashed marker cannot impersonate an emitted binary chunk'{
    $r=Clone $baseline;$fake=Artifact 'not-a-chunk' ($utf8.GetBytes("PASS: binary`n"))
    $r.producers[0].process.stdout_path=$fake.path;$r.producers[0].process.stdout_sha256=$fake.sha256;$r.producers[0].process.stdout_bytes=$fake.bytes
    Reject {Replay $r} 'actual Lua binary chunk'
}
Case 'wrong actual driver or mode cannot borrow matching stdout'{
    $r=Clone $baseline;$r.producers[0].process.executable_sha256=$hashes.ReferenceC;Reject {Replay $r} 'actual process driver'
    $r=Clone $baseline;$r.consumers[1].process.arguments=@('--stdin-text');Reject {Replay $r} 'actual process driver'
    $r=Clone $baseline;$r.consumers[1].process.working_directory='another-source-tree';Reject {Replay $r} 'actual process driver'
}
Case 'binary consumer binds its particular actual producer and raw snapshot'{
    $r=Clone $baseline;$r.consumers[1].process.standard_input.source_path=$producers[1].process.stdout_path
    Reject {Replay $r} 'exact selected producer'
    $r=Clone $baseline;$r.consumers[1].process.standard_input.sha256='0'*64
    Reject {Replay $r} 'exact selected producer'
    $r=Clone $baseline;$r.consumers[1].process.standard_input.path=$text.path
    Reject {Replay $r} 'capture hash mismatch'
}
Case 'incomplete write absent EOF or coerced byte count cannot become stdin execution'{
    foreach($field in @('write_completed','eof_sent','bytes','byte_limit')){
        $r=Clone $baseline
        $r.consumers[0].process.standard_input[$field]=if($field -cin @('write_completed','eof_sent')){$false}else{[string]$r.consumers[0].process.standard_input[$field]}
        Reject {Replay $r} 'exact selected producer'
    }
}
Case 'equal completion records cannot hide unreviewed output or stderr'{
    $r=Clone $baseline;$extra=Artifact extra ($utf8.GetBytes("extra`nPASS: public loadfile stdin`n"))
    $r.consumers[0].process.stdout_path=$extra.path;$r.consumers[0].process.stdout_sha256=$extra.sha256;$r.consumers[0].process.stdout_bytes=$extra.bytes
    Reject {Replay $r} 'completion protocol'
    $r=Clone $baseline;$err=Artifact error ($utf8.GetBytes('unexpected'))
    $r.consumers[0].process.stderr_path=$err.path;$r.consumers[0].process.stderr_sha256=$err.sha256;$r.consumers[0].process.stderr_bytes=$err.bytes
    Reject {Replay $r} 'unreviewed stderr'
}
function Image($Value){
    $items=@($Value.text_input)+@($Value.drivers.Values)
    foreach($entry in @($Value.producers)+@($Value.consumers)){
        foreach($stream in @('stdout','stderr')){$items+=@{path=$entry.process["${stream}_path"];sha256=$entry.process["${stream}_sha256"]}}
        if($entry.process.Contains('standard_input')){$items+=$entry.process.standard_input}
    }
    return @{files=@($items|ForEach-Object{@{path=[IO.Path]::GetRelativePath($root,$_.path).Replace('\','/');sha256=$_.sha256}})}
}
Case 'all synthetic input driver producer and consumer artifacts require exact image membership'{
    $image=Image $baseline
    Assert-FileConsumerIOImageBinding -Image $image -Observation $baseline
    foreach($type in @('input','driver','producer')){
        $image=Image $baseline
        $missing=if($type -ceq 'input'){$baseline.consumers[0].process.standard_input.path}elseif($type -ceq 'driver'){$baseline.drivers.Ada.path}else{$baseline.producers[0].process.stdout_path}
        $relative=[IO.Path]::GetRelativePath($root,$missing).Replace('\','/')
        $image.files=@($image.files|Where-Object path -CNE $relative)
        Reject {Assert-FileConsumerIOImageBinding -Image $image -Observation $baseline} 'exact frozen image'
    }
}
Write-Output "PASS: $script:Cases file stdin validator regressions; fabricated fixtures only, no compiler/Lua/API execution"
