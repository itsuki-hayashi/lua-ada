param([switch] $GitHubOutput)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
$plan=Get-TargetContextPlan -Root $root
$build=@{include=$plan.contexts} | ConvertTo-Json -Compress -Depth 12
$execution=@{include=$plan.partitions} | ConvertTo-Json -Compress -Depth 12
if ($GitHubOutput) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) { throw 'GITHUB_OUTPUT is absent' }
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT,"build_matrix=$build`nexecution_matrix=$execution`n",[Text.UTF8Encoding]::new($false))
} else {
    @{build_matrix=($build | ConvertFrom-Json -AsHashtable);execution_matrix=($execution | ConvertFrom-Json -AsHashtable);
        runtime_acceptance=$false;coverage_authority=$false} | ConvertTo-Json -Depth 16
}
