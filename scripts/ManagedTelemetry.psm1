Set-StrictMode -Version Latest

function Assert-ManagedTelemetry {
    param(
        [Parameter(Mandatory)][Collections.IDictionary] $Telemetry,
        [Parameter(Mandatory)][string] $RunId,
        [Parameter(Mandatory)][int] $ProcessId,
        [Parameter(Mandatory)][string] $Configuration,
        [long] $LimitBytes = 2147483648,
        [switch] $RequireShutdown
    )
    foreach ($field in @('schema_version', 'process_id', 'allocator_limit_bytes',
        'managed_refusals', 'outstanding_bytes', 'outstanding_blocks')) {
        if (-not $Telemetry.Contains($field) -or
            ($Telemetry[$field] -isnot [int] -and $Telemetry[$field] -isnot [long] -and
             $Telemetry[$field] -isnot [ulong]) -or $Telemetry[$field] -lt 0) {
            throw "Invalid managed telemetry field: $field"
        }
    }
    if ($Telemetry.schema_version -ne 1 -or $Telemetry.run_id -cne $RunId -or
        $Telemetry.process_id -ne $ProcessId -or $Telemetry.configuration -cne $Configuration -or
        $Telemetry.allocator_limit_bytes -ne $LimitBytes -or
        $Telemetry.outstanding_bytes -ne 0 -or $Telemetry.outstanding_blocks -ne 0) {
        throw 'Mismatched or unbalanced managed telemetry'
    }
    if ($RequireShutdown -and
        ($Telemetry.shutdown_complete -isnot [bool] -or -not $Telemetry.shutdown_complete -or
         $Telemetry.accounting_fault -isnot [bool] -or $Telemetry.accounting_fault)) {
        throw 'Missing shutdown or failed allocator accounting'
    }
}

Export-ModuleMember -Function Assert-ManagedTelemetry
