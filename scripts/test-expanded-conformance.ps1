param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module "$PSScriptRoot/ConformanceScope.psm1" -Force
Import-Module "$PSScriptRoot/ConformanceMatrix.psm1" -Force
Import-Module "$PSScriptRoot/ScopedAcceptancePolicy.psm1" -Force
$directory = Join-Path $root ('reports/expanded-harness-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$cases = 0
function Case([string] $Name, [scriptblock] $Action, [string] $Expected = '') {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
    if (($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))) {
        throw "Expanded harness case failed ($Name): $failure; expected $Expected"
    }
    $script:cases++
    Write-Output "EXPANDED HARNESS PASS: $Name"
}
$suite = Get-Content "$root/tests/conformance/suite.json" -Raw | ConvertFrom-Json -AsHashtable
$policy = Get-ConformanceScopePolicy expanded-t-conformance
if ($policy.Files.Count -ne 13 -or $policy.Helpers.Count -ne 1 -or
    $policy.Helpers[0] -cne 'bwcoercion.lua') { throw 'Expanded scope boundary differs' }
$identity = @{report='synthetic/report.json'; artifact_root='synthetic'; sha256=('a'*64)}
$baseline = @{schema_version=1; scope='expanded-t-conformance'; revision=('b'*40);
    operations=@(foreach ($context in $suite.acceptance_contexts) {
        foreach ($file in $policy.Files) {
            $entry = @{file=$file; context=$context; c=$identity.Clone(); ada=$identity.Clone()}
            if ($file -ceq 'constructs.lua') {
                $entry.supplemental=@(@{variant='constructs-branch-1'; c=$identity.Clone(); ada=$identity.Clone()})
            }
            $entry
        }
    })}
function MatrixCase([string] $Name, [scriptblock] $Mutate, [string] $Expected = '') {
    $matrix = $baseline | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable
    & $Mutate $matrix
    Case $Name { Assert-ScopedMatrixIndex -Manifest $matrix -Contexts $suite.acceptance_contexts } $Expected
}
MatrixCase '338 primary pairs with 26 supplementary template pairs' {}
if ($baseline.operations.Count -ne 338) { throw 'Unexpected primary operation count' }
MatrixCase 'missing primary pair' {param($m) $m.operations=@($m.operations | Select-Object -Skip 1)} 'Incomplete scoped matrix'
MatrixCase 'duplicate primary pair' {param($m) $m.operations += $m.operations[0]} 'Duplicate scoped matrix'
MatrixCase 'helper cannot masquerade as primary' {param($m) $m.operations[0].file='bwcoercion.lua'} 'Unknown scoped matrix'
MatrixCase 'unknown scope rejected' {param($m) $m.scope='invented'} 'Invalid scoped matrix'
MatrixCase 'wrong context rejected' {param($m) $m.operations[0].context='upstream-test/linux/release/static'} 'Unknown scoped matrix'
MatrixCase 'second constructs template required' {param($m)
    ($m.operations | Where-Object file -CEQ 'constructs.lua' | Select-Object -First 1).Remove('supplemental')
} 'second seeded template'
MatrixCase 'duplicate constructs supplement rejected' {param($m)
    $entry=$m.operations | Where-Object file -CEQ 'constructs.lua' | Select-Object -First 1
    $entry.supplemental += $entry.supplemental[0]
} 'second seeded template'
MatrixCase 'wrong constructs template rejected' {param($m)
    ($m.operations | Where-Object file -CEQ 'constructs.lua' | Select-Object -First 1).supplemental[0].variant='constructs-branch-0'
} 'second seeded template'
MatrixCase 'missing supplemental Ada capture rejected' {param($m)
    ($m.operations | Where-Object file -CEQ 'constructs.lua' | Select-Object -First 1).supplemental[0].ada.sha256=''
} 'supplemental report identity'
MatrixCase 'unreviewed extra suite execution rejected' {param($m)
    $m.operations[0].supplemental=@(@{variant='other'})
} 'Unexpected supplemental'

# Mutate disposable definitions only. Full structural inventory validation
# remains enabled, including all unrelated source and public-header anchors.
foreach ($name in @('suite.json','c-api.jsonl','coverage','scopes')) {
    Copy-Item -LiteralPath "$root/tests/conformance/$name" -Destination $directory -Recurse
}
$definitionPath = Join-Path $directory 'scopes/expanded-t-conformance.json'
$original = [IO.File]::ReadAllText($definitionPath)
function ScopeCase([string] $Name, [scriptblock] $Mutate, [string] $Expected) {
    $definition = $original | ConvertFrom-Json -AsHashtable -Depth 32
    & $Mutate $definition
    [IO.File]::WriteAllText($definitionPath, ($definition | ConvertTo-Json -Depth 32))
    try { Case $Name { Test-ConformanceScope -Root $root -Scope expanded-t-conformance -InventoryDirectory $directory } $Expected }
    finally { [IO.File]::WriteAllText($definitionPath, $original) }
}
Case 'source inventory includes helper without scheduling another primary' {
    $record=Test-ConformanceScope -Root $root -Scope expanded-t-conformance -InventoryDirectory $directory
    if ($record.Files -ne 13 -or $record.Helpers -ne 1 -or $record.FullM3Complete) { throw 'Scope count differs' }
}
ScopeCase 'missing helper rejected' {param($d) $d.helpers=@()} 'selected helpers'
ScopeCase 'duplicate helper rejected' {param($d) $d.helpers += $d.helpers[0]} 'selected helpers'
ScopeCase 'helper source drift rejected' {param($d) $d.helpers[0].sha256='f'*64} 'source hash drift|Scope selected source review differs'
ScopeCase 'missing extra primary rejected' {param($d) $d.files=@($d.files | Where-Object path -CNE 'math.lua')} 'selected delivery files'
ScopeCase 'expanded API ledger cannot reuse narrower path' {param($d) $d.api_coverage_file='scopes/gc-io-events.api.jsonl'} 'Unsafe scoped API'
ScopeCase 'reviewer names cannot replace selection approval bytes' {param($d)
    $d.review=@{status='reviewed'; author='synthetic-author'; reviewer='synthetic-reviewer';
        artifact='missing-selection-approval.json'; artifact_sha256=('f'*64); rationale='synthetic'}
} 'missing or outside'
ScopeCase 'source classification review bytes are mandatory' {param($d)
    $d.source_classification_review.sha256='f'*64
} 'hash differs'
ScopeCase 'API semantic review bytes are mandatory' {param($d)
    $d.api_semantic_review.sha256='f'*64
} 'hash differs'
$apiLedger=Join-Path $directory 'scopes/expanded-t-conformance.api.jsonl'
$savedApi=[IO.File]::ReadAllText($apiLedger)
foreach ($field in @('invariant','scoped_boundaries','named_cases',
        'named_aunit_cases','selected_lua_runtime_obligations')) {
    try {
        $rows=@(Get-Content -LiteralPath $apiLedger | ForEach-Object {
            $_ | ConvertFrom-Json -AsHashtable -Depth 64
        })
        $rows[0][$field]=if($field -in @('invariant','scoped_boundaries')) {
            'Synthetic broader semantic claim without fresh approval'
        } else { @(@{id='invented-unreviewed-witness'}) }
        [IO.File]::WriteAllText($apiLedger,(@($rows | ForEach-Object {
            $_ | ConvertTo-Json -Compress -Depth 64
        }) -join "`n")+"`n")
        Case "API $field cannot drift while retaining approved named mappings" {
            Test-ConformanceScope -Root $root -Scope expanded-t-conformance -InventoryDirectory $directory
        } 'Reviewed API semantic descriptor differs'
    } finally { [IO.File]::WriteAllText($apiLedger,$savedApi) }
}
$mathLedger=Join-Path $directory 'coverage/math.jsonl'
$savedMath=[IO.File]::ReadAllText($mathLedger)
try {
    $rows=@(Get-Content -LiteralPath $mathLedger | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable -Depth 64 })
    foreach($row in $rows) {
        if($row.id -ceq 'LUA-MATH-REVIEWED-BLOCK-0026') { $row.measured_condition.value=64 }
        if($row.Contains('conditional_applicability') -and
            $row.conditional_applicability.measured_guard_obligation -ceq 'LUA-MATH-REVIEWED-BLOCK-0026') {
            $row.conditional_applicability.condition.value=64
        }
    }
    [IO.File]::WriteAllText($mathLedger,(@($rows | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 64 }) -join "`n")+"`n")
    Case 'editing both guard and lexical conditions cannot retain historical source approval' {
        Test-ConformanceScope -Root $root -Scope expanded-t-conformance -InventoryDirectory $directory
    } 'Reviewed source applicability descriptor differs'
} finally { [IO.File]::WriteAllText($mathLedger,$savedMath) }
Case 'pending expanded scope stays diagnostic' {
    $record=Test-ConformanceScope -Root $root -Scope expanded-t-conformance
    $selected=Get-ScopedAcceptancePolicy -Root $root -Scope expanded-t-conformance -Context 'default/windows/validation/static'
    $pending=$record.UnresolvedSourceAnchors -gt 0 -or $record.UnresolvedApiEntries -gt 0
    if ($selected.acceptance -eq $pending -or $selected.full_m3_acceptance) { throw 'Expanded policy differs' }
}
$stdoutPath = Join-Path $directory 'process.stdout'
function ProcessCase([string] $Name, [string] $File, [string] $Output, [string] $Expected = '') {
    [IO.File]::WriteAllText($stdoutPath,$Output)
    $process=@{exit_code=0; timed_out=$false; capture_exceeded=$false;
        pipe_drain_failed=$false; process_tree_kill_error=$null; process_id=123; stdout_path=$stdoutPath}
    $telemetry=@{schema_version=1; process_id=123; run_id='synthetic'; configuration='upstream-test';
        allocator_limit_bytes=2147483648L; managed_refusals=0; outstanding_bytes=0;
        outstanding_blocks=0; shutdown_complete=$true; accounting_fault=$false}
    Case $Name { Assert-ScopedProcessCompletion -File $File -Process $process -Telemetry $telemetry `
        -RunId synthetic -Configuration upstream-test } $Expected
}
ProcessCase 'UTF8 preserves lowercase terminal success' utf8.lua "testing UTF-8 library`nok`n"
ProcessCase 'UTF8 uppercase marker cannot replace source completion' utf8.lua "testing UTF-8 library`nOK`n" 'final ok'
ProcessCase 'bitwise primary OK cannot certify helper witness' bitwise.lua "testing bitwise operations`ntesting bitwise library`nOK`n" 'helper completion'
ProcessCase 'bitwise helper has distinct completion' bitwise.lua "testing bitwise operations`ntesting bitwise library`nOK`nBWCOERCION HELPER OK`n"
$coroutine="testing coroutines`ntesting yields inside metamethods`ntesting yields inside 'for' iterators`n"
ProcessCase 'coroutine primary OK cannot certify instrumented tail' coroutine.lua ($coroutine+"OK`n") 'hook/API tail'
ProcessCase 'coroutine hook alone cannot certify both API phases' coroutine.lua ($coroutine+"testing yields inside hooks`ntesting coroutine API`nOK`n") 'hook/API tail'
ProcessCase 'coroutine both API phases required' coroutine.lua ($coroutine+"testing yields inside hooks`ntesting coroutine API`ntesting coroutine API`nOK`n")
$math="testing numbers and math lib`ntesting 'math.random'`ntesting precision of 'tostring'`n"
ProcessCase 'math completion requires actual replay seed pair' math.lua ($math+"OK`n") 'random seed'
ProcessCase 'math actual signed seed pair retained' math.lua ($math+"random seeds: -17, 349`nOK`n")
ProcessCase 'late failure output cannot follow terminal OK' closure.lua "testing closures`nOK`nFAILED`n" 'terminal OK'
$profile='source profile facts: {"integer_bits":64,"mantissa_bits":53,"max_exponent":1023,"byte_order":"little","bitwise_precision":true}'
$observed=@{integer_bytes=8; number_bytes=8}
Case 'actual source profile accepts supported little endian layout' {
    Get-ScopedSourceProfileFacts -Output $profile -Observed $observed
}
Case 'source profile preserves native big endian applicability' {
    Get-ScopedSourceProfileFacts -Output $profile.Replace('little','big') -Observed $observed
}
Case 'whole-file OK cannot substitute for source profile measurement' {
    Get-ScopedSourceProfileFacts -Output 'OK' -Observed $observed
} 'missing or duplicated'
Case 'duplicate source profiles cannot select a convenient layout' {
    Get-ScopedSourceProfileFacts -Output ($profile+"`n"+$profile) -Observed $observed
} 'missing or duplicated'
Case 'source profile cannot stringify numeric facts' {
    Get-ScopedSourceProfileFacts -Output $profile.Replace(':53',':"53"') -Observed $observed
} 'not an integer'
Case 'source profile cannot disguise float width' {
    Get-ScopedSourceProfileFacts -Output $profile.Replace(':53',':24') -Observed $observed
} 'supported int64/binary64'
Case 'source profile cannot omit precision guard evidence' {
    Get-ScopedSourceProfileFacts -Output $profile.Replace(',"bitwise_precision":true','') -Observed $observed
} 'field set'
Case 'source profile precision guard must match native configuration' {
    Get-ScopedSourceProfileFacts -Output $profile.Replace(':true',':false') -Observed $observed
} 'supported int64/binary64'
$facts=Get-ScopedSourceProfileFacts -Output $profile -Observed $observed
Case 'measured guard compares two actual native dimensions' {
    $result=Get-ScopedMeasuredConditionResults -Records @(@{id='width';
        measured_condition=@{fact='mantissa_bits';operator='lt';value_fact='integer_bits'}}) -Facts $facts
    if ($result.width -ne $true) { throw 'Width comparison differs' }
}
Case 'inactive native body records false without claiming its assertions passed' {
    $result=Get-ScopedMeasuredConditionResults -Records @(@{id='rng-high-half';
        measured_condition=@{fact='mantissa_bits';operator='le';value=32}}) -Facts $facts
    if ($result['rng-high-half'] -isnot [bool] -or $result['rng-high-half']) { throw 'Inactive condition differs' }
}
Case 'condition language cannot execute author-supplied code' {
    Get-ScopedMeasuredConditionResults -Records @(@{id='code';
        measured_condition=@{fact='mantissa_bits';operator='Invoke-Expression';value='arbitrary'}}) -Facts $facts
} 'Invalid measured'
Case 'condition cannot invent a native measurement' {
    Get-ScopedMeasuredConditionResults -Records @(@{id='unknown';
        measured_condition=@{fact='invented';operator='eq';value=$true}}) -Facts $facts
} 'Invalid measured'
Case 'condition cannot compare numeric width to string text' {
    Get-ScopedMeasuredConditionResults -Records @(@{id='typed';
        measured_condition=@{fact='mantissa_bits';operator='lt';value='64'}}) -Facts $facts
} 'types differ'
Case 'condition cannot supply both literal and other-fact operands' {
    Get-ScopedMeasuredConditionResults -Records @(@{id='ambiguous';
        measured_condition=@{fact='mantissa_bits';operator='lt';value=64;value_fact='integer_bits'}}) -Facts $facts
} 'Invalid measured'
Case 'measured guard identities cannot repeat' {
    $record=@{id='duplicate';measured_condition=@{fact='byte_order';operator='eq';value='little'}}
    Get-ScopedMeasuredConditionResults -Records @($record,$record) -Facts $facts
} 'duplicate or missing'
$scopeModule=Get-Module ConformanceScope
$conditional=@{id='anchor';status='reviewed';obligations=@('guard');
    conditional_applicability=@{condition=@{fact='mantissa_bits';operator='le';value=32};
        when=$false;inactive_body='reviewed-reference-only';measured_guard_obligation='guard'}}
$guard=@{id='guard';measured_condition=@{fact='mantissa_bits';operator='le';value=32}}
Case 'inactive lexical assertion remains a reviewed reference to measured guard' {
    & $scopeModule {param($rows) Assert-ScopedConditionalReferences -Records $rows} @($conditional,$guard)
}
Case 'inactive lexical assertion cannot be promoted to passed' {
    $row=$conditional.Clone();$row.status='passed'
    & $scopeModule {param($rows) Assert-ScopedConditionalReferences -Records $rows} @($row,$guard)
} 'cannot claim inactive body'
Case 'conditional reference cannot omit actual guard linkage' {
    $row=$conditional.Clone();$row.obligations=@()
    & $scopeModule {param($rows) Assert-ScopedConditionalReferences -Records $rows} @($row,$guard)
} 'lacks its measured guard'
Case 'conditional reference cannot change applicability after source review' {
    $row=$guard.Clone();$row.measured_condition=@{fact='mantissa_bits';operator='le';value=64}
    & $scopeModule {param($rows) Assert-ScopedConditionalReferences -Records $rows} @($conditional,$row)
} 'predicate differs'
Write-Output "PASS: $cases expanded harness regressions; synthetic reports grant no runtime acceptance"
