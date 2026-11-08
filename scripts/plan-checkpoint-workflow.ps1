param([switch]$GitHubOutput)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CheckpointPlan.psm1')
$plan=Get-CheckpointPlan -Root (Split-Path -Parent $PSScriptRoot)
$matrix=@{include=@($plan.contexts)}
if($GitHubOutput){
    if(-not $env:GITHUB_OUTPUT){throw 'GitHub output path is required'}
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT,('checkpoint_matrix='+($matrix|ConvertTo-Json -Depth 16 -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
}else{$plan|ConvertTo-Json -Depth 16}
