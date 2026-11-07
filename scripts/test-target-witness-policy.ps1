param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1') -Force
$temporary = Join-Path $root ('reports/target-witness-selftests/' + [Guid]::NewGuid().ToString('N'))
$proposals = Join-Path $temporary 'proposals'
[void][IO.Directory]::CreateDirectory($temporary)
$utf8 = [Text.UTF8Encoding]::new($false); $script:Cases=0
& (Join-Path $PSScriptRoot 'new-target-witness-proposals.ps1') -OutputDirectory $proposals
if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare synthetic policy source fixtures' }
$policyRelative = [IO.Path]::GetRelativePath($root,(Join-Path $proposals 'witness-policy.author-proposal.json')).Replace('\','/')
function Case([string] $Name,[scriptblock] $Action) { & $Action; $script:Cases++; Write-Output "TARGET WITNESS TEST PASS: $Name" }
function Assert-True([bool] $Value,[string] $Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock] $Action,[string] $Expected) {
    $failure=$null; try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
    Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"
}
function Save([string] $Path,[object] $Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n")+"`n",$utf8)
    return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function New-Fixture {
    $fixture = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    $policy = Get-Content (Join-Path $root $policyRelative) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $consumer = Get-Content (Join-Path $root $policy.consumer.path) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $unit = Get-Content (Join-Path $root $policy.aunit.path) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $api = Get-Content (Join-Path $root $policy.global_api.path) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $paths = @($policyRelative,$policy.consumer.path,$policy.aunit.path,$policy.global_api.path,
        'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json',
        'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json',
        'tests/conformance/scopes/expanded-t-conformance.api.jsonl','tests/conformance/suite.json','tests/conformance/c-api.jsonl') +
        @($consumer.source_bindings.path) + @($unit.bindings.path)
    foreach ($path in ($paths | Sort-Object -Unique)) {
        $destination=Join-Path $fixture $path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy((Join-Path $root $path),$destination)
    }
    return @{root=$fixture;policy=$policy;consumer=$consumer;aunit=$unit;api=$api}
}
function Update-Fixture([Collections.IDictionary] $Fixture) {
    foreach ($kind in @('consumer','aunit','global_api')) {
        $value=if($kind -ceq 'global_api'){$Fixture.api}else{$Fixture[$kind]}
        $Fixture.policy[$kind].sha256=Save (Join-Path $Fixture.root $Fixture.policy[$kind].path) $value
    }
    $null=Save (Join-Path $Fixture.root $policyRelative) $Fixture.policy
}
function Read-Fixture([Collections.IDictionary] $Fixture,[switch] $Review) {
    Read-TargetWitnessPolicy -Root $Fixture.root -Path $policyRelative -RequireReview:$Review
}
# Every review/report/case object below is a disposable source/validator fixture.
# No named C/Ada case executes and no global catalogue is installed as accepted.
Case 'current source proposals retain 100 C and 94 AUnit protocols with 473 pending API entries' {
    $f=New-Fixture; $r=Read-Fixture $f
    Assert-True ($r.consumer.cases.Count -eq 100 -and $r.aunit.entries.Count -eq 94 -and
        $r.global_api.entries.Count -eq 473 -and -not $r.source_reviewed -and -not $r.runtime_acceptance) 'Proposal gained authority'
    Reject { Read-Fixture $f -Review } 'incomplete|independent review|function source'
}
Case 'retained C and AUnit witness protocols cannot be weakened or removed' {
    $f=New-Fixture; $f.consumer.cases[0].exact_witnesses=@('invented completion'); Update-Fixture $f
    Reject { Read-Fixture $f } 'Retained C witness protocol'
    $f=New-Fixture; $f.aunit.entries[0].required_stdout_line='OK arbitrary'; Update-Fixture $f
    Reject { Read-Fixture $f } 'Retained AUnit witness protocol'
    $f=New-Fixture; $f.consumer.cases=@($f.consumer.cases | Select-Object -Skip 1); Update-Fixture $f
    Reject { Read-Fixture $f } 'omit retained'
}
Case 'fresh source hashes do not permit changing frozen predecessor expectations' {
    $f=New-Fixture
    [IO.File]::AppendAllText((Join-Path $f.root 'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json')," `n",$utf8)
    Reject { Read-Fixture $f } 'hash differs'
}
Case 'changed actual source cannot inherit an old source binding' {
    $f=New-Fixture
    [IO.File]::AppendAllText((Join-Path $f.root $f.consumer.cases[0].source),'changed synthetic source',$utf8)
    Reject { Read-Fixture $f } 'hash differs'
}
Case 'global inventory cardinality anchors and retained routes are independently mandatory' {
    $f=New-Fixture; $f.api.entries=@($f.api.entries | Select-Object -Skip 1); Update-Fixture $f
    Reject { Read-Fixture $f } 'omit retained or global'
    $f=New-Fixture; $f.api.entries[0].anchor_sha256='0'*64; Update-Fixture $f
    Reject { Read-Fixture $f } 'declaration anchor'
    $f=New-Fixture; $entry=@($f.api.entries | Where-Object { $_.retained_route -and $_.named_c_cases.Count -gt 0 })[0]
    $entry.named_c_cases=@(); Update-Fixture $f
    Reject { Read-Fixture $f } 'lost a retained C route'
}
Case 'unknown witness routes and null-array camouflage fail before semantic approval' {
    $f=New-Fixture; $f.api.entries[0].named_c_cases=@('source.c#invented'); Update-Fixture $f
    Reject { Read-Fixture $f } 'unknown C witness'
    $f=New-Fixture; $f.api.entries[0].compiled_witnesses=$null; Update-Fixture $f
    Reject { Read-Fixture $f } 'explicit array'
}
Case 'an accepted ledger count cannot supply absent actual per-context witnesses' {
    $policy=@{source_reviewed=$false;global_api=@{entries=@()}}
    $evidence=@{context='default/windows/validation/static';revision=('a'*40);runtime_observed=$true;named_c_cases=@();named_aunit_cases=@()}
    Reject { Assert-TargetGlobalApiRoutes -Policy $policy -NamedEvidence $evidence -CompiledCases @{} -Context $evidence.context } 'reviewed mapping'
    $policy.source_reviewed=$true
    $policy.global_api.entries=@(@{id='synthetic-only';context_witnesses=@(@{context=$evidence.context;
        named_c_cases=@('source.c#real-case-needed');named_aunit_cases=@();compiled_witnesses=@()})})
    Reject { Assert-TargetGlobalApiRoutes -Policy $policy -NamedEvidence $evidence -CompiledCases @{} -Context $evidence.context } 'actual C witness'
    $policy.global_api.entries[0].context_witnesses[0].named_c_cases=@()
    $policy.global_api.entries[0].context_witnesses[0].compiled_witnesses=@('compiled-header-case')
    Reject { Assert-TargetGlobalApiRoutes -Policy $policy -NamedEvidence $evidence -CompiledCases @{} -Context $evidence.context } 'actual compiled'
}
Case 'runtime functions cannot borrow declaration-only classification or invent a conditional guard'{
    foreach($classification in @('compiled-declaration','conditional-declaration')){
        $f=New-Fixture
        foreach($case in $f.consumer.cases){if($case.Contains('function_source_review')){$case.function_source_review='accepted-current-source'}}
        $entry=@($f.api.entries|Where-Object{ $_.kind -ceq 'function' -and $_.conditions.Count -eq 0 })[0]
        $entry.classification=$classification;$entry.review_status='accepted';$entry.invariant='synthetic classification guard';$entry.boundaries='No execution claim'
        $suite=Get-Content (Join-Path $f.root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable
        $entry.context_witnesses=@($suite.acceptance_contexts|ForEach-Object{
            @{context=$_;disposition='compiled-observed';named_c_cases=@();named_aunit_cases=@();compiled_witnesses=@('synthetic-compiled-only')}
        })
        $f.api.entries=@($entry)+@($f.api.entries|Where-Object id -CNE $entry.id);Update-Fixture $f
        Reject {Read-Fixture $f -Review} 'function/type classification'
    }
}
function New-PublicProposals([string]$Routes){
    $destination=Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    & (Join-Path $PSScriptRoot 'new-target-witness-proposals.ps1') -OutputDirectory $destination `
        -AdditionalConsumerCases (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/additional-public-consumer.author-cases.json') `
        -AdditionalAUnitCases (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/additional-public-aunit.author-cases.json') `
        -AdditionalApiRoutes $Routes|Out-Null
    return $destination
}
Case 'new value auxiliary and scalar source routes remain proposals with no execution or approval authority'{
    $path=New-PublicProposals (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/additional-public-api.author-routes.json')
    $relative=[IO.Path]::GetRelativePath($root,(Join-Path $path 'witness-policy.author-proposal.json')).Replace('\','/')
    $r=Read-TargetWitnessPolicy -Root $root -Path $relative
    $new=@($r.global_api.entries|Where-Object{ $_.Contains('proposed_classification') })
    Assert-True ($r.consumer.cases.Count -eq 187 -and $r.aunit.entries.Count -eq 104 -and $new.Count -eq 32 -and
        @($new|Where-Object{ $_.classification -cne 'pending-semantic-review' -or $_.review_status -cne 'pending' -or
            $_.runtime_acceptance -or $_.execution_evidence.Count }).Count -eq 0 -and -not $r.source_reviewed -and -not $r.runtime_acceptance) 'Source routes invented acceptance'
    foreach($entry in $new){Assert-True ($entry.proposed_context_witnesses.Count -eq 26 -and -not $entry.Contains('context_witnesses')) 'A future route became an actual context observation'}
    Reject {Read-TargetWitnessPolicy -Root $root -Path $relative -RequireReview} 'incomplete|independent review|function source'
}
Case 'API author routes reject invented witnesses declaration-only calls and smuggled passing metadata'{
    $original=Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/additional-public-api.author-routes.json') -Raw
    foreach($change in @('unknown','declaration','approved','evidence')){
        $routes=ConvertFrom-Json $original -AsHashtable -Depth 48
        switch($change){
            unknown{$routes.entries[0].named_c_cases=@('c_api/tests/missing.c#invented')}
            declaration{$routes.entries[0].id='CAPI-LUA-H-MACRO-LUA_VERSION_MAJOR_N-20'}
            approved{$routes.entries[0].review_status='accepted'}
            evidence{$routes.entries[0].execution_evidence=@(@{result='passed'})}
        }
        $path=Join-Path $temporary ('invalid-route-'+$change+'.json');$null=Save $path $routes
        Reject {New-PublicProposals $path} 'unknown actual C witness|Declaration-only|distinct pending actual named'
    }
}
Write-Output "PASS: $script:Cases target witness policy regressions; synthetic source/capture objects only, no executed API acceptance"
