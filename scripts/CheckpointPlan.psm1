Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
function Get-CheckpointPlan {
    param([Parameter(Mandatory)][string]$Root)
    $full=Get-TargetContextPlan -Root $Root
    $contexts=@($full.contexts|Where-Object{$_.profile -ceq 'validation' -and $_.library_type -cin @('static','relocatable')})
    if($contexts.Count -ne 12){throw 'Checkpoint requires exactly12 validation static/shared contexts'}
    return @{schema_version=1;kind='bounded-progress-checkpoint-plan';contexts=$contexts;
        deferred_full_target_contexts=$full.contexts.Count;runtime_acceptance=$false;coverage_authority=$false}
}
Export-ModuleMember -Function Get-CheckpointPlan
