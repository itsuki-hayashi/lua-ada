param(
    [Parameter(Mandatory)][string]$Interpreter,
    [ValidateSet('default','upstream-test')][string]$Configuration='default',
    [string]$OutputDirectory=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceAllocatorEvidence.psm1')
$exe=(Resolve-Path -LiteralPath $Interpreter).Path
if($OutputDirectory -eq ''){
    $OutputDirectory=Join-Path $root ('reports/allocator-ceiling/'+[guid]::NewGuid().ToString('N'))
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$records=@()
$hadInherited=Test-Path Env:LUA_ADA_CONFORMANCE_ALLOCATOR
$inherited=[Environment]::GetEnvironmentVariable('LUA_ADA_CONFORMANCE_ALLOCATOR')
function Observe([string]$Name,[string[]]$Arguments,[hashtable]$Environment){
    $prefix=Join-Path $OutputDirectory $Name
    $Environment.LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.telemetry'
    $Environment.LUA_ADA_CONFORMANCE_RUN_ID=[guid]::NewGuid().ToString('N')
    $p=Invoke-ConformanceProcess -Executable $exe -Arguments $Arguments -Directory $root `
        -OutputPrefix $prefix -TimeoutSeconds 120 -Environment $Environment
    if($p.timed_out -or $p.capture_exceeded -or $p.pipe_drain_failed -or
        $p.process_tree_kill_error -or $p.abnormal_exit_kind){
        throw "Allocator configuration child failed abnormally: $Name"
    }
    return @{name=$Name;process=$p;environment=$Environment}
}
function Sidecar([Collections.IDictionary]$Observation,[long]$Limit){
    $identity=Read-ConformanceAllocatorSidecar -Observation $Observation -OutputDirectory $OutputDirectory `
        -Configuration $Configuration -Limit $Limit
    $Observation.telemetry=$identity
    return $identity.observed
}
try{
    # This mutation affects this regression script's process only. Children
    # receive explicit overrides; absence is tested without inheriting a
    # surrounding matrix operation's own selected ceiling.
    Remove-Item Env:LUA_ADA_CONFORMANCE_ALLOCATOR -ErrorAction SilentlyContinue
    foreach($case in @(
        @{name='absent-default';value=$null;limit=2147483648L},
        @{name='explicit-ordinary';value='2147483648';limit=2147483648L},
        @{name='explicit-heavy';value='67108864';limit=67108864L})){
        $environment=@{}
        if($null -ne $case.value){$environment.LUA_ADA_CONFORMANCE_ALLOCATOR=$case.value}
        $o=Observe $case.name @('--conformance-config') $environment
        if($o.process.exit_code -ne 0 -or $o.process.stderr_bytes -ne 0){throw 'Configuration probe failed'}
        $c=Get-Content $o.process.stdout_path -Raw|ConvertFrom-Json -AsHashtable
        if($c.configuration -cne $Configuration -or $c.allocator_limit_bytes -ne $case.limit -or
            $c.test_adapter -isnot [bool] -or $c.test_adapter -ne ($Configuration -ceq 'upstream-test')){
            throw 'Measured conformance configuration ignored its selected allocator ceiling'
        }
        $null=Sidecar $o $case.limit
        $records+=$o
        Write-Output "ALLOCATOR CEILING PASS: $($case.name)"
    }
    $index=0
    foreach($invalid in @('0','-1','67108865','67108864junk','+67108864','067108864','67108864 ','16#4000000#')){
        $index++
        $o=Observe ("invalid-$index") @('--conformance-config') @{LUA_ADA_CONFORMANCE_ALLOCATOR=$invalid}
        if($o.process.exit_code -eq 0 -or $o.process.stdout_bytes -ne 0 -or
            [IO.File]::ReadAllText($o.process.stderr_path) -notmatch 'invalid conformance allocator ceiling'){
            throw 'Unsupported allocator configuration silently became a valid image'
        }
        $records+=$o
        Write-Output "ALLOCATOR CEILING PASS: rejected malformed selection $index"
    }
    # A representable but oversized real string allocation must reach the
    # selected storage allocator and fail inside the actual protected call.
    # Owner ceilings may refuse before the backing provider is called: keep
    # both real counters rather than forcing or fabricating a provider call.
    # A printed memory error alone would also accept an unrelated limit.
    $code="if T then T.totalmem(0)end;local ok,err=pcall(string.rep,'x',80*1024*1024);assert(not ok and err=='not enough memory',tostring(err));collectgarbage();local t=table.create(2);t[1]=37;assert(t[1]==37);print('CEILING caught actual allocator refusal')"
    $o=Observe 'actual-heavy-refusal' @('-e',$code) @{LUA_ADA_CONFORMANCE_ALLOCATOR='67108864'}
    if($o.process.exit_code -ne 0 -or $o.process.stderr_bytes -ne 0 -or
        [IO.File]::ReadAllText($o.process.stdout_path).Replace("`r`n","`n") -cne "CEILING caught actual allocator refusal`n"){
        throw 'Actual heavy refusal/recovery protocol failed'
    }
    $s=Sidecar $o 67108864L
    if($s.managed_refusals -lt 1 -and $s.provider_refusals -lt 1){
        throw 'Heavy error lacks an actual managed or provider allocator refusal'
    }
    $records+=$o
    Write-Output 'ALLOCATOR CEILING PASS: actual protected refusal and healthy recovery'
    # The same representable request succeeds under the ordinary cap. This
    # distinguishes provider refusal from a fixed implementation-size limit.
    $code="local s=string.rep('x',80*1024*1024);assert(#s==80*1024*1024 and s:sub(1,1)=='x' and s:sub(-1)=='x');print('CEILING ordinary allocation succeeded')"
    $o=Observe 'actual-ordinary-success' @('-e',$code) @{LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648'}
    if($o.process.exit_code -ne 0 -or $o.process.stderr_bytes -ne 0 -or
        [IO.File]::ReadAllText($o.process.stdout_path).Replace("`r`n","`n") -cne "CEILING ordinary allocation succeeded`n"){
        throw 'The same request did not succeed under the ordinary ceiling'
    }
    $null=Sidecar $o 2147483648L
    $records+=$o
    Write-Output 'ALLOCATOR CEILING PASS: identical request succeeds under ordinary ceiling'
    $result=@{schema_version=1;kind='conformance-allocator-ceiling-regressions';configuration=$Configuration;
        executable=@{path=$exe;sha256=(Get-FileHash $exe).Hash.ToLowerInvariant()};
        runtime_acceptance=$false;coverage_authority=$false;observations=$records}
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'result.json'),
        ($result|ConvertTo-Json -Depth 32).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    Write-Output "PASS:13 actual allocator ceiling regressions; $OutputDirectory"
}finally{
    if($hadInherited){[Environment]::SetEnvironmentVariable('LUA_ADA_CONFORMANCE_ALLOCATOR',$inherited)}
    else{Remove-Item Env:LUA_ADA_CONFORMANCE_ALLOCATOR -ErrorAction SilentlyContinue}
}
