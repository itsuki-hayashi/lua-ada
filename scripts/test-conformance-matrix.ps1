param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceMatrix.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
$root = Split-Path -Parent $PSScriptRoot
$suite = Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw | ConvertFrom-Json -AsHashtable
$temporary = Join-Path $root ('reports/matrix-selftest/' + [Guid]::NewGuid().ToString('N'))
$bundle = Join-Path $temporary 'bundle'
$captureDirectory = Join-Path $bundle 'reports/synthetic'
[void][IO.Directory]::CreateDirectory($captureDirectory)
$script:serial = 0
$script:cases = 0
$nativeWitness = "native branch facts: cint=4 lua_integer=8`nnative branch facts: time_2pow40=representable`nnative branch facts: year4000=representable`nnative branch facts: isdst=boolean`nnative C-int field boundary counterpart OK`nnative time range recovery counterpart OK`nnative DST inference counterpart OK`n"
$nativeSource = 'tests/conformance/platform/files-native-branches.lua'
$nativeCopy = Join-Path $captureDirectory 'equivalent-files-native-branches.lua'
Copy-Item -LiteralPath (Join-Path $root $nativeSource) -Destination $nativeCopy
$nativeHash = (Get-FileHash $nativeCopy).Hash.ToLowerInvariant()
$nativeMappingPath = 'tests/conformance/reviews/files-native-branches.proposal.json'
$nativeReviewPath = 'tests/conformance/reviews/files-native-branches.gc-cross-review.json'
$nativeReview = @{mapping=$nativeMappingPath; review=$nativeReviewPath;
    mapping_sha256=(Get-FileHash (Join-Path $root $nativeMappingPath)).Hash.ToLowerInvariant();
    review_sha256=(Get-FileHash (Join-Path $root $nativeReviewPath)).Hash.ToLowerInvariant()}
function Write-Json([string] $Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32) + "`n")
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function New-Process([string] $Text, [int] $PidValue, [int] $Timeout = 30) {
    $script:serial++
    $prefix = Join-Path $captureDirectory "process-$script:serial"
    [IO.File]::WriteAllText("$prefix.stdout", $Text)
    [IO.File]::WriteAllText("$prefix.stderr", '')
    return @{process_id=$PidValue; exit_code=0; timed_out=$false; capture_exceeded=$false;
        pipe_drain_failed=$false; process_tree_kill_error=$null; timeout_seconds=$Timeout;
        executable_sha256=('1'*64); stdout_path="$prefix.stdout"; stderr_path="$prefix.stderr";
        stdout_sha256=(Get-FileHash "$prefix.stdout").Hash.ToLowerInvariant();
        stderr_sha256=(Get-FileHash "$prefix.stderr").Hash.ToLowerInvariant();
        stdout_bytes=(Get-Item "$prefix.stdout").Length; stderr_bytes=0}
}
function New-Telemetry([string] $RunId, [string] $Configuration, [int] $PidValue) {
    $script:serial++
    $path = Join-Path $captureDirectory "telemetry-$script:serial.$PidValue.json"
    $data = @{schema_version=1; run_id=$RunId; configuration=$Configuration; process_id=$PidValue;
        allocator_limit_bytes=2147483648L; managed_refusals=1; outstanding_bytes=0; outstanding_blocks=0;
        shutdown_complete=$true; accounting_fault=$false}
    $hash = Write-Json $path $data
    return @{path=$path; sha256=$hash; data=$data}
}
# These are deliberately synthetic reports, used only to exercise artifact
# validation. They never claim actual Lua execution or scoped acceptance.
$manifest = @{schema_version=1; scope='gc-io-events'; revision=('a'*40); operations=@(); review=$null}
foreach ($context in $suite.acceptance_contexts) {
    foreach ($file in @('events.lua','gc.lua','gengc.lua','files.lua')) {
        $entry = @{file=$file; context=$context}
        foreach ($target in @('c','ada')) {
            $configuration = $context.Split('/')[0]
            $instrumented = $configuration -eq 'upstream-test'
            $identity = if ($target -eq 'c') { 'C Lua' } else { 'Lua Ada' }
            $settings = @{schema_version=1; configuration=$configuration; implementation=$identity;
                runtime_build_profile=$context.Split('/')[2]; launcher_build_profile=$context.Split('/')[2];
                launcher_library_type=$(if($context.Split('/')[3] -eq 'shared'){'relocatable'}else{$context.Split('/')[3]});
                lua_release='Lua 5.5.1'; integer_bytes=8; number_bytes=8; pointer_bytes=[IntPtr]::Size;
                extra_space_bytes=[IntPtr]::Size; expected_extra_space_bytes=[IntPtr]::Size;
                allocator_limit_bytes=2147483648L; allocator_accounting='synthetic'; test_adapter=$instrumented;
                max_stack=$(if($instrumented){68000}else{1000000}); max_c_calls=$(if($instrumented){180}else{200});
                aux_buffer_bytes=$(if($instrumented){23}else{1024}); compat_global=$(if($instrumented){0}else{1});
                rand32=$instrumented; compat_math=$instrumented}
            $text = ($settings | ConvertTo-Json -Compress) + "`n"
            $output = switch ($file) {
                'gc.lua' { "OK`n>>> closing state <<<`n" }
                'gengc.lua' { "testing stop-the-world collection`nOK`n" }
                'files.lua' { "native unbuffered visibility counterpart OK`ntesting i/o`ntesting flush`ntesting large files (> BUFSIZ)`ntesting popen/pclose and execute`ntesting date/time`ntesting failed write`ntest done on 01/01/2026, at 00:00:00`nLua 5.5`n" }
                default { "OK`n" }
            }
            $runId = "$context/$file/$target"
            $report = @{repository_revision=$manifest.revision; repository_dirty=$false;
                host=@{platform=$context.Split('/')[1]};
                reference_revision=$suite.reference_revision; target=$(if($target -eq 'c'){'ReferenceC'}else{'Ada'});
                coverage_scope=$manifest.scope; operation="file:$file"; acceptance_context=$context;
                requested_configuration=$configuration; allocator_limit_bytes=2147483648L; timeout_seconds=900;
                status='passed'; setup_error=$null; acceptance_error=$null; gate_acceptance=$false; fixture_changes=@();
                configuration_verified=$true; reference_tree_verified=$true;
                fixture_records=@($suite.files | Where-Object {$_.path -ceq $file}); launcher_identity=@{sha256=('1'*64)};
                runtime_library_records=@(@{sha256=('2'*64)}); reference_library_records=@(@{sha256=('2'*64)});
                configuration_process=(New-Process $text 100); child_configuration_process=(New-Process $text 101);
                arg_child_configuration_process=(New-Process $text 102); process=(New-Process $output 103 900);
                launcher_probe_run_id="$runId/probes"; launcher_probe_telemetry=@();
                run_id=$runId; allocator_telemetry=(New-Telemetry $runId $configuration 103);
                child_allocator_telemetry=@(); execution_disposition='unchanged'; scoped_operation_acceptance=$false}
            $probePids = if ($target -eq 'ada') { @(100,101,102,104,105) } else { @(101,102) }
            foreach ($probePid in $probePids) {
                $report.launcher_probe_telemetry += New-Telemetry "$runId/probes" $configuration $probePid
            }
            if ($file -eq 'files.lua') {
                $report.process = New-Process ($nativeWitness + $output) 103 900
                $report.native_branch_facts = Get-ScopedNativeBranchFacts -Output $nativeWitness
                $report.native_branch_review = $nativeReview
                $report.native_fixture_records = @(@{source=$nativeSource; source_sha256=$nativeHash;
                    artifact=$nativeCopy; artifact_sha256=$nativeHash; disposition='native-platform-equivalent'})
                $windows = $context.Split('/')[1] -eq 'windows'
                $count = if($windows){4}else{2}
                if(-not $windows -and $instrumented){$count++}
                if($target -eq 'ada'){$count+=4}
                for($i=0;$i -lt $count;$i++){
                    $report.child_allocator_telemetry += New-Telemetry $runId $configuration (200+$i)
                }
            }
            $script:serial++
            $name = "report-$script:serial.json"
            $entry[$target] = @{report=$name; artifact_root='bundle'; sha256=(Write-Json (Join-Path $temporary $name) $report)}
        }
        $manifest.operations += $entry
    }
}
$manifestPath = Join-Path $temporary 'matrix.json'
$null = Write-Json $manifestPath $manifest
$original = [IO.File]::ReadAllText($manifestPath)
function Reject([string] $Name, [scriptblock] $Mutate, [string] $Expected, [switch] $Full) {
    $m = $original | ConvertFrom-Json -AsHashtable -Depth 64
    & $Mutate $m
    $null = Write-Json $manifestPath $m
    $failure = $null
    try {
        if ($Full) { Test-ScopedMatrix -Root $root -ManifestPath $manifestPath | Out-Null }
        else { Assert-ScopedMatrixIndex -Manifest $m -Contexts $suite.acceptance_contexts }
    } catch { $failure=$_.Exception.Message }
    if ($null -eq $failure -or $failure -notmatch $Expected) { throw "Matrix negative failed ($Name): $failure" }
    $script:cases++
    Write-Output "MATRIX TEST PASS: $Name"
}
$baseline = Test-ScopedMatrix -Root $root -ManifestPath $manifestPath
if ($baseline.operations -ne 104 -or $baseline.contexts -ne 26 -or
    $baseline.executions.Count -ne 208 -or $baseline.scoped_acceptance -or $baseline.full_m3_acceptance) {
    throw 'Synthetic matrix incorrectly reports acceptance or coverage count'
}
$script:cases++
Write-Output 'MATRIX TEST PASS: all 104 synthetic pairs validate without acceptance authority'
Reject 'missing instrumented context' {param($m) $m.operations=@($m.operations | Where-Object {$_.context -ne 'upstream-test/linux/validation/static'})} 'Incomplete scoped matrix'
Reject 'duplicate operation' {param($m) $m.operations += $m.operations[0]} 'Duplicate scoped matrix'
Reject 'unknown file' {param($m) $m.operations[0].file='all.lua'} 'Unknown scoped matrix'
Reject 'missing C baseline' {param($m) $m.operations[0].c=$null} 'Missing matrix c'
Reject 'invalid report hash' {param($m) $m.operations[0].ada.sha256='not-a-hash'} 'Missing matrix ada'
Reject 'changed report bytes' {param($m) $m.operations[0].c.sha256='0'*64} 'artifact hash mismatch' -Full
$first = $manifest.operations[0].c
$reportPath = Join-Path $temporary $first.report
$savedReport = [IO.File]::ReadAllText($reportPath)
foreach ($case in @(
    @{Name='dirty execution'; Field='repository_dirty'; Value=$true; Expected='identity, policy'},
    @{Name='wrong revision'; Field='repository_revision'; Value=('b'*40); Expected='identity, policy'},
    @{Name='wrong host'; Field='host'; Value=@{platform='unknown'}; Expected='identity, policy'},
    @{Name='unknown disposition'; Field='execution_disposition'; Value='skipped'; Expected='identity, policy'},
    @{Name='wrong implementation'; Field='target'; Value='Ada'; Expected='identity, policy'})) {
    $r = $savedReport | ConvertFrom-Json -AsHashtable -Depth 64
    $r[$case.Field]=$case.Value
    $hash=Write-Json $reportPath $r
    Reject $case.Name {param($m) $m.operations[0].c.sha256=$hash} $case.Expected -Full
}
[IO.File]::WriteAllText($reportPath,$savedReport)
# These mutations preserve report hashing but alter the actual probe state
# records, demonstrating that matching configuration output cannot hide a
# missing, duplicated, wrong-run or leaked probe lifetime.
foreach ($case in @(
    @{Name='missing probe telemetry'; Mutate={param($r) $r.launcher_probe_telemetry=@()}; Expected='probe telemetry missing'},
    @{Name='duplicate probe telemetry'; Mutate={param($r) $r.launcher_probe_telemetry[1]=$r.launcher_probe_telemetry[0]}; Expected='duplicates a process'},
    @{Name='shared main and probe run'; Mutate={param($r) $r.launcher_probe_run_id=$r.run_id}; Expected='separate run identity'},
    @{Name='wrong probe run'; Mutate={param($r) $r.launcher_probe_run_id='wrong'}; Expected='Mismatched or unbalanced'},
    @{Name='probe PID not owned by recorded parent'; Mutate={param($r) $r.child_configuration_process.process_id=999}; Expected='probe telemetry missing parent'},
    @{Name='changed probe capture hash'; Mutate={param($r) $r.launcher_probe_telemetry[0].sha256='0'*64}; Expected='capture hash mismatch'})) {
    $r=$savedReport | ConvertFrom-Json -AsHashtable -Depth 64
    & $case.Mutate $r
    $hash=Write-Json $reportPath $r
    Reject $case.Name {param($m) $m.operations[0].c.sha256=$hash} $case.Expected -Full
}
[IO.File]::WriteAllText($reportPath,$savedReport)
$r=$savedReport | ConvertFrom-Json -AsHashtable -Depth 64
$probePath=$r.launcher_probe_telemetry[0].path
$savedProbe=[IO.File]::ReadAllText($probePath)
$probeData=$savedProbe | ConvertFrom-Json -AsHashtable
$probeData.outstanding_blocks=1
$r.launcher_probe_telemetry[0].sha256=Write-Json $probePath $probeData
$hash=Write-Json $reportPath $r
Reject 'leaked probe allocation' {param($m) $m.operations[0].c.sha256=$hash} 'Mismatched or unbalanced' -Full
[IO.File]::WriteAllText($probePath,$savedProbe)
[IO.File]::WriteAllText($reportPath,$savedReport)
$adaReportPath=Join-Path $temporary $manifest.operations[0].ada.report
$savedAdaReport=[IO.File]::ReadAllText($adaReportPath)
$adaReport=$savedAdaReport | ConvertFrom-Json -AsHashtable -Depth 64
$adaProbePath=$adaReport.launcher_probe_telemetry[0].path
$savedAdaProbe=[IO.File]::ReadAllText($adaProbePath)
$adaProbe=$savedAdaProbe | ConvertFrom-Json -AsHashtable
$adaProbe.shutdown_complete=$false
$adaReport.launcher_probe_telemetry[0].sha256=Write-Json $adaProbePath $adaProbe
$hash=Write-Json $adaReportPath $adaReport
Reject 'Ada probe lacks physical shutdown' {param($m) $m.operations[0].ada.sha256=$hash} 'Missing shutdown' -Full
[IO.File]::WriteAllText($adaProbePath,$savedAdaProbe)
[IO.File]::WriteAllText($adaReportPath,$savedAdaReport)
$fileEntry = @($manifest.operations | Where-Object { $_.file -eq 'files.lua' })[0]
$filePath = Join-Path $temporary $fileEntry.ada.report
$savedFile = [IO.File]::ReadAllText($filePath)
foreach ($case in @('facts','identity','divergence')) {
    $r = $savedFile | ConvertFrom-Json -AsHashtable -Depth 64
    $savedOutput = [IO.File]::ReadAllText($r.process.stdout_path)
    $expected = switch ($case) {
        'facts' { $r.native_branch_facts.year='year4000=representation'; 'facts differ from capture' }
        'identity' { $r.native_fixture_records[0].source_sha256='0'*64; 'counterpart identity differs' }
        'divergence' {
            $changed = $savedOutput.Replace('year4000=representable','year4000=representation')
            [IO.File]::WriteAllText($r.process.stdout_path,$changed)
            $r.process.stdout_sha256=(Get-FileHash $r.process.stdout_path).Hash.ToLowerInvariant()
            $r.process.stdout_bytes=(Get-Item $r.process.stdout_path).Length
            $r.native_branch_facts.year='year4000=representation'
            'C/Ada native branch facts differ'
        }
    }
    $hash = Write-Json $filePath $r
    Reject "native branch $case" {param($m)
        $entry = @($m.operations | Where-Object { $_.file -eq 'files.lua' })[0]
        $entry.ada.sha256=$hash
    } $expected -Full
    [IO.File]::WriteAllText($r.process.stdout_path,$savedOutput)
    [IO.File]::WriteAllText($filePath,$savedFile)
}
$r=$savedReport | ConvertFrom-Json -AsHashtable -Depth 64
[IO.File]::AppendAllText($r.process.stdout_path,'tamper')
Reject 'changed captured output' {param($m)} 'capture hash mismatch' -Full
[IO.File]::WriteAllText($manifestPath,$original)
$failure=$null
try { Test-ScopedMatrix -Root $root -ManifestPath $manifestPath -RequireScopedAcceptance | Out-Null }
catch { $failure=$_.Exception.Message }
if ($failure -notmatch 'independent review|Unresolved coverage') { throw "Pending ledger did not prevent acceptance: $failure" }
$script:cases++
Write-Output 'MATRIX TEST PASS: unresolved real ledger blocks synthetic acceptance'
foreach ($field in @('runtime_build_profile','launcher_build_profile','launcher_library_type')) {
    $identity = @{runtime_build_profile='validation'; launcher_build_profile='validation'; launcher_library_type='static'}
    Assert-ScopedBuildIdentity -Observed $identity -Context 'default/windows/validation/static'
    $identity[$field] = 'wrong'
    $failure = $null
    try { Assert-ScopedBuildIdentity -Observed $identity -Context 'default/windows/validation/static' }
    catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'measured runtime/launcher build identity') { throw "Build identity negative failed: $field" }
    $script:cases++
    Write-Output "MATRIX TEST PASS: rejects mislabeled $field"
}
# Exercise the production review validator independently of the unresolved
# real ledger. These names are synthetic shape fixtures, never review evidence.
# This catches vocabulary drift between the generator and matrix verifier.
$module = Get-Module ConformanceMatrix
$review = @{status='accepted'; author='fixture-author'; reviewer='fixture-reviewer'; artifact='synthetic-only'}
& $module { param($r) Assert-MatrixReview -Review $r } $review
$script:cases++
Write-Output 'MATRIX TEST PASS: accepted review vocabulary agrees with equivalent generator'
foreach ($case in @(
    @{Name='pending review'; Field='status'; Value='pending'},
    @{Name='unknown review status'; Field='status'; Value='reviewed'},
    @{Name='self review'; Field='reviewer'; Value='fixture-author'},
    @{Name='absent review artifact'; Field='artifact'; Value=''})) {
    $changed = $review.Clone()
    $changed[$case.Field] = $case.Value
    $failure = $null
    try { & $module { param($r) Assert-MatrixReview -Review $r } $changed }
    catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'completed independent review') { throw "Review negative failed: $($case.Name)" }
    $script:cases++
    Write-Output "MATRIX TEST PASS: rejects $($case.Name)"
}
Write-Output "PASS: $script:cases matrix regressions; no executed conformance claim"
# Approval-file binding is tested separately from synthetic execution reports.
# Both default CI and instrumented campaigns call this retained entrypoint.
& (Join-Path $PSScriptRoot 'test-conformance-review.ps1')
& (Join-Path $PSScriptRoot 'test-consumer-evidence.ps1')
& (Join-Path $PSScriptRoot 'test-aunit-evidence.ps1')
