Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceExclusionEligibility.psm1')

function Invoke-ConformanceProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Executable,
        [string[]] $Arguments = @(),
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $OutputPrefix,
        [ValidateRange(1, 3600)][int] $TimeoutSeconds,
        [hashtable] $Environment = @{},
        [ValidateRange(1024, 1073741824)][long] $CaptureLimitBytes = 67108864,
        [string] $StandardInputPath = '',
        [ValidateRange(1, 1073741824)][long] $InputLimitBytes = 67108864
    )
    # Streams go directly to files, preserving invalid UTF-8 and avoiding an
    # unbounded in-memory capture. Classification decodes a separate view only.
    $outPath = $OutputPrefix + '.stdout'
    $errPath = $OutputPrefix + '.stderr'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $outPath))
    $inputFile=$null;$inputRecord=$null;$inputTask=$null;$inputClosed=$false
    if($StandardInputPath -ne ''){
        # Freeze the bytes actually supplied, including empty input, NUL and
        # invalid UTF-8. A later change to the producer's output cannot rewrite
        # the consumer's evidence. Copy before opening stdout, since a caller
        # may intentionally use an earlier stdout capture as its input.
        $sourceInput=(Resolve-Path -LiteralPath $StandardInputPath -ErrorAction Stop).Path
        if(-not (Test-Path -LiteralPath $sourceInput -PathType Leaf) -or
            (Get-Item -LiteralPath $sourceInput).Length -gt $InputLimitBytes){throw 'Standard input file is missing or exceeds its byte limit'}
        $inputPath=$OutputPrefix+'.stdin'
        [IO.File]::Copy($sourceInput,$inputPath,$false)
        if((Get-Item -LiteralPath $inputPath).Length -gt $InputLimitBytes){throw 'Standard input snapshot exceeds its byte limit'}
        $inputFile=[IO.File]::OpenRead($inputPath)
        $inputRecord=[ordered]@{source_path=$sourceInput;path=$inputPath;bytes=$inputFile.Length;
            sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($inputFile)).ToLowerInvariant();
            byte_limit=$InputLimitBytes;write_completed=$false;eof_sent=$false}
        $inputFile.Position=0
    }
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
                         'LUA_ADA_CONFORMANCE_ALLOCATOR',
                         'LUA_ADA_CONFORMANCE_TELEMETRY',
                         'LUA_ADA_CONFORMANCE_RUN_ID')) {
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
        $processId = $process.Id
        $outTask = $process.StandardOutput.BaseStream.CopyToAsync($outFile)
        $errTask = $process.StandardError.BaseStream.CopyToAsync($errFile)
        if($null -eq $inputFile){$process.StandardInput.Close();$inputClosed=$true}
        else{
            # Output draining starts before the asynchronous input write: a
            # child may fill stdout before reading stdin, or stop reading.
            # Neither case may block the timer on a synchronous pipe write.
            $inputTask=$inputFile.CopyToAsync($process.StandardInput.BaseStream)
        }
        while (-not $process.WaitForExit(50)) {
            if($null -ne $inputTask -and $inputTask.IsCompleted -and -not $inputClosed){
                $process.StandardInput.BaseStream.Close();$inputClosed=$true
                $inputRecord.eof_sent=$true
            }
            $timedOut = $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds
            $captureExceeded = $outFile.Length -gt $CaptureLimitBytes -or
                               $errFile.Length -gt $CaptureLimitBytes
            if ($timedOut -or $captureExceeded -or $outTask.IsFaulted -or $errTask.IsFaulted -or
                ($null -ne $inputTask -and $inputTask.IsFaulted)) {
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
        [Threading.Tasks.Task[]]$tasks = @($outTask, $errTask)
        if($null -ne $inputTask){$tasks+=$inputTask}
        $combined = [Threading.Tasks.Task]::WhenAll($tasks)
        try {
            if (-not $combined.Wait(5000)) { $drainFailed = $true }
        }
        catch { $drainFailed = $true }
        if($null -ne $inputTask){
            # Close the raw stream, avoiding any text writer encoding or BOM.
            # A child which exits before reading the supplied data leaves an
            # explicit failed pipe observation even if it returned status 0.
            if(-not $inputClosed){$process.StandardInput.BaseStream.Close();$inputClosed=$true;$inputRecord.eof_sent=$true}
            $inputRecord.write_completed=$inputTask.IsCompletedSuccessfully
            if(-not $inputRecord.write_completed){$drainFailed=$true}
        }
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
        if($null -ne $inputFile){$inputFile.Dispose()}
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
    $record=[ordered]@{
        executable = $Executable
        process_id = $processId
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
    if($null -ne $inputRecord){$record.standard_input=$inputRecord}
    return $record
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

function Test-ConformanceConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Observed,
          [Parameter(Mandatory)][ValidateSet('default', 'upstream-test')][string] $Configuration,
          [Parameter(Mandatory)][ValidateSet('ReferenceC', 'Ada')][string] $Target,
          [Parameter(Mandatory)][long] $AllocatorLimitBytes)
    # Verify measured configuration before executing fixtures. In particular,
    # a renamed C oracle cannot certify the Ada implementation or its ABI.
    $required = @('schema_version', 'configuration', 'lua_release', 'integer_bytes',
        'number_bytes', 'pointer_bytes', 'extra_space_bytes', 'expected_extra_space_bytes',
        'allocator_limit_bytes', 'max_stack', 'max_c_calls', 'aux_buffer_bytes',
        'compat_global', 'rand32', 'compat_math', 'allocator_accounting')
    foreach ($field in $required) {
        if (-not $Observed.Contains($field)) { throw "Configuration field missing: $field" }
    }
    foreach ($field in @('schema_version','integer_bytes','number_bytes','pointer_bytes',
        'extra_space_bytes','expected_extra_space_bytes','allocator_limit_bytes',
        'max_stack','max_c_calls','aux_buffer_bytes','compat_global')) {
        if ($Observed[$field] -isnot [int] -and $Observed[$field] -isnot [long] -and
            $Observed[$field] -isnot [ulong]) { throw "Nonintegral configuration field: $field" }
    }
    if ($Observed.rand32 -isnot [bool] -or $Observed.compat_math -isnot [bool] -or
        $Observed.extra_space_bytes -le 0) { throw 'Invalid boolean/extra-space configuration field' }
    if ($Observed.schema_version -ne 1 -or $Observed.configuration -cne $Configuration -or
        $Observed.lua_release -cne 'Lua 5.5.1' -or
        $Observed.integer_bytes -ne 8 -or $Observed.number_bytes -ne 8 -or
        $Observed.pointer_bytes -ne [IntPtr]::Size -or
        $Observed.extra_space_bytes -ne $Observed.expected_extra_space_bytes -or
        $Observed.allocator_limit_bytes -ne $AllocatorLimitBytes -or
        [string]::IsNullOrWhiteSpace($Observed.allocator_accounting)) {
        throw 'Observed configuration does not match the requested numeric/allocator baseline'
    }
    $expected = if ($Configuration -eq 'default') {
        @{ compat_global=1; max_stack=1000000; max_c_calls=200;
           extra_space_bytes=[IntPtr]::Size; aux_buffer_bytes=16 * [IntPtr]::Size * 8;
           rand32=$false; compat_math=$false }
    } else {
        @{ compat_global=0; max_stack=68000; max_c_calls=180;
           aux_buffer_bytes=23; rand32=$true; compat_math=$true }
    }
    foreach ($field in $expected.Keys) {
        if ($Observed[$field] -cne $expected[$field]) {
            throw "Configuration drift: $Configuration/$field"
        }
    }
    if ($Target -eq 'Ada' -and
        (-not $Observed.Contains('implementation') -or
         $Observed.implementation -cne 'Lua Ada' -or
         -not $Observed.Contains('test_adapter') -or
         $Observed.test_adapter -isnot [bool] -or
         $Observed.test_adapter -cne ($Configuration -eq 'upstream-test'))) {
        throw 'Ada configuration probe does not identify the actual runtime/test adapter'
    }
      if ($Target -eq 'ReferenceC' -and
          (-not $Observed.Contains('implementation') -or
           $Observed.implementation -cne 'C Lua' -or
           -not $Observed.Contains('test_adapter') -or
           $Observed.test_adapter -isnot [bool] -or
           $Observed.test_adapter -cne ($Configuration -eq 'upstream-test'))) {
          throw 'C configuration probe does not identify the pinned oracle/test adapter'
      }
    return $true
}

function Test-ConformanceAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Process,
          [Parameter(Mandatory)][System.Collections.IDictionary] $Outcome,
          [Parameter(Mandatory)][System.Collections.IDictionary] $Contract,
          [Parameter(Mandatory)][string] $Operation,
          [Parameter(Mandatory)][string] $Context,
          [Parameter(Mandatory)][object[]] $SourceRecords,
          [Parameter(Mandatory)][string] $RunId,
          [Parameter(Mandatory)][string] $Configuration,
          [Parameter(Mandatory)][long] $AllocatorLimitBytes,
          [bool] $CoverageComplete = $false,
          [System.Collections.IDictionary] $CoverageRecords = @{},
          [System.Collections.IDictionary] $Telemetry,
          [ValidateSet('strict-upstream','remaining-upstream-compatibility')]
          [string] $TargetPolicy = 'strict-upstream',
          [Collections.IDictionary] $ResolvedExclusions = @{})
    # A process observation deliberately carries no coverage authority. This
    # second, explicit gate requires the reviewed execution protocol AND the
    # complete source/API ledger. Callers cannot promote an OK marker alone.
    if (-not $CoverageComplete) { throw 'Complete reviewed coverage is required for acceptance' }
    if ($TargetPolicy -ceq 'strict-upstream' -and $ResolvedExclusions.Count -ne 0) {
        throw 'Strict upstream execution cannot consume target exclusions'
    }
    foreach ($field in @('schema_version','operation','context','reference_revision',
                          'source_hashes','review','completion_marker','stdout_required',
                          'stderr_expected','expected_skips')) {
        if (-not $Contract.Contains($field)) { throw "Execution contract field missing: $field" }
    }
    if ($Contract.schema_version -ne 1 -or $Contract.operation -cne $Operation -or
        $Contract.context -cne $Context -or
        $Contract.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294') {
        throw 'Execution contract identifies a different operation/context/reference'
    }
    $review = $Contract.review
    foreach ($field in @('author','reviewer','artifact','rationale','original_c_evidence')) {
        if ($null -eq $review -or -not $review.Contains($field) -or
            [string]::IsNullOrWhiteSpace([string]$review[$field])) {
            throw "Execution contract lacks independent review: $field"
        }
    }
    if ($review.author -ceq $review.reviewer) { throw 'Execution contract author cannot be its reviewer' }
    $hashes = $Contract.source_hashes
    if ($null -eq $hashes -or $hashes.Count -eq 0) { throw 'Execution contract lacks source hashes' }
    foreach ($entry in $hashes.GetEnumerator()) {
        $matching = @($SourceRecords | Where-Object { $_.path -ceq $entry.Key })
        if ($matching.Count -ne 1 -or $matching[0].sha256 -cne $entry.Value) {
            throw "Execution contract source differs: $($entry.Key)"
        }
    }
    $requiredFile = switch ($Operation) {
        'aggregate' { 'all.lua' } 'heavy' { 'heavy.lua' }
        { $_.StartsWith('file:') } { $_.Substring(5) }
        default { throw 'Smoke observations cannot establish M3 acceptance' }
    }
    if (-not $hashes.Contains($requiredFile)) { throw 'Execution contract omits its primary source' }
    if ($Operation -eq 'aggregate' -and @($hashes.Keys | Where-Object { $_ -like '*.lua' }).Count -ne 34) {
        throw 'Aggregate contract must identify all 34 original Lua sources'
    }
    if (-not $Outcome.execution_completed) { throw "Execution did not complete: $($Outcome.status)" }
    $stdout = [IO.File]::ReadAllText($Process.stdout_path)
    $stderr = [IO.File]::ReadAllText($Process.stderr_path)
    $marker = [string]$Contract.completion_marker
    if ($marker -ne '' -and -not [regex]::IsMatch($stdout,
        '(?m)^' + [regex]::Escape($marker) + '\r?$')) { throw 'Reviewed completion marker missing' }
    if ($marker -eq '' -and @($Contract.stdout_required).Count -eq 0) {
        throw 'A reviewed semantic completion witness is required'
    }
    foreach ($expectation in @($Contract.stdout_required)) {
        if ($expectation.count -lt 1 -or [string]::IsNullOrWhiteSpace($expectation.pattern) -or
            [regex]::Matches($stdout, $expectation.pattern).Count -ne $expectation.count) {
            throw 'Reviewed stdout semantic witness differs'
        }
    }
    # Every stderr line must belong to a counted expected warning/progress
    # pattern. Aggregate runs intentionally print warnings, but unconstrained
    # stderr would also hide allocator aborts and missing-feature diagnostics.
    foreach ($expectation in @($Contract.stderr_expected)) {
        if ($expectation.count -lt 1 -or -not $expectation.pattern.StartsWith('^') -or
            -not $expectation.pattern.EndsWith('$') -or
            [regex]::Matches($stderr, '(?m)' + $expectation.pattern).Count -ne $expectation.count) {
            throw 'Reviewed stderr warning/progress count differs'
        }
    }
    foreach ($line in ($stderr -split '\r\n|\n|\r' | Where-Object { $_ -ne '' })) {
        if (@($Contract.stderr_expected | Where-Object {
            [regex]::IsMatch($line, $_.pattern)
        }).Count -eq 0) { throw "Unexpected stderr: $line" }
    }
    $expectedSkips = @($Contract.expected_skips)
    $actualSkips = @($Outcome.skip_messages)
    $excludedOmissions = @{}
    if ($expectedSkips.Count -ne $actualSkips.Count) { throw 'Unreviewed or missing omission message' }
    foreach ($skip in $expectedSkips) {
        $expectedCount = @($expectedSkips | Where-Object { $_.message -ceq $skip.message }).Count
        if (@($actualSkips | Where-Object { $_ -ceq $skip.message }).Count -ne $expectedCount -or
            @($skip.coverage_ids).Count -eq 0 -or
            [string]::IsNullOrWhiteSpace($skip.review_artifact) -or
            [string]::IsNullOrWhiteSpace($skip.original_c_evidence)) {
            throw 'Omission message lacks exact independently reviewed coverage disposition'
        }
        foreach ($id in $skip.coverage_ids) {
            # Link omissions to genuine resolved runtime obligations, never to
            # a reviewed guard/template or an arbitrary nonempty identifier.
            if (-not $CoverageRecords.Contains($id)) {
                throw "Omission names an unknown coverage obligation: $id"
            }
            $record = $CoverageRecords[$id]
            if ($TargetPolicy -ceq 'remaining-upstream-compatibility' -and $ResolvedExclusions.Contains($id)) {
                # The inventory caller has already checked original bytes and
                # independent exclusion authority. Only a genuine default-T
                # absence may link to that decision here. It remains a named
                # exclusion, without inventing instrumented execution proof.
                $excluded = $ResolvedExclusions[$id]
                if ($Configuration -cne 'default' -or $skip.message -cnotmatch 'testC not active' -or
                    $record.kind -cnotin @('assert-call','reviewed-block') -or $record.status -cne 'pending' -or
                    $excluded.id -cne $id -or $excluded.status -cne 'excluded' -or
                    $excluded.disposition -cne 'reviewed-t-internal-exclusion' -or
                    $excluded.eligibility -cne 't-only-private-invariant' -or
                    @($excluded.configurations).Count -ne 1 -or $excluded.configurations[0] -cne 'upstream-test' -or
                    -not (Test-ConformanceExclusionCompatibilityShape $excluded) -or
                    @($excluded.evidence).Count -ne 0) {
                    throw "Omission cannot use this target exclusion: $id"
                }
                $excludedOmissions[$id] = $true
                continue
            }
            if ($record.status -cne 'passed' -or
                $record.kind -notin @('assert-call','reviewed-block') -or
                @($record.evidence | Where-Object { $_.result -ceq 'passed' }).Count -eq 0) {
                throw "Omission lacks executed runtime coverage: $id"
            }
            # A T-absent process cannot discharge another T-absent process's
            # omission. Require actual instrumented evidence for the linked
            # invariant; exact omitted-body membership remains independently
            # reviewed in the source-bound execution contract.
            if ($skip.message -match 'testC not active' -and
                @($record.evidence | Where-Object {
                    $_.result -ceq 'passed' -and
                    $_.context -cmatch '^upstream-test/(?:(?:windows|linux|macos)/validation/(?:static|shared)|windows/validation/static-pic)$'
                }).Count -eq 0) {
                throw "T omission lacks instrumented runtime coverage: $id"
            }
        }
    }
    # Only the process owning this report can certify its allocator events.
    # Child interpreters use distinct PID sidecars, so their refusals cannot
    # accidentally make the parent heavy.lua run appear to have caught one.
    if ($null -eq $Telemetry) { throw 'Managed-allocation telemetry is missing' }
    foreach ($field in @('schema_version','process_id','allocator_limit_bytes',
        'managed_refusals','outstanding_bytes','outstanding_blocks')) {
        if (-not $Telemetry.Contains($field) -or
            ($Telemetry[$field] -isnot [int] -and $Telemetry[$field] -isnot [long] -and
             $Telemetry[$field] -isnot [ulong]) -or $Telemetry[$field] -lt 0) {
            throw "Invalid managed-allocation telemetry field: $field"
        }
    }
    if ($Telemetry.schema_version -ne 1 -or
        $Telemetry.run_id -cne $RunId -or $Telemetry.process_id -ne $Process.process_id -or
        $Telemetry.configuration -cne $Configuration -or
        $Telemetry.allocator_limit_bytes -ne $AllocatorLimitBytes -or
        $Telemetry.outstanding_bytes -ne 0 -or $Telemetry.outstanding_blocks -ne 0) {
        throw 'Missing, mismatched or unbalanced managed-allocation telemetry'
    }
    if ($Operation -eq 'heavy' -and
        ($Telemetry.managed_refusals -lt 1 -or
         -not [regex]::IsMatch($stdout, '(?im)^expected error:\s+.*not enough memory'))) {
        throw 'heavy.lua did not demonstrate caught managed-allocation refusal'
    }
    return [ordered]@{ gate_acceptance=$true; operation=$Operation; context=$Context;
        review_artifact=$review.artifact; allocator_telemetry_verified=$true;
        excluded_omissions=@($excludedOmissions.Keys | Sort-Object) }
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
    Copy-ConformanceFixtures, Test-ConformanceFixtureHashes,
    Test-ConformanceConfiguration, Test-ConformanceAcceptance
