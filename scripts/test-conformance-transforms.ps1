param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
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

Case 'all three accepted equivalents reconstruct their reviewed bytes exactly' {
    foreach ($name in @('gc-ada-instrumented','files-windows-platform','files-macos-platform')) {
        $manifest = Join-Path $root "tests/conformance/equivalents/$name.json"
        $spec = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        $replay = Get-ConformanceEquivalentReplay -Root $root -Specification $spec
        $output = Join-Path $temporary "$name.lua"
        $generated = & (Join-Path $PSScriptRoot 'New-ConformanceEquivalent.ps1') -Manifest $manifest -Output $output |
            ConvertFrom-Json -AsHashtable
        Assert-True ($replay.sha256 -ceq $generated.output_sha256 -and
            [Convert]::ToBase64String($replay.bytes) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($output))) `
            'Existing producer differs from pure equivalent reconstruction'
    }
}
Case 'an unreviewed equivalent never becomes replay authority' {
    $spec = Get-Content (Join-Path $root 'tests/conformance/equivalents/gc-ada-instrumented.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $spec.review.status = 'pending'
    Reject { Get-ConformanceEquivalentReplay -Root $root -Specification $spec } 'independent and accepted'
}
Case 'equivalent reconstruction rejects wider or changed source spans' {
    $spec = Get-Content (Join-Path $root 'tests/conformance/equivalents/gc-ada-instrumented.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $spec.replacements[0].length_bytes++
    Reject { Get-ConformanceEquivalentReplay -Root $root -Specification $spec } 'original span hash differs'
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
    $spec = Get-Content (Join-Path $root $manifest) -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    $replay = Get-ConformanceEquivalentReplay -Root $root -Specification $spec
    $manifestHash = (Get-FileHash (Join-Path $root $manifest)).Hash.ToLowerInvariant()
    $report = @{execution_disposition='ada-internal-equivalent';target='Ada';requested_configuration='default';
        equivalent=@{manifest_path=$manifest;manifest_sha256=$manifestHash;diagnostic_only=$false;review_status='accepted';
            output=(Join-Path $temporary 'gc-ada-instrumented.lua');output_sha256=$replay.sha256}}
    $entry = @{operation='file:gc.lua'}
    $contract = @{equivalent_manifest_sha256=$manifestHash;executed_sha256=$replay.sha256;disposition='ada-internal-equivalent'}
    Invoke-MatrixTransform $root $root $report $entry $contract @{}
    $report.target = 'ReferenceC'
    Reject { Invoke-MatrixTransform $root $root $report $entry $contract @{} } 'cannot replace original C execution'
}
Case 'matrix cannot accept a platform mapping without original C applicability' {
    $manifest = 'tests/conformance/equivalents/files-windows-platform.json'
    $manifestHash = (Get-FileHash (Join-Path $root $manifest)).Hash.ToLowerInvariant()
    $report = @{execution_disposition='native-platform-equivalent';target='Ada';requested_configuration='default';
        host=@{platform='windows'};native_applicability_verified=$false;
        equivalent=@{manifest_path=$manifest;manifest_sha256=$manifestHash;diagnostic_only=$false;review_status='accepted'}}
    Reject { Invoke-MatrixTransform $root $root $report @{operation='file:files.lua'} @{} @{} $true } 'source-linked original C applicability'
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
        host=@{platform='windows'};requested_configuration='default';reference_tree_verified=$true;
        configuration_verified=$true;setup_error=$null;allocator_limit_bytes=2147483648L;observed_configuration=$settings;
        fixture_records=@(@{path='sample.lua';sha256=$f.spec.source_sha256});process=@{executable_sha256=('c'*64);
            exit_code=0;timed_out=$false;capture_exceeded=$false;pipe_drain_failed=$false;process_tree_kill_error=$null;
            abnormal_exit_kind=$null;stdout_path=$stdout;stderr_path=$stderr;stdout_bytes=(Get-Item $stdout).Length;stderr_bytes=0;
            stdout_sha256=(Get-FileHash $stdout).Hash.ToLowerInvariant();stderr_sha256=(Get-FileHash $stderr).Hash.ToLowerInvariant()}}
    $proof = @{schema_version=1;kind='native-platform-applicability';synthetic_fixture=$true;
        reference_revision=$f.spec.reference_revision;repository_revision=('b'*40);mapping_id=$mapping.id;
        mapping_sha256=('d'*64);source=$mapping.source;source_sha256=$mapping.source_sha256;
        configuration='default';platform='windows';observations=@(@{id='original-native';native_limitation='Synthetic native mismatch';
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
        decision='accepted';source_linked_c_applicability='Synthetic original C source condition only'}
    $approval = @{schema_version=1;kind='native-platform-applicability-approval';decision='accepted';
        author=$proof.review.author;reviewer=$proof.review.reviewer;review_evidence=@{path='native-narrative.json';sha256=$narrative};
        observations_sha256=(Get-ConformanceHash ($utf8.GetBytes((ConvertTo-Json -InputObject @($proof.observations) -Compress -Depth 64))))}
    foreach ($field in @('reference_revision','repository_revision','mapping_id','mapping_sha256','source','source_sha256','configuration','platform')) {
        $approval[$field] = $proof[$field]
    }
    $proof.review.artifact_sha256 = Write-Json (Join-Path $Fixture.root 'native-approval.json') $approval
    $Fixture.native_identity = @{path='reports/native/proof.json';sha256=(Write-Json (Join-Path $Fixture.root 'reports/native/proof.json') $proof)}
}
function Invoke-NativeFixture([Collections.IDictionary] $Fixture,[switch] $Runtime) {
    Assert-ConformanceNativeApplicability -Root $Fixture.root -ArtifactRoot $Fixture.root -Identity $Fixture.native_identity `
        -Specification $Fixture.mapping -ManifestSha256 ('d'*64) -Configuration default -Platform windows `
        -Revision ('b'*40) -RequireRuntimeEvidence:$Runtime
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

Write-Output "PASS: $script:Cases exact-byte transform regressions; synthetic approval fixtures, no runtime conformance claim"
exit 0
