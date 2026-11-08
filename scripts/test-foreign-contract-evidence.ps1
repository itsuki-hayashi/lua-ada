param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ForeignContractEvidence.psm1') -Force
$directory=Join-Path $root ('reports/foreign-contract-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$script:cases=0;$hash='a'*64
function Case($Name,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "FOREIGN PROTOCOL PASS: $Name"}
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert ($null -ne $failure -and $failure -match $Pattern) "Wrong failure: $failure; expected $Pattern"
}
function Capture($Text){
    $path=Join-Path $directory ([guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($path,$Text)
    return @{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
}
function New-Fixture($Configuration='upstream-test',$Maximum=26){
    $t=$Configuration -ceq 'upstream-test';$skip=if($t){1}else{0}
    $omitted=@();$arguments=@();if($t){$omitted=@('foreign-hook-24');$arguments=@('--without-release-reentry')}
    $report=@{foreign_contract=@{hook_case_maximum=$Maximum;matched_cases=(25+$Maximum-1+5+4-$skip);
        skipped_native_lock_cases=$skip;native_omitted_cases=$omitted;
        ada_full_consumer=$(if($t){'foreign-full-api'}else{'foreign-api'})};consumers=@()}
    $names=@('foreign-api','foreign-oracle');if($t){$names+='foreign-full-api'}
    foreach($name in $names){
        $full=$name -ceq 'foreign-full-api';$argsForProcess=$arguments;if($full){$argsForProcess=@()}
        $out=Capture (Get-ForeignContractOutput -HookMaximum $Maximum -WithoutPrivateLockReentry:($t -and -not $full))
        $err=Capture ''
        $report.consumers+=@{name=$name;executable='synthetic-foreign-driver';executable_sha256=$hash;arguments=$argsForProcess;
            configuration=$Configuration;profile='validation';library_type='static';exit_code=0;timed_out=$false;
            stdout=$out.path;stdout_sha256=$out.sha256;stderr=$err.path;stderr_sha256=$err.sha256}
    }
    return @{report=$report;context="$Configuration/windows/validation/static";maximum=$Maximum}
}
$resolve={param($path,$hash)
    if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $hash){throw 'capture hash differs'}
    return $path
}
function Replay($Fixture){Assert-ForeignContractEvidence -Report $Fixture.report -Context $Fixture.context -HookMaximum $Fixture.maximum -ResolveCapture $resolve}
function Replace-Output($Record,$Text){$out=Capture $Text;$Record.stdout=$out.path;$Record.stdout_sha256=$out.sha256}
Case 'current driver maximum comes from the actual source loop' {
    Assert ((Get-ForeignContractHookMaximum -Root $root) -ge 24) 'current driver protocol unavailable'
}
Case 'default keeps complete identical paired output including reentry' {Replay (New-Fixture default)}
Case 'T private native skip still requires actual full Ada operation capture' {
    $f=New-Fixture;Replay $f
    $text=[IO.File]::ReadAllText($f.report.consumers[2].stdout)
    Assert ($text.Contains("PASS: foreign-hook-24`n") -and $text.Contains("PASS: foreign-hook-25`n") -and
        $text.Contains("PASS: foreign-hook-26`n")) 'the complete process dropped current or later operations'
}
Case 'T may not omit its complete Ada process' {
    $f=New-Fixture;$f.report.consumers=@($f.report.consumers|Where-Object name -CNE 'foreign-full-api')
    Reject {Replay $f} 'observation missing or duplicate'
}
Case 'a reduced process cannot be relabelled as full' {
    $f=New-Fixture;$f.report.foreign_contract.ada_full_consumer='foreign-api'
    Reject {Replay $f} 'identifies a reduced process'
}
Case 'full Ada process must use the same actual executable' {
    $f=New-Fixture;$f.report.consumers[2].executable_sha256='0'*64
    Reject {Replay $f} 'different executable image'
}
Case 'complete Ada observation cannot use skip arguments' {
    $f=New-Fixture;$f.report.consumers[2].arguments=@('--without-release-reentry')
    Reject {Replay $f} 'process mode'
}
Case 'paired T arguments cannot silently run another mode' {
    $f=New-Fixture;$f.report.consumers[1].arguments=@()
    Reject {Replay $f} 'process mode'
}
Case 'source maximum cannot be downgraded to hide later cases' {
    $f=New-Fixture;$f.report.foreign_contract.hook_case_maximum=24
    Reject {Replay $f} 'source-bound case counts'
}
Case 'T native omitted case cannot be described as passing' {
    $f=New-Fixture;$f.report.foreign_contract.native_omitted_cases=@();$f.report.foreign_contract.skipped_native_lock_cases=0
    Reject {Replay $f} 'native private lock omissions'
}
Case 'default cannot borrow native T private-lock omissions' {
    $f=New-Fixture default;$f.report.foreign_contract.native_omitted_cases=@('foreign-hook-24')
    Reject {Replay $f} 'native private lock omissions'
}
foreach($which in @(24,25,26)){
    Case "full Ada case$which cannot disappear behind completion" {
        $f=New-Fixture;$row=$f.report.consumers[2]
        Replace-Output $row ([IO.File]::ReadAllText($row.stdout).Replace("PASS: foreign-hook-$which`n",''))
        Reject {Replay $f} 'complete ordered public protocol'
    }
}
Case 'paired native T later public operation remains required' {
    $f=New-Fixture;$row=$f.report.consumers[1]
    Replace-Output $row ([IO.File]::ReadAllText($row.stdout).Replace("PASS: foreign-hook-25`n",''))
    Reject {Replay $f} 'complete ordered public protocol'
}
Case 'source parser retains future hook cases without broadening private skip' {
    $fixture=Join-Path $directory 'source-fixture';[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'c_api/tests'))
    $text="for (which = 1; which <= 25; ++which)`nfor (which = 1; which <= 26; ++which)`n"+
        "for (which = 1; which <= 5; ++which)`nfor (which = 1; which <= 4; ++which)`n"
    [IO.File]::WriteAllText((Join-Path $fixture 'c_api/tests/foreign_api_contract.c'),$text)
    Assert ((Get-ForeignContractHookMaximum -Root $fixture) -eq 26) 'future source operations lost'
}
Write-Output "PASS: $script:cases foreign contract regressions; fabricated protocols/source snippets only, no executed API acceptance"
