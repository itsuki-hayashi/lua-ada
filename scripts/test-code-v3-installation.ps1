param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceExclusionEligibility.psm1')
$base='tests/conformance/targets/remaining-upstream-compatibility'
$script:cases=0
function ReadJson($path){Get-Content (Join-Path $root $path) -Raw|ConvertFrom-Json -AsHashtable -Depth 100}
function CopyValue($value){ConvertTo-Json -InputObject $value -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100}
function Check($condition,$message){if(-not $condition){throw $message}}
function Case($name,[scriptblock]$action){&$action;$script:cases++;Write-Output "CODE8 SOURCE GUARD PASS: $name"}
function Reject([scriptblock]$action,$pattern){
    $failure=$null
    try{&$action|Out-Null}catch{$failure=$_.Exception.Message}
    Check ($null -ne $failure -and $failure -match $pattern) "Wrong source rejection: $failure; expected $pattern"
}
$inventory=Test-ConformanceInventory -Root $root -TargetPolicy remaining-upstream-compatibility
$policyHash=(Get-FileHash (Join-Path $root ($base+'.exclusions.json'))).Hash.ToLowerInvariant()
$resolved=@{};foreach($entry in $inventory.Exclusions){$resolved[$entry.id]=$entry}
$code=ReadJson ($base+'/code-private-optimizer-v3.transform.json')
$api=ReadJson ($base+'/api-fixed-buffer-private-bound.transform.json')
function Replay($value,$entries=$resolved){Get-ConformanceTReplay -Root $root -Specification $value -PolicySha256 $policyHash -ResolvedExclusions $entries}
$codeBytes=[IO.File]::ReadAllBytes((Join-Path $root 'references/lua/testes/code.lua'))
$records=@(Read-ConformanceJsonLines (Join-Path $root 'tests/conformance/coverage/code.jsonl'))
$original=@(Read-ConformanceJsonLines (Join-Path $root ($base+'/reviews/code-v3-installation-inputs/code.original-51.jsonl')))
$byId=@{};foreach($r in $records){$byId[$r.id]=$r}

# These checks inspect real installed source metadata and normal readers.
# They neither execute Lua nor emit an adapted file, and exclusions never
# become passing tests. Mutated objects below stay in memory as negatives.
Case 'normal inventory has exactly API18 plus eight closed Code exclusions' {
    $expected=@('LUA-API-REVIEWED-BLOCK-9001')+@(9001..9008|ForEach-Object {'LUA-CODE-REVIEWED-BLOCK-'+$_})
    Check ($inventory.ExcludedSourceObligations -eq 9 -and
        (($resolved.Keys|Sort-Object)-join '|') -ceq (($expected|Sort-Object)-join '|') -and
        -not $inventory.TargetComplete -and -not $inventory.Complete) 'Unexpected source policy or false completion'
}
Case 'the frozen 51-record input and all current original identities remain exact' {
    Check ((Get-FileHash (Join-Path $root ($base+'/reviews/code-v3-installation-inputs/code.original-51.jsonl'))).Hash.ToLowerInvariant() -ceq
        '27231932dffbd450a7fbdabfbf0de2c9edafd4ab0bbaecf3a16457af98e5fd94') 'Frozen input changed'
    Check ($original.Count -eq 51 -and $records.Count -eq 68) 'Original/derived ledger count differs'
    foreach($r in $original){
        Check ($byId.Contains($r.id) -and -not $resolved.Contains($r.id)) 'Original deleted or excluded'
        foreach($key in @('id','kind','byte_offset','byte_length','line','end_line','anchor_sha256')){
            Check ($byId[$r.id][$key] -ceq $r[$key]) "Original source identity changed: $($r.id)/$key"
        }
        Check (@($byId[$r.id].evidence).Count -eq 0 -and $byId[$r.id].status -cne 'passed') 'Original gained invented execution'
    }
}
Case '18 exact references retain private children and all nine required public nodes' {
    $references=@($records|Where-Object status -CEQ reviewed)
    $public=@($records|Where-Object {$_.id -match '^LUA-CODE-REVIEWED-BLOCK-901[1-9]$'})
    Check ($references.Count -eq 18 -and $public.Count -eq 9) 'Closed decomposition changed'
    foreach($r in $references){
        Check ($r.classification -ceq 'reference' -and $r.review.author -ceq 'Codex /root/validation_delivery' -and
            $r.review.reviewer -ceq 'Codex /root/remaining_suite') 'Classification author/reviewer differs'
        $required=@($r.obligations|Where-Object {$_ -match '901[1-9]$'})
        Check ($required.Count -gt 0) 'Reference links only to private exclusion'
        foreach($id in $required){Check ($byId[$id].status -ceq 'pending' -and @($byId[$id].evidence).Count -eq 0) 'Public requirement completed without runtime'}
    }
    Reject {Test-ConformanceSourceLinks -Records $records -RequireComplete -TargetPolicy remaining-upstream-compatibility -ResolvedExclusions $resolved} 'Linked runtime obligation remains pending'
}
Case 'all derived line metadata follows the existing exclusive-byte-end convention' {
    $text=[Text.Encoding]::Latin1.GetString($codeBytes)
    foreach($r in $records|Where-Object kind -CEQ reviewed-block){
        $first=1+[regex]::Matches($text.Substring(0,$r.byte_offset),'\r\n|\n\r|\n|\r').Count
        $last=1+[regex]::Matches($text.Substring(0,$r.byte_offset+$r.byte_length),'\r\n|\n\r|\n|\r').Count
        Check ($r.line -eq $first -and $r.end_line -eq $last) "Wrong manual line: $($r.id)"
    }
    $review=ReadJson ($base+'/reviews/code-v3-installation.independent-review.json')
    Check ($review.derived_metadata_corrections.Count -eq 12) 'Dated correction record missing'
}
Case 'normal Code8 reconstruction preserves exact checkR and expected output without runtime authority' {
    $r=Replay $code
    $checkR=[Text.Encoding]::Latin1.GetString($codeBytes[2079..2205])
    Check (-not $r.diagnostic_only -and $r.review_status -ceq 'accepted' -and $r.bytes.Length -eq 14299 -and
        $r.sha256 -ceq '676304c019ee3afe8796da7ddfaf8f14cba43c2c49332d96f19b3f4c84211fe0' -and
        [Text.Encoding]::Latin1.GetString($r.bytes).Contains($checkR,[StringComparison]::Ordinal)) 'Code reconstruction/checkR differs'
    Check (-not $code.runtime_acceptance -and -not $code.coverage_authority -and @($code.execution_evidence).Count -eq 0) 'Transform gained runtime credit'
}
Case 'normal API18 successor keeps the exact mixed assertion and both pending parents' {
    $r=Replay $api;$text=[Text.Encoding]::Latin1.GetString($r.bytes)
    Check ($r.sha256 -ceq '51389bf3404ab2f13ae88a8cc3f88e7188ac0639f77b7871f4c9baf1830492bc' -and
        $text.Contains('assert(m2 > m1)') -and $text.Contains('X = 0; code(); assert(X == N and Y == string.rep("a", N))') -and
        $text.Contains('checkerr(":301:", code)')) 'API retained behavior differs'
    $rows=@(Read-ConformanceJsonLines (Join-Path $root 'tests/conformance/coverage/api.jsonl'))
    foreach($id in @('LUA-API-ASSERT-CALL-0125','LUA-API-ASSERT-CALL-0195')){
        $parent=@($rows|Where-Object id -CEQ $id)
        Check ($parent.Count -eq 1 -and $parent[0].status -ceq 'pending' -and @($parent[0].evidence).Count -eq 0) 'API parent completed'
    }
}
Case 'replacement and resolved-dictionary permutations preserve the accepted bytes' {
    $changed=CopyValue $code;$changed.replacements=@($changed.replacements|Sort-Object start_byte -Descending)
    $entries=@{};foreach($id in $resolved.Keys|Sort-Object -Descending){$entries[$id]=$resolved[$id]}
    Check ((Replay $changed $entries).sha256 -ceq $code.output_sha256) 'Permutation changed exact output'
}
Case 'pending status and self-review cannot use actual transform approval' {
    $changed=CopyValue $code;$changed.review.status='pending'
    Reject {Replay $changed} 'lacks independent semantic approval'
    $changed=CopyValue $code;$changed.review.reviewer=$changed.review.author
    Reject {Replay $changed} 'author cannot approve'
}
Case 'bad approval hash and changed source identity are rejected by normal readers' {
    $changed=CopyValue $code;$changed.review.artifact_sha256='0'*64
    Reject {Replay $changed} 'Review file hash differs'
    $changed=CopyValue $code;$changed.source_sha256='0'*64
    Reject {Replay $changed} 'Review file hash differs'
}
Case 'current policy binding rejects the retired API18 manifest and fabricated policy hash' {
    $old=ReadJson ($base+'/reviews/code-v3-installation-inputs/api18.pre-code-policy.transform.json')
    Reject {Replay $old} 'Invalid T transform identity or exclusion policy hash'
    $changed=CopyValue $code;$changed.exclusion_policy_sha256='0'*64
    Reject {Replay $changed} 'Invalid T transform identity or exclusion policy hash'
}
Case 'widening and duplicate exclusions cannot consume retained source' {
    $changed=CopyValue $code;$changed.replacements[0].length_bytes++
    Reject {Replay $changed} 'wider than or differs'
    $changed=CopyValue $code;$changed.replacements+=@($changed.replacements[0])
    Reject {Replay $changed} 'missing or duplicate approved exclusions'
}
Case 'executable and unterminated-comment replacements remain forbidden' {
    $changed=CopyValue $code;$changed.replacements[0].replacement='do end'
    Reject {Replay $changed} 'introduces executable behavior'
    $changed=CopyValue $code;$changed.replacements[0].replacement='-- swallow'
    Reject {Replay $changed} 'comment must terminate'
}
Case 'default configuration and any overlap with checkR are rejected' {
    $changed=CopyValue $code;$changed.configuration='default'
    Reject {Replay $changed} 'Invalid T transform identity'
    $changed=CopyValue $code;$changed.replacements[0].start_byte=2079;$changed.replacements[0].length_bytes=127
    Reject {Replay $changed} 'cannot alter code.lua checkR'
}
Case 'source-reference classification still requires a distinct reviewer' {
    $changed=CopyValue (@($records|Where-Object status -CEQ reviewed)[0]);$changed.review.reviewer=$changed.review.author
    Reject {Test-ConformanceResolvedRecord -Record $changed -Contexts @('upstream-test/windows/validation/static')} 'Missing independent classification review'
}
Write-Output "PASS: $script:cases installed Code8/API18 source guards; no Lua execution, adapted file emission or runtime acceptance"
