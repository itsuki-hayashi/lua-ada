param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTargetMatrix.psm1') -Force
$suite = Get-Content -LiteralPath (Join-Path $root 'tests/conformance/suite.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 32
$temporary = Join-Path $root ('reports/target-matrix-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Cases = 0
$script:Serial = 0
$policyHash = (Get-FileHash (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json')).Hash.ToLowerInvariant()

# All processes, runtime identities and review labels below are synthetic
# validator fixtures. No Lua/C process runs; none can grant target acceptance.
function Case([string] $Name, [scriptblock] $Action) {
    & $Action
    $script:Cases++
    Write-Output "TARGET MATRIX TEST PASS: $Name"
}
function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Reject([scriptblock] $Action, [string] $Expected) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong target matrix failure: $failure; expected $Expected"
}
function Write-Json([string] $Path, [object] $Value) {
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 48).Replace("`r`n","`n") + "`n", $utf8)
    return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Clone([object] $Value) {
    return ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 48) -AsHashtable -Depth 48
}
function New-Entry([string] $Operation, [string] $Context, [string] $Variant = '') {
    $entry = @{operation=$Operation;context=$Context;comparison='exact';
        c=@{report='c.json';artifact_root='bundle';sha256=('1'*64)};
        ada=@{report='ada.json';artifact_root='bundle';sha256=('2'*64)};
        contract=@{path='contract.json';sha256=('3'*64)}}
    if ($Variant -ne '') { $entry.variant = $Variant }
    return $entry
}
function New-Manifest {
    $manifest = @{schema_version=1;kind='full-target-matrix';target='remaining-upstream-compatibility';
        reference_revision=$suite.reference_revision;revision=('a'*40);synthetic_fixture=$true;
        operations=@();supplemental=@();review=$null;
        exclusion_policy=@{path='tests/conformance/targets/remaining-upstream-compatibility.exclusions.json';sha256=$policyHash};
        retained_evidence=$null}
    foreach ($context in $suite.acceptance_contexts) {
        foreach ($source in ($suite.files | Where-Object role -CEQ primary)) {
            $manifest.operations += New-Entry ('file:' + $source.path) $context
        }
        foreach ($operation in @('aggregate','heavy')) { $manifest.operations += New-Entry $operation $context }
        $manifest.supplemental += New-Entry file:constructs.lua $context constructs-branch-1
    }
    return $manifest
}
function New-Process([string] $Directory, [string] $Text, [int] $PidValue, [int] $Timeout) {
    $script:Serial++
    $prefix = Join-Path $Directory "process-$script:Serial"
    [IO.File]::WriteAllText("$prefix.stdout",$Text,$utf8)
    [IO.File]::WriteAllText("$prefix.stderr",'',$utf8)
    return @{process_id=$PidValue;exit_code=0;timed_out=$false;capture_exceeded=$false;
        pipe_drain_failed=$false;process_tree_kill_error=$null;abnormal_exit_kind=$null;
        timeout_seconds=$Timeout;executable_sha256=('1'*64);stdout_path="$prefix.stdout";stderr_path="$prefix.stderr";
        stdout_sha256=(Get-FileHash "$prefix.stdout").Hash.ToLowerInvariant();
        stderr_sha256=(Get-FileHash "$prefix.stderr").Hash.ToLowerInvariant();
        stdout_bytes=(Get-Item "$prefix.stdout").Length;stderr_bytes=0}
}
function New-Telemetry([string] $Directory, [string] $RunId, [string] $Configuration,
    [int] $PidValue, [long] $LimitBytes, [int] $Refusals = 0) {
    $script:Serial++
    $path = Join-Path $Directory "telemetry-$script:Serial.$PidValue.json"
    $data = @{schema_version=1;run_id=$RunId;configuration=$Configuration;process_id=$PidValue;
        allocator_limit_bytes=$LimitBytes;managed_refusals=$Refusals;outstanding_bytes=0;outstanding_blocks=0;
        shutdown_complete=$true;accounting_fault=$false}
    return @{path=$path;sha256=(Write-Json $path $data)}
}
function New-ReportFixture([string] $Operation = 'file:api.lua', [string] $Target = 'Ada',
    [string] $Context = 'upstream-test/windows/validation/static', [string] $Variant = '') {
    $directory = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    $captures = Join-Path $directory 'bundle/reports/captures'
    [void][IO.Directory]::CreateDirectory($captures)
    $parts = $Context.Split('/')
    $instrumented = $parts[0] -ceq 'upstream-test'
    $limit = if ($Operation -ceq 'heavy') { 67108864L } else { 2147483648L }
    $timeout = if ($Operation -ceq 'heavy') { 600 } elseif ($Operation -ceq 'aggregate') { 3600 } else { 900 }
    $settings = @{schema_version=1;configuration=$parts[0];implementation=$(if($Target -ceq 'Ada'){'Lua Ada'}else{'C Lua'});
        lua_release='Lua 5.5.1';integer_bytes=8;number_bytes=8;pointer_bytes=[IntPtr]::Size;
        extra_space_bytes=[IntPtr]::Size;expected_extra_space_bytes=[IntPtr]::Size;
        allocator_limit_bytes=$limit;allocator_accounting='synthetic-only';test_adapter=$instrumented;
        max_stack=$(if($instrumented){68000}else{1000000});max_c_calls=$(if($instrumented){180}else{200});
        aux_buffer_bytes=$(if($instrumented){23}else{1024});compat_global=$(if($instrumented){0}else{1});
        rand32=$instrumented;compat_math=$instrumented;runtime_build_profile=$parts[2];launcher_build_profile=$parts[2];
        launcher_library_type=$(if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]})}
    $text = (ConvertTo-Json -InputObject $settings -Compress) + "`n"
    $output = if ($Operation -ceq 'heavy') { "expected error: not enough memory`nOK`n" }
        elseif ($Operation -ceq 'aggregate') { "final OK !!!`n" }
        elseif ($Operation -ceq 'file:constructs.lua') {
            'testing short-circuit optimizations (' + $(if($Variant -ceq 'constructs-branch-1'){1}else{0}) + ")`nOK`n"
        } else { "OK`n" }
    $runId = [Guid]::NewGuid().ToString('N'); $probeRun = [Guid]::NewGuid().ToString('N')
    $report = @{repository_revision=('a'*40);repository_dirty=$false;repository_status=@();synthetic_fixture=$true;
        target_policy='remaining-upstream-compatibility';coverage_scope='';reference_revision=$suite.reference_revision;
        target=$Target;operation=$Operation;acceptance_context=$Context;requested_configuration=$parts[0];host=@{platform=$parts[1]};
        variant=$(if($Variant -ne ''){$Variant}else{'primary'});allocator_limit_bytes=$limit;timeout_seconds=$timeout;
        configuration_verified=$true;reference_tree_verified=$true;setup_error=$null;acceptance_error=$null;
        fixture_changes=@();status='passed';execution_disposition='unchanged';gate_acceptance=$false;scoped_operation_acceptance=$false;
        fixture_records=@($suite.files);launcher_identity=@{sha256=('1'*64)};
        runtime_library_records=@(@{path='C:/build/liblua.dll';sha256=('2'*64)});
        reference_library_records=@(@{path='C:/build/libconformance_lua.dll';sha256=('3'*64)});
        observed_configuration=$settings;configuration_process=(New-Process $captures $text 100 30);
        child_configuration_process=(New-Process $captures $text 101 30);
        arg_child_configuration_process=(New-Process $captures $text 102 30);
        process=(New-Process $captures $output 103 $timeout);launcher_probe_run_id=$probeRun;launcher_probe_telemetry=@();
        run_id=$runId;allocator_telemetry=(New-Telemetry $captures $runId $parts[0] 103 $limit $(if($Operation -ceq 'heavy'){1}else{0}));
        excluded_obligations=@();exclusion_policy_sha256=$policyHash}
    if ($Operation -ceq 'file:constructs.lua') { $report.constructs_branch = if ($Variant -ceq 'constructs-branch-1') { 1 } else { 0 } }
    $probePids = if ($Target -ceq 'Ada') { @(100,101,102,104,105) } else { @(101,102) }
    foreach ($pidValue in $probePids) { $report.launcher_probe_telemetry += New-Telemetry $captures $probeRun $parts[0] $pidValue $limit }
    return @{report=$report;entry=(New-Entry $Operation $Context $Variant);target=$Target;
        artifact_root=(Join-Path $directory 'bundle');exclusions=@()}
}
function Invoke-Report([Collections.IDictionary] $Fixture) {
    Test-TargetMatrixReport -Report $Fixture.report -Entry $Fixture.entry -Suite $suite -Revision ('a'*40) `
        -ArtifactRoot $Fixture.artifact_root -Target $Fixture.target -ExclusionPolicySha256 $policyHash -Exclusions $Fixture.exclusions
}

Case 'complete index includes 832 required pairs and 26 required supplements' {
    $m = New-Manifest
    Assert-TargetMatrixIndex $m $suite
    Assert-True ($m.operations.Count -eq 832 -and $m.supplemental.Count -eq 26) 'Wrong full-target operation count'
}
foreach ($missing in @('file:api.lua','aggregate','heavy')) {
    Case "missing $missing operation cannot be replaced by other passing files" {
        $m = New-Manifest; $context = $suite.acceptance_contexts[-1]
        $m.operations = @($m.operations | Where-Object { $_.context -cne $context -or $_.operation -cne $missing })
        Reject { Assert-TargetMatrixIndex $m $suite } 'Incomplete full-target matrix'
    }
}
Case 'instrumented context cannot be omitted' {
    $m = New-Manifest
    $m.operations = @($m.operations | Where-Object context -CNE 'upstream-test/linux/validation/shared')
    Reject { Assert-TargetMatrixIndex $m $suite } 'Incomplete full-target matrix'
}
Case 'duplicate operations and missing C reports fail' {
    $m = New-Manifest; $m.operations += $m.operations[0]
    Reject { Assert-TargetMatrixIndex $m $suite } 'Duplicate full-target'
    $m = New-Manifest; $m.operations[0].c = $null
    Reject { Assert-TargetMatrixIndex $m $suite } 'Missing full-target c'
}
Case 'helper files cannot be substituted for scheduled primaries' {
    $m = New-Manifest; $m.operations[0].operation = 'file:tracegc.lua'
    Reject { Assert-TargetMatrixIndex $m $suite } 'Unknown full-target operation'
}
Case 'all required constructs templates must be present' {
    $m = New-Manifest; $m.supplemental = @($m.supplemental | Select-Object -Skip 1)
    Reject { Assert-TargetMatrixIndex $m $suite } 'Missing required constructs supplement'
}
Case 'supplements cannot replace primary operations or duplicate one another' {
    $m = New-Manifest; $m.supplemental[0].variant = 'primary'
    Reject { Assert-TargetMatrixIndex $m $suite } 'Unknown full-target'
    $m = New-Manifest; $m.supplemental += $m.supplemental[0]
    Reject { Assert-TargetMatrixIndex $m $suite } 'Duplicate full-target'
}
Case 'unknown comparison and unsigned contract are rejected' {
    $m = New-Manifest; $m.operations[0].comparison = 'ignore-output'
    Reject { Assert-TargetMatrixIndex $m $suite } 'Unknown full-target comparison'
    $m = New-Manifest; $m.operations[0].contract.sha256 = 'not-a-hash'
    Reject { Assert-TargetMatrixIndex $m $suite } 'execution contract identity'
}
Case 'synthetic Ada and C report replay grants no acceptance' {
    foreach ($target in @('Ada','ReferenceC')) {
        $f = New-ReportFixture -Target $target
        $result = Invoke-Report $f
        Assert-True ($result.report.synthetic_fixture -and -not $result.Contains('target_acceptance')) 'Synthetic fixture gained authority'
    }
}
Case 'aggregate and heavy replay apply their distinct resource policies' {
    foreach ($operation in @('aggregate','heavy')) { Invoke-Report (New-ReportFixture -Operation $operation) | Out-Null }
}
Case 'constructs supplemental branch comes from actual captured witness' {
    $f = New-ReportFixture -Operation file:constructs.lua -Variant constructs-branch-1
    Invoke-Report $f | Out-Null
    $f.report.constructs_branch = 0
    Reject { Invoke-Report $f } 'supplemental branch witness differs'
    $f.report.constructs_branch = 1
    $path = $f.report.process.stdout_path
    [IO.File]::WriteAllText($path,[IO.File]::ReadAllText($path).Replace('(1)','(0)'),$utf8)
    $f.report.process.stdout_sha256 = (Get-FileHash $path).Hash.ToLowerInvariant()
    Reject { Invoke-Report $f } 'supplemental branch witness differs'
}
foreach ($change in @(
    @{name='dirty report';field='repository_dirty';value=$true},
    @{name='wrong revision';field='repository_revision';value=('b'*40)},
    @{name='scoped report in full matrix';field='coverage_scope';value='expanded-t-conformance'},
    @{name='wrong target policy';field='target_policy';value='strict-upstream'},
    @{name='wrong configuration';field='requested_configuration';value='default'},
    @{name='whole M3 flag cannot be smuggled into target evidence';field='gate_acceptance';value=$true}
)) {
    Case $change.name {
        $f = New-ReportFixture; $f.report[$change.field] = $change.value
        Reject { Invoke-Report $f } 'revision, identity or policy differs'
    }
}
Case 'wrong source hash or executable identity fails' {
    $f = New-ReportFixture; $f.report.fixture_records = Clone $f.report.fixture_records
    $f.report.fixture_records[0].sha256 = '0'*64
    Reject { Invoke-Report $f } 'original source identity differs'
    $f = New-ReportFixture; $f.report.launcher_identity.sha256 = '0'*64
    Reject { Invoke-Report $f } 'executable identity differs'
}
Case 'missing and duplicate runtime libraries fail' {
    $f = New-ReportFixture; $f.report.runtime_library_records = @()
    Reject { Invoke-Report $f } 'library identity missing'
    $f = New-ReportFixture; $f.report.runtime_library_records += $f.report.runtime_library_records[0]
    Reject { Invoke-Report $f } 'library identities missing or duplicated'
}
Case 'changed actual output bytes cannot reuse old hashes' {
    $f = New-ReportFixture
    [IO.File]::AppendAllText($f.report.process.stdout_path,'tamper',$utf8)
    Reject { Invoke-Report $f } 'capture hash differs'
}
Case 'successful exit does not hide a timeout' {
    $f = New-ReportFixture; $f.report.process.timed_out = $true
    Reject { Invoke-Report $f } 'did not complete cleanly'
}
Case 'bare and arg-selected children must retain measured configuration' {
    $f = New-ReportFixture
    $changed = Clone $f.report.observed_configuration; $changed.compat_global = 1
    $text = (ConvertTo-Json -InputObject $changed -Compress) + "`n"
    $f.report.child_configuration_process = New-Process (Split-Path $f.report.process.stdout_path) $text 101 30
    Reject { Invoke-Report $f } 'child configuration differs'
}
Case 'probe telemetry cannot be missing or attributed to another run' {
    $f = New-ReportFixture; $f.report.launcher_probe_telemetry = @()
    Reject { Invoke-Report $f } 'probe telemetry missing'
    $f = New-ReportFixture; $f.report.launcher_probe_run_id = 'another-run'
    Reject { Invoke-Report $f } 'Mismatched or unbalanced'
}
Case 'main allocator evidence must belong to actual process and shut down' {
    $f = New-ReportFixture; $path = $f.report.allocator_telemetry.path
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    $data.process_id = 999; $f.report.allocator_telemetry.sha256 = Write-Json $path $data
    Reject { Invoke-Report $f } 'Mismatched or unbalanced'
    $f = New-ReportFixture; $path = $f.report.allocator_telemetry.path
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    $data.shutdown_complete = $false; $f.report.allocator_telemetry.sha256 = Write-Json $path $data
    Reject { Invoke-Report $f } 'Missing shutdown'
}
Case 'heavy refusal cannot be borrowed from child telemetry' {
    $f = New-ReportFixture -Operation heavy; $path = $f.report.allocator_telemetry.path
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    $data.managed_refusals = 0; $f.report.allocator_telemetry.sha256 = Write-Json $path $data
    Reject { Invoke-Report $f } 'own caught allocator refusal'
}
Case 'unapproved or silently missing exclusion IDs fail report replay' {
    $f = New-ReportFixture; $f.report.excluded_obligations = @('unapproved')
    Reject { Invoke-Report $f } 'excluded obligation set or policy hash differs'
    $f = New-ReportFixture; $f.exclusions = @(@{id='private-opcode';source='api.lua'})
    Reject { Invoke-Report $f } 'excluded obligation set or policy hash differs'
}
Case 'approved exclusions stay distinct from a process pass disposition' {
    $f = New-ReportFixture; $f.exclusions = @(@{id='private-opcode';source='api.lua'})
    $f.report.excluded_obligations = @('private-opcode'); $f.report.execution_disposition = 'reviewed-t-adapted'
    $observed = Invoke-Report $f
    Assert-True ($observed.excluded_obligations.Count -eq 1 -and
        $observed.report.execution_disposition -ceq 'reviewed-t-adapted') 'Exclusion lost its disposition'
    $f.report.execution_disposition = 'unchanged'
    Reject { Invoke-Report $f } 'adapted execution disposition differ'
}
Case 'source completion cannot bypass pending global API obligations' {
    $inventory = @{PendingApiEntries=1;RequiredPendingSourceAnchors=0;TargetComplete=$true}
    Reject { Assert-TargetMatrixCoverage $inventory -RequireComplete } 'global public API coverage remains unresolved'
    $inventory.PendingApiEntries = 0; $inventory.RequiredPendingSourceAnchors = 1
    Reject { Assert-TargetMatrixCoverage $inventory -RequireComplete } 'source coverage remains unresolved'
}
Case 'synthetic full matrix can never establish target acceptance' {
    $m = New-Manifest; $path = Join-Path $temporary 'synthetic-matrix.json'
    $null = Write-Json $path $m
    Reject { Test-FullTargetMatrix -Root $root -ManifestPath $path -RequireTargetAcceptance } 'Synthetic fixture matrix'
}
Case 'actual-target flag does not bypass unresolved real global API ledger' {
    $m = New-Manifest; $m.synthetic_fixture = $false
    $path = Join-Path $temporary 'pending-api-matrix.json'; $null = Write-Json $path $m
    Reject { Test-FullTargetMatrix -Root $root -ManifestPath $path -RequireTargetAcceptance } 'global public API coverage remains unresolved'
}
Case 'bundle contracts cannot escape the reviewed artifact directory' {
    $m = New-Manifest; $m.operations[0].contract.path = '../escape.json'
    $path = Join-Path $temporary 'escaping-matrix.json'; $null = Write-Json $path $m
    Reject { Test-FullTargetMatrix -Root $root -ManifestPath $path } 'bundle path escapes its root'
}
Case 'retained warnings require every context even without primary processes' {
    Import-Module (Join-Path $PSScriptRoot 'ConformanceMatrix.psm1')
    $retained = @{scope='expanded-t-conformance';warning_regressions=@()}
    Reject { Test-RetainedMatrixWitnesses -Root $root -Manifest $retained -Bundle $temporary -Suite $suite } 'Missing retained warning context'
}

# Exercise content-bound review independently from process observations. These
# fixture author/reviewer labels and decisions have no execution authority.
$reviewManifest = New-Manifest
$reviewManifest.retained_evidence = @{path='retained.json';sha256=('4'*64)}
$narrativePath = Join-Path $temporary 'matrix-narrative.json'
$narrativeHash = Write-Json $narrativePath @{target=$reviewManifest.target;revision=$reviewManifest.revision;
    reviewer='fixture-reviewer';decision='accepted'}
$approval = @{schema_version=1;kind='full-target-matrix-approval';target=$reviewManifest.target;
    revision=$reviewManifest.revision;reference_revision=$suite.reference_revision;
    author='fixture-author';reviewer='fixture-reviewer';decision='accepted';
    exclusion_policy=$reviewManifest.exclusion_policy;retained_evidence=$reviewManifest.retained_evidence;
    operations=@();inventory_files=@();review_evidence=@{
        path=[IO.Path]::GetRelativePath($root,$narrativePath).Replace('\','/');sha256=$narrativeHash}}
foreach ($entry in (@($reviewManifest.operations) + @($reviewManifest.supplemental))) {
    $approval.operations += @{operation=$entry.operation;context=$entry.context;
        variant=$(if($entry.Contains('variant')){$entry.variant}else{'primary'});decision='accepted';
        c_report_sha256=$entry.c.sha256;ada_report_sha256=$entry.ada.sha256;
        contract_sha256=$entry.contract.sha256;comparison=$entry.comparison}
}
foreach ($relative in (@('tests/conformance/suite.json','tests/conformance/c-api.jsonl') +
    @($suite.files | ForEach-Object { 'tests/conformance/' + $_.coverage_file }))) {
    $approval.inventory_files += @{path=$relative;sha256=(Get-FileHash (Join-Path $root $relative)).Hash.ToLowerInvariant()}
}
$approvalPath = Join-Path $temporary 'matrix-approval.json'
$reviewManifest.review = @{status='accepted';author='fixture-author';reviewer='fixture-reviewer';
    artifact=[IO.Path]::GetRelativePath($root,$approvalPath).Replace('\','/');artifact_sha256=''}
$targetModule = Get-Module ConformanceTargetMatrix
function Invoke-Review([Collections.IDictionary] $Manifest, [Collections.IDictionary] $Approval) {
    $Manifest.review.artifact_sha256 = Write-Json $approvalPath $Approval
    & $targetModule {param($r,$m,$s) Assert-TargetMatrixReview -Root $r -Manifest $m -Suite $s} $root $Manifest $suite
}
Case 'independent review binds synthetic reports without executing them' {
    Invoke-Review (Clone $reviewManifest) (Clone $approval)
}
Case 'matrix author cannot approve their own reconciliation' {
    $m = Clone $reviewManifest; $m.review.reviewer = $m.review.author
    Reject { Invoke-Review $m (Clone $approval) } 'accepted independent reconciliation'
}
Case 'matrix approval cannot bless a different revision or policy' {
    $m = Clone $reviewManifest; $a = Clone $approval; $a.revision = 'b'*40
    Reject { Invoke-Review $m $a } 'approval identity differs'
    $m = Clone $reviewManifest; $a = Clone $approval; $a.exclusion_policy.sha256 = '0'*64
    Reject { Invoke-Review $m $a } 'reviewed policy or retained evidence differs'
}
Case 'missing approved operations cannot hide aggregate or heavy work' {
    $a = Clone $approval; $a.operations = @($a.operations | Select-Object -Skip 1)
    Reject { Invoke-Review (Clone $reviewManifest) $a } 'approved operation count differs'
}
Case 'supplemental report and comparison changes require a fresh decision' {
    $m = Clone $reviewManifest; $m.supplemental[0].ada.sha256 = '0'*64
    Reject { Invoke-Review $m (Clone $approval) } 'approved operation binding differs'
    $m = Clone $reviewManifest; $m.operations[0].comparison = 'reviewed-semantic'
    Reject { Invoke-Review $m (Clone $approval) } 'approved operation binding differs'
}
Case 'complete global API and source inventory bytes bind the final review' {
    $a = Clone $approval
    $a.inventory_files[1].sha256 = '0'*64
    Reject { Invoke-Review (Clone $reviewManifest) $a } 'Review file hash differs'
}

Write-Output "PASS: $script:Cases full-target matrix regressions; synthetic fixtures only, no execution or target acceptance"
exit 0
