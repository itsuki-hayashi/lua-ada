param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$module=Import-Module "$PSScriptRoot/ConformanceMatrix.psm1" -Force -PassThru
$fixture=Join-Path $root ('reports/named-matrix-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$consumerPath='tests/conformance/reviews/api.consumer-witness-proposal.json'
$consumerReview='tests/conformance/reviews/api.consumer-witness.cross-review.json'
$unitPath='tests/conformance/reviews/gc-aunit-context-replay.proposal.json'
$unitReview='tests/conformance/reviews/gc-aunit-context-replay.cross-review.json'
function Read-Json($path){Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64}
function Hash($path){(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
function Save-Json($path,$value){[IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 64),[Text.UTF8Encoding]::new($false))}
$cm=Read-Json (Join-Path $root $consumerPath)
$cr=Read-Json (Join-Path $root $consumerReview)
$am=Read-Json (Join-Path $root $unitPath)
$ar=Read-Json (Join-Path $root $unitReview)
$files=@($consumerPath,$consumerReview,$unitPath,$unitReview,'tests/conformance/scopes/gc-io-events.api.jsonl')+
    @($cr.source_bindings.path)+@($am.bindings.path)+@($cm.cases.source)+
    @('c_api/tests/gc_api_contract.c','c_api/tests/io_api_contract.c','c_api/tests/consumer_allocator.h')
foreach($file in @($files | Sort-Object -Unique)){
    $destination=Join-Path $fixture $file
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $destination
}
# Synthetic fixtures use the current copied source bytes. Historical review
# artifacts remain unchanged in the repository; their old revision hashes do
# not make a self-test's fabricated review describe this new implementation.
foreach($binding in $cr.source_bindings){$binding.sha256=Hash (Join-Path $fixture $binding.path)}
foreach($case in $cm.cases){$case.source_sha256=Hash (Join-Path $fixture $case.source)}
foreach($binding in $am.bindings){$binding.sha256=Hash (Join-Path $fixture $binding.path)}
foreach($entry in $am.entries){$entry.source_sha256=Hash (Join-Path $fixture $entry.case.Split('#')[0])}
$captureDirectory=Join-Path $fixture 'reports/captures'
[void][IO.Directory]::CreateDirectory($captureDirectory)
function Capture($name,$text){
    $path=Join-Path $captureDirectory $name
    [IO.File]::WriteAllText($path,$text)
    return @{path=$path; sha256=(Hash $path)}
}
$revision='a'*40
$context='default/windows/validation/static'
$hash='b'*64
$sources=@($cm.cases | Group-Object source | ForEach-Object {@{file=$_.Name;sha256=$_.Group[0].source_sha256}})
$consumers=@()
$markers=@{'c-api'='PASS: real Ada C API bootstrap consumer';'gc-api'='PASS: public GC contract';'io-api'='PASS: public IO/OS contract'}
foreach($name in $markers.Keys){
    $lines=@(foreach($case in $cm.cases | Where-Object consumer -eq $name){
        $case.exact_witnesses
        if($null -ne $case.pattern_witness){'C API PASS: cold constructor failure sweep (17 growth points)'}
    })+@($markers[$name])
    $out=Capture "$name.stdout" (($lines -join "`n")+"`n")
    $err=Capture "$name.stderr" ''
    $consumers+=@{name=$name;stdout=$out.path;stdout_sha256=$out.sha256;stderr=$err.path;stderr_sha256=$err.sha256;
        configuration='default';profile='validation';library_type='static';exit_code=0;timed_out=$false;executable_sha256=$hash}
    if($name -ne 'c-api'){
        $oracle=$consumers[-1].Clone();$oracle.name=$name.Replace('-api','-oracle');$consumers+=$oracle
    }
}
$cReport=@{repository_revision=$revision;repository_dirty=$false;platform='windows';configuration='default';
    profile='validation';library_type='static';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
    library_files=@(@{file='liblua.a';sha256=$hash});consumer_sources=$sources;consumers=$consumers}
foreach($kind in @('gc','io')){
    $cReport["${kind}_contract"]=@{matching_output=$true;reference_library_files=@(@{file='libconformance_lua.dll';sha256=$hash});
        sources=@(foreach($file in @("${kind}_api_contract.c","${kind}_contract.h",'consumer_allocator.h')){
            @{file="c_api/tests/$file";sha256=(Hash (Join-Path $root "c_api/tests/$file"))}
        })}
}
$unitLines=@($am.entries.required_stdout_line)
$out=Capture 'aunit.stdout' (($unitLines -join "`n")+"`n`nTotal Tests Run:   $($unitLines.Count)`nSuccessful Tests:  $($unitLines.Count)`nFailed Assertions: 0`nUnexpected Errors: 0`n")
$err=Capture 'aunit.stderr' "Lua warning: error in __gc ((native):1: ordinary failure)`n"
$probe=Capture 'probe.stdout' '{"configuration":"default"}'
$empty=Capture 'probe.stderr' ''
$aReport=@{repository_revision=$revision;repository_dirty=$false;platform='windows';configuration='default';
    profile='validation';library_type='static';completed=$true;exit_code=0;executable_sha256=$hash;
    library_files=@(@{file='liblua.a';sha256=$hash});stdout=$out.path;stdout_sha256=$out.sha256;stderr=$err.path;stderr_sha256=$err.sha256;
    sources=@($am.entries | Group-Object { $_.case.Split('#')[0] } | ForEach-Object {@{file=$_.Name;sha256=$_.Group[0].source_sha256}});
    configuration_probe=@{executable_sha256=$hash;stdout=$probe.path;stdout_sha256=$probe.sha256;stderr=$empty.path;stderr_sha256=$empty.sha256}}
$base=@{cm=$cm;cr=$cr;am=$am;ar=$ar;c=$cReport;a=$aReport}
$count=0
function Run-Case($Name,$Mutation,$Expected){
    $v=$base | ConvertTo-Json -Depth 64 | ConvertFrom-Json -AsHashtable -Depth 64
    & $Mutation $v
    Save-Json (Join-Path $fixture $consumerPath) $v.cm
    $v.cr.proposal.sha256=Hash (Join-Path $fixture $consumerPath)
    Save-Json (Join-Path $fixture $consumerReview) $v.cr
    Save-Json (Join-Path $fixture $unitPath) $v.am
    $v.ar.proposal.sha256=Hash (Join-Path $fixture $unitPath)
    Save-Json (Join-Path $fixture $unitReview) $v.ar
    Save-Json (Join-Path $fixture 'consumer.json') $v.c
    Save-Json (Join-Path $fixture 'aunit.json') $v.a
    $manifest=@{scope='gc-io-events';revision=$revision;consumer_mapping=@{path=$consumerPath;sha256=(Hash (Join-Path $fixture $consumerPath));
        review=$consumerReview;review_sha256=(Hash (Join-Path $fixture $consumerReview))};
        aunit_mapping=@{path=$unitPath;sha256=(Hash (Join-Path $fixture $unitPath));review=$unitReview;review_sha256=(Hash (Join-Path $fixture $unitReview))};
        named_consumers=@(@{context=$context;report='consumer.json';sha256=(Hash (Join-Path $fixture 'consumer.json'));artifact_root='.'});
        named_aunit=@(@{context=$context;report='aunit.json';sha256=(Hash (Join-Path $fixture 'aunit.json'));artifact_root='.'})}
    $failure=$null
    try{$null=& $module {param($r,$m) Test-MatrixNamedEvidence -Root $r -Manifest $m -Bundle $r -Suite @{acceptance_contexts=@('default/windows/validation/static')}} $fixture $manifest}
    catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "$Name failed: $failure (expected $Expected)"}
    $script:count++;Write-Output "NAMED MATRIX PASS: $Name"
}
Run-Case 'reviewed mappings with synthetic captures' {} ''
Run-Case 'consumer self review' {param($v) $v.cr.reviewer=$v.cr.author} 'independent review'
Run-Case 'consumer missing source bindings' {param($v) $v.cr.source_bindings=@()} 'binding incomplete'
Run-Case 'consumer missing API' {param($v) $v.cm.entries=@($v.cm.entries | Select-Object -Skip 1)} 'API inventory'
Run-Case 'consumer missing mapped case' {param($v) $v.cm.entries[0].cases=@()} 'API cases'
Run-Case 'consumer absent case definition' {param($v) $v.cm.cases=@($v.cm.cases | Select-Object -Skip 1)} 'case missing'
Run-Case 'oracle driver source missing' {param($v) $v.c.gc_contract.sources=@()} 'driver source missing'
Run-Case 'AUnit self review' {param($v) $v.ar.reviewer=$v.ar.author} 'independent review'
Run-Case 'AUnit missing source bindings' {param($v) $v.am.bindings=@()} 'binding incomplete'
Run-Case 'AUnit library differs from C consumer' {param($v) $v.a.library_files[0].sha256='c'*64} 'libraries differ'
Run-Case 'consumer wrong platform' {param($v) $v.c.platform='linux'} 'context'
Run-Case 'AUnit wrong platform' {param($v) $v.a.platform='linux'} 'identity'
Write-Output "PASS: $count matrix named-evidence regressions; synthetic observations only"
