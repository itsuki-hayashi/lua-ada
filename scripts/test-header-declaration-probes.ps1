param([string] $Compiler='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'HeaderDeclarationProbes.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TargetCompiledWitnesses.psm1')
Import-Module (Join-Path $PSScriptRoot 'TargetWitnessPolicy.psm1')
$directory=Join-Path $root ('reports/header-probe-selftests/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$mapping=New-HeaderDeclarationMapping -Root $root
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0;$script:Serial=0
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "HEADER PROBE TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64)}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
Case 'closed declaration schedule retains all contexts C++ DLL and distinct private T modes'{
    Assert-HeaderDeclarationMapping -Root $root -Mapping $mapping
    Assert-True ($mapping.api_anchors.Count -eq 228 -and $mapping.applicability_anchors.Count -eq 28 -and $mapping.cases.Count -eq 132) 'Declaration/applicability context inventory narrowed'
    foreach($entry in $mapping.api_anchors){Assert-True ($entry.kind -ceq 'type' -or ($entry.kind -ceq 'macro' -and
        $entry.declaration -cnotmatch '^#define\s+[A-Za-z_][A-Za-z0-9_]*\(')) 'A function or callable macro acquired declaration-only classification'}
    foreach($case in $mapping.cases){
        Assert-True ('scripts/TargetWitnessPolicy.psm1' -cin @($case.source_bindings.path)) 'The final declaration/runtime boundary was not source-bound'
        Assert-True ($case.profile_assertions.LUA_EXTRASPACE -eq $(if($case.mode.StartsWith('private-t-')){16}else{8})) 'The exact header extraspace role was not asserted'
        $includes=@($case.sides.sdk.compile_arguments|Where-Object{$_ -cmatch '^\{root\}/(?:references/lua|c_api/include/api)$'})
        Assert-True ($includes.Count -eq 1 -and $includes[0] -ceq '{root}/c_api/include/api') 'SDK headers can fall back to the reference public tree'
    }
    foreach($context in @($mapping.cases.contexts|ForEach-Object{$_}|Sort-Object -Unique)){
        $selected=@($mapping.cases|Where-Object{ $context -cin $_.contexts })
        Assert-True ('public-cpp' -cin $selected.mode -and 'public-c' -cin $selected.mode) 'C++ was omitted from declaration applicability'
        Assert-True ('facade-c' -cin $selected.mode) 'Implementation configuration projection was omitted'
        Assert-True (($context.StartsWith('upstream-test/')) -eq ('private-t-c' -cin $selected.mode)) 'Private T mode was omitted or substituted for ordinary SDK'
    }
}
Case 'missing C++ mode fake declaration anchors and compiler flag drift fail the complete mapping binding'{
    $m=Clone $mapping;$m.cases=@($m.cases|Select-Object -Skip 1);Reject {Assert-HeaderDeclarationMapping -Root $root -Mapping $m} 'complete probe schedule'
    $m=Clone $mapping;$m.api_anchors[0].kind='function';Reject {Assert-HeaderDeclarationMapping -Root $root -Mapping $m} 'api_anchors'
    $m=Clone $mapping;$m.cases[0].sides.sdk.compile_arguments+=@('-DLUA_32BITS');Reject {Assert-HeaderDeclarationMapping -Root $root -Mapping $m} 'complete probe schedule'
    $m=Clone $mapping;$m.candidate_category_decisions.behavioral_macro='eligible-compiled-candidate';Reject {Assert-HeaderDeclarationMapping -Root $root -Mapping $m} 'candidate_category_decisions'
}
Case 'synthetic preprocessing parser preserves case-sensitive macro names and original source line identities'{
    $path=Join-Path $directory 'synthetic-origin.stdout'
    $header=($root.Replace('\','/')+'/c_api/include/api/luaconf.h')
    [IO.File]::WriteAllText($path,('# 524 "'+$header+'"'+"`n#define LUA_INTEGER long long`n#define lua_Integer invented`n"),$utf8)
    $history=Read-HeaderDefinitionProfile -Path $path -SourceRoot $root -Side sdk -Anchors $mapping.api_anchors
    Assert-True ($history.Count -eq 1 -and $history[0].name -ceq 'LUA_INTEGER' -and $history[0].line -eq 524) 'C macro/type spelling was folded or origin shifted'
}
Case 'synthetic global reconciliation cannot hide a C++-active branch behind a C-only applicability witness'{
    # These are deliberately incomplete, fabricated objects. Every call must
    # reject before the final 473-entry gate; they are never review evidence.
    $context='default/windows/validation/static';$id='synthetic-only-not-an-inventory-id';$hash='1'*64
    $policy=@{source_reviewed=$true;global_api=@{entries=@(@{id=$id;anchor_sha256=$hash;classification='conditional-declaration';
        context_witnesses=@(@{context=$context;disposition='compiled-not-applicable';named_c_cases=@();named_aunit_cases=@();compiled_witnesses=@('C-only')})})}}
    $named=@{context=$context;revision=('a'*40);runtime_observed=$true;named_c_cases=@();named_aunit_cases=@()}
    $c=@{protocol='paired-header-profile-v1';context=$context;revision=$named.revision;runtime_observed=$true;actual_evidence=$true;
        validation_kind='verified-compiled-context-witness';api_anchor_states=@{$id=@{anchor_sha256=$hash;state='not-selected';declaration_only=$true}}}
    $cpp=Clone $c;$cpp.api_anchor_states[$id].state='processed-effective'
    $compiled=@{'C-only'=$c;'C++-selected'=$cpp}
    Reject {Assert-TargetGlobalApiRoutes -Policy $policy -NamedEvidence $named -CompiledCases $compiled -Context $context} 'hides an active C\+\+'
    $policy.global_api.entries[0].context_witnesses[0].disposition='compiled-observed'
    $cpp.api_anchor_states[$id].declaration_only=$false
    Reject {Assert-TargetGlobalApiRoutes -Policy $policy -NamedEvidence $named -CompiledCases $compiled -Context $context} 'cannot certify callable behavior'
    $cpp.api_anchor_states[$id].declaration_only=$true;$cpp.api_anchor_states[$id].anchor_sha256='0'*64
    Reject {Assert-TargetGlobalApiRoutes -Policy $policy -NamedEvidence $named -CompiledCases $compiled -Context $context} 'exact original declaration anchor'
}
function Write-ReviewFixture($Value,[bool]$ApprovalSynthetic=$true,[bool]$NarrativeSynthetic=$true){
    # This fixture exercises content binding only. It is explicitly labelled
    # synthetic and may never pass the final actual-review consumer.
    $script:Serial++;$prefix=Join-Path $directory ('review-'+$script:Serial)
    $claims=Get-HeaderProbePayloadHash (Get-HeaderDeclarationReviewClaims $Value)
    $narrative=@{reviewer='synthetic independent reviewer';decision='accepted';claims_sha256=$claims;
        synthetic_fixture=$NarrativeSynthetic;source_and_configuration_findings='Synthetic binding fixture only.';
        behavioral_and_runtime_boundaries='No runtime execution, semantic classification or coverage authority.'}
    $narrativePath=$prefix+'-narrative.json'
    [IO.File]::WriteAllText($narrativePath,(ConvertTo-Json $narrative -Depth 16).Replace("`r`n","`n")+"`n",$utf8)
    $approval=@{schema_version=1;kind='header-declaration-probe-source-approval';scope='header-probe-source-and-configuration';
        decision='accepted';author=$Value.author;reviewer=$narrative.reviewer;synthetic_fixture=$ApprovalSynthetic;
        global_api_classifications_accepted=$false;runtime_acceptance=$false;claims_sha256=$claims;
        category_decisions=@{type_layout='eligible-compiled-candidate';object_macro='eligible-compiled-candidate';
            callable_function='runtime-required';behavioral_macro='runtime-required';conditional_behavioral_applicability='not-runtime-evidence'};
        review_evidence=@{path=[IO.Path]::GetRelativePath($root,$narrativePath).Replace('\','/');sha256=(Get-FileHash $narrativePath).Hash.ToLowerInvariant()}}
    $approvalPath=$prefix+'-approval.json'
    [IO.File]::WriteAllText($approvalPath,(ConvertTo-Json $approval -Depth 16).Replace("`r`n","`n")+"`n",$utf8)
    $Value.review=@{status='accepted';author=$Value.author;reviewer=$narrative.reviewer;
        artifact=[IO.Path]::GetRelativePath($root,$approvalPath).Replace('\','/');artifact_sha256=(Get-FileHash $approvalPath).Hash.ToLowerInvariant()}
    return $Value
}
Case 'source review requires distinct actual artifacts and exact closed configuration claims'{
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $mapping} 'accepted independent review'
    $fixture=Write-ReviewFixture (Clone $mapping)
    $value=Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture -AllowSynthetic
    Assert-True ($value.source_reviewed -and -not $value.global_api_classifications_accepted -and -not $value.runtime_acceptance) 'Binding review acquired semantic authority'
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture} 'approval scope'
    $fixture=Write-ReviewFixture (Clone $mapping) $false $true
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture} 'actual independent source review narrative'
    $fixture=Write-ReviewFixture (Clone $mapping)
    $fixture.review.reviewer=$fixture.review.author
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture -AllowSynthetic} 'accepted independent review'
    $fixture=Write-ReviewFixture (Clone $mapping)
    $fixture.cases[0].sides.sdk.compile_arguments+='-DLUA_32BITS'
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture -AllowSynthetic} 'approval scope'
    $fixture=Write-ReviewFixture (Clone $mapping)
    $fixture.api_anchors[0].anchor_sha256='0'*64
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture -AllowSynthetic} 'approval scope'
    $fixture=Write-ReviewFixture (Clone $mapping)
    $fixture.review.artifact_sha256='0'*64
    Reject {Assert-HeaderDeclarationSourceReview -Root $root -Mapping $fixture -AllowSynthetic} 'hash differs'
}
if($Compiler -ne ''){
    $platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
    $records=@();$selectedCases=@()
    foreach($selection in @(@{configuration='default';mode='public-c'},@{configuration='default';mode='public-cpp'},
        @{configuration='upstream-test';mode='private-t-c'},@{configuration='upstream-test';mode='private-t-cpp'},
        @{configuration='default';mode='facade-c'},@{configuration='upstream-test';mode='facade-c'})){
        $context=$selection.configuration+'/'+$platform+'/validation/static'
        $case=Clone (@($mapping.cases|Where-Object{ $context -cin $_.contexts -and $_.mode -ceq $selection.mode })[0])
        # An isolated author capture uses the same source/flags but a new
        # reports destination. It cannot satisfy the closed final schedule.
        $destination='{root}/'+[IO.Path]::GetRelativePath($root,$directory).Replace('\','/')+'/'+$case.id
        foreach($side in @('sdk','native')){
            $old=$case.sides[$side].output;$new=$destination+'/'+[IO.Path]::GetFileName($old)
            $case.sides[$side].output=$new
            $case.sides[$side].compile_arguments=@($case.sides[$side].compile_arguments|ForEach-Object{if($_ -ceq $old){$new}else{$_}})
        }
        $record=Invoke-HeaderDeclarationPair -Root $root -Compiler $Compiler -Case $case
        $selectedCases+=$case;$records+=$record
    }
    $compilerHash=(Get-FileHash $Compiler).Hash.ToLowerInvariant()
    function Replay($Record,$Case){Test-HeaderDeclarationPair -Root $root -ArtifactRoot $root -SourceRoot $root `
        -CompilerSha256 $compilerHash -Mapping $mapping -Case $Case -Record $Record}
    Case 'actual C99 C++17 private T and facade counterparts agree within each measured role'{
        for($i=0;$i -lt $records.Count;$i++){
            $value=Replay $records[$i] $selectedCases[$i]
            Assert-True ($value.measured_fields -eq 145 -and $value.api_anchor_states.Count -eq 256 -and -not $value.runtime_acceptance) 'Measured profile was narrowed or promoted to API acceptance'
        }
    }
    Case 'actual SDK compiler cannot silently borrow a missing public header from the oracle tree'{
        $case=Clone $selectedCases[0]
        $missing=Join-Path $directory 'empty-sdk-include';[void][IO.Directory]::CreateDirectory($missing)
        $case.sides.sdk.compile_arguments=@($case.sides.sdk.compile_arguments|ForEach-Object{if($_ -ceq '{root}/c_api/include/api'){$missing}else{$_}})
        $case.sides.sdk.preprocessing_arguments=@($case.sides.sdk.preprocessing_arguments|ForEach-Object{if($_ -ceq '{root}/c_api/include/api'){$missing}else{$_}})
        foreach($side in @('sdk','native')){
            $old=$case.sides[$side].output
            $new=($directory.Replace('\','/')+'/missing-sdk-probe/'+[IO.Path]::GetFileName($old))
            $case.sides[$side].output=$new
            $case.sides[$side].compile_arguments=@($case.sides[$side].compile_arguments|ForEach-Object{if($_ -ceq $old){$new}else{$_}})
        }
        Reject {Invoke-HeaderDeclarationPair -Root $root -Compiler $Compiler -Case $case} 'compiler failed'
    }
    Case 'actual pair cannot lose its native counterpart or reuse the SDK executable for both sides'{
        $r=Clone $records[0];[void]$r.sides.Remove('native');Reject {Replay $r $selectedCases[0]} 'counterpart is missing'
        $r=Clone $records[0];$r.sides.native=Clone $r.sides.sdk;Reject {Replay $r $selectedCases[0]} 'executable output path'
    }
    Case 'actual compiler identity argument configuration source and completion drift fail paired replay'{
        foreach($mutation in @('compiler','flags','source','timeout','authority')){
            $r=Clone $records[0]
            switch($mutation){
                compiler{$r.sides.native.processes.compile.executable_sha256='0'*64}
                flags{$r.sides.native.processes.preprocessing.arguments+='-DLUA_32BITS'}
                source{$r.source_bindings[0].sha256='0'*64}
                timeout{$r.sides.native.processes.compile.timed_out=$true}
                authority{$r.runtime_acceptance=$true}
            }
            Reject {Replay $r $selectedCases[0]} 'identity or completion|arguments differ|source bindings|cannot claim'
        }
    }
    function Rewrite-Capture($Process,[string]$Text){
        $script:Serial++;$path=Join-Path $directory ("edited-$script:Serial.stdout")
        [IO.File]::WriteAllText($path,$Text,$utf8)
        $Process.stdout_path=$path;$Process.stdout_sha256=(Get-FileHash $path).Hash.ToLowerInvariant();$Process.stdout_bytes=(Get-Item $path).Length
    }
    Case 'both equal captures cannot invent a wrong stable numeric ABI or hide a duplicate measured field'{
        $r=Clone $records[0]
        foreach($side in @('sdk','native')){
            $p=$r.sides[$side].processes.execution
            Rewrite-Capture $p ([IO.File]::ReadAllText($p.stdout_path).Replace('"sizeof.lua_Integer":8','"sizeof.lua_Integer":7'))
        }
        Reject {Replay $r $selectedCases[0]} 'fixed public ABI/version'
        $r=Clone $records[0]
        foreach($side in @('sdk','native')){
            $p=$r.sides[$side].processes.execution
            Rewrite-Capture $p ([IO.File]::ReadAllText($p.stdout_path).Replace('"LUA_EXTRASPACE":8','"LUA_EXTRASPACE":16'))
        }
        Reject {Replay $r $selectedCases[0]} 'fixed public ABI/version'
        $r=Clone $records[0];$p=$r.sides.native.processes.execution
        Rewrite-Capture $p ([IO.File]::ReadAllText($p.stdout_path).Replace('"cplusplus":0,','"cplusplus":0,"cplusplus":0,'))
        Reject {Replay $r $selectedCases[0]} 'duplicate or non-scalar'
    }
    Case 'rehashing altered native definition origins cannot borrow the exact source directive binding'{
        $r=Clone $records[0];$p=$r.sides.native.processes.preprocessing
        $text=[IO.File]::ReadAllText($p.stdout_path)
        # A rehashed macro body must still reproduce the original directive
        # at its claimed physical source line, before pair equality matters.
        $text=$text.Replace('#define LUA_VERSION_MAJOR_N 5','#define LUA_VERSION_MAJOR_N 6')
        Rewrite-Capture $p $text
        Reject {Replay $r $selectedCases[0]} 'exact source directive|original/final macro definitions differ'
    }
    Case 'conditional macro applicability never becomes a compiled callable-macro execution claim'{
        $value=Replay $records[0] $selectedCases[0]
        foreach($anchor in $mapping.applicability_anchors){Assert-True (-not $value.api_anchor_states[$anchor.id].declaration_only) 'A behavioral macro was classified as a declaration'}
    }
    [IO.File]::WriteAllText((Join-Path $directory 'actual-author-observations.json'),(ConvertTo-Json @{
        kind='header-pair-author-regression-observations';repository_dirty=$true;cases=$records;mapping_cases=$selectedCases;
        compiler_sha256=$compilerHash;runtime_acceptance=$false;coverage_authority=$false} -Depth 64).Replace("`r`n","`n")+"`n",$utf8)
}else{Write-Output 'NOT RUN: actual paired C/C++ compiler observations (Compiler not supplied)'}
Write-Output "PASS: $script:Cases header declaration probe regressions; actual compiler use only when explicitly supplied; no Lua API or target acceptance"
