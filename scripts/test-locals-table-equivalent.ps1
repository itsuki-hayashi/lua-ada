param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceLocalsEquivalent.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceReviewedSources.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$manifest='tests/conformance/targets/remaining-upstream-compatibility/locals-dead-table-storage.equivalent.author-proposal.json'
$mapping=Get-Content (Join-Path $root $manifest) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
$datedProposalHash=(Get-FileHash (Join-Path $root $manifest)).Hash.ToLowerInvariant()
$datedMapping=$mapping|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64
$installedPath=Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/locals-dead-table-storage.equivalent.json'
$installed=$null
if(Test-Path -LiteralPath $installedPath){
    $installed=Get-Content $installedPath -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    # Validate real current independent authority first. Negative fixtures then
    # clone only the current input identities, keeping the author's review
    # pending. Never rewrite its dated proposal or manufacture an approval to
    # make a stale source fixture pass.
    $null=Get-TargetLocalsTableEquivalentReplay -Root $root -Specification $installed -Implementation Ada -Configuration upstream-test
    $mapping.counterpart_source_snapshot=$installed.counterpart_source_snapshot|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64
}
$temporary=Join-Path $root ('reports/locals-equivalent-definition/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$originalHash=(Get-FileHash (Join-Path $root $mapping.source)).Hash.ToLowerInvariant()
$script:cases=0
function Case($Description,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "LOCALS DEFINITION PASS: $Description"}
function Clone {return $mapping|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $Pattern){throw "Wrong locals definition rejection: $failure; expected $Pattern"}
}
function Definition($Value,$SourceRoot=$root,$Implementation='Ada',$Configuration='upstream-test'){
    Assert-TargetLocalsTableEquivalentDefinition -Root $SourceRoot -Specification $Value `
        -Implementation $Implementation -Configuration $Configuration
}
function Replay($Value,$SourceRoot=$root,$Implementation='Ada',$Configuration='upstream-test'){
    Get-TargetReviewedSourceReplay -Root $SourceRoot -Specification $Value -Implementation $Implementation `
        -Configuration $Configuration -PolicySha256 ('0'*64) -ResolvedExclusions @{}
}
function Save($Directory,$Path,$Value){
    $file=Join-Path $Directory $Path
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
    [IO.File]::WriteAllText($file,($Value|ConvertTo-Json -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return (Get-FileHash $file).Hash.ToLowerInvariant()
}
function Source-Fixture {
    # Copy only unchanged reference/counterpart inputs. Negative mutations
    # below affect metadata or Ada/Powershell counterparts, never emit an
    # adapted Lua program and never modify the actual reference checkout.
    $directory=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
    $paths=@($mapping.source)+@($mapping.counterpart_source_snapshot.bindings.path)
    foreach($path in ($paths|Select-Object -Unique)){
        $file=Join-Path $directory $path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $file
    }
    return $directory
}
function Synthetic-Review-Fixture([switch]$Narrative) {
    # Deliberately invalid review JSON is isolated in a negative fixture.
    # No positive synthetic approval or successful source replay is created.
    $directory=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
    $value=Clone;$value.review.status='accepted';$value.review.reviewer='negative-fixture-reviewer'
    $value.review.artifact='reports/negative-review/approval.json'
    $approval=@{schema_version=1;kind='equivalent-approval';decision='accepted';author=$value.review.author;
        reviewer=$value.review.reviewer;synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;
        execution_evidence=@();decisions=@()}
    if($Narrative){
        $approval.synthetic_fixture=$false
        $detail=@{schema_version=1;kind='equivalent-source-review';author=$value.review.author;reviewer=$value.review.reviewer;
            synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@()}
        $detailPath='reports/negative-review/narrative.json'
        $detailHash=Save $directory $detailPath $detail
        $approval.decisions=@(@{review_evidence=@{path=$detailPath;sha256=$detailHash}})
    }
    $value.review.artifact_sha256=Save $directory $value.review.artifact $approval
    return @{root=$directory;mapping=$value}
}

if($null -ne $installed){
    Case 'installed actual independent review replays only in memory without runtime authority' {
        $r=Replay $installed
        if($r.sha256 -cne '54481f4b2c760ef1f8efd747706a3e6eb02553f582e15210aaaab6ec72c448d8' -or
            $r.runtime_acceptance -or $r.coverage_authority){throw 'Installed source replay gained runtime authority'}
    }
    Case 'dated pre-tail author proposal stays unchanged and stale production bindings reject' {
        Reject {Definition $datedMapping} 'hash differs'
        if((Get-FileHash (Join-Path $root $manifest)).Hash.ToLowerInvariant() -cne $datedProposalHash){throw 'Dated author proposal was rewritten'}
    }
}
Case 'pending proposal definition returns only a planned hash and no authority or bytes' {
    $r=Definition (Clone)
    if(-not $r.definition_validated -or $r.planned_sha256 -cne '54481f4b2c760ef1f8efd747706a3e6eb02553f582e15210aaaab6ec72c448d8' -or
        $r.Contains('bytes') -or $r.source_emission -or -not $r.diagnostic_only -or $r.review_status -cne 'not-granted' -or
        $r.runtime_acceptance -or $r.coverage_authority){throw 'Definition-only validator gained source or approval authority'}
}
Case 'pending review cannot select source bytes' {Reject {Replay (Clone)} 'accepted source-only independent review'}
Case 'native original cannot select the locals equivalent' {Reject {Replay (Clone) $root ReferenceC} 'instrumented Ada'}
Case 'default configuration cannot select the locals equivalent' {Reject {Replay (Clone) $root Ada default} 'instrumented Ada'}
Case 'definition validator also rejects native applicability' {Reject {Definition (Clone) $root ReferenceC} 'instrumented Ada'}
Case 'definition validator also rejects default applicability' {Reject {Definition (Clone) $root Ada default} 'instrumented Ada'}
Case 'first private span cannot widen into original deletion' {$m=Clone;$m.replacements[0].length_bytes++;Reject {Definition $m} 'two exact retained operations'}
Case 'second private span cannot widen into the original refusal sweep' {$m=Clone;$m.replacements[1].length_bytes++;Reject {Definition $m} 'two exact retained operations'}
Case 'exact source offsets cannot move' {$m=Clone;$m.replacements[0].start_byte--;Reject {Definition $m} 'two exact retained operations'}
Case 'a third patch cannot replace another original operation' {$m=Clone;$m.replacements+=@($m.replacements[0]);Reject {Definition $m} 'widened or incomplete'}
Case 'replacement cannot add an early return' {$m=Clone;$m.replacements[0].replacement+='return';Reject {Definition $m} 'two exact retained operations'}
Case 'weak witness cannot become a strong reference' {$m=Clone;$m.replacements[0].replacement=$m.replacements[0].replacement.Replace("__mode = 'v'","__mode = 'k'");Reject {Definition $m} 'two exact retained operations'}
Case 'actual four-before count cannot be weakened' {$m=Clone;$m.replacements[0].replacement=$m.replacements[0].replacement.Replace('live == 4','live >= 0');Reject {Definition $m} 'two exact retained operations'}
Case 'actual zero-after count cannot be weakened' {$m=Clone;$m.replacements[1].replacement=$m.replacements[1].replacement.Replace('live == 0','live >= 0');Reject {Definition $m} 'two exact retained operations'}
Case 'live count must retain its explicit integer type check' {$m=Clone;$m.replacements[1].replacement=$m.replacements[1].replacement.Replace("math.type(live) == 'integer'","type(live) == 'number'");Reject {Definition $m} 'two exact retained operations'}
Case 'neither original anchor can become an exclusion' {$m=Clone;$m.source_exclusions=@('LUA-LOCALS-ASSERT-CALL-0023');Reject {Definition $m} 'widened or incomplete'}
Case 'both original anchors remain required' {$m=Clone;$m.original_required_obligations=@($m.original_required_obligations[0]);Reject {Definition $m} 'widened or incomplete'}
Case 'another source identity cannot inherit the local decision' {$m=Clone;$m.source='references/lua/testes/api.lua';Reject {Definition $m} 'widened or incomplete'}
Case 'stale pinned source hash is rejected' {$m=Clone;$m.source_sha256='0'*64;Reject {Definition $m} 'widened or incomplete'}
Case 'stale feature snapshot is rejected' {$m=Clone;$m.feature_review.sha256='0'*64;Reject {Definition $m} 'exact independent feature snapshot'}
Case 'stale planned output hash is rejected' {$m=Clone;$m.output_sha256='0'*64;Reject {Definition $m} 'planned output hash'}
Case 'counterpart path cannot disappear from a patch' {$m=Clone;$m.replacements[0].counterpart_tests=@($m.replacements[0].counterpart_tests|Where-Object{$_ -cne 'tests/lua/table_storage_public.lua'});Reject {Definition $m} 'counterpart set'}
Case 'counterpart source snapshot cannot omit a file' {$m=Clone;$m.counterpart_source_snapshot.bindings=@($m.counterpart_source_snapshot.bindings|Select-Object -Skip 1);Reject {Definition $m} 'snapshot is incomplete'}
Case 'stale counterpart hash is rejected' {$m=Clone;$m.counterpart_source_snapshot.bindings[0].sha256='0'*64;Reject {Definition $m} 'hash differs'}
Case 'changed actual checker source stales the snapshot' {
    $directory=Source-Fixture
    [IO.File]::AppendAllText((Join-Path $directory 'tests/src/lua-conformance_adapter.adb'),"-- negative stale checker fixture`n")
    Reject {Definition (Clone) $directory} 'hash differs'
}
Case 'changed actual engine source stales the snapshot' {
    $directory=Source-Fixture
    [IO.File]::AppendAllText((Join-Path $directory 'src/lua-engine.ads'),"-- negative stale owner fixture`n")
    Reject {Definition (Clone) $directory} 'hash differs'
}
Case 'original draft author cannot review the proposal' {$m=Clone;$m.review.status='accepted';$m.review.reviewer='Codex /root';Reject {Get-TargetLocalsTableEquivalentReplay -Root $root -Specification $m -Implementation Ada -Configuration upstream-test} 'outside both authors'}
Case 'revision author cannot review the proposal' {$m=Clone;$m.review.status='accepted';$m.review.reviewer='Codex /root/remaining_suite';Reject {Get-TargetLocalsTableEquivalentReplay -Root $root -Specification $m -Implementation Ada -Configuration upstream-test} 'outside both authors'}
Case 'draft authorship cannot be renamed away' {$m=Clone;$m.draft_provenance.author='unrelated';Reject {Definition $m} 'rename or hide'}
Case 'synthetic specification cannot select original source' {$m=Clone;$m.synthetic_fixture=$true;Reject {Definition $m} 'Synthetic locals metadata'}
Case 'synthetic approval cannot emit source' {$f=Synthetic-Review-Fixture;Reject {Get-TargetLocalsTableEquivalentReplay -Root $f.root -Specification $f.mapping -Implementation Ada -Configuration upstream-test} 'actual nonsynthetic'}
Case 'synthetic narrative cannot inherit an accepted parent label' {$f=Synthetic-Review-Fixture -Narrative;Reject {Get-TargetLocalsTableEquivalentReplay -Root $f.root -Specification $f.mapping -Implementation Ada -Configuration upstream-test} 'actual nonsynthetic'}
Case 'source-only proposal cannot grant runtime acceptance' {$m=Clone;$m.runtime_acceptance=$true;Reject {Definition $m} 'runtime authority'}
Case 'source-only proposal cannot grant coverage authority' {$m=Clone;$m.coverage_authority=$true;Reject {Definition $m} 'runtime authority'}
Case 'source-only proposal cannot invent execution evidence' {$m=Clone;$m.execution_evidence=@(@{status='passed'});Reject {Definition $m} 'empty execution evidence'}
Case 'unknown source-authority fields are rejected' {$m=Clone;$m['allow_unreviewed']=$true;Reject {Definition $m} 'widened or incomplete'}
Case 'pending generator writes no derived source' {
    $output=Join-Path $temporary 'not-emitted.lua'
    $p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',
        (Join-Path $PSScriptRoot 'New-ConformanceReviewedSource.ps1'),'-Manifest',(Join-Path $root $manifest),'-Output',$output) `
        -Directory $root -OutputPrefix (Join-Path $temporary 'pending-generator') -TimeoutSeconds 60
    if($p.exit_code -eq 0 -or (Test-Path -LiteralPath $output) -or
        [IO.File]::ReadAllText($p.stderr_path) -notmatch 'accepted source-only independent review'){
        throw 'Pending generator emitted source or failed for an unrelated reason'
    }
}
Case 'actual original reference bytes remain unchanged' {
    if((Get-FileHash (Join-Path $root $mapping.source)).Hash.ToLowerInvariant() -cne $originalHash -or
        $originalHash -cne '56b5126c40f48bb1a701f041af28cd72a3a7d50b3db9b05da5659f2485f740c1'){
        throw 'Definition tests modified the original guard, table, deletion, collection or refusal sweep'
    }
}
Write-Output "PASS: $script:cases locals source-definition/rejection and accepted-memory tests; no adapted Lua source emitted or executed"
