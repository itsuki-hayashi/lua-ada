param()
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/ConsumerEvidence.psm1" -Force
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/consumer-evidence-selftest/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$hash = 'a' * 64
$revision = 'b' * 40
$context = 'default/windows/validation/static'
$mapping = @{cases=@(@{source='case.c'; case_id='case'; source_sha256=$hash;
    consumer='c-api'; expected_count=1; exact_witnesses=@('case passed'); pattern_witness=$null})}
$markers = @{'c-api'="case passed`nPASS: real Ada C API bootstrap consumer`n";
    'gc-api'="PASS: public GC contract`n"; 'gc-oracle'="PASS: public GC contract`n";
    'io-api'="PASS: public IO/OS contract`n"; 'io-oracle'="PASS: public IO/OS contract`n"}
$records = @(foreach ($name in $markers.Keys) {
    $out = Join-Path $directory "$name.stdout"
    $err = Join-Path $directory "$name.stderr"
    [IO.File]::WriteAllText($out,$markers[$name])
    [IO.File]::WriteAllText($err,'')
    @{name=$name; stdout=$out; stderr=$err;
        stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();
        stderr_sha256=(Get-FileHash $err).Hash.ToLowerInvariant();
        exit_code=0; timed_out=$false; configuration='default'; profile='validation';
        library_type='static'; executable_sha256=$hash}
})
$baseline = @{repository_revision=$revision; repository_dirty=$false;
    platform='windows'; reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
    gc_contract=@{matching_output=$true; reference_library_files=@(@{sha256=$hash})};
    io_contract=@{matching_output=$true; reference_library_files=@(@{sha256=$hash})};
    configuration='default'; profile='validation'; library_type='static';
    library_files=@(@{file='liblua.a'; sha256=$hash}); consumers=$records;
    consumer_sources=@(@{file='case.c'; sha256=$hash})}
$resolve = {param($path,$expected)
    if ((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $expected) { throw 'capture hash mismatch' }
    return $path
}
$count = 0
function Run-Case([string]$Name,[scriptblock]$Mutation,[string]$Expected,[switch]$Foreign,[switch]$Format,[string[]]$Additional=@()) {
    $report = $baseline | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
    & $Mutation $report
    $failure = $null
    try { $null = Test-NamedConsumerEvidence $report $mapping $revision $context $resolve -RequireForeignContract:$Foreign -RequireFormatContract:$Format -AdditionalContracts $Additional }
    catch { $failure = $_.Exception.Message }
    if (($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))) {
        throw "$Name failed: $failure (expected $Expected)"
    }
    $script:count++
    Write-Output "CONSUMER EVIDENCE PASS: $Name"
}
Run-Case 'complete synthetic observations' {} ''
Run-Case 'dirty source tree' {param($r) $r.repository_dirty=$true} 'dirty'
Run-Case 'wrong revision' {param($r) $r.repository_revision='c'*40} 'revision'
Run-Case 'wrong configuration' {param($r) $r.configuration='upstream-test'} 'context'
Run-Case 'wrong profile' {param($r) $r.profile='release'} 'context'
Run-Case 'wrong platform' {param($r) $r.platform='linux'} 'context'
Run-Case 'wrong oracle pin' {param($r) $r.reference_revision='c'*40} 'oracle provenance'
Run-Case 'missing oracle library' {param($r) $r.gc_contract.reference_library_files=@()} 'oracle provenance'
Run-Case 'wrong library type' {param($r) $r.library_type='relocatable'} 'context'
Run-Case 'missing library' {param($r) $r.library_files=@()} 'library identity'
Run-Case 'missing consumer' {param($r) $r.consumers=@($r.consumers | Where-Object name -ne 'c-api')} 'missing/duplicate'
Run-Case 'duplicate consumer' {param($r) $r.consumers+=@($r.consumers | Where-Object name -eq 'c-api')} 'missing/duplicate'
Run-Case 'timeout' {param($r) $r.consumers[0].timed_out=$true} 'process failed'
Run-Case 'failed child' {param($r) $r.consumers[0].exit_code=1} 'process failed'
Run-Case 'stale capture hash' {param($r) $r.consumers[0].stdout_sha256='f'*64} 'capture hash'
Run-Case 'stale source' {param($r) $r.consumer_sources[0].sha256='f'*64} 'source differs'
Run-Case 'missing source' {param($r) $r.consumer_sources=@()} 'source differs'
function Replace-Capture($Report, $Name, $Stream, $Text) {
    $record = @($Report.consumers | Where-Object name -eq $Name)[0]
    $path = Join-Path $directory ([guid]::NewGuid().ToString('N') + ".$Stream")
    [IO.File]::WriteAllText($path,$Text)
    $record[$Stream] = $path
    $record["${Stream}_sha256"] = (Get-FileHash $path).Hash.ToLowerInvariant()
}
Run-Case 'nonempty rehashed stderr' {param($r)
    Replace-Capture $r 'c-api' 'stderr' 'unexpected warning'
} 'consumer stderr'
Run-Case 'duplicate actual case output' {param($r)
    Replace-Capture $r 'c-api' 'stdout' ("case passed`n" + $markers['c-api'])
} 'witness missing/duplicate'
Run-Case 'different rehashed oracle output' {param($r)
    Replace-Capture $r 'gc-oracle' 'stdout' ("different observation`n" + $markers['gc-oracle'])
} 'oracle bytes differ'
Run-Case 'duplicate completion marker' {param($r)
    Replace-Capture $r 'io-api' 'stdout' ($markers['io-api'] + $markers['io-api'])
} 'completion missing/duplicate'
$context='default/windows/validation/shared'
Run-Case 'shared context uses relocatable build' {param($r)
    $r.library_type='relocatable'; foreach($child in $r.consumers){$child.library_type='relocatable'}
} ''
$context='default/windows/validation/static'
$mapping.cases[0].exact_witnesses=@('missing case')
Run-Case 'missing named case' {} 'witness missing'
$mapping.cases[0].exact_witnesses=@('case passed')
$mapping.cases+=@($mapping.cases[0])
Run-Case 'duplicate mapped case' {} 'duplicate named'
$mapping.cases=@($mapping.cases[0])
$mapping.cases+=@{source='foreign.c'; case_id='foreign-case'; source_sha256=$hash;
    consumer='foreign-api'; expected_count=1; exact_witnesses=@('foreign case passed'); pattern_witness=$null}
$baseline.consumer_sources+=@{file='foreign.c';sha256=$hash}
$baseline.foreign_contract=@{matching_output=$true; reference_library_files=@(@{sha256=$hash})}
foreach($name in @('foreign-api','foreign-oracle')) {
    $record=$records[0].Clone()
    $record.name=$name
    $out=Join-Path $directory "$name.stdout"
    [IO.File]::WriteAllText($out,"foreign case passed`nPASS: public foreign contract`n")
    $record.stdout=$out
    $record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant()
    $baseline.consumers+=$record
}
Run-Case 'expanded foreign case and matching native process required' {} '' -Foreign
Run-Case 'expanded foreign oracle cannot be absent' {param($r)
    $r.consumers=@($r.consumers | Where-Object name -CNE 'foreign-oracle')
} 'missing/duplicate' -Foreign
Run-Case 'expanded foreign metadata must identify original C runtime' {param($r)
    $r.foreign_contract.reference_library_files=@()
} 'oracle provenance' -Foreign
Run-Case 'expanded foreign captures must actually agree' {param($r)
    Replace-Capture $r 'foreign-oracle' stdout "different case result`nPASS: public foreign contract`n"
} 'oracle bytes differ' -Foreign
Run-Case 'expanded foreign named case cannot disappear behind completion' {param($r)
    Replace-Capture $r 'foreign-api' stdout "PASS: public foreign contract`n"
    Replace-Capture $r 'foreign-oracle' stdout "PASS: public foreign contract`n"
} 'witness missing' -Foreign
$mapping.cases+=@{source='format.c';case_id='format-case';source_sha256=$hash;consumer='format-api';
    expected_count=1;exact_witnesses=@('format-api-1: synthetic formatting case');pattern_witness=$null}
$baseline.consumer_sources+=@{file='format.c';sha256=$hash}
$baseline.format_contract=@{matching_output=$true;reference_library_files=@(@{sha256=$hash})}
foreach($name in @('format-api','format-oracle')){
    $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout"
    [IO.File]::WriteAllText($out,"format-api-1: synthetic formatting case`nPASS: public formatting contract`n")
    $record.stdout=$out;$record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
}
Run-Case 'target formatting requires named actual counterpart observations' {} '' -Foreign -Format
Run-Case 'target formatter cannot lose its C oracle' {param($r)
    $r.consumers=@($r.consumers|Where-Object name -CNE format-oracle)
} 'missing/duplicate' -Foreign -Format
Run-Case 'target formatter output must equal the C counterpart bytes' {param($r)
    Replace-Capture $r format-oracle stdout "wrong observation`nPASS: public formatting contract`n"
} 'oracle bytes differ' -Foreign -Format
Run-Case 'target formatter completion alone is not its named case evidence' {param($r)
    Replace-Capture $r format-api stdout "PASS: public formatting contract`n"
    Replace-Capture $r format-oracle stdout "PASS: public formatting contract`n"
} 'witness missing' -Foreign -Format
foreach($kind in @('value','auxiliary')){
    $completion=if($kind -ceq 'value'){'PASS: public value operation contract'}else{'PASS: public auxiliary contract'}
    $mapping.cases+=@{source="$kind.c";case_id="$kind-case";source_sha256=$hash;consumer="$kind-api";
        expected_count=1;exact_witnesses=@("$kind actual case");pattern_witness=$null}
    $baseline.consumer_sources+=@{file="$kind.c";sha256=$hash}
    $baseline["${kind}_contract"]=@{matching_output=$true;reference_library_files=@(@{sha256=$hash})}
    foreach($name in @("$kind-api","$kind-oracle")){
        $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout"
        $numbers=if($kind -ceq 'value'){"value-number-0: native spelling`nvalue-number-1: another native spelling`n"}else{''}
        [IO.File]::WriteAllText($out,($numbers+"$kind actual case`n$completion`n"))
        $record.stdout=$out;$record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
    }
}
$valueCase=@($mapping.cases|Where-Object consumer -CEQ value-api)[0]
$valueCase.ordered_witness_patterns=@('^value-number-0: [^\r\n]+\r?$','^value-number-1: [^\r\n]+\r?$','^value actual case\r?$')
Run-Case 'target value and auxiliary cases require identical actual native counterpart captures' {} '' -Foreign -Format -Additional value,auxiliary
Run-Case 'target auxiliary cannot lose its C oracle' {param($r)
    $r.consumers=@($r.consumers|Where-Object name -CNE auxiliary-oracle)
} 'missing/duplicate' -Foreign -Format -Additional value,auxiliary
Run-Case 'target value cannot replace a seeded result with another native result' {param($r)
    Replace-Capture $r value-oracle stdout "changed native value`nPASS: public value operation contract`n"
} 'oracle bytes differ' -Foreign -Format -Additional value,auxiliary
Run-Case 'target auxiliary case assertions cannot disappear behind matching completion lines' {param($r)
    Replace-Capture $r auxiliary-api stdout "PASS: public auxiliary contract`n"
    Replace-Capture $r auxiliary-oracle stdout "PASS: public auxiliary contract`n"
} 'witness missing' -Foreign -Format -Additional value,auxiliary
Run-Case 'target indexed number records cannot be omitted behind equal case markers' {param($r)
    foreach($name in @('value-api','value-oracle')){Replace-Capture $r $name stdout "value-number-0: native spelling`nvalue actual case`nPASS: public value operation contract`n"}
} 'ordered witness' -Foreign -Format -Additional value,auxiliary
Run-Case 'target indexed number records cannot be duplicated in both equal outputs' {param($r)
    foreach($name in @('value-api','value-oracle')){Replace-Capture $r $name stdout "value-number-0: native spelling`nvalue-number-0: native spelling`nvalue-number-1: another native spelling`nvalue actual case`nPASS: public value operation contract`n"}
} 'ordered witness' -Foreign -Format -Additional value,auxiliary
Run-Case 'target indexed number records retain their source order in both equal outputs' {param($r)
    foreach($name in @('value-api','value-oracle')){Replace-Capture $r $name stdout "value-number-1: another native spelling`nvalue-number-0: native spelling`nvalue actual case`nPASS: public value operation contract`n"}
} 'ordered witness' -Foreign -Format -Additional value,auxiliary
$extended=@('value','auxiliary','load-dump','debug','conversion','operator','index-type')
$completions=@{'load-dump'='PASS: public reader/writer contract';debug='PASS: public debug contract';conversion='PASS: public numeric conversion contract';
    operator='PASS: public C operator contract';'index-type'='PASS: public integer-index and type contract'}
foreach($kind in $completions.Keys){
    $mapping.cases+=@{source="$kind.c";case_id="$kind-case";source_sha256=$hash;consumer="$kind-api";
        expected_count=1;exact_witnesses=@("$kind actual case");pattern_witness=$null}
    $baseline.consumer_sources+=@{file="$kind.c";sha256=$hash}
    $baseline[$kind.Replace('-','_')+'_contract']=@{matching_output=$true;reference_library_files=@(@{sha256=$hash})}
    foreach($name in @("$kind-api","$kind-oracle")){
        $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout"
        [IO.File]::WriteAllText($out,("$kind actual case`n"+$completions[$kind]+"`n"))
        $record.stdout=$out;$record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
    }
}
Run-Case 'current reader debug conversion operator and integer-index contracts keep their own native comparisons' {} '' -Foreign -Format -Additional $extended
Run-Case 'new integer-index completion cannot replace a missing actual C process' {param($r)
    $r.consumers=@($r.consumers|Where-Object name -CNE index-type-oracle)
} 'missing/duplicate' -Foreign -Format -Additional $extended
Run-Case 'reader driver oracle bytes cannot be borrowed from another source contract' {param($r)
    Replace-Capture $r load-dump-oracle stdout "different reader results`nPASS: public reader/writer contract`n"
} 'oracle bytes differ' -Foreign -Format -Additional $extended
$externalNames=@('ordinary-short-identity','short-lookup-refusal','empty-buffer','short-buffer','long-buffer','embedded-zero','borrowed-buffer',
    'short-key-normalization','long-key-retention','existing-key-update','weak-value-string','allocation-refusal-recovery','state-close-lifetime',
    'callback-lua-reentry','callback-nested-collection','callback-interrupted-frame','callback-closure-lifetime','callback-close-reentry')
$externalFull=(@($externalNames|ForEach-Object{'PASS: external-'+$_}) -join "`n")+"`nPASS: public external string contract`n"
$externalOwned=(@($externalNames[0..12]|ForEach-Object{'PASS: external-'+$_}) -join "`n")+"`nSKIP: 5 release reentry cases (instrumented C lock rejects reentry)`nPASS: public external string contract`n"
$mapping.cases+=@{source='external.c';case_id='external-common';source_sha256=$hash;consumer='external-api';
    expected_count=1;exact_witnesses=@('PASS: external-empty-buffer');pattern_witness=$null}
$baseline.consumer_sources+=@{file='external.c';sha256=$hash}
$baseline.external_contract=@{matching_output=$true;reference_library_files=@(@{sha256=$hash});matched_cases=18;skipped_reentry_cases=0}
foreach($name in @('external-api','external-oracle')){
    $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout";[IO.File]::WriteAllText($out,$externalFull)
    $record.arguments=@();$record.stdout=$out;$record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
}
$extended+='external'
Run-Case 'default external string mode retains all five actual release-reentry witnesses' {} '' -Foreign -Format -Additional $extended
Run-Case 'default external mode cannot borrow the instrumented ownership-only argument vector' {param($r)
    foreach($name in @('external-api','external-oracle')){@($r.consumers|Where-Object name -CEQ $name)[0].arguments=@('--ownership-only')}
} 'actual arguments or case set' -Foreign -Format -Additional $extended
Run-Case 'a summary count cannot replace a missing default release-reentry witness' {param($r)
    foreach($name in @('external-api','external-oracle')){Replace-Capture $r $name stdout ($externalFull.Replace('PASS: external-callback-close-reentry','PASS: external-invented-case'))}
} 'actual release-reentry witnesses' -Foreign -Format -Additional $extended
$context='upstream-test/windows/validation/static'
Run-Case 'instrumented external mode records its exact native lock omission without inventing five passes' {param($r)
    $r.configuration='upstream-test';foreach($record in $r.consumers){$record.configuration='upstream-test'}
    $r.external_contract.matched_cases=13;$r.external_contract.skipped_reentry_cases=5
    foreach($name in @('external-api','external-oracle')){
        @($r.consumers|Where-Object name -CEQ $name)[0].arguments=@('--ownership-only')
        Replace-Capture $r $name stdout $externalOwned
    }
} '' -Foreign -Format -Additional $extended
$context='default/windows/validation/static'
$nativeNames=@('loadlib-missing-open-stage3values','loadlib-cached-missing-symbol-init-then-lookup','lib1-lib11-native-exports',
    'croot-lib1-sub-args-globals','hyphen-lib2-v2-loader-data','lib2-lib21-global-dependency','gc-retained-native-callback',
    'registry-lib22-external-string','explicit-lib2-newstr-external')
$nativeFull=(@($nativeNames|ForEach-Object{'PASS: native-module-'+$_}) -join "`n")+"`n"
$baseline.native_module_contract=@{matching_output=$true;reference_library_files=@(@{sha256=$hash});matched_cases=9;
    ada_fixture_directory='C:/synthetic/ada/libs';c_fixture_directory='C:/synthetic/c/libs'}
foreach($name in @('native-module-api','native-module-oracle')){
    $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout";[IO.File]::WriteAllText($out,$nativeFull)
    $record.arguments=@($(if($name -ceq 'native-module-api'){'C:/synthetic/ada/libs'}else{'C:/synthetic/c/libs'}))
    $record.stdout=$out;$record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
}
$extended+='native-module'
Run-Case 'native lifetime protocol retains nine ordered cases and exact separate fixture arguments' {} '' -Foreign -Format -Additional $extended
Run-Case 'native lifetime protocol cannot lose its actual C counterpart process' {param($r)
    $r.consumers=@($r.consumers|Where-Object name -CNE native-module-oracle)
} 'missing/duplicate' -Foreign -Format -Additional $extended
Run-Case 'matching counts and bytes cannot replace the retained native finalizer lifetime case' {param($r)
    foreach($name in @('native-module-api','native-module-oracle')){
        Replace-Capture $r $name stdout ($nativeFull.Replace('native-module-gc-retained-native-callback','native-module-invented-case'))
    }
} 'complete ordered lifetime protocol' -Foreign -Format -Additional $extended
Run-Case 'duplicate native lifetime records cannot hide behind the final case marker' {param($r)
    foreach($name in @('native-module-api','native-module-oracle')){Replace-Capture $r $name stdout ("PASS: native-module-lib1-lib11-native-exports`n"+$nativeFull)}
} 'complete ordered lifetime protocol' -Foreign -Format -Additional $extended
Run-Case 'native lifetime process cannot reuse another fixture directory or omit its argument' {param($r)
    @($r.consumers|Where-Object name -CEQ native-module-api)[0].arguments=@('C:/synthetic/c/libs')
} 'fixture argument' -Foreign -Format -Additional $extended
Run-Case 'native lifetime summary count must be the actual integer nine' {param($r)
    $r.native_module_contract.matched_cases='9'
} 'all nine actual lifetime cases' -Foreign -Format -Additional $extended
$bufferNames=@('empty-result','fixed-binary-nul','zero-null-add','addstring-terminator','direct-prep-addsize','buffinitsize-small','buffinitsize-heap',
    'addvalue-growth-gc','large-growth-prefix','buffsub-addchar','nested-buffers','callback-result','callback-error-closes','abandoned-closeslot',
    'fault-sweep-growth','pushresult-header-refusal','captured-deallocator-pair')
$bufferFull=(@($bufferNames|ForEach-Object{'PASS: buffer-'+$_}) -join "`n")+"`nPASS: public luaL_Buffer contract`n"
$baseline.buffer_contract=@{matching_output=$true;reference_library_files=@(@{sha256=$hash});matched_cases=17}
foreach($name in @('buffer-api','buffer-oracle')){
    $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout";[IO.File]::WriteAllText($out,$bufferFull)
    $record.arguments=@();$record.stdout=$out;$record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
}
$extended+='buffer'
Run-Case 'buffer contract requires all seventeen actual ordered ownership cases and its C counterpart' {} '' -Foreign -Format -Additional $extended
Run-Case 'buffer ownership contract cannot lose the actual native process' {param($r)
    $r.consumers=@($r.consumers|Where-Object name -CNE buffer-oracle)
} 'missing/duplicate' -Foreign -Format -Additional $extended
Run-Case 'buffer count and final completion cannot replace the captured allocator case' {param($r)
    foreach($name in @('buffer-api','buffer-oracle')){Replace-Capture $r $name stdout ($bufferFull.Replace('PASS: buffer-captured-deallocator-pair','PASS: buffer-invented-case'))}
} 'complete ordered ownership protocol' -Foreign -Format -Additional $extended
Run-Case 'buffer contract rejects an unreviewed mode argument and string summary count' {param($r)
    @($r.consumers|Where-Object name -CEQ buffer-api)[0].arguments=@('--skip-refusal')
} 'actual arguments' -Foreign -Format -Additional $extended
Run-Case 'buffer case summary must remain the actual integer seventeen' {param($r)
    $r.buffer_contract.matched_cases='17'
} 'seventeen actual cases' -Foreign -Format -Additional $extended
$allocatorNames=@('null-block-ignores-old-size','zero-size-frees-and-returns-null','grow-preserves-prefix','shrink-preserves-prefix',
    'fresh-allocation-after-free','numeric-userdata-alignment','huge-refusal-preserves-old-block','public-allocator-identity-and-use',
    'default-state-allocator-identity','makeseed-live-state-is-inert','makeseed-accepts-null','counted-state-closes-balanced','close-with-live-stack-balances')
$substitutionNames=@('literal-metachars','nonoverlap-matches','replacement-not-rescanned','shrinking-replacement','growing-replacement',
    'empty-replacement','no-match','empty-subject','prefix-suffix','embedded-nul-subject','embedded-nul-pattern','buffer-append-reuse',
    'large-growth-prefix','callback-result','callback-error-cleanup','allocator-refusal-recovery')
$newProtocols=@{}
foreach($kind in @('allocator','substitution')){
    $names=if($kind -ceq 'allocator'){$allocatorNames}else{$substitutionNames}
    $completion=if($kind -ceq 'allocator'){'PASS: public allocator contract'}else{'PASS: public luaL_addgsub and luaL_gsub contract'}
    $newProtocols[$kind]=(@(for($i=0;$i -lt $names.Count;$i++){
        if($kind -ceq 'allocator'){"PASS: allocator-api-$i $($names[$i])"}else{'PASS: substitution-'+$names[$i]}
    }) -join "`n")+"`n$completion`n"
    $baseline[$kind+'_contract']=@{matching_output=$true;reference_library_files=@(@{sha256=$hash});matched_cases=$names.Count}
    foreach($name in @("$kind-api","$kind-oracle")){
        $record=$records[0].Clone();$record.name=$name;$out=Join-Path $directory "$name.stdout"
        [IO.File]::WriteAllText($out,$newProtocols[$kind]);$record.arguments=@();$record.stdout=$out
        $record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$baseline.consumers+=$record
    }
}
$baseline.allocator_contract.panic_modes=@('string','number')
$panicSource='c_api/tests/allocator_api_contract.c'
$baseline.consumer_sources+=@{file=$panicSource;sha256=$hash}
foreach($mode in @('string','number')){
    $message=if($mode -ceq 'string'){'allocator panic witness'}else{'error object is not a string'}
    $line="PANIC: unprotected error in call to Lua API ($message)"
    $mapping.cases+=@{source=$panicSource;case_id="installed-panic-$mode";source_sha256=$hash;
        consumer="allocator-panic-$mode-api";witness_stream='stderr';expected_count=1;exact_witnesses=@($line);pattern_witness=$null}
    foreach($implementation in @('api','oracle')){
        $name="allocator-panic-$mode-$implementation";$record=$records[0].Clone();$record.name=$name
        $out=Join-Path $directory "$name.stdout";$err=Join-Path $directory "$name.stderr"
        [IO.File]::WriteAllText($out,'');[IO.File]::WriteAllText($err,$line+"`n")
        $record.arguments=@("--panic-$mode");$record.stdout=$out;$record.stderr=$err
        $record.stdout_sha256=(Get-FileHash $out).Hash.ToLowerInvariant();$record.stderr_sha256=(Get-FileHash $err).Hash.ToLowerInvariant()
        $baseline.consumers+=$record
    }
}
$extended+=@('allocator','substitution')
Run-Case 'allocator thirteen substitution sixteen and separate installed panic children retain exact paired protocols' {} '' -Foreign -Format -Additional $extended
Run-Case 'matching allocator output cannot replace default constructor identity' {param($r)
    foreach($name in @('allocator-api','allocator-oracle')){Replace-Capture $r $name stdout ($newProtocols.allocator.Replace('default-state-allocator-identity','invented-identity'))}
} 'complete ordered protocol' -Foreign -Format -Additional $extended
Run-Case 'matching substitution output cannot omit a literal case behind its final marker' {param($r)
    foreach($name in @('substitution-api','substitution-oracle')){Replace-Capture $r $name stdout ($newProtocols.substitution.Replace("PASS: substitution-embedded-nul-pattern`n",''))}
} 'complete ordered protocol' -Foreign -Format -Additional $extended
Run-Case 'installed panic requires its actual native counterpart process' {param($r)
    $r.consumers=@($r.consumers|Where-Object name -CNE allocator-panic-string-oracle)
} 'panic consumer missing' -Foreign -Format -Additional $extended
Run-Case 'installed panic actual numeric mode cannot silently reuse string mode' {param($r)
    @($r.consumers|Where-Object name -CEQ allocator-panic-number-api)[0].arguments=@('--panic-string')
} 'actual argument differs' -Foreign -Format -Additional $extended
Run-Case 'both matching panic captures cannot substitute a success marker for exact diagnostic' {param($r)
    foreach($name in @('allocator-panic-string-api','allocator-panic-string-oracle')){Replace-Capture $r $name stderr "PASS: panic observed`n"}
} 'exact stderr' -Foreign -Format -Additional $extended
Run-Case 'panic exception does not permit output on stdout' {param($r)
    Replace-Capture $r allocator-panic-number-api stdout "unreviewed output`n"
} 'empty stdout' -Foreign -Format -Additional $extended
Run-Case 'panic stderr allowance does not weaken regular allocator empty stderr' {param($r)
    Replace-Capture $r allocator-api stderr "PANIC: unprotected error in call to Lua API (allocator panic witness)`n"
} 'consumer stderr' -Foreign -Format -Additional $extended
$panicCase=@($mapping.cases|Where-Object case_id -CEQ installed-panic-string)[0]
$panicCase.witness_stream='stdout'
Run-Case 'panic mapping cannot treat diagnostic as a stdout success witness' {} 'witness stream' -Foreign -Format -Additional $extended
$panicCase.witness_stream='stderr'
$mapping.cases[0].witness_stream='stderr'
Run-Case 'ordinary witness cannot borrow the narrowly named panic stderr protocol' {} 'witness stream' -Foreign -Format -Additional $extended
$mapping.cases[0].Remove('witness_stream')
Write-Output "PASS: $count named consumer evidence regressions; synthetic observations only"
