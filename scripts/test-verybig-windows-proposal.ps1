Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$base='tests/conformance/targets/remaining-upstream-compatibility'
$spec=Get-Content (Join-Path $root "$base/verybig-windows-tempfile.author-proposal.json") -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$author=Get-Content (Join-Path $root "$base/verybig-windows-tempfile.source.author-proposal.json") -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$bytes=[IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/verybig.lua'))
$script:cases=0
function Clone($value){ConvertTo-Json -InputObject $value -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48}
function Check($s,$a){
    if($s.schema_version -ne 1 -or $s.id -cne 'verybig-windows-tempfile' -or
        $s.source -cne 'references/lua/testes/verybig.lua' -or $s.source_sha256 -cne (Get-ConformanceHash $bytes) -or
        $s.source_sha256 -cne '2b6d30c69cbe6974068881108eae297bdedd275b429be8ec614bf5f8ee89707e' -or
        $s.platform -cne 'windows' -or $s.configuration -cne 'default-and-upstream-test' -or
        $s.disposition -cne 'native-platform-equivalent' -or $s.replacements.Count -ne 1){throw 'Exact Windows source proposal identity differs'}
    foreach($flag in @('runtime_acceptance','coverage_authority','source_adaptation_authority')){
        if($s[$flag] -isnot [bool] -or $s[$flag] -or $a[$flag] -isnot [bool] -or $a[$flag]){throw 'Pending proposal cannot grant authority'}
    }
    if($s.review.status -cne 'pending' -or $null -ne $s.review.reviewer -or $null -ne $s.review.artifact_sha256 -or
        $s.execution_evidence.Count -or $a.execution_evidence.Count){throw 'Pending proposal cannot invent approval or execution'}
    $r=$s.replacements[0]
    if($r.id -cne 'windows-verybig-tempfile-cwd' -or $r.start_byte -ne 3491 -or $r.length_bytes -ne 12 -or
        ($r.start_byte -isnot [long] -and $r.start_byte -isnot [int]) -or
        ($r.length_bytes -isnot [long] -and $r.length_bytes -isnot [int]) -or
        $r.start_line -ne 141 -or $r.end_line -ne 141 -or $r.original_text -cne 'os.tmpname()' -or
        $r.source_sha256 -cne '5877a423400935af8288a4a9d58c43ba23153277ed30fdd2f7448ff190911e7a' -or
        $r.replacement -cne "'.'..os.tmpname()"){throw 'Only the exact original 12-byte expression is proposed'}
    $generated=Get-ConformancePatchedBytes -SourceBytes $bytes -Replacements @($s.replacements)
    if($generated.Length -ne 3729 -or (Get-ConformanceHash $generated) -cne $a.generated_in_memory.sha256 -or
        $a.generated_in_memory.sha256 -cne 'd973c7a66fd1f4d50ec48c7d2bc49ad2bf8aa3e0df9cadf7033c52f1e3ce00dc' -or
        $a.generated_in_memory.emitted -or $a.generated_in_memory.executed){throw 'In-memory preview identity or non-emission differs'}
    if($a.preserved.prefix.byte_offset -ne 0 -or $a.preserved.prefix.byte_length -ne 3491 -or
        $a.preserved.suffix.byte_offset -ne 3503 -or $a.preserved.suffix.byte_length -ne 221){
        throw 'Complete unpatched source interval descriptors differ'
    }
    foreach($span in @($a.preserved.prefix,$a.preserved.suffix)){
        $old=[byte[]]::new($span.byte_length);[Array]::Copy($bytes,$span.byte_offset,$old,0,$old.Length)
        $offset=if($span.byte_offset -eq 0){0}else{$span.byte_offset+5}
        $new=[byte[]]::new($span.byte_length);[Array]::Copy($generated,$offset,$new,0,$new.Length)
        if((Get-ConformanceHash $old) -cne $span.sha256 -or (Get-ConformanceHash $new) -cne $span.sha256){throw 'Unpatched source bytes changed'}
    }
    if(-not $a.preserved.all_other_bytes_identical -or $a.preserved.port_flag_added -or $a.preserved.soft_flag_added -or
        $a.preserved.skips.Count -or $a.preserved.exclusions.Count -or $a.preserved.assertion_calls_removed -ne 0){
        throw 'Every flag, assertion and unpatched workload remains required'
    }
    $oldTokens=@(Get-ConformanceTokens $bytes);$newTokens=@(Get-ConformanceTokens $generated)
    foreach($name in @('assert','_soft','_port','tmpname','dofile','remove')){
        if(@($oldTokens|Where-Object{-not $_.IsString -and $_.Text -ceq $name}).Count -ne
            @($newTokens|Where-Object{-not $_.IsString -and $_.Text -ceq $name}).Count){throw 'Semantic identifiers changed'}
    }
    $native=[IO.File]::ReadAllBytes((Join-Path $root $a.native_source_evidence.path))
    if($a.native_source_evidence.path -cne 'references/lua/loslib.c' -or
        (Get-ConformanceHash $native) -cne $a.native_source_evidence.sha256){throw 'Pinned native source binding differs'}
    foreach($span in $a.native_source_evidence.spans){
        $part=[byte[]]::new($span.byte_length);[Array]::Copy($native,$span.byte_offset,$part,0,$part.Length)
        if((Get-ConformanceHash $part) -cne $span.anchor_sha256){throw 'Pinned native source span differs'}
    }
    if($a.counterpart.path -cne 'tests/conformance/platform/windows-verybig-tempfile.lua' -or $a.counterpart.requires_T){
        throw 'Focused ordinary counterpart identity differs'
    }
    $file=Join-Path $root $a.counterpart.path
    if((Get-FileHash $file).Hash.ToLowerInvariant() -cne $a.counterpart.sha256){throw 'Focused counterpart source hash differs'}
    return $generated.Length
}
function Case($name,[scriptblock]$action){&$action;$script:cases++;Write-Output "VERYBIG WINDOWS SOURCE PASS: $name"}
function Reject([scriptblock]$action,$expected){$message=$null;try{&$action|Out-Null}catch{$message=$_.Exception.Message}
    if($null -eq $message -or $message -notmatch $expected){throw "Wrong proposal rejection: $message; expected $expected"}}
Case 'exact single expression has only an in-memory preview' {if((Check $spec $author) -ne 3729){throw 'preview size differs'}}
Case 'pending review blocks the approved equivalent path before any output' {Reject {Get-ConformanceEquivalentReplay -Root $root -Specification $spec} 'not independent and accepted'}
Case 'source bytes stay pinned' {$s=Clone $spec;$s.source_sha256='0'*64;Reject {Check $s $author} 'identity differs'}
Case 'other platforms cannot borrow this proposal' {$s=Clone $spec;$s.platform='linux';Reject {Check $s $author} 'identity differs'}
Case 'replacement cannot widen its expression' {$s=Clone $spec;$s.replacements[0].length_bytes=13;Reject {Check $s $author} '12-byte expression'}
Case 'replacement cannot shift source positions' {$s=Clone $spec;$s.replacements[0].start_byte++;Reject {Check $s $author} '12-byte expression'}
Case 'tmpname is retained rather than fabricated' {$s=Clone $spec;$s.replacements[0].replacement="'fixed-file.lua'";Reject {Check $s $author} '12-byte expression'}
Case 'separator stripping is not this exact expression' {$s=Clone $spec;$s.replacements[0].replacement="os.tmpname():sub(2)";Reject {Check $s $author} '12-byte expression'}
Case 'no adjacent skip or soft assignment is allowed' {$s=Clone $spec;$s.replacements[0].replacement="'.'..os.tmpname();_soft=true";Reject {Check $s $author} '12-byte expression'}
Case 'no second source edit can be introduced' {$s=Clone $spec;$s.replacements+=@((Clone $s.replacements[0]));Reject {Check $s $author} 'identity differs'}
foreach($flag in @('runtime_acceptance','coverage_authority','source_adaptation_authority')){Case "$flag remains false" {$s=Clone $spec;$s[$flag]=$true;Reject {Check $s $author} 'cannot grant authority'}}
Case 'no fake execution is attached' {$s=Clone $spec;$s.execution_evidence=@('passing');Reject {Check $s $author} 'invent approval or execution'}
Case 'preview hash cannot change' {$a=Clone $author;$a.generated_in_memory.sha256='0'*64;Reject {Check $spec $a} 'preview identity'}
Case 'no transformed full file has been emitted' {$a=Clone $author;$a.generated_in_memory.emitted=$true;Reject {Check $spec $a} 'non-emission'}
Case 'counterpart drift requires new review' {$a=Clone $author;$a.counterpart.sha256='0'*64;Reject {Check $spec $a} 'counterpart source hash'}
Case 'prefix preservation is byte exact' {$a=Clone $author;$a.preserved.prefix.sha256='0'*64;Reject {Check $spec $a} 'Unpatched source'}
Case 'suffix preservation is byte exact' {$a=Clone $author;$a.preserved.suffix.sha256='0'*64;Reject {Check $spec $a} 'Unpatched source'}
Case 'port and soft flags are not applicability evidence' {$a=Clone $author;$a.preserved.port_flag_added=$true;Reject {Check $spec $a} 'unpatched workload'}
Case 'prefix descriptor covers every untouched initial byte' {$a=Clone $author;$a.preserved.prefix.byte_length=0;Reject {Check $spec $a} 'interval descriptors differ'}
Case 'suffix descriptor covers every untouched final byte' {$a=Clone $author;$a.preserved.suffix.byte_length=0;Reject {Check $spec $a} 'interval descriptors differ'}
Case 'pinned native implementation source must stay current' {$a=Clone $author;$a.native_source_evidence.sha256='0'*64;Reject {Check $spec $a} 'native source binding'}
Case 'pinned native implementation span must stay current' {$a=Clone $author;$a.native_source_evidence.spans[0].anchor_sha256='0'*64;Reject {Check $spec $a} 'native source span'}
Write-Output "PASS: $script:cases exact verybig Windows proposal cases; no transformed whole-file emission or Lua execution"
