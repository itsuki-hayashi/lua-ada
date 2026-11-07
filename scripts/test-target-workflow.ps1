param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$temporary=Join-Path $root ('reports/target-workflow-selftests/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$shell=(Get-Command pwsh -ErrorAction Stop).Source;$script:Cases=0;$script:Serial=0
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "TARGET WORKFLOW TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Tool([string]$Name,[string[]]$Arguments,[hashtable]$Environment=@{}){
    $script:Serial++
    return Invoke-ConformanceProcess -Executable $shell -Arguments (@('-NoProfile','-File',(Join-Path $PSScriptRoot $Name))+$Arguments) `
        -Directory $root -OutputPrefix (Join-Path $temporary "tool-$script:Serial") -Environment $Environment -TimeoutSeconds 30
}
function Read-Result([Collections.IDictionary]$Process){
    Assert-True ($Process.exit_code -eq 0) ([IO.File]::ReadAllText($Process.stderr_path))
    return Get-Content -LiteralPath $Process.stdout_path -Raw|ConvertFrom-Json -AsHashtable -Depth 32
}
# Every invocation below is PlanOnly, a planner, or a deliberately invalid
# preflight. No Alire/compiler/Lua/AUnit or GitHub job is executed.
Case 'workflow matrix output includes all 26 contexts and 130 exact partitions'{
    $result=Read-Result (Tool plan-target-workflow.ps1 @())
    Assert-True ($result.build_matrix.include.Count -eq 26 -and $result.execution_matrix.include.Count -eq 130 -and
        -not $result.runtime_acceptance -and -not $result.coverage_authority) 'Planner narrowed the full target'
}
Case 'GitHub matrix outputs are one valid compact JSON object per output line'{
    $output=Join-Path $temporary 'github-output'
    $p=Tool plan-target-workflow.ps1 @('-GitHubOutput') @{GITHUB_OUTPUT=$output}
    Assert-True ($p.exit_code -eq 0) 'GitHub planner failed'
    $lines=@(Get-Content -LiteralPath $output)
    Assert-True ($lines.Count -eq 2) 'Planner emitted incomplete or multiline GitHub output'
    $build=$lines[0].Substring('build_matrix='.Length)|ConvertFrom-Json -AsHashtable
    $execution=$lines[1].Substring('execution_matrix='.Length)|ConvertFrom-Json -AsHashtable
    Assert-True ($build.include.Count -eq 26 -and $execution.include.Count -eq 130) 'GitHub output lost contexts'
}
Case 'context build planning selects the actual configuration profile library and paths'{
    foreach($context in @('default/windows/development/static','default/macos/release/shared',
        'upstream-test/linux/validation/static','upstream-test/windows/validation/static-pic')){
        $result=Read-Result (Tool build-target-context.ps1 @('-Context',$context,'-PlanOnly'))
        $parts=$context.Split('/')
        Assert-True ($result.configuration -ceq $parts[0] -and $result.profile -ceq $parts[2] -and
            $result.library_type -ceq $(if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]}) -and
            -not $result.runtime_acceptance -and -not $result.coverage_authority) 'Build plan selected another runtime'
    }
}
Case 'three File partitions keep every primary pair and the real constructs supplement'{
    $observations=@()
    foreach($partition in @('files-1','files-2','files-3')){
        $result=Read-Result (Tool run-target-partition.ps1 @('-Context','default/windows/validation/static','-Partition',$partition,'-PlanOnly'))
        Assert-True (-not $result.runtime_build_requested -and -not $result.runtime_acceptance) 'Plan claimed a runtime build or acceptance'
        $observations+=@($result.observations)
    }
    Assert-True ($observations.Count -eq 62 -and @($observations|Where-Object variant -CEQ primary).Count -eq 60 -and
        @($observations|Where-Object variant -CEQ constructs-branch-1).Count -eq 2) 'File shards narrowed a target or template'
    foreach($target in @('Ada','ReferenceC')){
        Assert-True (@($observations|Where-Object{ $_.target -ceq $target -and $_.variant -ceq 'primary' }|ForEach-Object file|Sort-Object -Unique).Count -eq 30) 'A target lost one primary'
    }
}
Case 'Aggregate and Heavy have distinct paired observations and cannot become a File smoke subset'{
    foreach($partition in @('aggregate','heavy')){
        $result=Read-Result (Tool run-target-partition.ps1 @('-Context','upstream-test/windows/validation/static','-Partition',$partition,'-PlanOnly'))
        Assert-True ($result.observations.Count -eq 2 -and @($result.observations|Where-Object operation -CNE $partition).Count -eq 0) 'Aggregate/Heavy lost one implementation'
    }
}
Case 'explicit target build flags fail before Alire when source witness policy is absent'{
    foreach($script in @('check.ps1','check-instrumented.ps1')){
        $p=Tool $script @('-TargetPolicy','remaining-upstream-compatibility')
        Assert-True ($p.exit_code -ne 0 -and [IO.File]::ReadAllText($p.stderr_path) -match 'requires its explicit successor witness policy') 'Missing source policy entered a compiler phase'
        $p=Tool $script @('-TargetDevelopmentObservation')
        Assert-True ($p.exit_code -ne 0 -and [IO.File]::ReadAllText($p.stderr_path) -match 'require TargetPolicy') 'Development flag softened the historical default'
    }
}
Write-Output "PASS: $script:Cases target workflow planning/preflight regressions; no compiler/runtime/GitHub execution or acceptance"
