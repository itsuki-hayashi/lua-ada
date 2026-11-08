param([Parameter(Mandatory)][string]$Report)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CliFixtureEvidence.psm1') -Force
$baseline=Get-Content $Report -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$temporary=Join-Path $root ('reports/cli-binding-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Case($Name,[scriptblock]$Change,$Expected=''){
    # Every mutation is a disposable binding fixture over preserved actual
    # captures. It is never serialized as new execution or review evidence.
    $r=ConvertTo-Json -InputObject $baseline -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48
    & $Change $r
    $failure=$null
    try{$observed=Assert-CliFixturePair -Root $root -Report $r -Interpreter $baseline.ada.executable}catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "CLI fixture regression $Name failed: $failure; expected $Expected"}
    if($Expected -eq '' -and ($observed.runtime_acceptance -or $observed.coverage_authority)){throw 'CLI observer gained acceptance authority'}
    $script:cases++;Write-Output "CLI FIXTURE PASS: $Name"
}
function Prompt($Report){return @($Report.ada.processes|Where-Object title -CEQ 'REPL converts numeric prompt values')[0]}
Case 'the actual full112 and native19 prompt operations reconcile without acceptance' {}
Case 'full host observations cannot be replaced by a selected prompt subset' {param($r)$r.ada.mode='prompt'} 'actual mode differs'
Case 'a missing ordinary CLI operation blocks host delegation' {param($r)$r.ada.processes=@($r.ada.processes|Select-Object -SkipLast 1)} 'ordered process set'
Case 'ordered CLI identities cannot be swapped behind a summary count' {param($r)$row=$r.ada.processes[4];$r.ada.processes[4]=$r.ada.processes[5];$r.ada.processes[5]=$row} 'operation title'
Case 'host setup needs its exact vararg selector' {param($r)(Prompt $r).process.arguments[1]=(Prompt $r).process.arguments[1].Replace("('number')","('boolean')")} 'exact arguments'
Case 'the actual prompt source copy must match the original' {param($r)@($r.ada.fixture_files|Where-Object name -CEQ prompt-controls.lua)[0].sha256='0'*64} 'setup source copy'
Case 'selected CLI input cannot disappear' {param($r)[void](Prompt $r).process.Remove('standard_input')} 'actual selected input'
Case 'input refusal is not completed observation' {param($r)(Prompt $r).process.standard_input.write_completed=$false} 'input was not completed'
Case 'ordinary REPL inputs cannot adopt a prompt-before-input exception' {param($r)(Prompt $r).process.early_input_close_requested=$true} 'capture protocol'
Case 'lost output cannot masquerade as expected early input close' {param($r)(Prompt $r).process.output_drain_failed=$true} 'complete actual capture'
Case 'raw output identities remain mandatory' {param($r)(Prompt $r).process.stdout_sha256='0'*64} 'capture bytes differ'
Case 'rehashing a success marker cannot replace exact prompt bytes' {param($r)
    $p=(Prompt $r).process;$path=Join-Path $temporary 'invented.stdout'
    [IO.File]::WriteAllText($path,'CLI PASS',[Text.UTF8Encoding]::new($false))
    $p.stdout_path=$path;$p.stdout_bytes=(Get-Item $path).Length;$p.stdout_sha256=(Get-FileHash $path).Hash.ToLowerInvariant()
} 'exact output differs'
Case 'typed prompt termination cannot become ordinary success' {param($r)
    @($r.ada.processes|Where-Object title -CEQ 'REPL prompt typed exit with close retains status')[0].process.exit_code=0
} 'typed exit'
Case 'a string exit code is not an actual process status' {param($r)(Prompt $r).process.exit_code='0'} 'actual exit status'
Case 'T or default source configuration cannot transfer between paired reports' {param($r)$r.native.context='upstream-test/windows/validation/static';if($r.context -ceq $r.native.context){$r.native.context='default/windows/validation/static'}} 'paired source or context'
Case 'a different native revision cannot borrow current prompt output' {param($r)$r.native.repository_revision='0'*40} 'paired source or context'
Case 'a labelled synthetic CLI process cannot close the actual host route' {param($r)$r.ada.synthetic_fixture=$true} 'actual mode differs'
Case 'a host report cannot invent runtime acceptance' {param($r)$r.runtime_acceptance=$true} 'pair identity'
Case 'another executable cannot reuse these prompt captures' {param($r)(Prompt $r).process.executable_sha256='0'*64} 'actual arguments|runtime directory'
Case 'a changed CLI source binding cannot inherit the old operation contract' {param($r)$r.ada.source_bindings[0].sha256='0'*64} 'source binding'
Case 'missing input fixtures cannot pass using only expected output' {param($r)$r.ada.fixture_files=@($r.ada.fixture_files|Select-Object -Skip 1)} 'fixture set'
Case 'the native prompt counterpart cannot be omitted' {param($r)$r.native.processes=@($r.native.processes|Select-Object -SkipLast 1)} 'ordered process set'
Case 'a different actual runtime library cannot reuse the selected configuration' {param($r)$r.native.library_files[0].sha256='0'*64} 'library bytes'
Case 'a native T-absent configuration probe cannot replace the selected runtime' {param($r)$r.native.configuration_probe.process.arguments[1]="io.write('CLI CONFIGURATION default')"} 'exact arguments'
Case 'runtime directory declarations cannot point outside the captured library files' {param($r)$r.native.runtime_directory='wrong/runtime'} 'library directory'
if($baseline.context.StartsWith('upstream-test/',[StringComparison]::Ordinal)){
    function Diagnostic($r){return @($r.native.processes|Where-Object observation_disposition -CEQ observed-native-test-teardown-diagnostic)[0]}
    Case 'the native T teardown diagnostic is never clean passing evidence' {param($r)(Diagnostic $r).passing_execution_evidence=$true} 'masquerade as a clean'
    Case 'a native T diagnostic cannot lose its independent original source direction' {param($r)[void](Diagnostic $r).Remove('feature_review')} 'independent source direction'
    Case 'a different assertion cannot use the zero-live-block diagnostic contract' {param($r)
        $p=(Diagnostic $r).process;$path=Join-Path $temporary 'wrong-assertion.stderr'
        [IO.File]::WriteAllText($path,[IO.File]::ReadAllText($p.stderr_path).Replace('numblocks == 0','total == 0'),[Text.UTF8Encoding]::new($false))
        $p.stderr_path=$path;$p.stderr_sha256=(Get-FileHash $path).Hash.ToLowerInvariant();$p.stderr_bytes=(Get-Item $path).Length
    } 'exact measured Windows assertion'
    Case 'the native default clean no-close sibling is mandatory' {param($r)[void]$r.Remove('native_default')} 'clean native default counterpart'
    Case 'a native T binary cannot be declared the clean default sibling' {param($r)$r.native_default.context=$r.context} 'default counterpart source or configuration'
    Case 'native T close=true must stay a clean operation' {param($r)
        @($r.native.processes|Where-Object title -CEQ 'REPL prompt typed exit with close retains status')[0].observation_disposition='observed-native-test-teardown-diagnostic'
    } 'masquerade as a clean'
    $reviewRoot=Join-Path $temporary 'missing-protocol-review'
    $feature='tests/conformance/targets/remaining-upstream-compatibility/reviews/cli-native-t-exit-no-close.independent-feature-review.json'
    $review=Get-Content (Join-Path $root $feature) -Raw|ConvertFrom-Json -AsHashtable
    foreach($path in @($feature)+@($review.source_bindings.path|Where-Object{$_ -cne 'scripts/check-cli.ps1'})){
        $target=Join-Path $reviewRoot $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        [IO.File]::Copy((Join-Path $root $path),$target)
    }
    $failure=$null
    try{$null=Assert-CliNativeTestExitDirection -Root $reviewRoot -RequireProtocolReview}catch{$failure=$_.Exception.Message}
    if($failure -notmatch 'independent current protocol review'){throw "Pending diagnostic protocol gained final authority: $failure"}
    $script:cases++
}

# These named receipts are explicitly synthetic linkage fixtures. The final
# image obtains the names from fresh verified AUnit reports, not this list.
$classification=Get-Content (Join-Path $root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 24
$names=@($classification.host_entries.aunit_named_cases.case)
$failure=$null
try{Assert-CliNamedCounterparts -Root $root -Context $baseline.context -NamedEvidence @{context=$baseline.context;runtime_observed=$true;named_aunit_cases=$names}}catch{$failure=$_.Exception.Message}
if($failure -notmatch 'actual portable frozen-context process protocol'){throw 'Author CLI argument observers were incorrectly treated as final context authority'}
$failure=$null
try{Assert-CliNamedCounterparts -Root $root -Context $baseline.context -NamedEvidence @{context=$baseline.context;runtime_observed=$true;named_aunit_cases=@($names|Select-Object -Skip 1)}}catch{$failure=$_.Exception.Message}
if($failure -notmatch 'actual required named'){throw 'CLI required named operation omission was not rejected'}
$script:cases+=2
Write-Output "PASS: $script:cases CLI fixture binding regressions; mutated and named fixtures grant no execution authority"
