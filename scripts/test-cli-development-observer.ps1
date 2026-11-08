param([Parameter(Mandatory)][string]$Report)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CliFixtureEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'CliFixtureCases.psm1')
$baseline=Get-Content $Report -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$script:guards=0
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){
    $failure=$null
    try{& $Action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or -not $failure.Contains($Expected,[StringComparison]::Ordinal)){
        throw "Development CLI regression failed: $Name; $failure"
    }
    $script:guards++;Write-Output "DEVELOPMENT CLI GUARD PASS: $Name"
}
function Clone($Value){ConvertTo-Json -InputObject $Value -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48}
Reject {Assert-CliFixtureReport -Root $root -Report $baseline -Interpreter $baseline.executable -Mode prompt} `
    'Development CLI collection cannot supply strict passing evidence' 'an actual development receipt is never passing evidence'
$fixture=Clone $baseline
$fixture.development_observation='False'
Reject {Assert-CliFixtureReport -Root $root -Report $fixture -Interpreter $fixture.executable -Mode prompt} `
    'Development CLI collection cannot supply strict passing evidence' 'a string false cannot relabel collection as strict execution'
$fixture=Clone $baseline
$fixture.development_observation=$false
$fixture.contract_failures=@(@{message='Explicit synthetic guard mutation, not execution evidence'})
Reject {Assert-CliFixtureReport -Root $root -Report $fixture -Interpreter $fixture.executable -Mode prompt} `
    'Development CLI collection cannot supply strict passing evidence' 'a failed contract cannot disappear behind a false mode flag'
foreach($arguments in @(
    @{CollectAllObservations=$true;PromptProtocol=$true;RuntimeRole='ReferenceC'},
    @{CollectAllObservations=$true;DevelopmentObservation=$true;PromptProtocol=$true;RuntimeRole='Ada'},
    @{CollectAllObservations=$true;DevelopmentObservation=$true;NativeProtocol=$true;RuntimeRole='ReferenceC'})){
    Reject {& (Join-Path $PSScriptRoot 'check-cli.ps1') -Interpreter $baseline.executable @arguments} `
        'CollectAllObservations requires explicit development-only native prompt observation' 'development collection cannot attach to another mode or role'
}

# Exercise the checked-in producer function with real native children. Only
# the first EXPECTED contract is deliberately false, making this a synthetic
# contract regression rather than a new passing compatibility observation.
# The second child must still execute, and neither row gains pass evidence.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'check-cli.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'CLI producer does not parse'}
$function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-Case'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$projectRoot=$root
$platform=$baseline.platform
$RuntimeRole='ReferenceC';$Configuration='default';$mode='prompt';$CollectAllObservations=$true
$executable=$baseline.executable;$RuntimeDirectory=$baseline.runtime_directory
$fixtureRoot=Join-Path $root ('reports/cli-development-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$utf8=[Text.UTF8Encoding]::new($false)
$raw=@{processes=@();contract_failures=@();executable_sha256=$baseline.executable_sha256}
$defaultPath=[IO.File]::ReadAllText($baseline.processes[0].process.stdout_path)
$defaultCPath=[IO.File]::ReadAllText($baseline.processes[1].process.stdout_path)
$definitions=Get-CliCaseDefinitions -DefaultPackagePath $defaultPath -DefaultPackageCPath $defaultCPath -Platform $platform -Mode prompt
$first=Clone $definitions.cases[0]
$first.Output='SYNTHETIC deliberately false expected stdout'
$null=Invoke-Case $first
$null=Invoke-Case $definitions.cases[1]
if($raw.processes.Count -ne 2 -or $raw.contract_failures.Count -ne 1 -or
    $raw.processes[0].contract_match -ne $false -or $raw.processes[1].contract_match -ne $true -or
    @($raw.processes|Where-Object passing_execution_evidence).Count -ne 0){
    throw 'Real native children did not continue after the synthetic contract mismatch'
}
$script:guards++
Reject {Assert-CliCaseCapture -Case $definitions.cases[1] -Row $raw.processes[1] -Executable $executable `
    -ExecutableHash $raw.executable_sha256 -Directory $fixtureRoot} `
    'CLI diagnostic cannot masquerade as a clean operation' 'removing the outer collection flag cannot promote a collected row'
$result=@{schema_version=1;kind='cli-development-observer-regressions';synthetic_expected_contract=$true;
    runtime_acceptance=$false;coverage_authority=$false;processes=$raw.processes;contract_failures=$raw.contract_failures;
    scope='Two real native child processes with one intentionally false expected contract; never passing conformance evidence.'}
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'result.json'),($result|ConvertTo-Json -Depth 48).Replace("`r`n","`n")+"`n",$utf8)
Write-Output "PASS:$script:guards development observer authority/continuation regressions; $fixtureRoot"
