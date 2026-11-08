param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1') -Force
$script:cases=0
$names=@('c_api/tests/substitution_api_contract.c','c_api/tests/consumer_allocator.h')
function Case($Name,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "ORACLE SOURCE PASS: $Name"}
function Fixture {
    return @{substitution_contract=@{sources=@($names|ForEach-Object{
        @{file=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash.ToLowerInvariant()}
    })}}
}
function Check($Consumer){
    & (Get-Module TargetWitnessPolicy) {param($r,$c,$n)
        Assert-TargetAdditionalOracleSources -Root $r -Consumer $c -Kind substitution -Names $n
    } $root $Consumer $names
}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $Pattern){throw "Wrong failure: $failure; expected $Pattern"}
}
Case 'actual public substitution source and included allocator header identities validate' {Check (Fixture)}
Case 'a header used by the source cannot disappear from the source-bound observation' {
    $f=Fixture;$f.substitution_contract.sources=@($f.substitution_contract.sources|Select-Object -First 1)
    Reject {Check $f} 'contract=substitution source=c_api/tests/consumer_allocator.h expected=1 observed=0'
}
Case 'duplicate included headers do not replace one exact identity' {
    $f=Fixture;$f.substitution_contract.sources+=@($f.substitution_contract.sources[1])
    Reject {Check $f} 'contract=substitution source=c_api/tests/consumer_allocator.h expected=1 observed=2'
}
Case 'a stale allocator header hash does not validate against the current tree' {
    $f=Fixture;$f.substitution_contract.sources[1].sha256='0'*64
    Reject {Check $f} 'Review file hash differs: c_api[/\\]tests[/\\]consumer_allocator.h'
}
Case 'the actual driver source identity remains required beside its included header' {
    $f=Fixture;$f.substitution_contract.sources=@($f.substitution_contract.sources|Select-Object -Last 1)
    Reject {Check $f} 'contract=substitution source=c_api/tests/substitution_api_contract.c expected=1 observed=0'
}
Case 'missing contract metadata is a diagnosed failure' {
    Reject {Check @{}} 'contract source metadata missing: substitution'
}
Write-Output "PASS: $script:cases target oracle source regressions; fabricated report metadata over real source files only, no API execution or acceptance"
