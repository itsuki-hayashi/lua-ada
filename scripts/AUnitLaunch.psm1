Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AUnitContextProcess {
    param([Parameter(Mandatory)][string] $RepositoryRoot,
          [Parameter(Mandatory)][string] $Executable,
          [Parameter(Mandatory)][string] $ExecutableSha256,
          [Parameter(Mandatory)][string] $ReceiptPath,
          [string[]] $Arguments = @(),
          [ValidateRange(1,890000)][int] $TimeoutMilliseconds = 890000)
    $root = (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
    $environmentDirectory = Join-Path $root 'tests'
    $observedDirectory = (Get-Location).ProviderPath
    if ($observedDirectory -cne $environmentDirectory) {
        throw 'AUnit child must inherit the selected nested test environment directory'
    }
    $executablePath = (Resolve-Path -LiteralPath $Executable).ProviderPath
    if ($ExecutableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $executablePath).Hash.ToLowerInvariant() -cne $ExecutableSha256) {
        throw 'AUnit child executable hash differs before launch'
    }
    # Alire selects the nested crate before this helper starts. Keep that
    # inherited environment, while giving the actual executable the same
    # repository-relative fixture paths as the documented root invocation.
    # Streams remain inherited so the outer collector captures exact output.
    $start = [Diagnostics.ProcessStartInfo]::new($executablePath)
    $start.WorkingDirectory = $root
    $start.UseShellExecute = $false
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Cannot start AUnit child process' }
        $childId = $process.Id
        $completed = $process.WaitForExit($TimeoutMilliseconds)
        if (-not $completed) { $process.Kill($true); $process.WaitForExit() }
        $record = [ordered]@{schema_version=1; kind='aunit-process-launch';
            repository_root=$root; selected_environment_directory=$environmentDirectory;
            observed_environment_directory=$observedDirectory; working_directory=$start.WorkingDirectory;
            executable=$executablePath; executable_sha256=$ExecutableSha256;
            arguments=@($Arguments); process_id=$childId; completed=$completed; exit_code=$process.ExitCode;
            source_bindings=@(foreach ($name in @('AUnitLaunch.psm1','run-aunit-in-context.ps1')) {
                @{path='scripts/'+$name; sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash.ToLowerInvariant()}
            }); runtime_acceptance=$false; coverage_authority=$false}
        [IO.File]::WriteAllText($ReceiptPath,
            (ConvertTo-Json -InputObject $record -Depth 8).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
        return $record
    } finally { $process.Dispose() }
}

function Assert-AUnitLaunchReceipt {
    param([Parameter(Mandatory)][Collections.IDictionary] $Receipt,
          [Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][string] $CapturedRepositoryRoot,
          [Parameter(Mandatory)][string] $Executable,
          [Parameter(Mandatory)][string] $ExecutableSha256,
          [string[]] $ExpectedArguments = @())
    # Captures can be reconciled on another OS. Compare the captured absolute
    # directory spelling without interpreting a Windows path on a POSIX host;
    # resolve only the relative first-party source bindings in the current tree.
    $capturedRoot=$CapturedRepositoryRoot.Replace('\','/').TrimEnd('/')
    if ($capturedRoot -cnotmatch '^(?:[A-Za-z]:/|/)' -or $capturedRoot -cmatch '(?:^|/)\.\.?(?:/|$)' -or
        $Receipt.schema_version -ne 1 -or $Receipt.kind -cne 'aunit-process-launch' -or
        $Receipt.repository_root.Replace('\','/').TrimEnd('/') -cne $capturedRoot -or
        $Receipt.selected_environment_directory.Replace('\','/') -cne "$capturedRoot/tests" -or
        $Receipt.observed_environment_directory.Replace('\','/') -cne "$capturedRoot/tests" -or
        $Receipt.working_directory.Replace('\','/').TrimEnd('/') -cne $capturedRoot) {
        throw 'AUnit launch environment or execution directory differs'
    }
    if ($Receipt.executable -cne $Executable -or $Receipt.executable_sha256 -cne $ExecutableSha256 -or
        $Receipt.executable_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Receipt.arguments -isnot [Array] -or $Receipt.arguments.Count -ne $ExpectedArguments.Count -or
        (ConvertTo-Json -InputObject $Receipt.arguments -Compress) -cne (ConvertTo-Json -InputObject @($ExpectedArguments) -Compress) -or
        ($Receipt.process_id -isnot [long] -and $Receipt.process_id -isnot [int]) -or $Receipt.process_id -le 0 -or
        $Receipt.completed -isnot [bool] -or -not $Receipt.completed -or $Receipt.exit_code -ne 0 -or
        $Receipt.runtime_acceptance -isnot [bool] -or $Receipt.runtime_acceptance -or
        $Receipt.coverage_authority -isnot [bool] -or $Receipt.coverage_authority) {
        throw 'AUnit launch process identity, arguments or completion differs'
    }
    if (@($Receipt.source_bindings).Count -ne 2) { throw 'AUnit launch source bindings missing' }
    foreach ($path in @('scripts/AUnitLaunch.psm1','scripts/run-aunit-in-context.ps1')) {
        $binding=@($Receipt.source_bindings | Where-Object path -CEQ $path)
        if ($binding.Count -ne 1 -or
            (Get-FileHash -LiteralPath (Join-Path $Root $path)).Hash.ToLowerInvariant() -cne $binding[0].sha256) {
            throw 'AUnit launch source binding differs'
        }
    }
}

Export-ModuleMember -Function Invoke-AUnitContextProcess, Assert-AUnitLaunchReceipt
