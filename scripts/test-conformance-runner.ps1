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
    # Deliberate upstream warnings are permitted only by reviewed explicit
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
Case 'unavailable locale messages remain coverage omissions' {
    # Pinned strings.lua reports unavailable collation/character locales
    # without the word 'skipping'. Keep both omissions visible even when the
    # file exits successfully and prints its required completion marker.
    $p = Run-Helper 'locales' 'Write-Output "collate locale not found"; Write-Output "ctype locale not found"; Write-Output "DONE"'
    $outcome = Get-ConformanceOutcome -Process $p -Marker 'DONE'
    Assert-True ($outcome.status -eq 'completed-with-skips') 'locale omission hidden'
    Assert-True ($outcome.skip_messages.Count -eq 2) 'locale omission count lost'
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

function New-Configuration {
    param([string] $Profile = 'default')
    # Synthetic measured records isolate validation from compiler availability.
    # Production runs obtain the same fields from the selected executable.
    $record = [ordered]@{schema_version=1; configuration=$Profile; lua_release='Lua 5.5.1';
        integer_bytes=8; number_bytes=8; pointer_bytes=[IntPtr]::Size;
        extra_space_bytes=[IntPtr]::Size; expected_extra_space_bytes=[IntPtr]::Size;
        allocator_limit_bytes=67108864L; allocator_accounting='test-only-synthetic';
        compat_global=1; max_stack=1000000; max_c_calls=200;
        aux_buffer_bytes=16 * [IntPtr]::Size * 8; rand32=$false; compat_math=$false;
        implementation='Lua Ada'; test_adapter=$false}
    if ($Profile -eq 'upstream-test') {
        $record.compat_global=0; $record.max_stack=68000; $record.max_c_calls=180
        $record.aux_buffer_bytes=23; $record.rand32=$true; $record.compat_math=$true
        $record.test_adapter=$true
    }
    return $record
}
function New-AcceptanceFixture {
    param([string] $Name = 'acceptance', [string] $Source = 'Write-Output "DONE"')
    # A fake helper is appropriate only for harness logic. No result from this
    # fixture is added to the actual upstream ledger or conformance reports.
    $p = Run-Helper $Name $Source
    return [ordered]@{ Process=$p; Outcome=(Get-ConformanceOutcome -Process $p -Marker 'DONE');
        Contract=[ordered]@{schema_version=1; operation='file:sample.lua';
            context='default/windows/validation/static';
            reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
            source_hashes=[ordered]@{'sample.lua'=('a' * 64)};
            review=[ordered]@{author='fixture author'; reviewer='fixture reviewer';
                artifact='fixture review'; rationale='exercise harness protocol';
                original_c_evidence='fixture baseline'};
            completion_marker='DONE'; stdout_required=@(); stderr_expected=@(); expected_skips=@()};
        Operation='file:sample.lua'; Context='default/windows/validation/static';
        SourceRecords=@([ordered]@{path='sample.lua';sha256=('a' * 64)});
        RunId='fixture-run'; Configuration='default'; AllocatorLimitBytes=67108864L;
        CoverageComplete=$true;
        Telemetry=[ordered]@{schema_version=1; run_id='fixture-run'; process_id=$p.process_id;
            configuration='default'; allocator_limit_bytes=67108864L;
            managed_refusals=0; outstanding_bytes=0; outstanding_blocks=0}}
}
function Assert-AcceptanceRejected {
    param([System.Collections.IDictionary] $Fixture, [string] $Reason)
    $caught = $false
    try { [void](Test-ConformanceAcceptance @Fixture) } catch { $caught = $true }
    Assert-True $caught $Reason
}
Case 'Ada default configuration is measured and identified' {
    # Correct numeric/ABI settings and actual runtime identity are prerequisites;
    # validation returns true without inferring that any source suite passed.
    $record = New-Configuration
    Assert-True (Test-ConformanceConfiguration -Observed $record -Configuration default `
        -Target Ada -AllocatorLimitBytes 67108864L) 'default record rejected'
}
Case 'instrumented Ada configuration has independent settings' {
    # The test profile changes language compatibility and semantic stack limits.
    # Accidentally accepting a default build here would hide missing T coverage.
    $record = New-Configuration 'upstream-test'
    Assert-True (Test-ConformanceConfiguration -Observed $record -Configuration upstream-test `
        -Target Ada -AllocatorLimitBytes 67108864L) 'instrumented record rejected'
}
Case 'a C oracle cannot masquerade as the Ada runtime' {
    # Keep all ABI values correct while changing identity; this detects selecting
    # the wrong executable independently from ordinary profile drift.
    $record = New-Configuration; $record.implementation = 'C Lua'
    $caught = $false
    try { [void](Test-ConformanceConfiguration -Observed $record -Configuration default `
        -Target Ada -AllocatorLimitBytes 67108864L) } catch { $caught = $true }
    Assert-True $caught 'renamed C oracle accepted for Ada'
}
Case 'instrumented configuration cannot omit its test adapter' {
    # T is needed for the API/internal blocks; matching integer sizes alone is
    # insufficient to call this an instrumented acceptance configuration.
    $record = New-Configuration 'upstream-test'; $record.test_adapter=$false
    $caught = $false
    try { [void](Test-ConformanceConfiguration -Observed $record -Configuration upstream-test `
        -Target Ada -AllocatorLimitBytes 67108864L) } catch { $caught = $true }
    Assert-True $caught 'missing adapter accepted'
}
Case 'Ada cannot masquerade as the C baseline' {
    $record = New-Configuration
    $failure = $null
    try { [void](Test-ConformanceConfiguration -Observed $record -Configuration default `
        -Target ReferenceC -AllocatorLimitBytes 67108864L) }
    catch { $failure = $_.Exception.Message }
    Assert-True ($failure -ceq 'C configuration probe does not identify the pinned oracle/test adapter') `
        'Ada identity accepted as C baseline'
}
Case 'C instrumented baseline requires its real adapter' {
    $record = New-Configuration 'upstream-test'
    $record.implementation='C Lua'; $record.test_adapter=$false
    $failure = $null
    try { [void](Test-ConformanceConfiguration -Observed $record -Configuration upstream-test `
        -Target ReferenceC -AllocatorLimitBytes 67108864L) }
    catch { $failure = $_.Exception.Message }
    Assert-True ($failure -ceq 'C configuration probe does not identify the pinned oracle/test adapter') `
        'C baseline without T accepted as instrumented'
}
Case 'profile stack-limit drift fails configuration validation' {
    # An enlarged semantic stack must not be silently introduced just to make a
    # stress assertion pass. Check against the pinned profile's actual limit.
    $record = New-Configuration; $record.max_stack=2000000
    $caught = $false
    try { [void](Test-ConformanceConfiguration -Observed $record -Configuration default `
        -Target Ada -AllocatorLimitBytes 67108864L) } catch { $caught = $true }
    Assert-True $caught 'semantic limit drift accepted'
}
Case 'configuration numeric strings cannot impersonate measured integers' {
    # JSON numbers and strings must remain distinct. PowerShell's coercing
    # comparisons alone would accept a malformed producer protocol here.
    $record = New-Configuration; $record.integer_bytes='8'
    $caught = $false
    try { [void](Test-ConformanceConfiguration -Observed $record -Configuration default `
        -Target Ada -AllocatorLimitBytes 67108864L) } catch { $caught = $true }
    Assert-True $caught 'numeric string accepted as a measured integer'
}
Case 'reviewed execution and complete coverage permit explicit acceptance' {
    # The positive control supplies every independent witness. Ordinary process
    # outcomes remain unaccepted even though this explicit composite gate passes.
    $fixture = New-AcceptanceFixture
    $result = Test-ConformanceAcceptance @fixture
    Assert-True $result.gate_acceptance 'complete protocol rejected'
    Assert-True (-not $fixture.Outcome.gate_acceptance) 'observation was mutated'
}
Case 'an OK marker cannot replace complete coverage' {
    # A process can pass while thousands of ledger obligations remain pending.
    # The final acceptance switch must fail closed in that common intermediate state.
    $fixture = New-AcceptanceFixture 'coverage-pending'; $fixture.CoverageComplete=$false
    Assert-AcceptanceRejected $fixture 'pending coverage accepted'
}
Case 'self review cannot authorize an execution contract' {
    # Independent review is substantive evidence, not merely a nonempty field.
    # Reject identical author/reviewer even when all process checks succeed.
    $fixture = New-AcceptanceFixture 'self-review'; $fixture.Contract.review.reviewer='fixture author'
    Assert-AcceptanceRejected $fixture 'self-reviewed contract accepted'
}
Case 'execution contract source hashes cannot drift' {
    # A valid old contract cannot silently authorize newly edited upstream source.
    # The expected hash must identify exactly the disposable fixture's bytes.
    $fixture = New-AcceptanceFixture 'contract-hash'; $fixture.Contract.source_hashes['sample.lua']=('b' * 64)
    Assert-AcceptanceRejected $fixture 'stale contract source accepted'
}
Case 'Aggregate cannot borrow a file contract missing the other original source hashes' {
    # The helper process is synthetic harness input. Even a reviewed successful
    # observation must bind all 34 original files for Aggregate acceptance.
    $fixture=New-AcceptanceFixture 'aggregate-incomplete-contract'
    $fixture.Operation='aggregate';$fixture.Contract.operation='aggregate'
    $fixture.Contract.source_hashes=[ordered]@{'all.lua'=('a'*64)}
    $fixture.SourceRecords=@([ordered]@{path='all.lua';sha256=('a'*64)})
    $failure=$null
    try{[void](Test-ConformanceAcceptance @fixture)}catch{$failure=$_.Exception.Message}
    Assert-True ($failure -ceq 'Aggregate contract must identify all 34 original Lua sources') 'Incomplete Aggregate contract was accepted or failed at an unrelated gate'
}
Case 'unexpected warning text fails reviewed execution acceptance' {
    # Unlike observation collection, acceptance enumerates every stderr line.
    # An unexpected warning cannot disappear behind a successful exit/marker.
    $fixture = New-AcceptanceFixture 'unexpected-warning' '[Console]::Error.WriteLine("Lua warning: unexpected"); Write-Output "DONE"'
    Assert-AcceptanceRejected $fixture 'unexpected warning accepted'
}
Case 'counted expected warnings remain valid acceptance evidence' {
    # Aggregate tests deliberately emit warnings. A counted, anchored protocol
    # permits exactly those lines without permitting unrelated diagnostics.
    $fixture = New-AcceptanceFixture 'expected-warning' '[Console]::Error.WriteLine("Lua warning: expected"); Write-Output "DONE"'
    $fixture.Contract.stderr_expected=@([ordered]@{pattern='^Lua warning: expected\r?$';count=1})
    Assert-True (Test-ConformanceAcceptance @fixture).gate_acceptance 'expected warning rejected'
}
Case 'T-only early returns require explicit omission dispositions' {
    # Successful T-absent exits are still incomplete until the omitted source
    # blocks have reviewed coverage elsewhere in the required configurations.
    $fixture = New-AcceptanceFixture 'unreviewed-skip' 'Write-Output ">>> testC not active: skipping API tests <<<"; Write-Output "DONE"'
    Assert-AcceptanceRejected $fixture 'T-only early return accepted'
}
Case 'reviewed omission cannot name an invented coverage obligation' {
    # Nonempty review fields are not enough: the named runtime invariant must
    # exist in the independently validated complete ledger.
    $fixture = New-AcceptanceFixture 'invented-skip' 'Write-Output "skipping API tests"; Write-Output "DONE"'
    $fixture.Contract.expected_skips=@([ordered]@{message='skipping API tests';
        coverage_ids=@('LUA-SAMPLE-REVIEWED-BLOCK-0001'); review_artifact='fixture review';
        original_c_evidence='fixture baseline'})
    Assert-AcceptanceRejected $fixture 'invented omission coverage accepted'
}
Case 'a reviewed guard is not executed coverage for an omission' {
    # Guard classification explains applicability but cannot certify its body.
    # A linked runtime assertion/equivalent must have real passing evidence.
    $fixture = New-AcceptanceFixture 'guard-skip' 'Write-Output "skipping API tests"; Write-Output "DONE"'
    $id='LUA-SAMPLE-REVIEWED-BLOCK-0001'
    $fixture.Contract.expected_skips=@([ordered]@{message='skipping API tests';
        coverage_ids=@($id); review_artifact='fixture review'; original_c_evidence='fixture baseline'})
    $fixture.CoverageRecords=@{$id=[ordered]@{status='reviewed';kind='conditional-guard';evidence=@()}}
    Assert-AcceptanceRejected $fixture 'guard review promoted to runtime pass'
}
Case 'omission requires a resolved executed invariant in another context' {
    # This synthetic positive control models default T omission with the actual
    # invariant covered in instrumented acceptance. It is not a suite result.
    $fixture = New-AcceptanceFixture 'covered-skip' 'Write-Output "skipping API tests"; Write-Output "DONE"'
    $id='LUA-SAMPLE-REVIEWED-BLOCK-0001'
    $fixture.Contract.expected_skips=@([ordered]@{message='skipping API tests';
        coverage_ids=@($id); review_artifact='fixture review'; original_c_evidence='fixture baseline'})
    $fixture.CoverageRecords=@{$id=[ordered]@{status='passed';kind='reviewed-block';
        evidence=@([ordered]@{result='passed'})}}
    Assert-True (Test-ConformanceAcceptance @fixture).gate_acceptance 'executed omission invariant rejected'
}
Case 'T omission rejects evidence from a default execution' {
    $fixture = New-AcceptanceFixture 'default-t-skip' 'Write-Output ">>> testC not active: skipping API tests <<<"; Write-Output "DONE"'
    $id='LUA-SAMPLE-REVIEWED-BLOCK-0001'
    $fixture.Contract.expected_skips=@([ordered]@{message=$fixture.Outcome.skip_messages[0];
        coverage_ids=@($id); review_artifact='fixture review'; original_c_evidence='fixture baseline'})
    $fixture.CoverageRecords=@{$id=[ordered]@{status='passed';kind='reviewed-block';
        evidence=@([ordered]@{result='passed';context='default/windows/validation/static'})}}
    Assert-AcceptanceRejected $fixture 'default evidence discharged T omission'
}
Case 'T omission accepts an instrumented runtime witness' {
    $fixture = New-AcceptanceFixture 'instrumented-t-skip' 'Write-Output ">>> testC not active: skipping API tests <<<"; Write-Output "DONE"'
    $id='LUA-SAMPLE-REVIEWED-BLOCK-0001'
    $fixture.Contract.expected_skips=@([ordered]@{message=$fixture.Outcome.skip_messages[0];
        coverage_ids=@($id); review_artifact='fixture review'; original_c_evidence='fixture baseline'})
    $fixture.CoverageRecords=@{$id=[ordered]@{status='passed';kind='reviewed-block';
        evidence=@([ordered]@{result='passed';context='upstream-test/windows/validation/static'})}}
    Assert-True (Test-ConformanceAcceptance @fixture).gate_acceptance 'instrumented T witness rejected'
}
Case 'T omission rejects an unsupported instrumented context' {
    $fixture = New-AcceptanceFixture 'invalid-context-t-skip' 'Write-Output ">>> testC not active: skipping API tests <<<"; Write-Output "DONE"'
    $id='LUA-SAMPLE-REVIEWED-BLOCK-0001'
    $fixture.Contract.expected_skips=@([ordered]@{message=$fixture.Outcome.skip_messages[0];
        coverage_ids=@($id); review_artifact='fixture review'; original_c_evidence='fixture baseline'})
    $fixture.CoverageRecords=@{$id=[ordered]@{status='passed';kind='reviewed-block';
        evidence=@([ordered]@{result='passed';context='upstream-test/linux/validation/static-pic'})}}
    Assert-AcceptanceRejected $fixture 'unsupported context discharged T omission'
}
Case 'a child refusal cannot certify parent allocator telemetry' {
    # Inherited environments create several sidecars. Bind the report to its PID
    # rather than accepting whichever child happened to write a result last.
    $fixture = New-AcceptanceFixture 'wrong-telemetry-pid'; $fixture.Telemetry.process_id++
    Assert-AcceptanceRejected $fixture 'child telemetry accepted'
}
Case 'outstanding allocations prevent acceptance after successful exit' {
    # A clean exit does not prove managed ownership was released. Keep the final
    # byte/block balance part of the runtime's independent telemetry contract.
    $fixture = New-AcceptanceFixture 'allocation-leak'; $fixture.Telemetry.outstanding_bytes=8
    Assert-AcceptanceRejected $fixture 'outstanding allocation accepted'
}
Case 'negative refusal counters are invalid telemetry' {
    # Counters are measured nonnegative quantities. Reject a corrupted provider
    # record even for a regular test that does not require a refusal event.
    $fixture = New-AcceptanceFixture 'negative-refusals'; $fixture.Telemetry.managed_refusals=-1
    Assert-AcceptanceRejected $fixture 'negative allocator counter accepted'
}
Case 'heavy OK without an actual allocation refusal is insufficient' {
    # heavy.lua itself does not assert the caught message. Require both measured
    # allocator refusal and its caught error so an early loop return cannot pass.
    $fixture = New-AcceptanceFixture 'heavy-without-refusal' 'Write-Output "expected error: not enough memory"; Write-Output "DONE"'
    $fixture.Operation='heavy'; $fixture.Contract.operation='heavy'
    $fixture.Contract.source_hashes=[ordered]@{'heavy.lua'=('a' * 64)}
    $fixture.SourceRecords=@([ordered]@{path='heavy.lua';sha256=('a' * 64)})
    Assert-AcceptanceRejected $fixture 'heavy marker promoted without allocator refusal'
}
Case 'heavy requires a caught allocation diagnostic as well as telemetry' {
    # A refusal during an unrelated operation cannot satisfy heavy.lua if its
    # protected workload never observes the language-level allocation failure.
    $fixture = New-AcceptanceFixture 'heavy-without-catch'
    $fixture.Operation='heavy'; $fixture.Contract.operation='heavy'
    $fixture.Contract.source_hashes=[ordered]@{'heavy.lua'=('a' * 64)}
    $fixture.SourceRecords=@([ordered]@{path='heavy.lua';sha256=('a' * 64)})
    $fixture.Telemetry.managed_refusals=1
    Assert-AcceptanceRejected $fixture 'heavy accepted without caught allocation error'
}
Case 'heavy accepts measured refusal caught by its protected workload' {
    # Positive control for the stress protocol: matching PID/config/limit,
    # balanced final storage, and a caught not-enough-memory diagnostic.
    $fixture = New-AcceptanceFixture 'heavy-caught' 'Write-Output "expected error: not enough memory"; Write-Output "DONE"'
    $fixture.Operation='heavy'; $fixture.Contract.operation='heavy'
    $fixture.Contract.source_hashes=[ordered]@{'heavy.lua'=('a' * 64)}
    $fixture.SourceRecords=@([ordered]@{path='heavy.lua';sha256=('a' * 64)})
    $fixture.Telemetry.managed_refusals=1
    Assert-True (Test-ConformanceAcceptance @fixture).gate_acceptance 'caught refusal rejected'
}

if ($ReferenceInterpreter -ne '') {
    Case 'native allocator refusal sidecar is process-bound and balanced' {
        # This case exercises the rebuilt native launcher rather than a mock:
        # Lua catches a request larger than its backing cap, then closes cleanly.
        # Its sidecar must record the actual refusal and final managed balance.
        $program = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
        $lib = Join-Path (Split-Path -Parent (Split-Path -Parent $program)) 'lib'
        $telemetryPrefix = Join-Path $temporary 'native-allocator'
        $environment = @{ LUA_ADA_CONFORMANCE_ALLOCATOR='1048576';
            LUA_ADA_CONFORMANCE_TELEMETRY=$telemetryPrefix;
            LUA_ADA_CONFORMANCE_RUN_ID='abcdef0123456789';
            PATH=$lib + [IO.Path]::PathSeparator + $env:PATH;
            LD_LIBRARY_PATH=$lib + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH;
            DYLD_LIBRARY_PATH=$lib + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH }
        $code = 'global <const> *; local ok,e=pcall(string.rep,"x",2000000); ' +
            'assert(not ok and tostring(e):find("not enough memory")); print("DONE")'
        $p = Invoke-ConformanceProcess -Executable $program -Arguments @('-e',$code) `
            -Directory $temporary -OutputPrefix (Join-Path $temporary 'native-refusal') `
            -TimeoutSeconds 30 -Environment $environment
        Assert-True ($p.exit_code -eq 0 -and $p.stderr_bytes -eq 0) 'native caught-refusal process failed'
        $sidecar = $telemetryPrefix + '.' + $p.process_id + '.json'
        Assert-True (Test-Path -LiteralPath $sidecar -PathType Leaf) 'native sidecar missing'
        $record = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json -AsHashtable
        Assert-True ($record.run_id -ceq 'abcdef0123456789' -and
            $record.process_id -eq $p.process_id -and $record.allocator_limit_bytes -eq 1048576) 'native sidecar identity differs'
        Assert-True ($record.managed_refusals -gt 0 -and
            $record.outstanding_bytes -eq 0 -and $record.outstanding_blocks -eq 0) 'native allocation evidence differs'
    }
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
function New-ExcludedOmissionFixture {
    # Only protocol fixtures are synthesized here. Real exclusions must first
    # pass the source/hash/independent-review inventory validator.
    $fixture = New-AcceptanceFixture 'target-excluded-omission' `
        'Write-Output ">>> testC not active: skipping opcode tests <<<"; Write-Output "DONE"'
    $id = 'LUA-SAMPLE-REVIEWED-BLOCK-0001'
    $fixture.Contract.expected_skips = @(@{message=$fixture.Outcome.skip_messages[0];coverage_ids=@($id);
        review_artifact='synthetic omission review';original_c_evidence='synthetic C absence'})
    $fixture.CoverageRecords = @{$id=@{status='pending';kind='reviewed-block';evidence=@()}}
    $fixture.TargetPolicy = 'remaining-upstream-compatibility'
    $fixture.ResolvedExclusions = @{$id=@{id=$id;status='excluded';disposition='reviewed-t-internal-exclusion';
        eligibility='t-only-private-invariant';configurations=@('upstream-test');public_api=$false;
        mixed_obligation=$false;module_observable=$false;evidence=@()}}
    return $fixture
}
Case 'explicit target T absence reports an exclusion without pass evidence' {
    $fixture = New-ExcludedOmissionFixture
    $result = Test-ConformanceAcceptance @fixture
    Assert-True ($result.gate_acceptance -and $result.excluded_omissions.Count -eq 1) 'Authorized target omission rejected'
    $record = @($fixture.CoverageRecords.Values)[0]
    Assert-True ($record.status -ceq 'pending' -and @($record.evidence).Count -eq 0) 'Exclusion became runtime evidence'
}
Case 'strict execution cannot consume an approved target exclusion' {
    $fixture = New-ExcludedOmissionFixture; $fixture.TargetPolicy = 'strict-upstream'
    Assert-AcceptanceRejected $fixture 'Strict original-suite protocol accepted an exclusion'
}
Case 'instrumented T absence cannot be waived by an exclusion' {
    $fixture = New-ExcludedOmissionFixture; $fixture.Configuration = 'upstream-test'
    Assert-AcceptanceRejected $fixture 'Instrumented T omission accepted'
}
Case 'non-T omissions cannot consume the T-private exclusion policy' {
    $fixture = New-ExcludedOmissionFixture
    $fixture.Outcome.skip_messages = @('skipping an ordinary test')
    $fixture.Contract.expected_skips[0].message = $fixture.Outcome.skip_messages[0]
    Assert-AcceptanceRejected $fixture 'Ordinary behavior was excluded through a T policy'
}
Case 'public and mixed omissions still require real execution' {
    foreach ($field in @('public_api','mixed_obligation','module_observable')) {
        $fixture = New-ExcludedOmissionFixture
        $fixture.ResolvedExclusions.Values | ForEach-Object { $_[$field] = $true }
        Assert-AcceptanceRejected $fixture "Target omission waived $field"
    }
}
Case 'target context mismatch blocks every operation before a compiler or Lua process' {
    # This launches only the PowerShell producer. A context that names another
    # host must stop before interpreter lookup or a fixture build, regardless
    # of whether the real coverage ledger is pending or complete.
    foreach ($mode in @('File','Aggregate','Heavy')) {
        $reportPath = Join-Path $temporary "target-$mode.json"
        $arguments = @('-NoProfile','-File',(Join-Path $PSScriptRoot 'run-conformance.ps1'),
            '-Target','Ada','-TargetPolicy','remaining-upstream-compatibility','-RequireTargetAcceptance',
            '-Mode',$mode,'-Context','default/unsupported/validation/static','-Report',$reportPath)
        if ($mode -ceq 'File') { $arguments += @('-File','api.lua') }
        $process = Invoke-ConformanceProcess -Executable $shell -Arguments $arguments -Directory $root `
            -OutputPrefix (Join-Path $temporary "target-$mode-capture") -TimeoutSeconds 60
        Assert-True ($process.exit_code -ne 0 -and -not $process.timed_out) 'Incomplete target accepted'
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-True ($report.setup_error -ceq 'Full-target context does not identify this configuration and host' -and
            $null -eq $report.process -and @($report.build_processes).Count -eq 0 -and
            -not $report.target_operation_acceptance -and -not $report.gate_acceptance -and
            $report.variant -ceq 'primary' -and $report.target_policy -ceq 'remaining-upstream-compatibility') `
            'Producer bypassed its incomplete-coverage gate or performed a build'
        if ($mode -ceq 'Heavy') {
            Assert-True ($report.allocator_limit_bytes -eq 67108864 -and $report.timeout_seconds -eq 600) 'Heavy policy drift'
        } elseif ($mode -ceq 'Aggregate') {
            Assert-True ($report.allocator_limit_bytes -eq 2147483648 -and $report.timeout_seconds -eq 3600) 'Aggregate policy drift'
        }
    }
}
Case 'full-target native fixture compiler omissions and frozen hash drift reject before Lua' {
    $platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
    foreach($selection in @(@(),@('-FixtureCompiler',$shell,'-FixtureCompilerSha256',('0'*64)))) {
        $reportPath=Join-Path $temporary ('target-native-compiler-'+[Guid]::NewGuid().ToString('N')+'.json')
        $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'run-conformance.ps1'),'-Target','ReferenceC',
            '-TargetPolicy','remaining-upstream-compatibility','-Mode','File','-File','attrib.lua',
            '-Context',('default/'+$platform+'/validation/static'),'-Report',$reportPath,'-Interpreter','unused')+@($selection)
        $process=Invoke-ConformanceProcess -Executable $shell -Arguments $arguments -Directory $root `
            -OutputPrefix (Join-Path $temporary ('native-compiler-'+[Guid]::NewGuid().ToString('N'))) -TimeoutSeconds 60
        $report=Get-Content $reportPath -Raw|ConvertFrom-Json -AsHashtable
        Assert-True ($process.exit_code -ne 0 -and $report.setup_error -match 'fixture.*compiler|frozen FixtureCompiler' -and
            $null -eq $report.configuration_process -and $null -eq $report.process -and $report.build_processes.Count -eq 0) 'Missing/stale compiler entered a Lua or build process'
    }
}
Case 'full-target smoke and mixed acceptance flags reject before setup' {
    foreach ($arguments in @(
        @('-TargetPolicy','remaining-upstream-compatibility','-Mode','Smoke'),
        @('-TargetPolicy','remaining-upstream-compatibility','-Scope','expanded-t-conformance','-Mode','File','-File','api.lua'),
        @('-RequireTargetAcceptance','-Target','Ada','-Mode','File','-File','api.lua'),
        @('-AggregateManifest','unreviewed.json','-Mode','Aggregate'),
        @('-AggregateManifest','unreviewed.json','-TargetPolicy','remaining-upstream-compatibility','-Mode','File','-File','code.lua'),
        @('-AggregateManifest','unreviewed.json','-TargetPolicy','remaining-upstream-compatibility','-Mode','Aggregate','-TAdaptationManifest','unreviewed-t.json'),
        @('-Variant','native-original','-Target','Ada','-TargetPolicy','remaining-upstream-compatibility','-Mode','File','-File','attrib.lua','-ReportOnly'),
        @('-Variant','native-original','-Target','ReferenceC','-TargetPolicy','remaining-upstream-compatibility','-Mode','File','-File','attrib.lua'),
        @('-Variant','native-original','-Target','ReferenceC','-TargetPolicy','remaining-upstream-compatibility','-Mode','File','-File','attrib.lua','-ReportOnly','-EquivalentManifest','unreviewed.json')
    )) {
        $process = Invoke-ConformanceProcess -Executable $shell `
            -Arguments (@('-NoProfile','-File',(Join-Path $PSScriptRoot 'run-conformance.ps1')) + $arguments) `
            -Directory $root -OutputPrefix (Join-Path $temporary ('bad-target-' + [Guid]::NewGuid().ToString('N'))) -TimeoutSeconds 20
        Assert-True ($process.exit_code -ne 0 -and $process.stderr_bytes -gt 0) 'Invalid target flags entered execution'
    }
}
Case 'exact binary stdin and bounded simultaneous pipe transport' {
    & (Join-Path $PSScriptRoot 'test-conformance-stdin.ps1')
}
Write-Output "RUNNER TESTS: $script:cases cases; $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
if ($ReferenceInterpreter -ne '') {
    & (Join-Path $PSScriptRoot 'test-target-file-protocols.ps1') -ReferenceInterpreter $ReferenceInterpreter
    if ($LASTEXITCODE -ne 0) { throw 'Target file wrapper execution regressions failed' }
}
exit 0
