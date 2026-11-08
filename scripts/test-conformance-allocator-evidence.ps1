param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceAllocatorEvidence.psm1') -Force
$base=Join-Path $root ('reports/allocator-evidence-selftest/'+[guid]::NewGuid().ToString('N'))
$script:cases=0
function Fixture {
    $dir=Join-Path $base ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    $run='0123456789abcdef0123456789abcdef'
    $s=@{schema_version=1;run_id=$run;process_id=12345;configuration='default';
        allocator_limit_bytes=67108864;managed_refusals=1;provider_refusals=0;
        outstanding_bytes=0;outstanding_blocks=0;peak_managed_bytes=196118;
        shutdown_complete=$true;accounting_fault=$false}
    $o=@{name='synthetic';process=@{process_id=12345};
        environment=@{LUA_ADA_CONFORMANCE_RUN_ID=$run}}
    return @{directory=$dir;path=(Join-Path $dir 'synthetic.telemetry.12345.json');data=$s;observation=$o;synthetic_fixture=$true}
}
function Write-Fixture($F){
    [IO.File]::WriteAllText($F.path,($F.data|ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false))
}
function Read-Fixture($F,[string]$Hash=''){
    Read-ConformanceAllocatorSidecar -Observation $F.observation -OutputDirectory $F.directory `
        -Configuration default -Limit 67108864 -ExpectedSha256 $Hash
}
function Case($Name,[scriptblock]$Action){
    &$Action
    $script:cases++
    Write-Output "ALLOCATOR DATA GUARD PASS: $Name"
}
function Reject([scriptblock]$Action,$Pattern){
    $errorText=$null
    try{&$Action|Out-Null}catch{$errorText=$_.Exception.Message}
    if($null -eq $errorText -or $errorText -notmatch $Pattern){throw "Wrong rejection: $errorText; expected $Pattern"}
}
Case 'synthetic identity binds the same raw bytes without runtime authority' {
    $f=Fixture;Write-Fixture $f
    $hash=(Get-FileHash $f.path).Hash.ToLowerInvariant()
    $r=Read-Fixture $f $hash
    if($r.sha256 -cne $hash -or $r.observed.managed_refusals -ne 1 -or $r.observed.provider_refusals -ne 0){throw 'Actual counter distinctions lost'}
}
foreach($mutation in @('filename','pid','run','configuration','expected-pid-type','expected-run','reported-pid-type','duplicate','missing')){
    Case "stale or wrong $mutation cannot supply child evidence" {
        $f=Fixture;Write-Fixture $f
        $pattern='identity'
        switch($mutation){
            'filename' {Rename-Item $f.path 'synthetic.telemetry.54321.json';$pattern='filename'}
            'pid' {$f.data.process_id=54321;Write-Fixture $f}
            'run' {$f.data.run_id='fedcba9876543210fedcba9876543210';Write-Fixture $f}
            'configuration' {$f.data.configuration='upstream-test';Write-Fixture $f}
            'expected-pid-type' {$f.observation.process.process_id='12345'}
            'expected-run' {$f.observation.environment.LUA_ADA_CONFORMANCE_RUN_ID='invalid'}
            'reported-pid-type' {$f.data.process_id='12345';Write-Fixture $f;$pattern='integral'}
            'duplicate' {Copy-Item $f.path (Join-Path $f.directory 'synthetic.telemetry.54321.json');$pattern='filename'}
            'missing' {$f.observation.name='absent';$pattern='filename'}
        }
        Reject {Read-Fixture $f} $pattern
    }
}
foreach($mutation in @('wrong-hash','changed-bytes','malformed-hash')){
    Case "a $mutation cannot replay a prior raw identity" {
        $f=Fixture;Write-Fixture $f;$hash=(Get-FileHash $f.path).Hash.ToLowerInvariant()
        switch($mutation){
            'wrong-hash' {$hash='0'*64}
            'changed-bytes' {$f.data.managed_refusals=2;Write-Fixture $f}
            'malformed-hash' {$hash='not-a-hash'}
        }
        Reject {Read-Fixture $f $hash} 'source hash'
    }
}
foreach($field in @('allocator_limit_bytes','peak_managed_bytes','outstanding_bytes','outstanding_blocks','shutdown_complete','accounting_fault')){
    Case "invalid ownership/limit field $field fails" {
        $f=Fixture
        switch($field){
            'allocator_limit_bytes' {$f.data[$field]=2147483648L}
            'peak_managed_bytes' {$f.data[$field]=67108865}
            'outstanding_bytes' {$f.data[$field]=1}
            'outstanding_blocks' {$f.data[$field]=1}
            'shutdown_complete' {$f.data[$field]=$false}
            'accounting_fault' {$f.data[$field]=$true}
        }
        Write-Fixture $f;Reject {Read-Fixture $f} 'ownership'
    }
}
foreach($field in @('schema_version','managed_refusals','provider_refusals')){
    Case "nonintegral or missing $field is not measured evidence" {
        $f=Fixture
        if($field -ceq 'provider_refusals'){[void]$f.data.Remove($field)}else{$f.data[$field]=$true}
        Write-Fixture $f;Reject {Read-Fixture $f} 'measurement'
    }
}
Write-Output "PASS:$script:cases allocator data guards; labelled synthetic non-execution fixtures, no Lua coverage"
