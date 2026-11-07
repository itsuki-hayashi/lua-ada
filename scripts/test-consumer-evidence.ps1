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
function Run-Case([string]$Name,[scriptblock]$Mutation,[string]$Expected,[switch]$Foreign) {
    $report = $baseline | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
    & $Mutation $report
    $failure = $null
    try { $null = Test-NamedConsumerEvidence $report $mapping $revision $context $resolve -RequireForeignContract:$Foreign }
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
Write-Output "PASS: $count named consumer evidence regressions; synthetic observations only"
