param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetObservationEnvelope.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
$temporary=Join-Path $root ('reports/envelope-selftests/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0
# Review labels and report/image objects are synthetic binding fixtures. There
# are no compiled images, executed API cases or actual acceptance claims here.
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "ENVELOPE TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
function Save([string]$Path,[object]$Value){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n")+"`n",$utf8);return (Get-FileHash $Path).Hash.ToLowerInvariant()}
function New-Fixture{
    $directory=Join-Path $temporary ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
    $report=@{schema_version=1;repository_revision=('a'*40);reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        acceptance_context='default/windows/validation/static';operation='file:api.lua';target='Ada';variant='primary';
        report_only=$true;target_operation_acceptance=$false;synthetic_fixture=$true;
        requested_configuration='default';observed_configuration=@{configuration='default';compat_global=1;test_adapter=$false};
        runtime_library_records=@(@{path='C:/synthetic/liblua.a';sha256=('1'*64)});reference_library_records=@();
        fixture_records=@(@{path='api.lua';sha256=('2'*64)});native_fixture_records=@();
        process=@{executable='C:/synthetic/lua.exe';executable_sha256=('3'*64);stdout_sha256=('4'*64);stderr_sha256=('5'*64)};
        configuration_process=@{stdout_sha256=('6'*64)};child_configuration_process=@{stdout_sha256=('6'*64)};
        arg_child_configuration_process=@{stdout_sha256=('6'*64)};exclusion_policy_sha256=('7'*64);excluded_obligations=@();execution_disposition='unchanged'}
    $rawPath=Join-Path $directory 'raw.json';$raw=@{path='raw.json';sha256=(Save $rawPath $report)}
    $contract=@{path='contract.json';sha256=('8'*64)};$image=@{path='image.json';sha256=('9'*64)}
    $claims=Get-TargetObservationClaims -Report $report -RawIdentity $raw -ContractIdentity $contract -ImageIdentity $image
    $narrative=@{target='remaining-upstream-compatibility';runtime_revision=('a'*40);reviewer='synthetic-reviewer';decision='accepted';synthetic_fixture=$true}
    $narrativePath=[IO.Path]::GetRelativePath($root,(Join-Path $directory 'narrative.json')).Replace('\','/')
    $narrativeHash=Save (Join-Path $root $narrativePath) $narrative
    $approval=@{schema_version=1;kind='target-observation-approval';author='synthetic-author';reviewer='synthetic-reviewer';decision='accepted';
        claims_sha256=(Get-TargetWitnessPayloadHash $claims);raw_report_sha256=$raw.sha256;contract_sha256=$contract.sha256;
        context_image_sha256=$image.sha256;review_evidence=@{path=$narrativePath;sha256=$narrativeHash};synthetic_fixture=$true}
    $approvalPath=[IO.Path]::GetRelativePath($root,(Join-Path $directory 'approval.json')).Replace('\','/')
    $approvalHash=Save (Join-Path $root $approvalPath) $approval
    $envelope=@{schema_version=1;kind='target-post-observation-envelope';claims=$claims;synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        review=@{status='accepted';author='synthetic-author';reviewer='synthetic-reviewer';artifact=$approvalPath;artifact_sha256=$approvalHash}}
    $envelope=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $envelope -Depth 64) -AsHashtable -Depth 64
    return @{directory=$directory;report=$report;raw_path=$rawPath;raw=$raw;contract=$contract;image=$image;
        envelope=$envelope;approval=$approval;approval_path=$approvalPath;narrative=$narrative;narrative_path=$narrativePath}
}
function Replay([Collections.IDictionary]$Fixture,[switch]$ActualReview){
    Assert-TargetObservationEnvelope -Root $root -Envelope $Fixture.envelope -Report $Fixture.report -RawReportPath $Fixture.raw_path `
        -RawIdentity $Fixture.raw -ContractIdentity $Fixture.contract -ImageIdentity $Fixture.image `
        -Revision ('a'*40) -Context default/windows/validation/static -Operation file:api.lua -Implementation Ada -AllowSynthetic:(-not $ActualReview)
}
function Save-Review([Collections.IDictionary]$Fixture){
    $Fixture.approval.review_evidence.sha256=Save (Join-Path $root $Fixture.narrative_path) $Fixture.narrative
    $Fixture.envelope.review.artifact_sha256=Save (Join-Path $root $Fixture.approval_path) $Fixture.approval
}
Case 'independent interpretation leaves the raw observation and acceptance flags unchanged'{
    $f=New-Fixture;$before=(Get-FileHash $f.raw_path).Hash;$r=Replay $f
    Assert-True ($r.review_verified -and -not $r.runtime_acceptance -and -not $r.coverage_authority -and
        $f.report.report_only -and -not $f.report.target_operation_acceptance -and (Get-FileHash $f.raw_path).Hash -ceq $before) 'Envelope rewrote or promoted the observation'
}
Case 'actual observations cannot borrow labelled synthetic envelope approval or narrative authority'{
    foreach($part in @('envelope','approval','narrative')){
        foreach($invalid in @($true,'false',$null)){
            $f=New-Fixture
            # These remain fabricated validator objects. Setting actual labels
            # here tests the final consumer's rejection, never execution proof.
            $f.report.synthetic_fixture=$false;$f.raw.sha256=Save $f.raw_path $f.report
            $f.envelope.synthetic_fixture=$false;$f.approval.synthetic_fixture=$false;$f.narrative.synthetic_fixture=$false
            $f.envelope.claims.raw_report.sha256=$f.raw.sha256
            $f.approval.raw_report_sha256=$f.raw.sha256
            $f.approval.claims_sha256=Get-TargetWitnessPayloadHash $f.envelope.claims
            if($null -eq $invalid){[void]$f[$part].Remove('synthetic_fixture')}else{$f[$part].synthetic_fixture=$invalid}
            Save-Review $f
            Reject {Replay $f -ActualReview} 'actual review artifact'
        }
    }
}
Case 'raw byte mutation fails even if the envelope still names its old SHA'{
    $f=New-Fixture;[IO.File]::AppendAllText($f.raw_path,'changed',$utf8)
    Reject {Replay $f} 'raw report bytes changed'
}
Case 'a refreshed raw hash cannot reuse the approval for the preceding observation'{
    $f=New-Fixture;$f.report.process.stdout_sha256='0'*64;$f.raw.sha256=Save $f.raw_path $f.report
    Reject {Replay $f} 'bindings differ'
}
Case 'selected reviewed source identity requires a fresh observation envelope decision'{
    $f=New-Fixture
    $f.report.reviewed_source=@{manifest_path='synthetic-reviewed-source.json';manifest_sha256=('4'*64);
        output_sha256=('5'*64);runtime_acceptance=$false;coverage_authority=$false}
    $f.raw.sha256=Save $f.raw_path $f.report
    Reject {Replay $f} 'bindings differ'
}
Case 'missing pending and self review each reject'{
    foreach($change in @('missing','pending','self')){
        $f=New-Fixture
        if($change -ceq 'missing'){$f.envelope.review=$null}
        elseif($change -ceq 'pending'){$f.envelope.review.status='pending'}
        else{$f.envelope.review.reviewer=$f.envelope.review.author}
        Reject {Replay $f} 'accepted independent review'
    }
}
Case 'configuration revision context image and source drift cannot borrow a review'{
    foreach($change in @('configuration','revision','context','image','source','runtime','contract','fixture')){
        $f=New-Fixture
        switch($change){
            configuration{$f.report.observed_configuration.compat_global=0}
            revision{$f.report.repository_revision='b'*40}
            context{$f.report.acceptance_context='upstream-test/windows/validation/static'}
            image{$f.image.sha256='0'*64}
            source{$f.report.fixture_records[0].sha256='0'*64}
            runtime{$f.report.runtime_library_records[0].sha256='0'*64}
            contract{$f.contract.sha256='0'*64}
            fixture{$f.report.native_fixture_records=@(@{source='fixture.c';source_sha256=('0'*64);artifact_sha256=('1'*64)})}
        }
        Reject {Replay $f} 'bindings differ|revision, context'
    }
}
Case 'approval bytes decision and narrative are content bound'{
    $f=New-Fixture;[IO.File]::AppendAllText((Join-Path $root $f.approval_path),'changed',$utf8)
    Reject {Replay $f} 'hash differs'
    $f=New-Fixture;$f.approval.decision='pending';$f.envelope.review.artifact_sha256=Save (Join-Path $root $f.approval_path) $f.approval
    Reject {Replay $f} 'exact observation'
    $f=New-Fixture;$f.approval.review_evidence.sha256='0'*64;$f.envelope.review.artifact_sha256=Save (Join-Path $root $f.approval_path) $f.approval
    Reject {Replay $f} 'hash differs'
}
Case 'reordered object keys cannot change canonical semantic binding hashes'{
    $a=[ordered]@{z=@();a=@(@{b=2;a=1})};$b=[ordered]@{a=@([ordered]@{a=1;b=2});z=@()}
    Assert-True ((Get-TargetWitnessPayloadHash $a) -ceq (Get-TargetWitnessPayloadHash $b)) 'Hash depends on Hashtable enumeration order'
}
Case 'actual observation host basename and runtime image hashes must match the frozen context'{
    $f=New-Fixture
    $image=@{context=$f.report.acceptance_context;revision=$f.report.repository_revision;launcher_basename='lua.exe';
        paths=@{ada_launcher='tests/bin/static/conformance_runner.exe';ada_runtime='lib/validation/static'};
        files=@(@{path='tests/bin/static/conformance_runner.exe';sha256=('3'*64)},@{path='lib/validation/static/liblua.a';sha256=('1'*64)})}
    Assert-TargetReportImageBinding -Image $image -Report $f.report
    $f.report.runtime_library_records[0].sha256='0'*64
    Reject {Assert-TargetReportImageBinding -Image $image -Report $f.report} 'different frozen runtime'
    $f.report.runtime_library_records[0].sha256='1'*64;$f.report.process.executable='C:/synthetic/renamed.exe'
    Reject {Assert-TargetReportImageBinding -Image $image -Report $f.report} 'launcher basename'
}
Case 'actual C and AUnit build receipt libraries cannot point to a different frozen runtime DLL'{
    $image=@{paths=@{ada_runtime='lib/validation/relocatable';c_runtime='build/conformance/default/lib'};
        files=@(@{path='lib/validation/relocatable/liblua.dll';sha256=('1'*64)},
            @{path='build/conformance/default/lib/libconformance_lua.dll';sha256=('2'*64)})}
    $consumer=@{library_files=@(@{file='liblua.dll';sha256=('1'*64)})}
    foreach($kind in @('gc','io','foreign')){$consumer["${kind}_contract"]=@{reference_library_files=@(@{file='libconformance_lua.dll';sha256=('2'*64)})}}
    Assert-TargetBuildRuntimeBindings -Image $image -ConsumerReport $consumer
    $consumer.library_files[0].sha256='0'*64
    Reject {Assert-TargetBuildRuntimeBindings -Image $image -ConsumerReport $consumer} 'different frozen Ada runtime'
    $consumer.library_files[0].sha256='1'*64;$consumer.io_contract.reference_library_files[0].sha256='0'*64
    Reject {Assert-TargetBuildRuntimeBindings -Image $image -ConsumerReport $consumer} 'different frozen C oracle'
}
Case 'additional public consumers cannot borrow another frozen C oracle DLL'{
    foreach($kind in @('value','auxiliary')){
        $image=@{paths=@{ada_runtime='lib/validation/relocatable';c_runtime='build/conformance/default/lib'};
            files=@(@{path='lib/validation/relocatable/liblua.dll';sha256=('1'*64)},
                @{path='build/conformance/default/lib/libconformance_lua.dll';sha256=('2'*64)})}
        $consumer=@{library_files=@(@{file='liblua.dll';sha256=('1'*64)})}
        foreach($contract in @('gc','io','foreign',$kind)){$consumer["${contract}_contract"]=@{reference_library_files=@(@{file='libconformance_lua.dll';sha256=('2'*64)})}}
        Assert-TargetBuildRuntimeBindings -Image $image -ConsumerReport $consumer
        $consumer["${kind}_contract"].reference_library_files[0].sha256='0'*64
        Reject {Assert-TargetBuildRuntimeBindings -Image $image -ConsumerReport $consumer} 'different frozen C oracle'
    }
}
Case 'non-synthetic and clean labels cannot replace empty or fabricated image build witnesses'{
    $directory=Join-Path $temporary ([Guid]::NewGuid().ToString('N'));$files=@()
    foreach($path in @('tests/bin/static/conformance_runner.exe','build/conformance/default/bin/lua.exe',
        'lib/validation/static/liblua.a','build/conformance/default/lib/libconformance_lua.dll')){
        $full=Join-Path $directory ('payload/'+$path);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
        [IO.File]::WriteAllText($full,'deliberate counterfeit image fixture',$utf8)
        $files+=@{path=$path;sha256=(Get-FileHash $full).Hash.ToLowerInvariant();bytes=(Get-Item $full).Length;
            unix_mode=$(if($IsWindows){0}else{[int][IO.File]::GetUnixFileMode($full)})}
    }
    $image=@{schema_version=1;kind='immutable-target-context-image';target='remaining-upstream-compatibility';
        context='default/windows/validation/static';revision=('a'*40);reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        repository_dirty=$false;synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;launcher_basename='lua.exe';
        files=$files;build_witnesses=@();paths=@{ada_launcher=$files[0].path;c_oracle=$files[1].path;
            ada_runtime='lib/validation/static';c_runtime='build/conformance/default/lib'}}
    $null=Save (Join-Path $directory 'image.json') $image
    Reject {Test-TargetImageBuildWitnesses -Root $root -ImageDirectory $directory -Context $image.context -Revision $image.revision -WitnessPolicy @{}} 'lacks actual source-bound'
    for($i=0;$i -lt 7;$i++){
        $path="reports/core-image/counterfeit-$i/result.json";$full=Join-Path $directory ('payload/'+$path)
        $hash=Save $full @{schema_version=1;kind='fabricated-pass';runtime_observed=$true}
        $image.files+=@{path=$path;sha256=$hash;bytes=(Get-Item $full).Length;
            unix_mode=$(if($IsWindows){0}else{[int][IO.File]::GetUnixFileMode($full)})}
        $image.build_witnesses+=@{path=$path;sha256=$hash}
    }
    $null=Save (Join-Path $directory 'image.json') $image
    Reject {Test-TargetImageBuildWitnesses -Root $root -ImageDirectory $directory -Context $image.context -Revision $image.revision -WitnessPolicy @{}} 'fabricated context build witness'
}
Write-Output "PASS: $script:Cases post-observation envelope regressions; synthetic interpretation fixtures only, no runtime acceptance"
