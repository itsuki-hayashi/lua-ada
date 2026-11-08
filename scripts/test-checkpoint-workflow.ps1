Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CheckpointPlan.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$temporary=Join-Path $root ('reports/checkpoint-plan-guards/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$plan=Get-CheckpointPlan -Root $root
Assert ($plan.contexts.Count -eq 12 -and $plan.deferred_full_target_contexts -eq 26 -and -not $plan.runtime_acceptance -and -not $plan.coverage_authority) 'Checkpoint changed the deferred full target'
foreach($configuration in @('default','upstream-test')){foreach($platform in @('windows','linux','macos')){
    $contexts=@($plan.contexts|Where-Object{$_.configuration -ceq $configuration -and $_.platform -ceq $platform})
    Assert ($contexts.Count -eq 2 -and (($contexts.library_type|Sort-Object)-join '|') -ceq 'relocatable|static') 'Checkpoint lost a configuration/platform/linkage'
}}
$count++;Write-Output 'CHECKPOINT GUARD PASS: exactly12 validation contexts preserve the full26 contract'
foreach($context in $plan.contexts){
    $p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Directory $root -OutputPrefix (Join-Path $temporary $context.id) -TimeoutSeconds 30 `
        -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'check-checkpoint.ps1'),'-Context',$context.context,'-PlanOnly')
    Assert ($p.exit_code -eq 0) ([IO.File]::ReadAllText($p.stderr_path))
    $value=Get-Content $p.stdout_path -Raw|ConvertFrom-Json -AsHashtable
    foreach($required in @('runtime-build','tests-build','cli-build','native-oracle-build','core-c-sdk-native','aunit','frontend-opcodes','canonical-compiler-runtime',
        'binary-cli','output-policy','batch-cli-79-plus-2','debug-console-lua','debug-console-c4','readline','allocator-ceiling')){
        Assert ($required -cin $value.steps) "Missing strict checkpoint gate: $required"
    }
    $order=@($value.steps)
    Assert ([Array]::IndexOf($order,'native-oracle-build') -lt [Array]::IndexOf($order,'core-c-sdk-native') -and
        [Array]::IndexOf($order,'native-oracle-build') -lt [Array]::IndexOf($order,'canonical-compiler-runtime')) 'Oracle executable must exist before native-dependent consumers'
    Assert ($value.batch_cli_source_cases -eq 79 -and $value.batch_cli_package_probes -eq 2 -and $value.full_cli_processes -eq 112 -and
        -not $value.runtime_build_requested -and -not $value.runtime_acceptance -and -not $value.coverage_authority) 'Planner invented execution/acceptance or altered CLI scope'
    if($context.configuration -ceq 'upstream-test'){Assert ('real-t-adapter' -cin $value.steps -and 'native-allocator-observer' -cin $value.steps) 'Instrumented context lost actual T gates'}
}
$count++;Write-Output 'CHECKPOINT GUARD PASS: all12 plans retain the required strict compiled and paired gates'
$output=Join-Path $temporary 'github-output'
$p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Directory $root -OutputPrefix (Join-Path $temporary 'github') -TimeoutSeconds 30 `
    -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'plan-checkpoint-workflow.ps1'),'-GitHubOutput') -Environment @{GITHUB_OUTPUT=$output}
Assert ($p.exit_code -eq 0) 'GitHub matrix planning failed'
$lines=@(Get-Content $output);Assert ($lines.Count -eq 1 -and $lines[0].StartsWith('checkpoint_matrix=')) 'Matrix output is not a single explicit JSON value'
$matrix=$lines[0].Substring('checkpoint_matrix='.Length)|ConvertFrom-Json -AsHashtable
Assert ($matrix.include.Count -eq 12) 'GitHub matrix narrowed checkpoint contexts'
$count++;Write-Output 'CHECKPOINT GUARD PASS: GitHub matrix is one12-context value'
$p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Directory $root -OutputPrefix (Join-Path $temporary 'unsupported') -TimeoutSeconds 30 `
    -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'check-checkpoint.ps1'),'-Context','default/windows/release/static','-PlanOnly')
Assert ($p.exit_code -ne 0 -and [IO.File]::ReadAllText($p.stderr_path).Contains('Unknown bounded checkpoint context')) 'Unapproved context entered compilation'
$count++;Write-Output 'CHECKPOINT GUARD PASS: unsupported contexts fail before toolchain/build activity'
foreach($file in @('build.yml','remaining-diagnostics.yml')){
    $text=Get-Content (Join-Path $root ('.github/workflows/'+$file)) -Raw
    Assert ($text -match '(?m)^  workflow_dispatch:' -and $text -notmatch '(?m)^  (?:push|pull_request):') 'Deferred campaign still runs automatically'
}
$count++;Write-Output 'CHECKPOINT GUARD PASS: full acceptance/diagnostic campaigns remain manual and unchanged in scope'
Write-Output "PASS:$count checkpoint planning/preflight guards; no compiler or Lua execution"
