Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ConformanceProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Executable,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $OutputPrefix,
        [ValidateRange(1, 3600)][int] $TimeoutSeconds,
        [hashtable] $Environment = @{},
        [ValidateRange(1024, 1073741824)][long] $CaptureLimitBytes = 67108864
    )
    # Streams go directly to files, preserving invalid UTF-8 and avoiding an
    # unbounded in-memory capture. Classification decodes a separate view only.
    $outPath = $OutputPrefix + '.stdout'
    $errPath = $OutputPrefix + '.stderr'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $outPath))
    $outFile = [IO.File]::Create($outPath)
    $errFile = [IO.File]::Create($errPath)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($name in @('LUA_INIT', 'LUA_INIT_5_5', 'LUA_PATH', 'LUA_PATH_5_5',
                         'LUA_CPATH', 'LUA_CPATH_5_5', 'LUA_READLINELIB', 'MEMLIMIT',
                         'LUA_ADA_CONFORMANCE_ALLOCATOR')) {
        [void]$start.Environment.Remove($name)
    }
    foreach ($entry in $Environment.GetEnumerator()) {
        $start.Environment[$entry.Key] = [string]$entry.Value
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $captureExceeded = $false
    $drainFailed = $false
    $killError = $null
    $started = $false
    $startedAt = [DateTime]::UtcNow.ToString('o')
    try {
        [void]$process.Start()
        $started = $true
        $process.StandardInput.Close()
        $outTask = $process.StandardOutput.BaseStream.CopyToAsync($outFile)
        $errTask = $process.StandardError.BaseStream.CopyToAsync($errFile)
        while (-not $process.WaitForExit(50)) {
            $timedOut = $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds
            $captureExceeded = $outFile.Length -gt $CaptureLimitBytes -or
                               $errFile.Length -gt $CaptureLimitBytes
            if ($timedOut -or $captureExceeded -or $outTask.IsFaulted -or $errTask.IsFaulted) {
                try { $process.Kill($true) } catch { $killError = $_.Exception.Message }
                break
            }
        }
        # A root process may exit while a child retains a pipe. Never wait
        # indefinitely for inherited handles; a failed drain is explicit and
        # cannot be reported as a passing run. Active roots are killed as trees.
        if (-not $process.WaitForExit(5000)) {
            try { $process.Kill($true) } catch { $killError = $_.Exception.Message }
            $drainFailed = $true
        }
        $tasks = [Threading.Tasks.Task[]]@($outTask, $errTask)
        $combined = [Threading.Tasks.Task]::WhenAll($tasks)
        try {
            if (-not $combined.Wait(5000)) { $drainFailed = $true }
        }
        catch { $drainFailed = $true }
        if ($drainFailed) {
            $process.StandardOutput.Close()
            $process.StandardError.Close()
        }
        if ($outTask.IsFaulted -or $errTask.IsFaulted) { $drainFailed = $true }
        $watch.Stop()
        $captureExceeded = $captureExceeded -or $outFile.Length -gt $CaptureLimitBytes -or
                           $errFile.Length -gt $CaptureLimitBytes
        $code = if ($process.HasExited) { $process.ExitCode } else { $null }
    }
    finally {
        $watch.Stop()
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true) } catch { $killError = $_.Exception.Message }
        }
        $process.Dispose()
        $outFile.Dispose()
        $errFile.Dispose()
    }
    # Exit codes alone cannot prove an abnormal exit's origin. Preserve the
    # conventional signal/exception ranges for triage; never reinterpret them
    # as ordinary syntax rejection or as a successful skipped test.
    $abnormal = if ($null -eq $code) { 'missing-exit-status' }
                elseif ($IsWindows -and $code -lt 0) { 'windows-high-bit-status' }
                elseif (-not $IsWindows -and $code -ge 129 -and $code -le 192) {
                    'possible-posix-signal-status'
                }
                else { $null }
    return [ordered]@{
        executable = $Executable
        executable_sha256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant()
        arguments = @($Arguments)
        working_directory = $Directory
        started_utc = $startedAt
        elapsed_milliseconds = $watch.ElapsedMilliseconds
        timeout_seconds = $TimeoutSeconds
        exit_code = $code
        abnormal_exit_kind = $abnormal
        timed_out = $timedOut
        capture_limit_bytes = $CaptureLimitBytes
        capture_exceeded = $captureExceeded
        pipe_drain_failed = $drainFailed
        process_tree_kill_error = $killError
        stdout_path = $outPath
        stdout_bytes = (Get-Item -LiteralPath $outPath).Length
        stdout_sha256 = (Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash.ToLowerInvariant()
        stderr_path = $errPath
        stderr_bytes = (Get-Item -LiteralPath $errPath).Length
        stderr_sha256 = (Get-FileHash -LiteralPath $errPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-ConformanceOutcome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Process,
          [string] $Marker = '')
    $stdout = [IO.File]::ReadAllText($Process.stdout_path)
    $stderr = [IO.File]::ReadAllText($Process.stderr_path)
    $messages = @([regex]::Matches($stdout + "`n" + $stderr,
        '(?im)^.*(?:skipp?ing|tests? not performed|cannot test|not active|locale.*not (?:found|available)).*$') |
        ForEach-Object { $_.Value.Trim() })
    $warnings = @([regex]::Matches($stderr, '(?im)^.*(?:Lua warning:|warning:).*$') |
        ForEach-Object { $_.Value.Trim() })
    $markerSeen = $Marker -eq '' -or
        [regex]::IsMatch($stdout, '(?m)^' + [regex]::Escape($Marker) + '\r?$')
    $resource = [regex]::IsMatch($stderr,
        '(?i)RESOURCE_ERROR|instruction (?:limit|budget)|heap object limit|host storage exhausted') -or
        ($Process.exit_code -ne 0 -and [regex]::IsMatch($stderr,
            '(?i)not enough memory|memory allocation error'))
    # An unhandled C Lua memory failure aborts the observation just as an Ada
    # quota does. Only failed processes with that diagnostic on stderr enter
    # this branch: heavy.lua legitimately catches allocation errors and may
    # print their text on stdout before completing successfully.
    $status = if ($Process.timed_out) { 'timed-out' }
              elseif ($Process.capture_exceeded) { 'output-limit' }
              elseif ($Process.pipe_drain_failed -or $Process.process_tree_kill_error) { 'capture-failed' }
              elseif ($Process.abnormal_exit_kind) { 'abnormal-exit' }
              elseif ($resource) { 'resource-exhausted' }
              elseif ($Process.exit_code -ne 0) { 'failed' }
              elseif (-not $markerSeen) { 'missing-marker' }
              elseif ($messages.Count -gt 0) { 'completed-with-skips' }
              else { 'passed' }
    return [ordered]@{
        status = $status
        completion_marker = $Marker
        completion_marker_seen = $markerSeen
        skip_messages = @($messages)
        warning_messages = @($warnings)
        abnormal_exit_kind = $Process.abnormal_exit_kind
        execution_completed = $status -in @('passed', 'completed-with-skips')
        # Execution alone never proves the composite M3 coverage ledger.
        gate_acceptance = $false
    }
}

function Copy-ConformanceFixtures {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Source,
          [Parameter(Mandatory)][string] $Destination)
    if (Test-Path -LiteralPath $Destination) { throw 'Fixture destination must be new' }
    [void][IO.Directory]::CreateDirectory($Destination)
    $records = @()
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse | Sort-Object FullName) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture symlinks are unsupported' }
        $relative = [IO.Path]::GetRelativePath($Source, $file.FullName)
        $target = Join-Path $Destination $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        [IO.File]::Copy($file.FullName, $target)
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) {
            throw "Fixture copy changed bytes: $relative"
        }
        $records += [ordered]@{ path = $relative.Replace('\', '/'); sha256 = $hash }
    }
    return ,$records
}

function Test-ConformanceFixtureHashes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Directory,
          [Parameter(Mandatory)][object[]] $Records)
    $changes = @()
    foreach ($record in $Records) {
        $path = Join-Path $Directory $record.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256) {
            $changes += $record.path
        }
    }
    return ,$changes
}

Export-ModuleMember -Function Invoke-ConformanceProcess, Get-ConformanceOutcome,
    Copy-ConformanceFixtures, Test-ConformanceFixtureHashes
