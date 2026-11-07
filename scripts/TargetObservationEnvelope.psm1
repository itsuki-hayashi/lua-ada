Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
Import-Module (Join-Path $PSScriptRoot 'FileConsumerIO.psm1')
Import-Module (Join-Path $PSScriptRoot 'NativeLuaFixtureEvidence.psm1')

function Get-TargetObservationClaims {
    param([Parameter(Mandatory)][Collections.IDictionary] $Report,
          [Parameter(Mandatory)][Collections.IDictionary] $RawIdentity,
          [Parameter(Mandatory)][Collections.IDictionary] $ContractIdentity,
          [Parameter(Mandatory)][Collections.IDictionary] $ImageIdentity,
          [Collections.IDictionary] $NativeApplicability = $null)
    $libraries=if($Report.target -ceq 'Ada'){$Report.runtime_library_records}else{$Report.reference_library_records}
    $images=@($libraries|ForEach-Object{@{file=[IO.Path]::GetFileName($_.path.Replace('\','/'));sha256=$_.sha256}}|Sort-Object file)
    $sources=@($Report.fixture_records|ForEach-Object{@{path=$_.path;sha256=$_.sha256}}|Sort-Object path)
    $fixtures=@($Report.native_fixture_records|ForEach-Object{
        @{source=$_.source;source_sha256=$_.source_sha256;artifact_sha256=$_.artifact_sha256}
    }|Sort-Object source,artifact_sha256)
    return [ordered]@{target='remaining-upstream-compatibility';runtime_revision=$Report.repository_revision;
        reference_revision=$Report.reference_revision;context=$Report.acceptance_context;operation=$Report.operation;
        variant=$Report.variant;implementation=$Report.target;raw_report=$RawIdentity;reviewed_contract=$ContractIdentity;
        context_image=$ImageIdentity;requested_configuration=$Report.requested_configuration;
        measured_configuration_sha256=(Get-TargetWitnessPayloadHash $Report.observed_configuration);
        executable_sha256=$Report.process.executable_sha256;runtime_images=$images;original_sources=$sources;native_fixtures=$fixtures;
        configuration_stdout_sha256=$Report.configuration_process.stdout_sha256;
        child_configuration_stdout_sha256=$Report.child_configuration_process.stdout_sha256;
        arg_child_configuration_stdout_sha256=$Report.arg_child_configuration_process.stdout_sha256;
        stdout_sha256=$Report.process.stdout_sha256;stderr_sha256=$Report.process.stderr_sha256;
        exclusion_policy_sha256=$Report.exclusion_policy_sha256;excluded_obligations=@($Report.excluded_obligations|Sort-Object);
        execution_disposition=$Report.execution_disposition;
        native_fixture_linkage=$(if($Report.Contains('native_fixture_linkage')){$Report.native_fixture_linkage}else{@()});
        aggregate_replay=$(if($Report.Contains('aggregate_replay')){$Report.aggregate_replay}else{$null});native_applicability=$NativeApplicability}
}

function Assert-TargetObservationEnvelope {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][Collections.IDictionary] $Envelope,
          [Parameter(Mandatory)][Collections.IDictionary] $Report,
          [Parameter(Mandatory)][string] $RawReportPath,
          [Parameter(Mandatory)][Collections.IDictionary] $RawIdentity,
          [Parameter(Mandatory)][Collections.IDictionary] $ContractIdentity,
          [Parameter(Mandatory)][Collections.IDictionary] $ImageIdentity,
          [Parameter(Mandatory)][string] $Revision,[Parameter(Mandatory)][string] $Context,
          [Parameter(Mandatory)][string] $Operation,[Parameter(Mandatory)][string] $Implementation,
          [string] $Variant='primary',
          [switch] $AllowSynthetic)
    if($Envelope.schema_version -ne 1 -or $Envelope.kind -cne 'target-post-observation-envelope' -or
        $Envelope.runtime_acceptance -isnot [bool] -or $Envelope.runtime_acceptance -or
        $Envelope.coverage_authority -isnot [bool] -or $Envelope.coverage_authority){throw 'Invalid post-observation envelope identity'}
    # Validator fixtures are useful for exercising bindings, but their reviews
    # must never discharge a real matrix obligation. Requiring explicit JSON
    # booleans also prevents a missing flag or string "false" from gaining the
    # authority of an actual independent review. Only unit tests opt in below.
    foreach($record in @($Envelope,$Report)){
        if(-not $record.Contains('synthetic_fixture') -or $record.synthetic_fixture -isnot [bool] -or
            ($record.synthetic_fixture -and -not $AllowSynthetic)){throw 'Post-observation envelope and report require actual review artifacts'}
    }
    if((Get-FileHash -LiteralPath $RawReportPath).Hash.ToLowerInvariant() -cne $RawIdentity.sha256){throw 'Envelope raw report bytes changed'}
    if($Report.repository_revision -cne $Revision -or $Report.acceptance_context -cne $Context -or
        $Report.operation -cne $Operation -or $Report.target -cne $Implementation -or $Report.variant -cne $Variant){
        throw 'Envelope observation revision, context, operation or implementation differs'
    }
    $claims=$Envelope.claims
    $expected=Get-TargetObservationClaims -Report $Report -RawIdentity $RawIdentity -ContractIdentity $ContractIdentity `
        -ImageIdentity $ImageIdentity -NativeApplicability $claims.native_applicability
    if((Get-TargetWitnessPayloadHash $claims) -cne (Get-TargetWitnessPayloadHash $expected)){
        throw 'Envelope source, executable, fixture, configuration, image or report bindings differ'
    }
    $review=$Envelope.review
    if($null -eq $review -or $review.status -cne 'accepted' -or
        [string]::IsNullOrWhiteSpace([string]$review.author) -or [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or
        $review.author -ceq $review.reviewer){throw 'Post-observation envelope requires accepted independent review'}
    $path=Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if(-not $approval.Contains('synthetic_fixture') -or $approval.synthetic_fixture -isnot [bool] -or
        ($approval.synthetic_fixture -and -not $AllowSynthetic)){throw 'Post-observation approval requires an actual review artifact'}
    if($approval.schema_version -ne 1 -or $approval.kind -cne 'target-observation-approval' -or
        $approval.decision -cne 'accepted' -or $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
        $approval.claims_sha256 -cne (Get-TargetWitnessPayloadHash $claims) -or
        $approval.raw_report_sha256 -cne $RawIdentity.sha256 -or $approval.contract_sha256 -cne $ContractIdentity.sha256 -or
        $approval.context_image_sha256 -cne $ImageIdentity.sha256){throw 'Post-observation approval does not bind the exact observation'}
    $narrativePath=Resolve-ReviewedFile -Root $Root -Path $approval.review_evidence.path -Sha256 $approval.review_evidence.sha256
    $narrative=Get-Content -LiteralPath $narrativePath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    if(-not $narrative.Contains('synthetic_fixture') -or $narrative.synthetic_fixture -isnot [bool] -or
        ($narrative.synthetic_fixture -and -not $AllowSynthetic)){throw 'Post-observation narrative requires an actual review artifact'}
    if($narrative.reviewer -cne $review.reviewer -or $narrative.decision -cne 'accepted' -or
        $narrative.target -cne 'remaining-upstream-compatibility' -or $narrative.runtime_revision -cne $claims.runtime_revision){
        throw 'Post-observation independent narrative identifies another candidate'
    }
    # This is a reviewed interpretation of immutable observations, not a
    # rewrite of their report_only/target_operation_acceptance fields. The full
    # matrix must still replay runtime captures, source/transform contracts,
    # image build witnesses, all 473 API routes and every context/supplement.
    return @{review_verified=$true;native_applicability=$claims.native_applicability;
        runtime_acceptance=$false;coverage_authority=$false;raw_report_sha256=$RawIdentity.sha256}
}

function Test-TargetImageBuildWitnesses {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $ImageDirectory,
          [Parameter(Mandatory)][string] $Context,[Parameter(Mandatory)][string] $Revision,
          [Parameter(Mandatory)][Collections.IDictionary] $WitnessPolicy)
    $identity=Assert-TargetContextImage -ImageDirectory $ImageDirectory -Context $Context -Revision $Revision -RequireActual
    $image=$identity.manifest
    if(@($image.build_witnesses).Count -lt 4){throw 'Final context image lacks actual source-bound build witness reports'}
    $payload=Join-Path $ImageDirectory 'payload';$receipt=$null;$consumerPath=$null;$unitPath=$null;$buildLog=$null;$seen=@{}
    foreach($witness in $image.build_witnesses){
        $path=Resolve-TargetImagePath -Root $payload -Relative $witness.path
        $file=@($image.files|Where-Object path -CEQ $witness.path)
        if($seen.ContainsKey($witness.path) -or $file.Count -ne 1 -or $file[0].sha256 -cne $witness.sha256 -or
            (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $witness.sha256){throw 'Context build witness report hash or membership differs'}
        $seen[$witness.path]=$true
        $value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 48
        if($value.Contains('kind') -and $value.kind -ceq 'target-build-named-witnesses'){
            if($null -ne $receipt){throw 'Duplicate target build witness receipt'}
            $receipt=$value
        }elseif($value.Contains('kind') -and $value.kind -ceq 'target-context-build-log'){
            if($null -ne $buildLog -or $value.context -cne $Context -or $value.revision -cne $Revision -or
                @($value.source_bindings).Count -lt 4){throw 'Context compiler/regression log source identity differs'}
            $buildLog=$value
            foreach($source in $value.source_bindings){[void](Resolve-ReviewedFile -Root $Root -Path $source.path -Sha256 $source.sha256)}
            $process=$value.process
            if($process.exit_code -ne 0 -or $process.timed_out -ne $false -or $process.capture_exceeded -ne $false -or
                $process.pipe_drain_failed -ne $false -or $process.process_tree_kill_error -or $process.abnormal_exit_kind){
                throw 'Context compiler/regression log did not complete successfully'
            }
            foreach($stream in @('stdout','stderr')){
                $original=$process["${stream}_path"].Replace('\','/');$offset=$original.LastIndexOf('/reports/',[StringComparison]::Ordinal)
                if($offset -lt 0){throw 'Context build log capture is outside reports'}
                $capture=Resolve-TargetImagePath -Root $payload -Relative $original.Substring($offset+1)
                if((Get-FileHash -LiteralPath $capture).Hash.ToLowerInvariant() -cne $process["${stream}_sha256"] -or
                    (Get-Item -LiteralPath $capture).Length -ne $process["${stream}_bytes"]){throw 'Context build log capture bytes differ'}
            }
        }elseif($value.Contains('consumers')){
            if($null -ne $consumerPath){throw 'Duplicate target C build report'}
            $consumerPath=$path
        }elseif($value.Contains('configuration_probe') -and $value.Contains('sources')){
            if($null -ne $unitPath){throw 'Duplicate target AUnit build report'}
            $unitPath=$path
        }else{throw 'Unknown or fabricated context build witness report'}
    }
    if($null -eq $receipt -or $null -eq $consumerPath -or $null -eq $unitPath -or $null -eq $buildLog -or
        $receipt.context -cne $Context -or $receipt.revision -cne $Revision -or
        $receipt.witness_policy.path -cne $WitnessPolicy.identity.path -or
        $receipt.witness_policy.sha256 -cne $WitnessPolicy.identity.sha256){throw 'Context image build receipt is missing or identifies another source policy'}
    if($WitnessPolicy.source_reviewed -ne $true){throw 'Final context image needs an independently reviewed source witness policy'}
    $named=Test-TargetNamedContextEvidence -Root $Root -Policy $WitnessPolicy -ConsumerReport $consumerPath -AUnitReport $unitPath `
        -Context $Context -Revision $Revision -ConsumerArtifactRoot $payload -AUnitArtifactRoot $payload
    $consumer=Get-Content -LiteralPath $consumerPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    Assert-TargetBuildRuntimeBindings -Image $image -ConsumerReport $consumer
    if($consumer.Contains('loadfile_contract') -and $null -ne $consumer.loadfile_contract){
        Assert-FileConsumerIOImageBinding -Image $image -Observation $consumer.loadfile_contract.stdin_io
    }
    foreach($implementation in @('ada','c')){
        $name=if($implementation -ceq 'ada'){'native-module-api'}else{'native-module-oracle'}
        $process=@($consumer.consumers|Where-Object name -CEQ $name)
        if($process.Count -ne 1){throw 'Frozen image lacks its actual named native module lifetime consumer'}
        $nativeReport=@{acceptance_context=$Context;target=$(if($implementation -ceq 'ada'){'Ada'}else{'ReferenceC'});
            process=$process[0];native_fixture_linkage=@($consumer.native_module_contract[$implementation+'_linkage']);
            native_fixture_records=$consumer.native_module_contract[$implementation+'_fixture_records'];
            native_fixture_directory=$consumer.native_module_contract[$implementation+'_fixture_directory']}
        $null=Assert-NativeLuaFixtureEvidence -Root $Root -ArtifactRoot $payload -ImagePayload $payload -Image $image -Report $nativeReport -ConsumerHost
    }
    return @{image=$identity;named_evidence=$named;consumer_report=$consumer;build_witnesses_verified=$true;
        runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-TargetBuildRuntimeBindings {
    param([Parameter(Mandatory)][Collections.IDictionary] $Image,
          [Parameter(Mandatory)][Collections.IDictionary] $ConsumerReport)
    if(@($ConsumerReport.library_files).Count -eq 0){throw 'Actual named build runtime libraries are missing'}
    foreach($library in $ConsumerReport.library_files){
        $path=$Image.paths.ada_runtime+'/'+$library.file
        if(@($Image.files|Where-Object{ $_.path -ceq $path -and $_.sha256 -ceq $library.sha256 }).Count -ne 1){
            throw 'Actual named build witnesses used a different frozen Ada runtime DLL/archive'
        }
    }
    $kinds=@('gc','io','foreign')
    foreach($kind in @('format','value','auxiliary','load_dump','debug','builtin','external','conversion','operator','index_type','base_closing','native_module','buffer','allocator','substitution','thread_reset','loadfile','pointer_identity','concat')){
        if($ConsumerReport.Contains("${kind}_contract") -and $null -ne $ConsumerReport["${kind}_contract"]){$kinds+=$kind}
    }
    foreach($kind in $kinds){
        foreach($library in $ConsumerReport["${kind}_contract"].reference_library_files){
            $path=$Image.paths.c_runtime+'/'+$library.file
            if(@($Image.files|Where-Object{ $_.path -ceq $path -and $_.sha256 -ceq $library.sha256 }).Count -ne 1){
                throw 'Actual named build witnesses used a different frozen C oracle runtime'
            }
        }
    }
}

function Assert-TargetReportImageBinding {
    param([Parameter(Mandatory)][Collections.IDictionary] $Image,
          [Parameter(Mandatory)][Collections.IDictionary] $Report)
    if($Report.target -cnotin @('Ada','ReferenceC') -or $Report.repository_revision -cne $Image.revision -or $Report.acceptance_context -cne $Image.context -or
        $Report.requested_configuration -cne $Image.context.Split('/')[0]){throw 'Observation and frozen context image identity differ'}
    $ada=$Report.target -ceq 'Ada'
    $launcher=$Image.paths[$(if($ada){'ada_launcher'}else{'c_oracle'})]
    if([IO.Path]::GetFileName($Report.process.executable.Replace('\','/')) -cne $Image.launcher_basename -or
        @($Image.files|Where-Object{ $_.path -ceq $launcher -and $_.sha256 -ceq $Report.process.executable_sha256 }).Count -ne 1){
        throw 'Observation executed a different frozen host image or launcher basename'
    }
    $directory=$Image.paths[$(if($ada){'ada_runtime'}else{'c_runtime'})]
    $libraries=if($ada){$Report.runtime_library_records}else{$Report.reference_library_records}
    if(@($libraries).Count -eq 0){throw 'Observation runtime libraries are missing'}
    foreach($library in $libraries){
        $path=$directory+'/'+[IO.Path]::GetFileName($library.path.Replace('\','/'))
        if(@($Image.files|Where-Object{ $_.path -ceq $path -and $_.sha256 -ceq $library.sha256 }).Count -ne 1){
            throw 'Observation used a different frozen runtime DLL/archive'
        }
    }
}

Export-ModuleMember -Function Get-TargetObservationClaims, Assert-TargetObservationEnvelope, Test-TargetImageBuildWitnesses,
    Assert-TargetBuildRuntimeBindings, Assert-TargetReportImageBinding
