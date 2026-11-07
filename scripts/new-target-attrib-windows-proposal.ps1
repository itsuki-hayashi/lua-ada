param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Test-ConformanceReferenceTree -Root $root
$relative='references/lua/testes/attrib.lua';$path=Join-Path $root $relative
$bytes=[IO.File]::ReadAllBytes($path);$text=[Text.Encoding]::Latin1.GetString($bytes)
$matches=[regex]::Matches($text,'"libs/[^"\r\n]+"')
$expected=@('B.lua','A.lua','A.lc','L','L','XXxX','P1/init.lua','P1/xuxu.lua','lib2-v2','lib1')
$ids=@('require-b-lua','require-a-lua','require-a-lc','fallback-l-first','fallback-l-reload','require-xx-x',
    'mixed-subpackage-template','subpackage-separator','hyphen-native-prefix','c-root-native-prefix')
if($matches.Count -ne $expected.Count){throw 'Pinned attrib path expectation set changed'}
$changes=@();$counterpart='tests/conformance/platform/windows-package-paths.lua'
for($i=0;$i -lt $matches.Count;$i++){
    $match=$matches[$i]
    if($match.Value -cne ('"libs/'+$expected[$i]+'"')){throw 'Pinned attrib expected path order changed'}
    $replacement=if($i -eq 6){'("libs"..dirsep.."P1/init.lua")'}else{'D"'+$expected[$i]+'"'}
    $span=[byte[]]::new($match.Length);[Array]::Copy($bytes,$match.Index,$span,0,$span.Length)
    $line=1+([regex]::Matches($text.Substring(0,$match.Index),"`n")).Count
    $changes+=[ordered]@{id=('windows-path-'+$ids[$i]);start_byte=$match.Index;length_bytes=$match.Length;
        start_line=$line;end_line=$line;source_sha256=(Get-ConformanceHash $span);original_text=$match.Value;
        invariant=$(if($i -eq 6){'Retain exact require loader data from the original mixed-separator package template; preserve the literal /init.lua suffix.'}
            elseif($i -ge 8){'Retain the native C-module path-prefix assertion and every loader/function/argument assertion, using the original D helper for the Windows separator.'}
            else{'Retain exact searchpath/require filename and loader-data equality using the original D helper; preserve all assertions and cache/reload behavior.'});
        counterpart_tests=@($counterpart+'#'+$ids[$i]);replacement=$replacement}
}
$output=Get-ConformancePatchedBytes -SourceBytes $bytes -Replacements $changes
$originalTokens=@(Get-ConformanceTokens -Bytes $bytes);$generatedTokens=@(Get-ConformanceTokens -Bytes $output)
foreach($name in @('assert','T')){
    if(@($originalTokens|Where-Object{ -not $_.IsString -and $_.Text -ceq $name }).Count -ne
        @($generatedTokens|Where-Object{ -not $_.IsString -and $_.Text -ceq $name }).Count){throw 'Path mapping changed assertion or T identifiers'}
}
$protected=@()
foreach($helper in @(@{id='D';pattern='(?ms)^local function D \(x\)\r?\n.*?^end\r?$'},
    @{id='DC';pattern='(?ms)^local function DC \(x\)\r?\n.*?^end\r?$'},
    @{id='try';pattern='(?ms)^local try = function \(p, n, r, ext\)\r?\n.*?^end\r?$'})){
    $match=[regex]::Match($text,$helper.pattern)
    if(-not $match.Success){throw 'Pinned attrib helper preservation span is missing'}
    foreach($change in $changes){if($change.start_byte -lt $match.Index+$match.Length -and $change.start_byte+$change.length_bytes -gt $match.Index){throw 'Path adaptation overlaps an original helper'}}
    $span=[byte[]]::new($match.Length);[Array]::Copy($bytes,$match.Index,$span,0,$span.Length)
    $protected+=@{id=$helper.id;start_byte=$match.Index;length_bytes=$match.Length;source_sha256=(Get-ConformanceHash $span)}
}
$directory='tests/conformance/targets/remaining-upstream-compatibility'
$packetPath=$directory+'/attrib-windows.source.author-proposal.json'
$manifest=[ordered]@{schema_version=1;id='attrib-windows-paths';source=$relative;source_sha256=(Get-ConformanceHash $bytes);
    disposition='native-platform-equivalent';platform='windows';configuration='default-and-upstream-test';
    target='remaining-upstream-compatibility';review=@{status='pending';author='Codex /root/validation_delivery';reviewer=$null;
        artifact=($directory+'/attrib-windows.equivalence-approval.json');artifact_sha256=$null};
    replacements=$changes;output_sha256=(Get-ConformanceHash $output);authoring_observation=$null;
    independent_review_status='pending';runtime_acceptance=$false;coverage_authority=$false}
$suite=Get-Content (Join-Path $root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$packet=[ordered]@{schema_version=1;kind='attrib-windows-source-author-proposal';author='Codex /root/validation_delivery';
    source=$relative;source_sha256=$manifest.source_sha256;generated_sha256=$manifest.output_sha256;
    exact_replacement_count=$changes.Count;replacement_ids=@($changes.id);counterpart=@{path=$counterpart;sha256=(Get-FileHash (Join-Path $root $counterpart)).Hash.ToLowerInvariant()};
    preserved_helper_spans=$protected;
    assertion_identifier_count=@($originalTokens|Where-Object{ -not $_.IsString -and $_.Text -ceq 'assert' }).Count;
    T_identifier_count=@($originalTokens|Where-Object{ -not $_.IsString -and $_.Text -ceq 'T' }).Count;
    source_preservation=@{all_changes_are_exact_expected_path_literals=$true;D_helper_unchanged=$true;DC_helper_unchanged=$true;
        try_helper_unchanged=$true;port_guard_unchanged=$true;all_T_checks_unchanged=$true;assertion_calls_removed=0;exclusions=@()};
    required_contexts=@($suite.acceptance_contexts|Where-Object{$_ -cmatch '/windows/'});
    review_status='pending';runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@();
    pending_requirements=@('Independent exact-span semantic review before executing an adapted Ada target.',
        'Fresh unchanged original C native captures for each selected actual context/image/configuration, including the Windows path assertion failure.',
        'Fresh actual standalone path counterpart captures with unchanged fixture C bytes and same-image linkage receipts.',
        'Fresh full transformed File and Aggregate C/Ada observations after source approval; preserve the 27 return protocol and every native/T assertion.',
        'Post-observation native applicability review must bind original C source spans and captures; no Ada-only exception or passing claim.')}
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $root $packetPath),(ConvertTo-Json $packet -Depth 48).Replace("`r`n","`n")+"`n",$utf8)
$manifest.authoring_observation=@{path=$packetPath;sha256=(Get-FileHash (Join-Path $root $packetPath)).Hash.ToLowerInvariant()}
$manifestPath=Join-Path $root ($directory+'/attrib-windows-equivalence.author-proposal.json')
[IO.File]::WriteAllText($manifestPath,(ConvertTo-Json $manifest -Depth 48).Replace("`r`n","`n")+"`n",$utf8)
Write-Output "AUTHOR PROPOSAL ONLY: 10 exact Windows attrib expectation spans; output=$($manifest.output_sha256); no exclusions, approvals or passing evidence"
