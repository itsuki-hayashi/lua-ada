Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CliFixtureCases.psm1')
Import-Module (Join-Path $PSScriptRoot 'CliFixtureEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$temporary=Join-Path $root ('reports/cli-batch-guards/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Case([string]$Name,[scriptblock]$Body){&$Body;$script:count++;Write-Output "BATCH CLI GUARD PASS: $Name"}
function Reject([scriptblock]$Body,[string]$Expected){
    $message=$null;try{&$Body|Out-Null}catch{$message=$_.Exception.Message}
    Assert ($null -ne $message -and $message -match $Expected) "Expected rejection $Expected; observed $message"
}
foreach($platform in @('windows','linux','macos')){
    Case "$platform retains79 identical batch definitions and all110 full definitions" {
        $all=Get-CliCaseDefinitions SOURCE SOURCE $platform full
        $batch=Get-CliCaseDefinitions SOURCE SOURCE $platform batch
        Assert ($all.cases.Count -eq 110 -and $batch.cases.Count -eq 79 -and $batch.excluded_interactive_titles.Count -eq 31) 'Checkpoint narrowed its declared source contract'
        Assert (@($batch.cases|Where-Object{'-i' -cin $_.Args}).Count -eq 0) 'Interactive operation entered batch mode'
        foreach($case in $batch.cases){
            $original=@($all.cases|Where-Object Title -CEQ $case.Title)
            Assert ($original.Count -eq 1 -and (Get-TargetWitnessPayloadHash $original[0]) -ceq (Get-TargetWitnessPayloadHash $case)) 'Batch changed an original setup/input/output/error/argv contract'
        }
    }
}
Case 'batch evidence cannot replace a full host receipt' {
    $counterfactual=@{schema_version=1;kind='cli-fixture-observations';mode='batch';synthetic_fixture=$false}
    Reject {Assert-CliFixtureReport -Root $root -Report $counterfactual -Interpreter 'not-executed' -Mode full} 'identity or actual mode differs'
}
Case 'an unreviewed interactive source definition cannot be silently omitted' {
    # This altered module is a source-selection fixture only. It is never
    # used by a CLI/runtime producer and contains no observed test evidence.
    $source=Get-Content (Join-Path $PSScriptRoot 'CliFixtureCases.psm1') -Raw
    $marker='    if($Mode -ceq ''batch''){'
    $insertion='    $cases+=@(@{Title=''UNREVIEWED INTERACTIVE'';Args=@(''-i'');Input='''';Output=''''})' + "`n"
    Assert ($source.Contains($marker)) 'Source-selection mutation anchor missing'
    $path=Join-Path $temporary 'altered-cases.psm1'
    [IO.File]::WriteAllText($path,$source.Replace($marker,$insertion+$marker),[Text.UTF8Encoding]::new($false))
    $module=Import-Module $path -PassThru
    Reject {&$module {Get-CliCaseDefinitions SOURCE SOURCE windows batch}} 'exact reviewed interactive IDs and arguments'
    Remove-Module $module
}
Case 'conflicting batch and interactive selectors fail before any Lua child' {
    $process=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Directory $root `
        -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'check-cli.ps1'),'-Interpreter',(Get-Command pwsh).Source,'-BatchProtocol','-PromptProtocol') `
        -OutputPrefix (Join-Path $temporary 'conflict') -TimeoutSeconds 30
    Assert ($process.exit_code -ne 0 -and [IO.File]::ReadAllText($process.stderr_path).Contains('Choose one explicit CLI protocol subset')) 'Conflicting protocol entered execution'
}
Case 'development collection cannot relabel batch as accepted evidence' {
    $process=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Directory $root `
        -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'check-cli.ps1'),'-Interpreter',(Get-Command pwsh).Source,'-RuntimeRole','ReferenceC','-BatchProtocol','-CollectAllObservations','-DevelopmentObservation') `
        -OutputPrefix (Join-Path $temporary 'development') -TimeoutSeconds 30
    Assert ($process.exit_code -ne 0 -and [IO.File]::ReadAllText($process.stderr_path).Contains('development-only native prompt')) 'Development flags softened batch mode'
}
Write-Output "PASS:$script:count batch selection/preflight guards; source and synthetic metadata only, no Lua execution or target acceptance"
