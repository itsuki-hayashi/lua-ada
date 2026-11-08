param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceAggregateReplay.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$temporary = Join-Path $root ('reports/transform-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Cases = 0

# Synthetic source, C observations and reviewer identities below test binding
# and rejection only. They are never installed in a production ledger and
# cannot establish native execution, exclusion authority or target acceptance.
function Case([string] $Name,[scriptblock] $Action) {
    & $Action; $script:Cases++; Write-Output "TRANSFORM TEST PASS: $Name"
}
function Assert-True([bool] $Condition,[string] $Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock] $Action,[string] $Expected) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong transform failure: $failure; expected $Expected"
}
function Write-Json([string] $Path,[object] $Value) {
    [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n") + "`n",$utf8)
    return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Copy-FrozenInput([string] $Relative,[string] $ExpectedHash,[string] $DestinationRoot) {
    $relativeFile = $Relative.Split('#')[0]
    $current = Join-Path $root $relativeFile
    $bytes = [IO.File]::ReadAllBytes($current)
    if ((Get-ConformanceHash $bytes) -cne $ExpectedHash) {
        # The accepted predecessor is historical test input, not approval of
        # changed production code. Read its actual Git blob without shell
        # text/newline conversion and verify every expected byte afterwards.
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = 'git'; $start.WorkingDirectory = $root
        $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $start.ArgumentList.Add('show')
        $start.ArgumentList.Add('d438f1fb2491006c1c248e0888637b4afa5ae0fc:' + $relativeFile)
        $process = [Diagnostics.Process]::Start($start)
        $buffer = [IO.MemoryStream]::new()
        try {
            $process.StandardOutput.BaseStream.CopyTo($buffer)
            $diagnostic = $process.StandardError.ReadToEnd(); $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw ("Cannot read required frozen predecessor blob d438f1fb2491006c1c248e0888637b4afa5ae0fc:$relativeFile. " +
                    "CI checkout must retain repository history (fetch-depth: 0). $diagnostic")
            }
            $bytes = $buffer.ToArray()
        } finally { $buffer.Dispose(); $process.Dispose() }
    }
    if ((Get-ConformanceHash $bytes) -cne $ExpectedHash) { throw "Frozen predecessor input differs: $relativeFile" }
    $target = Join-Path $DestinationRoot $relativeFile
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllBytes($target,$bytes)
}
$frozenRoot = Join-Path $temporary 'frozen-predecessor'
[void][IO.Directory]::CreateDirectory((Join-Path $frozenRoot 'reports/generated'))
foreach ($name in @('gc-ada-instrumented','files-windows-platform','files-macos-platform')) {
    $relative = "tests/conformance/equivalents/$name.json"
    $path = Join-Path $root $relative
    Copy-FrozenInput $relative (Get-ConformanceHash ([IO.File]::ReadAllBytes($path))) $frozenRoot
    $spec = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    Copy-FrozenInput $spec.source $spec.source_sha256 $frozenRoot
    Copy-FrozenInput $spec.review.artifact $spec.review.artifact_sha256 $frozenRoot
    $approval = Get-Content (Join-Path $frozenRoot $spec.review.artifact) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    foreach ($decision in $approval.decisions) {
        Copy-FrozenInput $decision.review_evidence.path $decision.review_evidence.sha256 $frozenRoot
        foreach ($counterpart in $decision.counterparts) { Copy-FrozenInput $counterpart.path $counterpart.sha256 $frozenRoot }
    }
}
foreach ($relative in @('scripts/New-ConformanceEquivalent.ps1','scripts/ConformanceReview.psm1')) {
    $path = Join-Path $root $relative
    Copy-FrozenInput $relative (Get-ConformanceHash ([IO.File]::ReadAllBytes($path))) $frozenRoot
}
function New-TFixture([string] $SourceName = 'sample.lua') {
    $directory = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory((Join-Path $directory 'references/lua/testes'))
    $source = "if not T then return end`nlocal function checkR (f, p, r, ...)`n  local r1 = f(p)`n  assert(r == r1 and math.type(r) == math.type(r1))`nend`nassert(T.private_layout())`nassert(public_result() == 7)`n"
    $bytes = $utf8.GetBytes($source)
    $private = 'assert(T.private_layout())'
    $offset = $source.IndexOf($private,[StringComparison]::Ordinal)
    $sourcePath = "references/lua/testes/$SourceName"
    [IO.File]::WriteAllBytes((Join-Path $directory $sourcePath),$bytes)
    $id = 'LUA-' + [IO.Path]::GetFileNameWithoutExtension($SourceName).ToUpperInvariant() + '-REVIEWED-BLOCK-0001'
    $hash = Get-ConformanceHash $bytes
    $spanHash = Get-ConformanceHash ($utf8.GetBytes($private))
    $exclusion = @{id=$id;source=$SourceName;source_sha256=$hash;byte_offset=$offset;byte_length=$private.Length;
        anchor_sha256=$spanHash;status='excluded';disposition='reviewed-t-internal-exclusion';
        eligibility='t-only-private-invariant';configurations=@('upstream-test');public_api=$false;
        mixed_obligation=$false;module_observable=$false}
    $spec = @{schema_version=1;kind='t-private-transform';target='remaining-upstream-compatibility';
        id='fixture-private-check';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        configuration='upstream-test';source=$sourcePath;source_sha256=$hash;exclusion_policy_sha256=('a'*64);
        replacements=@(@{id='remove-private-layout';exclusion_id=$id;start_byte=$offset;length_bytes=$private.Length;
            source_sha256=$spanHash;replacement="-- explicitly excluded private layout check`n"});
        output_sha256='';review=@{status='accepted';author='fixture-author';reviewer='fixture-reviewer';
            artifact='approval.json';artifact_sha256=''}}
    $resolved = @{}; $resolved[$id] = $exclusion
    $fixture = @{root=$directory;source=$source;bytes=$bytes;spec=$spec;resolved=$resolved}
    Set-TApproval $fixture
    return $fixture
}
function Set-TApproval([Collections.IDictionary] $Fixture) {
    $spec = $Fixture.spec
    $bytes = Get-ConformancePatchedBytes -SourceBytes $Fixture.bytes -Replacements $spec.replacements
    $spec.output_sha256 = Get-ConformanceHash $bytes
    $identity = @{}
    foreach ($field in @('id','target','reference_revision','source','source_sha256','configuration','exclusion_policy_sha256','output_sha256')) {
        $identity[$field] = $spec[$field]
    }
    $narrativeHash = Write-Json (Join-Path $Fixture.root 'narrative.json') @{reviewer='fixture-reviewer';
        decision='accepted';transform_id=$spec.id;public_assertion_preservation='checkR and public result/type assertions remain verbatim'}
    $approval = @{schema_version=1;kind='t-private-transform-approval';author='fixture-author';reviewer='fixture-reviewer';
        decision='accepted';transform=$identity;decisions=@();review_evidence=@{path='narrative.json';sha256=$narrativeHash}}
    foreach ($change in $spec.replacements) {
        $approval.decisions += @{id=$change.id;decision='accepted';exclusion_id=$change.exclusion_id;
            start_byte=$change.start_byte;length_bytes=$change.length_bytes;source_sha256=$change.source_sha256;
            replacement_sha256=(Get-ConformanceHash ($utf8.GetBytes($change.replacement)));
            private_only=$true;preserves_public_assertions=$true;rationale='Synthetic private-layout check only'}
    }
    $spec.review.artifact_sha256 = Write-Json (Join-Path $Fixture.root 'approval.json') $approval
}
function Invoke-TFixture([Collections.IDictionary] $Fixture) {
    Get-ConformanceTReplay -Root $Fixture.root -Specification $Fixture.spec -PolicySha256 ('a'*64) `
        -ResolvedExclusions $Fixture.resolved
}

Case 'all three frozen reviewed fixtures reconstruct their exact approved bytes' {
    foreach ($name in @('gc-ada-instrumented','files-windows-platform','files-macos-platform')) {
        $manifest = Join-Path $frozenRoot "tests/conformance/equivalents/$name.json"
        $spec = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        $replay = Get-ConformanceEquivalentReplay -Root $frozenRoot -Specification $spec
        $output = Join-Path $frozenRoot "reports/generated/$name.lua"
        $generated = & (Join-Path $frozenRoot 'scripts/New-ConformanceEquivalent.ps1') -Manifest $manifest -Output $output |
            ConvertFrom-Json -AsHashtable
        Assert-True ($replay.sha256 -ceq $generated.output_sha256 -and
            [Convert]::ToBase64String($replay.bytes) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($output))) `
            'Existing producer differs from pure equivalent reconstruction'
    }
}
Case 'an unreviewed equivalent never becomes replay authority' {
    $spec = Get-Content (Join-Path $frozenRoot 'tests/conformance/equivalents/gc-ada-instrumented.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $spec.review.status = 'pending'
    Reject { Get-ConformanceEquivalentReplay -Root $frozenRoot -Specification $spec } 'independent and accepted'
}
Case 'equivalent reconstruction rejects wider or changed source spans' {
    $spec = Get-Content (Join-Path $frozenRoot 'tests/conformance/equivalents/gc-ada-instrumented.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $spec.replacements[0].length_bytes++
    Reject { Get-ConformanceEquivalentReplay -Root $frozenRoot -Specification $spec } 'original span hash differs'
}
Case 'changed production counterparts cannot inherit frozen review authority' {
    $staleRoot = Join-Path $temporary 'deliberately-stale-current'
    Copy-Item -LiteralPath $frozenRoot -Destination $staleRoot -Recurse
    $counterpart = Join-Path $staleRoot 'tests/src/lua-conformance_adapter_tests.adb'
    [IO.File]::AppendAllText($counterpart,"`n-- synthetic later source change`n",$utf8)
    $spec = Get-Content (Join-Path $staleRoot 'tests/conformance/equivalents/gc-ada-instrumented.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    Reject { Get-ConformanceEquivalentReplay -Root $staleRoot -Specification $spec } 'Review file hash differs'
}
Case 'T private reconstruction preserves checkR and unrelated public assertions' {
    $f = New-TFixture code.lua; $replay = Invoke-TFixture $f
    $text = $utf8.GetString($replay.bytes)
    Assert-True ($text.Contains('local r1 = f(p)') -and
        $text.Contains('assert(r == r1 and math.type(r) == math.type(r1))') -and
        $text.Contains('assert(public_result() == 7)') -and
        -not $text.Contains('assert(T.private_layout())') -and -not $replay.diagnostic_only) 'Public assertions were changed'
}
Case 'no transform can consume the code.lua checkR execution helper' {
    $f = New-TFixture code.lua
    $start = $f.source.IndexOf('local function checkR')
    $length = $f.source.IndexOf("`nend",$start) + 4 - $start
    $change = $f.spec.replacements[0]; $excluded = @($f.resolved.Values)[0]
    $change.start_byte = $start; $change.length_bytes = $length
    $change.source_sha256 = Get-ConformanceHash ($utf8.GetBytes($f.source.Substring($start,$length)))
    $excluded.byte_offset = $start; $excluded.byte_length = $length; $excluded.anchor_sha256 = $change.source_sha256
    Set-TApproval $f
    Reject { Invoke-TFixture $f } 'cannot alter code.lua checkR'
}
Case 'a wider T transform cannot borrow an approved private exclusion' {
    $f = New-TFixture; $f.spec.replacements[0].start_byte--
    $f.spec.replacements[0].length_bytes++
    Reject { Invoke-TFixture $f } 'wider than or differs from its approved private exclusion'
}
Case 'mixed and module-visible invariants remain ineligible' {
    foreach ($field in @('mixed_obligation','public_api','module_observable')) {
        $f = New-TFixture; @($f.resolved.Values)[0][$field] = $true
        Reject { Invoke-TFixture $f } 'approved private exclusion'
    }
}
Case 'T=nil flags early returns and executable substitutes are forbidden' {
    foreach ($replacement in @('T=nil','_soft=true','_port=true','_U=true','_nomsg=true','return','return true','error("skip")')) {
        $f = New-TFixture; $f.spec.replacements[0].replacement = $replacement
        Reject { Invoke-TFixture $f } 'executable behavior or a blanket bypass'
    }
}
Case 'a comment cannot swallow untouched public source' {
    $f = New-TFixture; $f.spec.replacements[0].replacement = '-- omitted'
    Reject { Invoke-TFixture $f } 'comment must terminate'
    $f = New-TFixture; $f.spec.replacements[0].replacement = "--[[ omitted`n"
    Reject { Invoke-TFixture $f } 'Unterminated|complete simple line comments'
}
Case 'original generated and policy hashes cannot drift' {
    $f = New-TFixture; $f.spec.source_sha256 = '0'*64
    Reject { Invoke-TFixture $f } 'Review file hash differs'
    $f = New-TFixture; $f.spec.output_sha256 = '0'*64
    Reject { Invoke-TFixture $f } 'exact generated hash differs'
    $f = New-TFixture; $f.spec.exclusion_policy_sha256 = '0'*64
    Reject { Invoke-TFixture $f } 'exclusion policy hash'
}
Case 'a transform author cannot approve their own semantic mapping' {
    $f = New-TFixture; $f.spec.review.reviewer = $f.spec.review.author
    Reject { Invoke-TFixture $f } 'author cannot approve'
}
Case 'pending proposals are diagnostic bytes without production authority' {
    $f = New-TFixture; $f.spec.review.status = 'pending'
    Reject { Invoke-TFixture $f } 'lacks independent semantic approval'
    $preview = Get-ConformanceTReplay -Root $f.root -Specification $f.spec -PolicySha256 ('a'*64) `
        -ResolvedExclusions $f.resolved -AllowUnreviewedDiagnostics
    Assert-True ($preview.diagnostic_only -and $preview.review_status -ceq 'pending') 'Author preview gained review authority'
}
Case 'semantic approval must preserve public assertions and private scope' {
    foreach ($field in @('private_only','preserves_public_assertions')) {
        $f = New-TFixture; $path = Join-Path $f.root 'approval.json'
        $approval = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        $approval.decisions[0][$field] = $false
        $f.spec.review.artifact_sha256 = Write-Json $path $approval
        Reject { Invoke-TFixture $f } 'private-only semantic review'
    }
}
Case 'accepted semantics cannot be carried onto different replacement bytes' {
    $f = New-TFixture; $f.spec.replacements[0].replacement = "-- another private comment`n"
    $f.spec.output_sha256 = Get-ConformanceHash (Get-ConformancePatchedBytes $f.bytes $f.spec.replacements)
    Reject { Invoke-TFixture $f } 'approved identity differs|approved replacement bytes differ'
}
Case 'duplicate exclusions and overlapping patch regions are rejected' {
    $f = New-TFixture; $f.spec.replacements += $f.spec.replacements[0]
    Reject { Invoke-TFixture $f } 'duplicate approved exclusions'
    $f = New-TFixture
    Reject { Get-ConformancePatchedBytes $f.bytes @($f.spec.replacements[0],$f.spec.replacements[0]) } 'duplicate or overlapping'
}

Import-Module (Join-Path $PSScriptRoot 'ConformanceTargetMatrix.psm1') -Force
$targetModule = Get-Module ConformanceTargetMatrix
function Invoke-MatrixTransform([string] $SourceRoot,[string] $ArtifactRoot,[object] $Report,
    [object] $Entry,[object] $Contract,[object] $Resolved,[bool] $Acceptance = $false) {
    & $targetModule {param($r,$a,$p,$e,$c,$x,$accept)
        Assert-TargetTransformReplay -Root $r -ArtifactRoot $a -Report $p -Entry $e -Contract $c `
            -ResolvedExclusions $x -RequireAcceptance:$accept
    } $SourceRoot $ArtifactRoot $Report $Entry $Contract $Resolved $Acceptance
}
Case 'matrix reconstructs derived T bytes instead of trusting their reported hash' {
    $f = New-TFixture
    [void][IO.Directory]::CreateDirectory((Join-Path $f.root 'reports/derived'))
    $manifestPath = Join-Path $f.root 'transform.json'
    $manifestHash = Write-Json $manifestPath $f.spec
    $replay = Invoke-TFixture $f
    $output = Join-Path $f.root 'reports/derived/equivalent-sample.lua'
    [IO.File]::WriteAllBytes($output,$replay.bytes)
    $report = @{execution_disposition='reviewed-t-adapted';requested_configuration='upstream-test';target='Ada';
        exclusion_policy_sha256=('a'*64);excluded_obligations=$replay.excluded_obligations;
        t_adaptation=@{diagnostic_only=$false;review_status='accepted';manifest_path='transform.json';
            manifest_sha256=$manifestHash;output=$output;output_sha256=$replay.sha256}}
    $entry = @{operation='file:sample.lua'}
    $contract = @{t_transform_manifest_sha256=$manifestHash;exclusion_policy_sha256=('a'*64);
        executed_sha256=$replay.sha256;disposition='reviewed-t-adapted'}
    Invoke-MatrixTransform $f.root $f.root $report $entry $contract $f.resolved
    [IO.File]::AppendAllText($output,"assert(false)`n",$utf8)
    $report.t_adaptation.output_sha256 = (Get-FileHash $output).Hash.ToLowerInvariant()
    Reject { Invoke-MatrixTransform $f.root $f.root $report $entry $contract $f.resolved } 'executed transform bytes'
}
Case 'matrix replays existing Ada equivalence and protects the separate C oracle' {
    $manifest = 'tests/conformance/equivalents/gc-ada-instrumented.json'
    $spec = Get-Content (Join-Path $frozenRoot $manifest) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $replay = Get-ConformanceEquivalentReplay -Root $frozenRoot -Specification $spec
    $manifestHash = (Get-FileHash (Join-Path $frozenRoot $manifest)).Hash.ToLowerInvariant()
    $report = @{execution_disposition='ada-internal-equivalent';target='Ada';requested_configuration='default';
        equivalent=@{manifest_path=$manifest;manifest_sha256=$manifestHash;diagnostic_only=$false;review_status='accepted';
            output=(Join-Path $frozenRoot 'reports/generated/gc-ada-instrumented.lua');output_sha256=$replay.sha256}}
    $entry = @{operation='file:gc.lua'}
    $contract = @{equivalent_manifest_sha256=$manifestHash;executed_sha256=$replay.sha256;disposition='ada-internal-equivalent'}
    Invoke-MatrixTransform $frozenRoot $frozenRoot $report $entry $contract @{}
    $report.target = 'ReferenceC'
    Reject { Invoke-MatrixTransform $frozenRoot $frozenRoot $report $entry $contract @{} } 'cannot replace original C execution'
}
Case 'matrix cannot accept a platform mapping without original C applicability' {
    $manifest = 'tests/conformance/equivalents/files-windows-platform.json'
    $manifestHash = (Get-FileHash (Join-Path $frozenRoot $manifest)).Hash.ToLowerInvariant()
    $report = @{execution_disposition='native-platform-equivalent';target='Ada';requested_configuration='default';
        host=@{platform='windows'};native_applicability_verified=$false;
        equivalent=@{manifest_path=$manifest;manifest_sha256=$manifestHash;diagnostic_only=$false;review_status='accepted'}}
    Reject { Invoke-MatrixTransform $frozenRoot $frozenRoot $report @{operation='file:files.lua'} @{} @{} $true } 'source-linked original C applicability'
}

function New-NativeFixture {
    $f = New-TFixture
    [void][IO.Directory]::CreateDirectory((Join-Path $f.root 'reports/native'))
    $mapping = @{id='native-fixture';source=$f.spec.source;source_sha256=$f.spec.source_sha256;
        replacements=@(@{id='native-span';start_byte=$f.spec.replacements[0].start_byte;
            length_bytes=$f.spec.replacements[0].length_bytes;source_sha256=$f.spec.replacements[0].source_sha256})}
    $settings = @{schema_version=1;implementation='C Lua';configuration='default';lua_release='Lua 5.5.1';
        integer_bytes=8;number_bytes=8;pointer_bytes=[IntPtr]::Size;extra_space_bytes=[IntPtr]::Size;
        expected_extra_space_bytes=[IntPtr]::Size;allocator_limit_bytes=2147483648L;allocator_accounting='synthetic-only';
        max_stack=1000000;max_c_calls=200;aux_buffer_bytes=16*[IntPtr]::Size*8;compat_global=1;
        rand32=$false;compat_math=$false;test_adapter=$false}
    $stdout = Join-Path $f.root 'reports/native/original.stdout'; $stderr = Join-Path $f.root 'reports/native/original.stderr'
    [IO.File]::WriteAllText($stdout,"native condition unsupported`n",$utf8); [IO.File]::WriteAllText($stderr,'',$utf8)
    $report = @{target='ReferenceC';synthetic_fixture=$true;execution_disposition='unchanged';
        reference_revision=$f.spec.reference_revision;repository_revision=('b'*40);repository_dirty=$false;
        host=@{platform='windows'};requested_configuration='default';reference_tree_verified=$true;acceptance_context='default/windows/validation/static';
        configuration_verified=$true;setup_error=$null;allocator_limit_bytes=2147483648L;observed_configuration=$settings;
        reference_library_records=@(@{path='C:/synthetic/libconformance_lua.a';sha256=('e'*64)});
        fixture_records=@(@{path='sample.lua';sha256=$f.spec.source_sha256});process=@{executable='C:/synthetic/lua.exe';executable_sha256=('c'*64);
            exit_code=0;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;process_tree_kill_error=$null;
            abnormal_exit_kind=$null;stdout_path=$stdout;stderr_path=$stderr;stdout_bytes=(Get-Item $stdout).Length;stderr_bytes=0;
            stdout_sha256=(Get-FileHash $stdout).Hash.ToLowerInvariant();stderr_sha256=(Get-FileHash $stderr).Hash.ToLowerInvariant()}}
    $proof = @{schema_version=1;kind='native-platform-applicability';synthetic_fixture=$true;
        reference_revision=$f.spec.reference_revision;repository_revision=('b'*40);mapping_id=$mapping.id;
        mapping_sha256=('d'*64);source=$mapping.source;source_sha256=$mapping.source_sha256;
        configuration='default';platform='windows';acceptance_context='default/windows/validation/static';observations=@(@{id='original-native';native_limitation='Synthetic native mismatch';
            source_spans=@(@{replacement_id='native-span';start_byte=$mapping.replacements[0].start_byte;
                length_bytes=$mapping.replacements[0].length_bytes;source_sha256=$mapping.replacements[0].source_sha256});
            original_c_report=@{path='reports/native/original.json';sha256=''};expected_exit_code=0;
            stdout_required=@(@{pattern='^native condition unsupported$';count=1});stderr_expected=@()});
        review=@{status='accepted';author='fixture-author';reviewer='fixture-reviewer';artifact='native-approval.json';artifact_sha256=''}}
    $f.mapping = $mapping; $f.native_report = $report; $f.proof = $proof
    Set-NativeApproval $f
    return $f
}
function Set-NativeApproval([Collections.IDictionary] $Fixture) {
    $proof = $Fixture.proof
    $proof.observations[0].original_c_report.sha256 = Write-Json (Join-Path $Fixture.root 'reports/native/original.json') $Fixture.native_report
    $narrative = Write-Json (Join-Path $Fixture.root 'native-narrative.json') @{reviewer=$proof.review.reviewer;
        decision='accepted';synthetic_fixture=$true;source_linked_c_applicability='Synthetic original C source condition only'}
    $approval = @{schema_version=1;kind='native-platform-applicability-approval';decision='accepted';synthetic_fixture=$true;
        author=$proof.review.author;reviewer=$proof.review.reviewer;review_evidence=@{path='native-narrative.json';sha256=$narrative};
        observations_sha256=(Get-ConformanceHash ($utf8.GetBytes((ConvertTo-Json -InputObject @($proof.observations) -Compress -Depth 64))))}
    foreach ($field in @('reference_revision','repository_revision','mapping_id','mapping_sha256','source','source_sha256','configuration','platform','acceptance_context')) {
        $approval[$field] = $proof[$field]
    }
    $proof.review.artifact_sha256 = Write-Json (Join-Path $Fixture.root 'native-approval.json') $approval
    $Fixture.native_identity = @{path='reports/native/proof.json';sha256=(Write-Json (Join-Path $Fixture.root 'reports/native/proof.json') $proof)}
}
function Invoke-NativeFixture([Collections.IDictionary] $Fixture,[switch] $Runtime,[string] $Context='') {
    Assert-ConformanceNativeApplicability -Root $Fixture.root -ArtifactRoot $Fixture.root -Identity $Fixture.native_identity `
        -Specification $Fixture.mapping -ManifestSha256 ('d'*64) -Configuration default -Platform windows `
        -Revision ('b'*40) -RequireRuntimeEvidence:$Runtime -ExpectedContext $Context
}
Case 'native applicability binds original C facts without synthetic runtime authority' {
    $f = New-NativeFixture; $proof = Invoke-NativeFixture $f
    Assert-True (-not $proof.runtime_verified) 'Synthetic native facts gained runtime authority'
    Reject { Invoke-NativeFixture $f -Runtime } 'Synthetic native applicability'
}
Case 'an Ada-only failure cannot become a native platform exception' {
    $f = New-NativeFixture; $f.native_report.target = 'Ada'; Set-NativeApproval $f
    Reject { Invoke-NativeFixture $f } 'not matching original C execution'
}
Case 'native observations must cite every exact original transformed span' {
    $f = New-NativeFixture; $f.proof.observations[0].source_spans[0].start_byte++; Set-NativeApproval $f
    Reject { Invoke-NativeFixture $f } 'original source span differs'
    $f = New-NativeFixture; $extra = $f.mapping.replacements[0].Clone(); $extra.id = 'another-span'
    $f.mapping.replacements += $extra
    Reject { Invoke-NativeFixture $f } 'cover every transformed invariant'
}
Case 'matching hashes cannot turn failed C capture or changed witnesses into evidence' {
    $f = New-NativeFixture; $f.native_report.process.timed_out = $true; Set-NativeApproval $f
    Reject { Invoke-NativeFixture $f } 'not matching original C execution'
    $f = New-NativeFixture; $path = $f.native_report.process.stdout_path
    [IO.File]::WriteAllText($path,"different native result`n",$utf8)
    $f.native_report.process.stdout_sha256 = (Get-FileHash $path).Hash.ToLowerInvariant()
    $f.native_report.process.stdout_bytes = (Get-Item $path).Length; Set-NativeApproval $f
    Reject { Invoke-NativeFixture $f } 'measured C witness differs'
}
Case 'native applicability source context and independent review cannot drift' {
    $f = New-NativeFixture; $f.native_report.requested_configuration = 'upstream-test'; Set-NativeApproval $f
    Reject { Invoke-NativeFixture $f } 'not matching original C execution'
    $f = New-NativeFixture; $f.proof.review.reviewer = $f.proof.review.author; Set-NativeApproval $f
    Reject { Invoke-NativeFixture $f } 'independent semantic review'
}
Case 'native applicability cannot borrow another profile or library context baseline' {
    $f=New-NativeFixture
    $null=Invoke-NativeFixture $f -Context default/windows/validation/static
    Reject {Invoke-NativeFixture $f -Context default/windows/release/static} 'another acceptance context'
    $f.native_report.acceptance_context='default/windows/validation/shared';Set-NativeApproval $f
    Reject {Invoke-NativeFixture $f -Context default/windows/validation/static} 'Original C native observation identifies another acceptance context'
}
Case 'actual-labelled native facts cannot gain runtime authority from synthetic review artifacts' {
    $f=New-NativeFixture;$f.proof.synthetic_fixture=$false;$f.native_report.synthetic_fixture=$false;Set-NativeApproval $f
    Reject {Invoke-NativeFixture $f -Runtime -Context default/windows/validation/static} 'actual independent approval'
    $approval=Get-Content (Join-Path $f.root 'native-approval.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $approval.synthetic_fixture=$false
    $f.proof.review.artifact_sha256=Write-Json (Join-Path $f.root 'native-approval.json') $approval
    $f.native_identity.sha256=Write-Json (Join-Path $f.root 'reports/native/proof.json') $f.proof
    Reject {Invoke-NativeFixture $f -Runtime -Context default/windows/validation/static} 'actual independent narrative'
}
Case 'original C applicability cannot borrow a different frozen host runtime or context image' {
    $f=New-NativeFixture
    $image=@{revision=('b'*40);context='default/windows/validation/static';launcher_basename='lua.exe';
        paths=@{c_oracle='build/conformance/default/bin/lua.exe';c_runtime='build/conformance/default/lib'};
        files=@(@{path='build/conformance/default/bin/lua.exe';sha256=('c'*64)},
            @{path='build/conformance/default/lib/libconformance_lua.a';sha256=('e'*64)})}
    function Replay-NativeImage([Collections.IDictionary]$Fixture,[Collections.IDictionary]$Image){
        &$targetModule {param($r,$p,$i) Assert-TargetNativeOriginalImageBindings -ArtifactRoot $r -Proof $p -ContextImage $i} $Fixture.root $Fixture.proof $Image
    }
    Replay-NativeImage $f $image
    foreach($change in @('host','runtime','context','missing')){
        $altered=ConvertFrom-Json (ConvertTo-Json $image -Depth 32) -AsHashtable -Depth 32
        switch($change){host{$altered.files[0].sha256='0'*64};runtime{$altered.files[1].sha256='0'*64};context{$altered.context='default/windows/release/static'};missing{$altered=$null}}
        Reject {Replay-NativeImage $f $altered} 'frozen|context image identity'
    }
}

function New-AggregateFixture([switch]$WithFrozenEquivalents) {
    $f=New-TFixture code.lua
    $suite=Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 32
    foreach($source in $suite.files){
        $path=Join-Path $f.root ('references/lua/testes/'+$source.path)
        if($source.path -cne 'code.lua'){[IO.File]::WriteAllText($path,('-- synthetic unexecuted '+$source.path+"`n"),$utf8)}
        $source.sha256=(Get-FileHash $path).Hash.ToLowerInvariant()
    }
    if($WithFrozenEquivalents){
        # Old counterpart bytes remain a frozen unit-test input. They do not
        # approve the current production source; the explicit synthetic bundle
        # flag prevents this fixture from becoming runtime authority.
        foreach($file in Get-ChildItem -LiteralPath $frozenRoot -File -Recurse){
            $relative=[IO.Path]::GetRelativePath($frozenRoot,$file.FullName)
            $destination=Join-Path $f.root $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
            [IO.File]::Copy($file.FullName,$destination,$true)
        }
        foreach($source in $suite.files){$source.sha256=(Get-FileHash (Join-Path $f.root ('references/lua/testes/'+$source.path))).Hash.ToLowerInvariant()}
    }
    $selectionHash=Write-Json (Join-Path $f.root 'selected-t-transform.json') $f.spec
    $bundle=@{schema_version=1;kind='target-aggregate-replay';target='remaining-upstream-compatibility';id='synthetic-aggregate';
        reference_revision=$suite.reference_revision;configuration='upstream-test';implementation='Ada';platform='windows';
        synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        original_sources=@($suite.files|ForEach-Object{@{path=$_.path;sha256=$_.sha256}});
        selections=@(@{source='code.lua';kind='t-private';manifest=@{path='selected-t-transform.json';sha256=$selectionHash}});
        review=@{status='accepted';author='synthetic-author';reviewer='synthetic-reviewer';artifact='bundle-approval.json';artifact_sha256=''}}
    $f.suite=$suite;$f.bundle=$bundle;Set-AggregateApproval $f
    return $f
}
function Set-AggregateApproval([Collections.IDictionary]$Fixture){
    $narrative=@{reviewer='synthetic-reviewer';decision='accepted';replay_id=$Fixture.bundle.id;synthetic_fixture=$true;
        preserves_aggregate_protocol=$true;preserves_public_assertions=$true;source_preservation='Fabricated binding fixture only; original driver and all other source bytes are retained.'}
    $narrativeHash=Write-Json (Join-Path $Fixture.root 'bundle-narrative.json') $narrative
    $approval=@{schema_version=1;kind='target-aggregate-replay-approval';author='synthetic-author';reviewer='synthetic-reviewer';
        decision='accepted';synthetic_fixture=$true;selection_sha256=(Get-TargetWitnessPayloadHash (Get-TargetAggregateClaims $Fixture.bundle));
        review_evidence=@{path='bundle-narrative.json';sha256=$narrativeHash}}
    $Fixture.bundle.review.artifact_sha256=Write-Json (Join-Path $Fixture.root 'bundle-approval.json') $approval
}
function Replay-Aggregate([Collections.IDictionary]$Fixture,[switch]$Actual,[string]$Implementation='Ada',[string]$Configuration='upstream-test',[string]$Platform='windows'){
    Get-TargetAggregateReplay -Root $Fixture.root -Specification $Fixture.bundle -Suite $Fixture.suite -Configuration $Configuration `
        -Implementation $Implementation -Platform $Platform -PolicySha256 ('a'*64) -ResolvedExclusions $Fixture.resolved -AllowSynthetic:(-not $Actual)
}
Case 'Aggregate reconstructs every source while preserving the original driver and heavy bytes' {
    $f=New-AggregateFixture;$r=Replay-Aggregate $f
    Assert-True ($r.expected_sources.Count -eq 34 -and $r.transforms.Count -eq 1 -and -not $r.runtime_acceptance -and -not $r.coverage_authority) 'Aggregate source set or authority changed'
    foreach($name in @('all.lua','heavy.lua')){$record=@($r.expected_sources|Where-Object path -CEQ $name)[0];Assert-True ($record.sha256 -ceq $record.original_sha256) 'An unselected driver/heavy source changed'}
    Reject {Replay-Aggregate $f -Actual} 'Invalid aggregate replay identity'
}
Case 'Aggregate source selection rejects missing duplicate heavy mixed and wrong-source mappings' {
    $f=New-AggregateFixture;$f.bundle.original_sources=$f.bundle.original_sources[1..33];Reject {Replay-Aggregate $f} 'complete original source set'
    $f=New-AggregateFixture;$f.bundle.selections+=@($f.bundle.selections[0]);Reject {Replay-Aggregate $f} 'duplicate heavy or mixed'
    $f=New-AggregateFixture;$f.bundle.selections[0].source='heavy.lua';Reject {Replay-Aggregate $f} 'duplicate heavy or mixed'
    $f=New-AggregateFixture;$f.bundle.selections[0].source='all.lua';Reject {Replay-Aggregate $f} 'another source or configuration'
}
Case 'Aggregate cannot omit an approved exclusion or widen the independently reviewed T bytes' {
    $f=New-AggregateFixture;$extra=$f.resolved.Values|Select-Object -First 1;$copy=$extra.Clone();$copy.id='ANOTHER-PRIVATE-OBLIGATION';$f.resolved[$copy.id]=$copy
    Reject {Replay-Aggregate $f} 'exactly its approved exclusions'
    $f=New-AggregateFixture;$f.spec.replacements[0].start_byte--
    $f.bundle.selections[0].manifest.sha256=Write-Json (Join-Path $f.root 'selected-t-transform.json') $f.spec
    Reject {Replay-Aggregate $f} 'wider than or differs'
}
Case 'Aggregate cannot borrow another source selection approval or self-review' {
    $f=New-AggregateFixture;$f.bundle.review.reviewer=$f.bundle.review.author;Reject {Replay-Aggregate $f} 'independent source selection review'
    $f=New-AggregateFixture;$f.bundle.id='changed-bundle';Reject {Replay-Aggregate $f} 'exact source selection'
    $f=New-AggregateFixture;$f.bundle.review.status='pending';Reject {Replay-Aggregate $f} 'independent source selection review'
}
Case 'Aggregate preserves independent C execution and rejects default T or another native platform' {
    $f=New-AggregateFixture;$f.bundle.implementation='ReferenceC'
    Reject {Replay-Aggregate $f -Implementation ReferenceC} 'T adaptation cannot replace default or original C'
    $f=New-AggregateFixture;$f.bundle.configuration='default'
    Reject {Replay-Aggregate $f -Configuration default} 'another source or configuration|T adaptation cannot replace default'
    $f=New-AggregateFixture -WithFrozenEquivalents
    $path='tests/conformance/equivalents/gc-ada-instrumented.json'
    $f.bundle.selections=@(@{source='gc.lua';kind='equivalent';manifest=@{path=$path;sha256=(Get-FileHash (Join-Path $f.root $path)).Hash.ToLowerInvariant()}})
    $f.resolved=@{};Set-AggregateApproval $f
    $null=Replay-Aggregate $f
    $f.bundle.implementation='ReferenceC';Reject {Replay-Aggregate $f -Implementation ReferenceC} 'Ada equivalent cannot replace original C'
    $path='tests/conformance/equivalents/files-windows-platform.json'
    $f.bundle.selections=@(@{source='files.lua';kind='equivalent';manifest=@{path=$path;sha256=(Get-FileHash (Join-Path $f.root $path)).Hash.ToLowerInvariant()}})
    $f.bundle.platform='linux'
    Reject {Replay-Aggregate $f -Implementation ReferenceC -Platform linux} 'native equivalent identifies another platform'
}
Case 'Aggregate native applicability requires exact original C mappings for its context' {
    $f=New-NativeFixture
    $replay=@{transforms=@(@{source='sample.lua';manifest=@{sha256=('d'*64)};mapping=$f.mapping;replay=@{disposition='native-platform-equivalent'}})}
    $report=@{acceptance_context='default/windows/validation/static';repository_revision=('b'*40);requested_configuration='default';host=@{platform='windows'}}
    Reject {Get-TargetAggregateNativeProofs -Root $f.root -ArtifactRoot $f.root -Report $report -Replay $replay -RequireRuntimeEvidence} 'lack source-linked original C'
    $index=@{schema_version=1;kind='target-aggregate-native-applicability';context=$report.acceptance_context;revision=$report.repository_revision;synthetic_fixture=$true;
        mappings=@(@{source='sample.lua';manifest_sha256=('d'*64);identity=$f.native_identity})}
    $identity=@{path='reports/native/index.json';sha256=(Write-Json (Join-Path $f.root 'reports/native/index.json') $index)}
    $proofs=Get-TargetAggregateNativeProofs -Root $f.root -ArtifactRoot $f.root -Report $report -Replay $replay -Identity $identity
    Assert-True ($proofs.Count -eq 1 -and -not $proofs[0].runtime_verified) 'Synthetic aggregate applicability gained authority'
    $index.mappings[0].manifest_sha256='0'*64;$identity.sha256=Write-Json (Join-Path $f.root 'reports/native/index.json') $index
    Reject {Get-TargetAggregateNativeProofs -Root $f.root -ArtifactRoot $f.root -Report $report -Replay $replay -Identity $identity} 'missing or duplicate source bindings'
    $index.context='default/windows/release/static';$identity.sha256=Write-Json (Join-Path $f.root 'reports/native/index.json') $index
    Reject {Get-TargetAggregateNativeProofs -Root $f.root -ArtifactRoot $f.root -Report $report -Replay $replay -Identity $identity} 'another context or transform set'
}
Case 'Aggregate derived tree keeps original snapshots immutable and detects changed executed bytes' {
    $f=New-AggregateFixture;$r=Replay-Aggregate $f;$directory=Join-Path $f.root 'reports/execution';$original=Join-Path $f.root 'reports/original'
    $originalRecords=Copy-ConformanceFixtures -Source (Join-Path $f.root 'references/lua/testes') -Destination $original
    $records=New-TargetAggregateExecutionTree -Root $f.root -SourceDirectory $original -Destination $directory -Replay $r
    $changes=Test-ConformanceFixtureHashes -Directory $original -Records $r.original_sources
    Assert-True ($changes.Count -eq 0) 'Original source snapshot changed'
    $manifestHash=Write-Json (Join-Path $f.root 'aggregate.json') $f.bundle
    $report=@{operation='aggregate';execution_disposition='reviewed-aggregate-replay';requested_configuration='upstream-test';target='Ada';host=@{platform='windows'};
        exclusion_policy_sha256=('a'*64);excluded_obligations=$r.excluded_obligations;fixture_records=$originalRecords;
        process=@{working_directory=$directory;arguments=@('-e','synthetic setup never executed','all.lua')};
        aggregate_replay=@{entry='all.lua';execution_directory=$directory;original_directory=$original;expected_sources=$r.expected_sources;manifest_path='aggregate.json';manifest_sha256=$manifestHash;
            selection_sha256=$r.selection_sha256;execution_changes=@();execution_input_records=$records}}
    $contract=@{aggregate_replays=@{Ada=@{manifest_sha256=$manifestHash;selection_sha256=$r.selection_sha256;
        executed_sources_sha256=(Get-TargetWitnessPayloadHash @{sources=$r.expected_sources});setup_sha256=(Get-ConformanceHash ($utf8.GetBytes('synthetic setup never executed')));
        disposition='reviewed-aggregate-replay'}}}
    function Replay-AggregateReport {
        Assert-TargetAggregateReportReplay -Root $f.root -ArtifactRoot $f.root -Report $report -Contract $contract -Suite $f.suite -ResolvedExclusions $f.resolved -AllowSynthetic
    }
    $null=Replay-AggregateReport
    [IO.File]::AppendAllText((Join-Path $directory 'code.lua'),'changed',$utf8)
    Reject {Replay-AggregateReport} 'observation path or hash differs'
    [IO.File]::WriteAllBytes((Join-Path $directory 'code.lua'),$r.transforms[0].replay.bytes)
    [IO.File]::AppendAllText((Join-Path $original 'all.lua'),'changed',$utf8)
    Reject {Replay-AggregateReport} 'observation path or hash differs'
    [IO.File]::Copy((Join-Path $f.root 'references/lua/testes/all.lua'),(Join-Path $original 'all.lua'),$true)
    $report.process.arguments[2]='different.lua';Reject {Replay-AggregateReport} 'exact reviewed driver tree'
    $report.process.arguments[2]='all.lua';$contract.aggregate_replays.Ada.setup_sha256='0'*64
    Reject {Replay-AggregateReport} 'execution contract'
}

Case 'API mixed assertion reconstruction removes only its separately bound private conjunct' {
    # Real immutable source with an explicitly synthetic resolved-exclusion
    # object tests byte reconstruction only. No approval is installed and
    # no original or adapted Lua process executes in this fixture.
    $packet=Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/api-fixed-buffer-private-bound.author-proposal.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $spec=Get-Content (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/api-fixed-buffer-private-bound.transform.author-proposal.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $syntheticExclusion=$packet.proposed_private_child.exclusion_candidate|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64
    # The pending author object is intentionally not an installed payload.
    # Only this unit fixture supplies a synthetic resolved state.
    $syntheticExclusion.status='excluded';$syntheticExclusion.disposition='reviewed-t-internal-exclusion'
    $syntheticResolved=@{};$syntheticResolved[$packet.proposed_private_child.record.id]=$syntheticExclusion
    $r=Get-ConformanceTReplay -Root $root -Specification $spec -PolicySha256 $spec.exclusion_policy_sha256 -ResolvedExclusions $syntheticResolved -AllowUnreviewedDiagnostics
    $text=[Text.Encoding]::UTF8.GetString($r.bytes)
    Assert-True ($r.diagnostic_only -and $text.Contains('assert(m2 > m1)') -and
        $text.Contains('X = 0; code(); assert(X == N and Y == string.rep("a", N))') -and
        $text.Contains('checkerr(":301:", code)')) 'Private child erased retained growth, execution or debug behavior'
    $wide=$spec|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64
    $wide.replacements[0].start_byte=$packet.original_mixed_assertion.full_expression.byte_offset
    $wide.replacements[0].length_bytes=$packet.original_mixed_assertion.full_expression.byte_length
    $wide.replacements[0].source_sha256=$packet.original_mixed_assertion.full_expression.anchor_sha256
    Reject {Get-ConformanceTReplay -Root $root -Specification $wide -PolicySha256 $spec.exclusion_policy_sha256 -ResolvedExclusions $syntheticResolved -AllowUnreviewedDiagnostics} 'wider than or differs'
    Reject {Get-ConformanceTReplay -Root $root -Specification $spec -PolicySha256 $spec.exclusion_policy_sha256 -ResolvedExclusions @{}} 'missing or duplicate approved exclusions'
}

Write-Output "PASS: $script:Cases exact-byte transform regressions; synthetic approval fixtures, no runtime conformance claim"
$productionBlockers = @()
foreach ($name in @('gc-ada-instrumented','files-windows-platform','files-macos-platform')) {
    $spec = Get-Content (Join-Path $root "tests/conformance/equivalents/$name.json") -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    try { $null = Get-ConformanceEquivalentReplay -Root $root -Specification $spec }
    catch { $productionBlockers += @{id=$name;error=$_.Exception.Message} }
}
$null = Write-Json (Join-Path $temporary 'production-applicability.json') @{
    schema_version=1;unit_fixtures_only=$true;runtime_acceptance=$false;current_production_blockers=$productionBlockers}
foreach ($blocker in $productionBlockers) {
    Write-Output "PRODUCTION REPLAY BLOCKED: $($blocker.id): $($blocker.error); frozen unit fixtures do not clear this integration blocker"
}
& (Join-Path $PSScriptRoot 'test-conformance-verifier-equivalents.ps1')
exit 0
