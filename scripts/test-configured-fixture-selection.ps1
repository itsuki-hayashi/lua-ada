Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConfiguredFixtureEvidence.psm1') -Force
$temporary=Join-Path $root ('reports/configured-selection-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $temporary 'tests/lua'))
[void][IO.Directory]::CreateDirectory((Join-Path $temporary 'tests/conformance/targets'))
$classification='tests/conformance/targets/configured-fixture-classification.json'
$sources=@(Get-ConfiguredFixtureDefinitions upstream-test|ForEach-Object source)
$script:cases=0
function Case($Name,[scriptblock]$Change,$Expected=''){
    # These are source-selection fixtures only. No copied file is executed and
    # none of the mutations below represents an observation or passing test.
    Get-ChildItem (Join-Path $temporary 'tests/lua') -File|Remove-Item
    foreach($path in $sources){Copy-Item -LiteralPath (Join-Path $root $path) -Destination (Join-Path $temporary $path)}
    Copy-Item -LiteralPath (Join-Path $root $classification) -Destination (Join-Path $temporary $classification)
    & $Change
    $failure=$null
    try{$audit=Get-ConfiguredFixtureAudit -Root $temporary}catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){
        throw "Configured source-selection regression $Name failed: $failure; expected $Expected"
    }
    if($Expected -eq '' -and ($audit.runtime_acceptance -or $audit.coverage_authority)){
        throw 'Source-selection fixtures cannot claim runtime authority'
    }
    $script:cases++;Write-Output "CONFIGURED SELECTION PASS: $Name"
}
function Add-Source($Text){
    [IO.File]::WriteAllText((Join-Path $temporary 'tests/lua/new-fixture.lua'),$Text,[Text.UTF8Encoding]::new($false))
}
function Change-Classification([scriptblock]$Change){
    $path=Join-Path $temporary $classification
    $value=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable
    & $Change $value
    [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $value -Depth 12),[Text.UTF8Encoding]::new($false))
}
Case 'source-bound complete configured selections produce no runtime authority' {}
Case 'ordinary assertions remain selected for ordinary comparison' {Add-Source 'assert(1+1==2)'}
Case 'T inside strings and comments does not omit ordinary assertions' {Add-Source "-- T.stacklevel()`nassert('T'=='T')"}
Case 'unknown real T operations require an explicit campaign review' {Add-Source 'assert(T.stacklevel())'} 'Unclassified T-bearing fixture'
Case 'a mixed ordinary and T file cannot be silently omitted' {Add-Source "assert(1+1==2)`nif T then assert(T.stacklevel()) end"} 'Unclassified T-bearing fixture'
Case 'new ordinary assertions in a T-only fixture invalidate its classification' {
    $path=Join-Path $temporary 'tests/lua/stack_inspection.lua'
    [IO.File]::AppendAllText($path,"`nassert(1+1==2)`n")
} 'fresh mixed/default/T source review'
Case 'a missing T-only classification cannot become an omitted file' {
    Change-Classification {param($v)$v.entries=@($v.entries|Select-Object -Skip 1)}
} 'classification is incomplete'
Case 'a duplicate classification cannot hide a different T-only source' {
    Change-Classification {param($v)$v.entries[1]=$v.entries[0]}
} 'fresh mixed/default/T source review'
Case 'a source-classification artifact cannot claim runtime acceptance' {
    Change-Classification {param($v)$v.runtime_acceptance=$true}
} 'claims runtime authority'
Write-Output "PASS: $script:cases configured source-selection regressions; synthetic non-execution fixtures"
