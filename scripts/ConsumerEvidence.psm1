Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NamedConsumerEvidence {
    param([Collections.IDictionary] $Report,
          [Collections.IDictionary] $Mapping,
          [string] $Revision, [string] $Context,
          [scriptblock] $ResolveCapture,
          [switch] $RequireForeignContract,
          [switch] $RequireFormatContract,
          [ValidateSet('format','value','auxiliary','load-dump','debug','external','conversion','operator','index-type','base-closing','native-module','buffer')]
          [string[]] $AdditionalContracts=@())
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
        'base-closing'='PASS: public host base C closing contract';'native-module'='PASS: native-module-explicit-lib2-newstr-external';buffer='PASS: public luaL_Buffer contract'}
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
    $seen = @{}
    foreach ($case in $Mapping.cases) {
        $key = $case.source + '#' + $case.case_id
        if ($seen.ContainsKey($key) -or $case.expected_count -ne 1 -or
            $case.consumer -cnotin $consumerKinds) {
            throw "Invalid/duplicate named consumer mapping: $key"
        }
        $source = @($Report.consumer_sources | Where-Object { $_.file -ceq $case.source })
        if ($source.Count -ne 1 -or $source[0].sha256 -cne $case.source_sha256) {
            throw "Named consumer source differs: $key"
        }
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
        runtime_observed=$true; scoped_acceptance=$false}
}

Export-ModuleMember -Function Test-NamedConsumerEvidence
