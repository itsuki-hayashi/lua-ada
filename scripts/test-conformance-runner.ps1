param([string] $ReferenceInterpreter = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path $root ('reports/conformance-selftests/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$shell = (Get-Command pwsh -ErrorAction Stop).Source
$encoding = [Text.UTF8Encoding]::new($false)
$failures = [Collections.Generic.List[string]]::new()
$script:cases = 0

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}
function Case {
    param([string] $Name, [scriptblock] $Body)
    $script:cases++
    try { & $Body; Write-Output "RUNNER PASS: $Name" }
    catch { $failures.Add($Name + ': ' + $_.Exception.Message); [Console]::Error.WriteLine("RUNNER FAIL: $Name`: $_") }
}
function Run-Helper {
    param([string] $Name, [string] $Source, [int] $Seconds = 10,
          [long] $CaptureLimit = 67108864)
    $path = Join-Path $temporary ($Name + '.ps1')
    [IO.File]::WriteAllText($path, $Source, $encoding)
    return Invoke-ConformanceProcess -Executable $shell -Arguments @('-NoProfile', '-File', $path) `
        -Directory $temporary -OutputPrefix (Join-Path $temporary $Name) `
        -TimeoutSeconds $Seconds -CaptureLimitBytes $CaptureLimit
}

Case 'empty streams retain zero-byte files' {
    # A successful silent process exercises both CopyToAsync tasks and the
    # explicit Task[] overload; no empty-array-to-null conversion is involved.
    $p = Run-Helper 'empty' 'exit 0'
    Assert-True ($p.exit_code -eq 0 -and $p.stdout_bytes -eq 0 -and $p.stderr_bytes -eq 0) 'empty capture'
    Assert-True (-not $p.pipe_drain_failed) 'asynchronous stream drain'
    Assert-True ($p.stdout_sha256 -eq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') 'empty digest'
}
Case 'binary stdout survives invalid UTF-8 and NUL' {
    # TextReader replacement would hide malformed bytes. Compare the saved
    # raw stream with the exact bytes emitted by a native console stream.
    $p = Run-Helper 'binary' '$s=[Console]::OpenStandardOutput(); $s.Write([byte[]](0,255,195,40,10)); $s.Flush()'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($p.stdout_path)) -ceq 'AP/DKAo=') 'binary capture changed'
    Assert-True ($p.exit_code -eq 0) 'binary helper status'
}
Case 'stderr warnings remain observable' {
    # Deliberate upstream warnings are permitted only by later explicit
    # contracts; this collector preserves them rather than requiring silence.
    $p = Run-Helper 'warning' '[Console]::Error.WriteLine("Lua warning: #expected"); Write-Output "DONE"'
    $outcome = Get-ConformanceOutcome -Process $p -Marker 'DONE'
    Assert-True ($p.stderr_bytes -gt 0 -and $outcome.warning_messages.Count -eq 1) 'warning evidence missing'
    Assert-True ($outcome.status -eq 'passed' -and -not $outcome.gate_acceptance) 'warning collection is not M3 acceptance'
}
Case 'nonzero exit cannot become success with a marker' {
    # A final marker does not override the process result. A deliberate
    # failing helper proves exit status remains part of acceptance.
    $p = Run-Helper 'exit' 'Write-Output "DONE"; exit 17'
    $outcome = Get-ConformanceOutcome -Process $p -Marker 'DONE'
    Assert-True ($outcome.status -eq 'failed' -and $p.exit_code -eq 17) 'exit failure hidden'
}
Case 'signal-like exit stays a separate abnormal observation' {
    # Exit 139 conventionally means SIGSEGV on POSIX, but may be an explicit
    # application return. Preserve that uncertainty instead of inventing a
    # crash cause or folding a potentially crashed process into ordinary fail.
    $code = if ($IsWindows) { 'exit -1073741819' } else { 'exit 139' }
    $p = Run-Helper 'abnormal' $code
    $outcome = Get-ConformanceOutcome -Process $p
    Assert-True ($outcome.status -eq 'abnormal-exit') 'abnormal status lost'
    Assert-True (-not $outcome.execution_completed) 'abnormal run completed'
}
Case 'successful early exit lacks the completion marker' {
    # Some tests return early when unavailable. Ordinary exit success cannot
    # replace a required whole-file completion contract.
    $p = Run-Helper 'marker' 'Write-Output "partial"'
    $outcome = Get-ConformanceOutcome -Process $p -Marker 'DONE'
    Assert-True ($outcome.status -eq 'missing-marker') 'missing marker accepted'
}
Case 'T-only skip is recorded separately from a pass' {
    # The pinned API test prints this message with T absent. Preserve it as
    # incomplete coverage instead of interpreting its zero exit as conformance.
    $p = Run-Helper 'skip' 'Write-Output ">>> testC not active: skipping API tests <<<"; Write-Output "DONE"'
    $outcome = Get-ConformanceOutcome -Process $p -Marker 'DONE'
    Assert-True ($outcome.status -eq 'completed-with-skips' -and $outcome.skip_messages.Count -eq 1) 'skip hidden'
    Assert-True (-not $outcome.gate_acceptance) 'skip promoted to acceptance'
}
Case 'Ada resource abort is not a syntax rejection' {
    # A controlled host quota remains a failed execution observation, even
    # when the tested language source would otherwise be valid.
    $p = Run-Helper 'resource' '[Console]::Error.WriteLine("RESOURCE_ERROR: instruction limit exceeded"); exit 1'
    $outcome = Get-ConformanceOutcome -Process $p -Marker ''
    Assert-True ($outcome.status -eq 'resource-exhausted') 'resource category lost'
}
Case 'unhandled C Lua memory failure aborts the observation' {
    # The unchanged CLI reports an uncaught allocation failure on stderr and
    # returns failure. ReportOnly must not excuse that resource abort merely
    # because it uses C Lua wording rather than Ada's RESOURCE_ERROR tag.
    $p = Run-Helper 'c-memory' '[Console]::Error.WriteLine("lua: not enough memory"); exit 1'
    $outcome = Get-ConformanceOutcome -Process $p
    Assert-True ($outcome.status -eq 'resource-exhausted') 'C allocation abort treated as ordinary failure'
    Assert-True (-not $outcome.execution_completed) 'allocation abort completed'
}
Case 'caught allocation text on stdout remains a successful observation' {
    # heavy.lua prints errors caught with pcall. Diagnostic text in successful
    # stdout cannot itself prove an execution abort or a failed stress test.
    $p = Run-Helper 'caught-memory' 'Write-Output "caught: not enough memory"; Write-Output "DONE"'
    $outcome = Get-ConformanceOutcome -Process $p -Marker 'DONE'
    Assert-True ($outcome.status -eq 'passed' -and $outcome.execution_completed) 'caught allocation text rejected'
    Assert-True (-not $outcome.gate_acceptance) 'process success promoted to M3 acceptance'
}
Case 'wall timeout kills an active root process' {
    # This helper never completes within its allowance. The runner must
    # terminate it and retain timeout evidence rather than block on its pipes.
    $p = Run-Helper 'timeout' 'Start-Sleep -Seconds 30' -Seconds 1
    $outcome = Get-ConformanceOutcome -Process $p
    Assert-True ($p.timed_out -and $outcome.status -eq 'timed-out') 'timeout hidden'
    Assert-True ($p.elapsed_milliseconds -lt 15000) 'timeout cleanup blocked'
}
Case 'excess output fails the capture budget' {
    # The output limit protects the harness itself. Saturating a pipe must
    # never deadlock the parent or be misreported as ordinary test success.
    $p = Run-Helper 'output' '$s=[Console]::OpenStandardOutput(); $b=[byte[]]::new(4096); while($true){$s.Write($b)}' -CaptureLimit 4096
    $outcome = Get-ConformanceOutcome -Process $p
    Assert-True ($p.capture_exceeded -and $outcome.status -eq 'output-limit') 'output ceiling hidden'
}
Case 'process start failure releases capture handles' {
    # A missing executable is a harness setup error. Ensure cleanup does not
    # replace the original failure with an invalid Process.Id access or leak.
    $prefix = Join-Path $temporary 'missing'
    $caught = $false
    try {
        [void](Invoke-ConformanceProcess -Executable (Join-Path $temporary 'absent-program') `
            -Directory $temporary -OutputPrefix $prefix -TimeoutSeconds 1)
    }
    catch { $caught = $true }
    Assert-True $caught 'missing executable unexpectedly ran'
    $stream = [IO.File]::Open($prefix + '.stdout', [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $stream.Dispose()
}
Case 'fixture bytes and hashes survive copying' {
    # Mixed newline and byte values are intentional. The runner must copy
    # bytes without newline normalization, then detect any later mutation.
    $source = Join-Path $temporary 'source'
    [void][IO.Directory]::CreateDirectory($source)
    [IO.File]::WriteAllBytes((Join-Path $source 'sample.lua'), [byte[]](35,10,13,0,255))
    $destination = Join-Path $temporary 'copied'
    $records = Copy-ConformanceFixtures -Source $source -Destination $destination
    Assert-True ((Test-ConformanceFixtureHashes -Directory $destination -Records $records).Count -eq 0) 'copy drift'
    [IO.File]::AppendAllText((Join-Path $destination 'sample.lua'), 'changed')
    $changes = Test-ConformanceFixtureHashes -Directory $destination -Records $records
    Assert-True ($changes.Count -eq 1 -and $changes[0] -eq 'sample.lua') 'mutation not detected'
}
Case 'fixture destination reuse is rejected' {
    # Reusing old fixture trees could retain time.txt or module state and
    # contaminate baseline warnings/results. Every run starts from a new tree.
    $caught = $false
    try { [void](Copy-ConformanceFixtures -Source (Join-Path $temporary 'source') -Destination (Join-Path $temporary 'copied')) }
    catch { $caught = $true }
    Assert-True $caught 'existing fixture directory accepted'
}

if ($ReferenceInterpreter -ne '') {
    Case 'negative allocator ceiling is rejected before CLI execution' {
        # strtoull accepts -1 as a large unsigned number; the first-party
        # launcher must reject that spelling before allocating a Lua state.
        $program = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
        $lib = Join-Path (Split-Path -Parent (Split-Path -Parent $program)) 'lib'
        $environment = @{ LUA_ADA_CONFORMANCE_ALLOCATOR='-1';
            PATH=$lib + [IO.Path]::PathSeparator + $env:PATH;
            LD_LIBRARY_PATH=$lib + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH;
            DYLD_LIBRARY_PATH=$lib + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH }
        $p = Invoke-ConformanceProcess -Executable $program -Arguments @('--conformance-config') `
            -Directory $temporary -OutputPrefix (Join-Path $temporary 'negative-budget') `
            -TimeoutSeconds 10 -Environment $environment
        Assert-True ($p.exit_code -ne 0 -and $p.stdout_bytes -eq 0) 'negative budget accepted'
        Assert-True ([IO.File]::ReadAllText($p.stderr_path).Contains('invalid LUA_ADA_CONFORMANCE_ALLOCATOR')) 'budget diagnostic missing'
    }
}
Write-Output "RUNNER TESTS: $script:cases cases; $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
