Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConfiguredFixtureEvidence.psm1') -Force
$temporary=Join-Path $root ('reports/configured-selection-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $temporary 'tests/lua'))
[void][IO.Directory]::CreateDirectory((Join-Path $temporary 'tests/conformance/targets'))
$classification='tests/conformance/targets/configured-fixture-classification.json'
$sources=@(Get-ConfiguredFixtureDefinitions upstream-test|ForEach-Object source)
$sourceLinks=@((Get-Content (Join-Path $root $classification) -Raw|ConvertFrom-Json -AsHashtable -Depth 24).entries|
    Where-Object selection -CEQ configured-Ada-internal-counterpart-only)[0].source_linkage.bindings.path
$sources+=@($sourceLinks)
$sources+=@((Get-Content (Join-Path $root $classification) -Raw|ConvertFrom-Json -AsHashtable -Depth 24).entries|
    Where-Object{$_.Contains('retained_default_counterpart')}|ForEach-Object{$_.retained_default_counterpart.path})
$script:cases=0
function Case($Name,[scriptblock]$Change,$Expected=''){
    # These are source-selection fixtures only. No copied file is executed and
    # none of the mutations below represents an observation or passing test.
    Get-ChildItem (Join-Path $temporary 'tests/lua') -File|Remove-Item
    foreach($path in $sources){
        $target=Join-Path $temporary $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $target
    }
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
Case 'Ada internal storage cannot be reclassified as a native paired facade' {
    Change-Classification {param($v)@($v.entries|Where-Object selection -CEQ configured-Ada-internal-counterpart-only)[0].selection='paired-configured-T-only'}
} 'fresh mixed/default/T source review'
Case 'an invented source link is not an actual AUnit case' {
    Change-Classification {param($v)@($v.entries|Where-Object selection -CEQ configured-Ada-internal-counterpart-only)[0].source_linkage.aunit_named_cases[0].case='invented'}
} 'named AUnit linkage differs'
Case 'source linkage cannot pretend it contains passing runtime evidence' {
    Change-Classification {param($v)@($v.entries|Where-Object selection -CEQ configured-Ada-internal-counterpart-only)[0].source_linkage.runtime_evidence=@('passed')}
} 'invents execution evidence'
Case 'mixed public semantics cannot lose their ordinary counterpart' {
    Change-Classification {param($v)$row=@($v.entries|Where-Object path -CEQ tests/lua/call_metadata_windows.lua)[0];[void]$row.Remove('retained_default_counterpart')}
} 'lacks its ordinary counterpart'
Case 'an ordinary counterpart cannot replace a body with a named marker' {
    $script:mutatedOrdinaryPath=Join-Path $temporary 'tests/lua/call_metadata_public.lua'
    [IO.File]::WriteAllText($script:mutatedOrdinaryPath,[IO.File]::ReadAllText($script:mutatedOrdinaryPath).Replace('calls==1','calls==2'),[Text.UTF8Encoding]::new($false))
    Change-Classification {param($v)$row=@($v.entries|Where-Object path -CEQ tests/lua/call_metadata_windows.lua)[0];$row.retained_default_counterpart.sha256=(Get-FileHash $script:mutatedOrdinaryPath).Hash.ToLowerInvariant()}
} 'ordinary correspondence source bytes differ'
Case 'mixed default correspondence cannot omit a public case' {
    Change-Classification {param($v)$row=@($v.entries|Where-Object path -CEQ tests/lua/call_metadata_windows.lua)[0];$row.retained_default_counterpart.case_spans=@($row.retained_default_counterpart.case_spans|Select-Object -Skip 1)}
} 'ordinary correspondence is incomplete'
function Link-Case($Name,[scriptblock]$Action,$Expected=''){
    $failure=$null
    try{& $Action}catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){
        throw "Configured linkage regression $Name failed: $failure; expected $Expected"
    }
    $script:cases++;Write-Output "CONFIGURED LINKAGE PASS: $Name"
}
# The named-evidence objects below are synthetic guard inputs. Actual callers
# obtain this projection only from source-bound raw AUnit evidence validation;
# passing this small linkage unit test never claims that a case was executed.
$context='upstream-test/windows/validation/static'
$namedCases=@((Get-Content (Join-Path $root $classification) -Raw|ConvertFrom-Json -AsHashtable -Depth 24).entries|
    Where-Object selection -CEQ configured-Ada-internal-counterpart-only)[0].source_linkage.aunit_named_cases.case
Link-Case 'only Ada can supply the actual owned-storage inspector role' {
    $definition=@(Get-ConfiguredFixtureDefinitions upstream-test|Where-Object id -CEQ table-storage-private)[0]
    if((@(Get-ConfiguredFixtureRoles $definition) -join '|') -cne 'Ada'){throw 'Wrong private inspector role'}
}
Link-Case 'native T cannot be declared an Ada inspector facade' {
    $null=Get-ConfiguredFixtureRoles @{id='table-storage-private';roles=@('ReferenceC')}
} 'internal counterpart roles differ'
Link-Case 'all22 named identities satisfy only the source-linkage guard' {
    Assert-ConfiguredFixtureNamedCounterparts -Root $root -Context $context -NamedEvidence @{context=$context;runtime_observed=$true;named_aunit_cases=$namedCases}
}
Link-Case 'source labels alone cannot replace actual named observations' {
    Assert-ConfiguredFixtureNamedCounterparts -Root $root -Context $context -NamedEvidence @{context=$context;runtime_observed=$false;named_aunit_cases=$namedCases}
} 'actual same-context named'
Link-Case 'named observations from a different configuration cannot transfer' {
    Assert-ConfiguredFixtureNamedCounterparts -Root $root -Context $context -NamedEvidence @{context='default/windows/validation/static';runtime_observed=$true;named_aunit_cases=$namedCases}
} 'actual same-context named'
Link-Case 'one missing actual named inspector counterpart blocks target receipts' {
    Assert-ConfiguredFixtureNamedCounterparts -Root $root -Context $context -NamedEvidence @{context=$context;runtime_observed=$true;named_aunit_cases=@($namedCases|Select-Object -Skip 1)}
} 'lacks an actual required named'
Link-Case 'invented names cannot replace required actual inspector cases' {
    Assert-ConfiguredFixtureNamedCounterparts -Root $root -Context $context -NamedEvidence @{context=$context;runtime_observed=$true;named_aunit_cases=@('invented')+@($namedCases|Select-Object -Skip 1)}
} 'lacks an actual required named'
Write-Output "PASS: $script:cases configured source-selection regressions; synthetic non-execution fixtures"
