param([Parameter(Mandatory)][string]$Report)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConfiguredFixtureEvidence.psm1') -Force
$baseline=Get-Content -LiteralPath $Report -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$interpreter=@($baseline.runtimes|Where-Object role -CEQ Ada)[0].executable
$temporary=Join-Path $root ('reports/configured-fixture-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Case($Name,[scriptblock]$Change,$Expected=''){
    $r=ConvertTo-Json -InputObject $baseline -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48
    & $Change $r
    $failure=$null
    try{$null=Assert-ConfiguredFixtureReport -Root $root -Report $r -Configuration $baseline.configuration -Interpreter $interpreter}catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "Configured fixture regression $Name failed: $failure; expected $Expected"}
    $script:cases++;Write-Output "CONFIGURED FIXTURE PASS: $Name"
}
function Replace-Capture($Process,$Stream,$Text){
    $path=Join-Path $temporary ([guid]::NewGuid().ToString('N')+'.'+$Stream)
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
    $Process[$Stream+'_path']=$path;$Process[$Stream+'_sha256']=(Get-FileHash $path).Hash.ToLowerInvariant()
    $Process[$Stream+'_bytes']=(Get-Item $path).Length
}
function Row($r,$Operation){return @($r.processes|Where-Object{$_.role -ceq 'Ada' -and $_.operation -ceq $Operation})[0]}
Case 'actual complete paired captures reconcile without granting acceptance' {}
Case 'configured fixture process cannot disappear' {param($r)$r.processes=@($r.processes|Select-Object -Skip 1)} 'process set is incomplete'
Case 'duplicate configuration cannot replace a mandatory actual operation' {param($r)$r.processes[1]=$r.processes[0]} 'actual process is missing or duplicated'
Case 'generic script-only arguments cannot omit the measured stack setup' {param($r)(Row $r portal).process.arguments=@('tests/lua/coroutine_result_portal.lua')} 'explicit setup'
Case 'wrong selected stack limit rejects even unchanged matching output' {param($r)(Row $r portal).process.arguments[1]='_PORTAL_LIMIT=37'} 'explicit setup'
Case 'another executable cannot reuse an Ada observation receipt' {param($r)$r.runtimes[1].executable=$r.runtimes[0].executable} 'another Ada interpreter'
Case 'executable hash drift rejects old observations' {param($r)$r.runtimes[1].executable_sha256='0'*64} 'runtime identity differs'
Case 'runtime library drift rejects old observations' {param($r)$r.runtimes[1].library_files[0].sha256='0'*64} 'runtime library identity differs'
Case 'source changes require new configured observations' {param($r)$r.source_bindings[0].sha256='0'*64} 'source identity'
Case 'configuration names cannot be relabelled after execution' {param($r)$r.configuration='wrong'} 'kind/configuration'
Case 'configuration probe must identify an actual Ada implementation' {param($r)
    $p=(Row $r configuration).process;$v=Get-Content $p.stdout_path -Raw|ConvertFrom-Json -AsHashtable
    $v.implementation='C Lua';Replace-Capture $p stdout (ConvertTo-Json -InputObject $v)
} 'actual runtime/test adapter'
Case 'successful completion alone cannot replace the explicit setup marker' {param($r)
    Replace-Capture (Row $r portal).process stdout "PASS: coroutine result capacity and recipients`n"
} 'complete ordered protocol'
Case 'rehashed stderr cannot become a passing empty-error observation' {param($r)Replace-Capture (Row $r portal).process stderr 'failure'} 'complete ordered protocol|raw capture|process failed'
Case 'labelled synthetic observations cannot discharge this actual campaign' {param($r)$r.synthetic_fixture=$true} 'observation authority'
Case 'component observations cannot claim whole runtime acceptance' {param($r)$r.runtime_acceptance=$true} 'observation authority'
if($baseline.configuration -ceq 'upstream-test'){
    Case 'T-absent configuration cannot certify a real instrumented fixture' {param($r)
        $p=(Row $r configuration).process;$v=Get-Content $p.stdout_path -Raw|ConvertFrom-Json -AsHashtable
        $v.test_adapter=$false;Replace-Capture $p stdout (ConvertTo-Json -InputObject $v)
    } 'actual runtime/test adapter'
    Case 'four completion lines cannot replace the real T setup witness' {param($r)
        $p=(Row $r stack-inspection).process
        Replace-Capture $p stdout ((1..4|ForEach-Object{"PASS: stack inspection $_"})-join "`n")
    } 'complete ordered protocol'
    Case 'a skipped stack inspection case is not an instrumented pass' {param($r)
        $p=(Row $r stack-inspection).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS: stack inspection 4`n",''))
    } 'complete ordered protocol'
}
Write-Output "PASS: $script:cases configured fixture rejection regressions over actual observations; mutations are non-execution fixtures"
