Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FileConsumerIO.psm1')
Import-Module (Join-Path $PSScriptRoot 'SdkMacroEvidence.psm1')

function Test-NamedConsumerEvidence {
    param([Collections.IDictionary] $Report,
          [Collections.IDictionary] $Mapping,
          [string] $Revision, [string] $Context,
          [scriptblock] $ResolveCapture,
          [switch] $RequireForeignContract,
          [switch] $RequireFormatContract,
          [ValidateSet('format','value','auxiliary','load-dump','debug','external','conversion','operator','index-type','base-closing','native-module','buffer','allocator','substitution','loadfile','pointer-identity','concat','thread-reset','macro','macro-compat')]
          [string[]] $AdditionalContracts=@(),
          [ValidateSet('','remaining-upstream-compatibility')][string] $TargetPolicy='')
    # This replay checks actual observations, not review authority. Its caller
    # must bind the mapping and report to independently reviewed artifacts.
    $parts = $Context.Split('/')
    $libraryType = if ($parts.Count -eq 4 -and $parts[3] -eq 'shared') { 'relocatable' } elseif ($parts.Count -eq 4) { $parts[3] } else { '' }
    if ($parts.Count -ne 4 -or $Report.repository_revision -cne $Revision -or
        $Report.repository_dirty -ne $false -or
        $Report.configuration -cne $parts[0] -or
        $Report.platform -cne $parts[1] -or
        $Report.profile -cne $parts[2] -or $Report.library_type -cne $libraryType) {
        throw 'Named consumer context/revision differs or is dirty'
    }
    if (@($Report.library_files).Count -eq 0) { throw 'Named consumer library identity missing' }
    foreach ($library in $Report.library_files) {
        if ($library.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Named consumer library hash invalid' }
    }
    $outputs = @{}
    $markers = @{'c-api'='PASS: real Ada C API bootstrap consumer';
        'gc-api'='PASS: public GC contract'; 'io-api'='PASS: public IO/OS contract';
        'gc-oracle'='PASS: public GC contract'; 'io-oracle'='PASS: public IO/OS contract'}
    $contractKinds = @('gc','io')
    $consumerKinds = @('c-api','gc-api','io-api')
    if ($RequireForeignContract) {
        $markers['foreign-api']='PASS: public foreign contract'
        $markers['foreign-oracle']='PASS: public foreign contract'
        $contractKinds += 'foreign'
        $consumerKinds += 'foreign-api'
    }
    $additional=@($AdditionalContracts)
    if($RequireFormatContract){$additional+='format'}
    $additionalMarkers=@{format='PASS: public formatting contract';value='PASS: public value operation contract';auxiliary='PASS: public auxiliary contract';
        'load-dump'='PASS: public reader/writer contract';debug='PASS: public debug contract';external='PASS: public external string contract';
        conversion='PASS: public numeric conversion contract';operator='PASS: public C operator contract';'index-type'='PASS: public integer-index and type contract';
        'base-closing'='PASS: public host base C closing contract';'native-module'='PASS: native-module-explicit-lib2-newstr-external';buffer='PASS: public luaL_Buffer contract';
        allocator='PASS: public allocator contract';substitution='PASS: public luaL_addgsub and luaL_gsub contract';loadfile='PASS: public luaL_loadfilex contract';
        'pointer-identity'='PASS: public pointer identity contract';concat='PASS: public lua_concat contract';
        'thread-reset'='PASS: public thread reset/base closing contract';macro='PASS: public SDK macro contract';'macro-compat'='PASS: public SDK macro contract'}
    foreach($kind in $additional|Sort-Object -Unique){
        $markers["$kind-api"]=$additionalMarkers[$kind];$markers["$kind-oracle"]=$additionalMarkers[$kind]
        $contractKinds+=$kind;$consumerKinds+="$kind-api"
    }
    foreach ($name in $markers.Keys) {
        $matches = @($Report.consumers | Where-Object { $_.name -ceq $name })
        if ($matches.Count -ne 1) { throw "Named consumer missing/duplicate: $name" }
        $record = $matches[0]
        if ($record.exit_code -ne 0 -or $record.timed_out -ne $false -or
            $record.configuration -cne $parts[0] -or $record.profile -cne $parts[2] -or
            $record.library_type -cne $libraryType -or
            $record.executable_sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Named consumer process failed or differs: $name"
        }
        $outPath = & $ResolveCapture $record.stdout $record.stdout_sha256
        $errPath = & $ResolveCapture $record.stderr $record.stderr_sha256
        if ((Get-Item -LiteralPath $errPath).Length -ne 0) { throw "Named consumer stderr: $name" }
        $stdout = [IO.File]::ReadAllText($outPath)
        if ([regex]::Matches($stdout, '(?m)^' + [regex]::Escape($markers[$name]) + '\r?$').Count -ne 1) {
            throw "Named consumer completion missing/duplicate: $name"
        }
        $outputs[$name] = @{text=$stdout; hash=$record.stdout_sha256}
    }
    foreach ($kind in $contractKinds) {
        $contract = $Report[$kind.Replace('-','_')+'_contract']
        if ($Report.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
            $null -eq $contract -or $contract.matching_output -ne $true -or
            @($contract.reference_library_files).Count -eq 0) {
            throw 'Named consumer oracle provenance missing'
        }
        foreach ($library in $contract.reference_library_files) {
            if ($library.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Named consumer oracle library hash invalid' }
        }
        if ($outputs["$kind-api"].hash -cne $outputs["$kind-oracle"].hash) {
            throw "Named consumer oracle bytes differ: $kind"
        }
    }
    if('external' -cin $additional){
        # The five release-callback reentry cases are deliberately absent
        # only in the instrumented C-lock mode. Bind the actual argument
        # vector, complete emitted case set and measured omission marker so
        # default coverage cannot quietly reuse the ownership-only process.
        $instrumented=$parts[0] -ceq 'upstream-test'
        $expectedArguments=if($instrumented){'--ownership-only'}else{''}
        $expectedCount=if($instrumented){13}else{18}
        $skipped=if($instrumented){5}else{0}
        $external=$Report.external_contract
        if(($external.matched_cases -isnot [int] -and $external.matched_cases -isnot [long]) -or
            ($external.skipped_reentry_cases -isnot [int] -and $external.skipped_reentry_cases -isnot [long]) -or
            $external.matched_cases -ne $expectedCount -or $external.skipped_reentry_cases -ne $skipped){
            throw 'Named external consumer mode case counts differ'
        }
        foreach($name in @('external-api','external-oracle')){
            $record=@($Report.consumers|Where-Object name -CEQ $name)[0]
            if(-not $record.Contains('arguments') -or $record.arguments -isnot [Array] -or
                (@($record.arguments)-join '|') -cne $expectedArguments -or
                [regex]::Matches($outputs[$name].text,'(?m)^PASS: external-[a-z0-9-]+\r?$').Count -ne $expectedCount){
                throw 'Named external consumer actual arguments or case set differs'
            }
            $skipLine='SKIP: 5 release reentry cases (instrumented C lock rejects reentry)'
            if([regex]::Matches($outputs[$name].text,'(?m)^'+[regex]::Escape($skipLine)+'\r?$').Count -ne [int]$instrumented){
                throw 'Named external consumer actual native-lock omission differs'
            }
            foreach($caseName in @('callback-lua-reentry','callback-nested-collection','callback-interrupted-frame',
                'callback-closure-lifetime','callback-close-reentry')){
                if([regex]::Matches($outputs[$name].text,'(?m)^PASS: external-'+$caseName+'\r?$').Count -ne [int](-not $instrumented)){
                    throw 'Named external consumer actual release-reentry witnesses differ'
                }
            }
        }
    }
    if('native-module' -cin $additional){
        $names=@('loadlib-missing-open-stage3values','loadlib-cached-missing-symbol-init-then-lookup','lib1-lib11-native-exports',
            'croot-lib1-sub-args-globals','hyphen-lib2-v2-loader-data','lib2-lib21-global-dependency','gc-retained-native-callback',
            'registry-lib22-external-string','explicit-lib2-newstr-external')
        $expected=(@($names|ForEach-Object{'PASS: native-module-'+$_}) -join "`n")+"`n"
        $contract=$Report.native_module_contract
        if(($contract.matched_cases -isnot [int] -and $contract.matched_cases -isnot [long]) -or $contract.matched_cases -ne 9){
            throw 'Named native module driver requires all nine actual lifetime cases'
        }
        foreach($implementation in @('ada','c')){
            $name=if($implementation -ceq 'ada'){'native-module-api'}else{'native-module-oracle'}
            $record=@($Report.consumers|Where-Object name -CEQ $name)[0]
            $directory=$contract[$implementation+'_fixture_directory']
            if([string]::IsNullOrWhiteSpace([string]$directory) -or $record.arguments -isnot [Array] -or @($record.arguments).Count -ne 1 -or
                $record.arguments[0].Replace('\','/') -cne $directory.Replace('\','/') -or
                $outputs[$name].text.Replace("`r`n","`n") -cne $expected){
                throw 'Named native module actual fixture argument or complete ordered lifetime protocol differs'
            }
        }
    }
    if('buffer' -cin $additional){
        $names=@('empty-result','fixed-binary-nul','zero-null-add','addstring-terminator','direct-prep-addsize','buffinitsize-small',
            'buffinitsize-heap','addvalue-growth-gc','large-growth-prefix','buffsub-addchar','nested-buffers','callback-result',
            'callback-error-closes','abandoned-closeslot','fault-sweep-growth','pushresult-header-refusal','captured-deallocator-pair')
        $expected=(@($names|ForEach-Object{'PASS: buffer-'+$_}) -join "`n")+"`nPASS: public luaL_Buffer contract`n"
        if(($Report.buffer_contract.matched_cases -isnot [int] -and $Report.buffer_contract.matched_cases -isnot [long]) -or
            $Report.buffer_contract.matched_cases -ne 17){throw 'Named buffer contract requires seventeen actual cases'}
        foreach($name in @('buffer-api','buffer-oracle')){
            $record=@($Report.consumers|Where-Object name -CEQ $name)[0]
            if($record.arguments -isnot [Array] -or $record.arguments.Count -ne 0 -or $outputs[$name].text.Replace("`r`n","`n") -cne $expected){
                throw 'Named buffer actual arguments or complete ordered ownership protocol differ'
            }
        }
    }
    foreach($kind in @('allocator','substitution','loadfile','pointer-identity','concat')){if($kind -cin $additional){
        $names=if($kind -ceq 'allocator'){
            @('null-block-ignores-old-size','zero-size-frees-and-returns-null','grow-preserves-prefix','shrink-preserves-prefix',
                'fresh-allocation-after-free','numeric-userdata-alignment','huge-refusal-preserves-old-block','public-allocator-identity-and-use',
                'default-state-allocator-identity','makeseed-live-state-is-inert','makeseed-accepts-null','counted-state-closes-balanced','close-with-live-stack-balances')
        }elseif($kind -ceq 'substitution'){
            @('literal-metachars','nonoverlap-matches','replacement-not-rescanned','shrinking-replacement','growing-replacement',
                'empty-replacement','no-match','empty-subject','prefix-suffix','embedded-nul-subject','embedded-nul-pattern',
                'buffer-append-reuse','large-growth-prefix','callback-result','callback-error-cleanup','allocator-refusal-recovery')
        }elseif($kind -ceq 'loadfile'){
            @('empty-file-no-results','bom-skipped','shebang-line-numbers','crlf-line-numbers','incomplete-bom-syntax','syntax-error-class',
                'text-mode-rejects-binary','binary-mode-rejects-text','dump-file-loads-runs','stripped-dump-no-source','source-info-matches-file',
                'missing-file-errno','filename-nul-suffix','success-keeps-stack','missing-keeps-stack','syntax-failure-keeps-stack','protected-callback',
                'persistent-refusal-recovers','prefixed-binary-alignment','actual-file-growth-sweep','shebang-lone-CR')
        }elseif($kind -ceq 'pointer-identity'){
            @('table-identity','full-userdata-identity','light-userdata-identity','null-light-userdata-identity',
                'light-cfunction-identity','captured-closure-identity','coroutine-identity','raw-string-identity')
        }else{
            @('caller-mutation','weak-operand-lifetime','retained-prefix','error-location','current-pair-roots','primitive-suffix',
                'numeric-primitives','empty-result','singleton-identity','empty-right-refusal','empty-left-refusal','external-empty-copy',
                'handler-error-identity','nonyieldable-handler','external-empty-left-copy','empty-handler-result','number-before-handler',
                'number-after-handler','grouped-storage','transient-growth-retry','binary-run')
        }
        $lines=@(for($i=0;$i -lt $names.Count;$i++){
            if($kind -ceq 'allocator'){"PASS: allocator-api-$i $($names[$i])"}else{"PASS: $kind-$($names[$i])"}
        })
        $expected=($lines -join "`n")+"`n"+$additionalMarkers[$kind]+"`n"
        $contract=$Report[$kind.Replace('-','_')+'_contract']
        if(($contract.matched_cases -isnot [int] -and $contract.matched_cases -isnot [long]) -or $contract.matched_cases -ne $names.Count){
            throw "Named $kind contract requires all $($names.Count) actual cases"
        }
        foreach($name in @("$kind-api","$kind-oracle")){
            $record=@($Report.consumers|Where-Object name -CEQ $name)[0]
            if($record.arguments -isnot [Array] -or $record.arguments.Count -ne 0 -or $outputs[$name].text.Replace("`r`n","`n") -cne $expected){
                throw "Named $kind actual arguments or complete ordered protocol differ"
            }
        }
    }}
    if('loadfile' -cin $additional){
        if(-not $Report.loadfile_contract.Contains('stdin_io')){throw 'Named loadfile contract lacks mandatory actual stdin producer/consumer operations'}
        $hashes=@{Ada=@($Report.consumers|Where-Object name -CEQ loadfile-api)[0].executable_sha256;
            ReferenceC=@($Report.consumers|Where-Object name -CEQ loadfile-oracle)[0].executable_sha256}
        $stdin=Test-FileConsumerIO -Observation $Report.loadfile_contract.stdin_io -Context $Context -DriverHashes $hashes -ResolveCapture $ResolveCapture
        foreach($name in $stdin.named_outputs.Keys){$outputs[$name]=$stdin.named_outputs[$name];$consumerKinds+=$name}
    }
    if('thread-reset' -cin $additional){
        $names=@('fresh-values','suspended-lua','suspended-c','original-error','closing-error','reinitialize-thread',
            'weak-prefix-lifetime','no-closer-refusal','self-close-direct','self-close-nested','self-close-lua-resume',
            'base-c-settop','base-c-closeslot','base-c-reset','self-reader','self-writer','self-warning','self-hook',
            'self-close-error','c-closer-refusal','multiple-closers-refusal','closer-error-refusal','recursive-self-close','reset-memory-recovery')
        $instrumented=$parts[0] -ceq 'upstream-test'
        $count=if($instrumented){23}else{24};$skip=[int]$instrumented
        $contract=$Report.thread_reset_contract
        if(($contract.matched_cases -isnot [int] -and $contract.matched_cases -isnot [long]) -or $contract.matched_cases -ne $count -or
            ($contract.skipped_warning_reentry_cases -isnot [int] -and $contract.skipped_warning_reentry_cases -isnot [long]) -or
            $contract.skipped_warning_reentry_cases -ne $skip){throw 'Named thread reset actual case and native instrumentation skip counts differ'}
        $lines=@($names|ForEach-Object{if($instrumented -and $_ -ceq 'self-warning'){'SKIP: reset-self-warning (native T lock rejects API reentry)'}else{'PASS: reset-'+$_}})
        $expected=($lines -join "`n")+"`nPASS: public thread reset/base closing contract`n"
        foreach($name in @('thread-reset-api','thread-reset-oracle')){
            $record=@($Report.consumers|Where-Object name -CEQ $name)[0]
            if($record.arguments -isnot [Array] -or ($record.arguments -join '|') -cne $(if($instrumented){'--without-warning-reentry'}else{''}) -or
                $outputs[$name].text.Replace("`r`n","`n") -cne $expected){throw 'Named thread reset actual native-lock mode or complete ordered protocol differs'}
        }
    }
    foreach($kind in @('macro','macro-compat')){if($kind -cin $additional){
        $role=if($kind -ceq 'macro'){'ordinary'}else{'client-opt-ins'}
        foreach($name in @("$kind-api","$kind-oracle")){
            $record=@($Report.consumers|Where-Object name -CEQ $name)[0]
            if($record.arguments -isnot [Array] -or $record.arguments.Count -ne 0){throw 'SDK macro consumer acquired an unreviewed receiver argument'}
            $null=Test-SdkMacroProtocol -Text $outputs[$name].text -Role $role -Platform $parts[1] `
                -ReportedCases $Report[$kind.Replace('-','_')+'_contract'].matched_cases
        }
    }}
    if('allocator' -cin $additional){
        # Default panic is intentionally observed through the installed public
        # function, in separate actual children. It returns to the C driver;
        # no deliberate host abort or foreign jump crosses an Ada frame. Only
        # these fixed two operations may supply stderr witnesses. Their exact
        # counterpart bytes are mandatory even though the normal allocator
        # child and every historical consumer still require empty stderr.
        if($Report.allocator_contract.panic_modes -isnot [Array] -or
            ($Report.allocator_contract.panic_modes -join '|') -cne 'string|number'){throw 'Named allocator installed panic modes differ'}
        foreach($mode in @('string','number')){
            $message=if($mode -ceq 'string'){'allocator panic witness'}else{'error object is not a string'}
            $expected="PANIC: unprotected error in call to Lua API ($message)`n"
            foreach($implementation in @('api','oracle')){
                $name="allocator-panic-$mode-$implementation"
                $matches=@($Report.consumers|Where-Object name -CEQ $name)
                if($matches.Count -ne 1){throw "Named installed panic consumer missing/duplicate: $name"}
                $record=$matches[0]
                if($record.exit_code -ne 0 -or $record.timed_out -ne $false -or $record.configuration -cne $parts[0] -or
                    $record.profile -cne $parts[2] -or $record.library_type -cne $libraryType -or
                    $record.executable_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $record.arguments -isnot [Array] -or
                    ($record.arguments -join '|') -cne "--panic-$mode"){throw 'Named installed panic process or actual argument differs'}
                $outPath=& $ResolveCapture $record.stdout $record.stdout_sha256
                $errPath=& $ResolveCapture $record.stderr $record.stderr_sha256
                $stderr=[IO.File]::ReadAllText($errPath)
                if((Get-Item $outPath).Length -ne 0 -or $stderr.Replace("`r`n","`n") -cne $expected){throw 'Named installed panic exact stderr or empty stdout differs'}
                $outputs[$name]=@{text=$stderr;hash=$record.stderr_sha256;stream='stderr'}
            }
            if($outputs["allocator-panic-$mode-api"].hash -cne $outputs["allocator-panic-$mode-oracle"].hash){throw 'Named installed panic actual oracle bytes differ'}
            $consumerKinds+="allocator-panic-$mode-api"
        }
    }
    $seen = @{};$allIds=@{};$contextOmissions=@()
    foreach ($case in $Mapping.cases) {
        $key = $case.source + '#' + $case.case_id
        if ($allIds.ContainsKey($key) -or $case.expected_count -ne 1 -or
            $case.consumer -cnotin $consumerKinds) {
            throw "Invalid/duplicate named consumer mapping: $key"
        }
        $allIds[$key]=$true
        if($case.Contains('contexts')){
            if($TargetPolicy -cne 'remaining-upstream-compatibility' -or $case.contexts -isnot [Array] -or
                $case.contexts.Count -eq 0 -or @($case.contexts|Sort-Object -Unique).Count -ne $case.contexts.Count){
                throw 'Context-specific C witnesses require the explicit remaining target selector and a nonempty context array'
            }
            if($Context -cnotin $case.contexts){$contextOmissions+=$key;continue}
        }
        $source = @($Report.consumer_sources | Where-Object { $_.file -ceq $case.source })
        if ($source.Count -ne 1 -or $source[0].sha256 -cne $case.source_sha256) {
            throw "Named consumer source differs: $key"
        }
        $stream=if($case.Contains('witness_stream')){$case.witness_stream}else{'stdout'}
        $panic=$case.consumer -cmatch '^allocator-panic-(string|number)-api$'
        if(($panic -and ($stream -cne 'stderr' -or $case.source -cne 'c_api/tests/allocator_api_contract.c')) -or
            (-not $panic -and $stream -cne 'stdout')){throw 'Named consumer witness stream is not the exact installed panic operation'}
        $patterns = @($case.exact_witnesses | ForEach-Object { '(?m)^' + [regex]::Escape($_) + '\r?$' })
        if ($null -ne $case.pattern_witness) { $patterns += '(?m)' + $case.pattern_witness }
        if ($patterns.Count -eq 0) { throw "Named consumer has no witness: $key" }
        foreach ($pattern in $patterns) {
            if ([regex]::Matches($outputs[$case.consumer].text, $pattern).Count -ne 1) {
                throw "Named consumer witness missing/duplicate: $key"
            }
        }
        if($case.Contains('ordered_witness_patterns')){
            # Some contracts emit a fixed sequence of indexed records before
            # their case marker. Native spellings may vary across platforms;
            # source-bound C/Ada byte equality above still binds every value.
            # Checking each anchored position prevents missing/duplicate or
            # reordered numeric records from hiding behind case completion.
            if($case.ordered_witness_patterns -isnot [Array] -or @($case.ordered_witness_patterns).Count -eq 0){
                throw "Invalid ordered named consumer witness: $key"
            }
            $position=-1
            foreach($pattern in $case.ordered_witness_patterns){
                if($pattern -isnot [string] -or -not $pattern.StartsWith('^') -or -not $pattern.EndsWith('$')){
                    throw "Invalid ordered named consumer witness: $key"
                }
                $matches=[regex]::Matches($outputs[$case.consumer].text,'(?m)'+$pattern)
                if($matches.Count -ne 1 -or $matches[0].Index -le $position){throw "Named consumer ordered witness missing/duplicate/reordered: $key"}
                $position=$matches[0].Index
            }
        }
        $seen[$key] = $true
    }
    if ($seen.Count -eq 0) { throw 'Named consumer mapping empty' }
    return [ordered]@{context=$Context; revision=$Revision; cases=@($seen.Keys | Sort-Object);
        context_inapplicable_witnesses=$contextOmissions;runtime_observed=$true; scoped_acceptance=$false}
}

Export-ModuleMember -Function Test-NamedConsumerEvidence
