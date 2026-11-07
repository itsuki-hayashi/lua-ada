param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$temporary = Join-Path $root ('reports/target-observer-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$shell = (Get-Command pwsh).Source
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Cases = 0
function Case([string] $Name,[scriptblock] $Action) {
    & $Action; $script:Cases++; Write-Output "TARGET OBSERVER TEST PASS: $Name"
}
function Assert-True([bool] $Condition,[string] $Message) { if (-not $Condition) { throw $Message } }
function Invoke-Tool([string] $Name,[string[]] $Arguments) {
    Invoke-ConformanceProcess -Executable $shell -Arguments (@('-NoProfile','-File',(Join-Path $PSScriptRoot $Name)) + $Arguments) `
        -Directory $root -OutputPrefix (Join-Path $temporary ([Guid]::NewGuid().ToString('N'))) -TimeoutSeconds 60
}
Case 'retained observer plans 28 physical processes without a scope policy or executable' {
    $p = Invoke-Tool observe-target-conformance.ps1 @('-Interpreter','unused','-ReferenceInterpreter','unused',
        '-RuntimeDirectory','unused','-PlanOnly')
    Assert-True ($p.exit_code -eq 0) 'Retained observation plan failed'
    $plan = Get-Content $p.stdout_path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    Assert-True ($plan.planned_processes.Count -eq 28 -and -not $plan.target_acceptance -and
        -not $plan.coverage_authority -and $plan.diagnostic_only) 'A plan gained acceptance authority'
}
Case 'all-file observer keeps 30 primaries and both constructs templates' {
    $p = Invoke-Tool observe-target-conformance.ps1 @('-Interpreter','unused','-ReferenceInterpreter','unused',
        '-RuntimeDirectory','unused','-Selection','All','-PlanOnly')
    Assert-True ($p.exit_code -eq 0) 'All-file observation plan failed'
    $plan = Get-Content $p.stdout_path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    Assert-True ($plan.planned_processes.Count -eq 62 -and
        @($plan.planned_processes | Where-Object file -CEQ api.lua).Count -eq 2 -and
        @($plan.planned_processes | Where-Object file -CEQ constructs.lua).Count -eq 4) 'Full file selection was narrowed'
}

$consumerSource = Join-Path $root 'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json'
$unitSource = Join-Path $root 'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json'
$consumerOriginalHash = (Get-FileHash $consumerSource).Hash
$unitOriginalHash = (Get-FileHash $unitSource).Hash
$consumer = Get-Content $consumerSource -Raw | ConvertFrom-Json -AsHashtable -Depth 64
$unit = Get-Content $unitSource -Raw | ConvertFrom-Json -AsHashtable -Depth 64
$fixtureRoot = Join-Path $temporary 'sources'
$sources = @(@($consumer.source_bindings.path) + @($unit.bindings.path) + @($consumer.cases.source) +
    @($unit.entries | ForEach-Object { $_.case.Split('#')[0] }) | Sort-Object -Unique)
foreach ($source in $sources) {
    $target = Join-Path $fixtureRoot $source
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    Copy-Item -LiteralPath (Join-Path $root $source) -Destination $target
}
$changed = Join-Path $fixtureRoot 'c_api/tests/c_api_consumer.c'
[IO.File]::AppendAllText($changed,"`n/* synthetic registration-only source change */`n",$utf8)
$proposalOutput = Join-Path $temporary 'successor'
Case 'fresh successor proposals retain all 100 C and 94 AUnit identities' {
    $p = Invoke-Tool new-target-witness-proposals.ps1 @('-SourceRoot',$fixtureRoot,'-OutputDirectory',$proposalOutput)
    Assert-True ($p.exit_code -eq 0) 'Successor authoring failed'
    $nextConsumer = Get-Content (Join-Path $proposalOutput 'consumer-witness.author-proposal.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $nextUnit = Get-Content (Join-Path $proposalOutput 'aunit-witness.author-proposal.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    Assert-True ($nextConsumer.cases.Count -eq 100 -and $nextUnit.entries.Count -eq 94 -and
        -not $nextConsumer.coverage_authority -and -not $nextConsumer.runtime_acceptance -and
        $nextConsumer.independent_review_status -ceq 'pending') 'Successor lost cases or gained authority'
    $oldIds = @($consumer.cases | ForEach-Object { $_.source + '#' + $_.case_id } | Sort-Object)
    $newIds = @($nextConsumer.cases | ForEach-Object { $_.source + '#' + $_.case_id } | Sort-Object)
    Assert-True (($oldIds -join '|') -ceq ($newIds -join '|')) 'Retained C IDs changed'
    Assert-True ((@($unit.entries.case | Sort-Object) -join '|') -ceq
        (@($nextUnit.entries.case | Sort-Object) -join '|')) 'Retained AUnit IDs changed'
    $matched = @($nextConsumer.source_bindings | Where-Object path -CEQ 'c_api/tests/c_api_consumer.c')[0]
    Assert-True ($matched.sha256 -ceq (Get-FileHash $changed).Hash.ToLowerInvariant()) 'Changed source was not rebound'
    $case = @($nextConsumer.cases | Where-Object source -CEQ 'c_api/tests/c_api_consumer.c')[0]
    Assert-True ($case.function_source_review -ceq 'pending' -and $case.Contains('historical_function_binding') -and
        -not $case.Contains('function_sha256')) 'Stale function binding was presented as current'
}
Case 'successor authoring cannot overwrite accepted historical artifacts' {
    $p = Invoke-Tool new-target-witness-proposals.ps1 @('-SourceRoot',$fixtureRoot,
        '-OutputDirectory',(Join-Path $root 'tests/conformance/reviews'))
    Assert-True ($p.exit_code -ne 0) 'Historical witness output directory was accepted'
    Assert-True ((Get-FileHash $consumerSource).Hash -ceq $consumerOriginalHash -and
        (Get-FileHash $unitSource).Hash -ceq $unitOriginalHash) 'Historical metadata changed'
}
Case 'new cases are explicit pending proposals rather than inferred runtime coverage' {
    $path = Join-Path $temporary 'additional.json'
    $extra = @{cases=@(@{source='c_api/tests/c_api_consumer.c';case_id='synthetic_reader_case';consumer='c-api';
        expected_count=1;exact_witnesses=@('C API PASS: synthetic reader only');pattern_witness=$null;
        runtime_acceptance=$true;execution_evidence=@(@{result='passed'})})}
    [IO.File]::WriteAllText($path,(ConvertTo-Json $extra -Depth 16),$utf8)
    $p = Invoke-Tool new-target-witness-proposals.ps1 @('-SourceRoot',$fixtureRoot,'-OutputDirectory',$proposalOutput,
        '-AdditionalConsumerCases',$path)
    Assert-True ($p.exit_code -eq 0) 'Additional author case failed'
    $mapping = Get-Content (Join-Path $proposalOutput 'consumer-witness.author-proposal.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $extra = @($mapping.cases | Where-Object case_id -CEQ synthetic_reader_case)[0]
    Assert-True ($mapping.cases.Count -eq 101 -and -not $extra.runtime_acceptance -and
        @($extra.execution_evidence).Count -eq 0 -and $extra.independent_review_status -ceq 'pending') 'New author case claimed execution'
}
Write-Output "PASS: $script:Cases development observer/proposal regressions; no Lua execution or coverage acceptance"
exit 0
