Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-ConformanceAllocatorSidecar {
    param([Parameter(Mandatory)][Collections.IDictionary]$Observation,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][long]$Limit,[string]$ExpectedSha256='')
    # This binds captured data; it does not certify that Lua ran or supply
    # coverage authority. The caller still validates the executable, actual
    # process, source operation, captures and configuration independently.
    if($Observation.name -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
        ($Observation.process.process_id -isnot [int] -and $Observation.process.process_id -isnot [long]) -or
        $Observation.process.process_id -le 0 -or
        $Observation.environment.LUA_ADA_CONFORMANCE_RUN_ID -isnot [string] -or
        $Observation.environment.LUA_ADA_CONFORMANCE_RUN_ID -cnotmatch '^[0-9a-f]{32}$'){
        throw 'Allocator sidecar lacks an actual expected process/run identity'
    }
    $name=$Observation.name+'.telemetry.'+$Observation.process.process_id+'.json'
    $files=@(Get-ChildItem -LiteralPath $OutputDirectory -Filter ($Observation.name+'.telemetry.*.json'))
    if($files.Count -ne 1 -or $files[0].Name -cne $name){
        throw 'Allocator sidecar filename differs from the actual child PID'
    }
    $bytes=[IO.File]::ReadAllBytes($files[0].FullName)
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if($ExpectedSha256 -ne '' -and ($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$' -or $ExpectedSha256 -cne $hash)){
        throw 'Allocator sidecar captured source hash differs'
    }
    $s=([Text.UTF8Encoding]::new($false,$true).GetString($bytes))|ConvertFrom-Json -AsHashtable
    if($s.process_id -isnot [int] -and $s.process_id -isnot [long]){throw 'Allocator sidecar process identity is not integral'}
    if($s.process_id -ne $Observation.process.process_id -or
        $s.run_id -isnot [string] -or $s.run_id -cne $Observation.environment.LUA_ADA_CONFORMANCE_RUN_ID -or
        $s.configuration -isnot [string] -or $s.configuration -cne $Configuration){
        throw 'Allocator sidecar process/run/configuration identity differs'
    }
    foreach($field in @('schema_version','allocator_limit_bytes','outstanding_bytes','outstanding_blocks',
        'peak_managed_bytes','managed_refusals','provider_refusals')){
        if(-not $s.Contains($field) -or ($s[$field] -isnot [int] -and $s[$field] -isnot [long]) -or $s[$field] -lt 0){
            throw 'Allocator sidecar contains a missing or nonintegral measurement'
        }
    }
    if($s.schema_version -ne 1 -or $s.allocator_limit_bytes -ne $Limit -or
        $s.outstanding_bytes -ne 0 -or $s.outstanding_blocks -ne 0 -or
        $s.shutdown_complete -isnot [bool] -or -not $s.shutdown_complete -or
        $s.accounting_fault -isnot [bool] -or $s.accounting_fault -or
        $s.peak_managed_bytes -gt $Limit){
        throw 'Allocator sidecar ceiling or ownership measurements differ'
    }
    return @{path=$files[0].FullName;sha256=$hash;observed=$s}
}
Export-ModuleMember -Function Read-ConformanceAllocatorSidecar
