param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceReviewedSources.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$base='tests/conformance/targets/remaining-upstream-compatibility/'
$inventory=Test-ConformanceInventory -Root $root -TargetPolicy remaining-upstream-compatibility
$resolved=@{};foreach($entry in $inventory.Exclusions){$resolved[$entry.id]=$entry}
$policyHash=(Get-FileHash (Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility.exclusions.json')).Hash.ToLowerInvariant()
$temporary=Join-Path $root ('reports/reviewed-source-tests/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Case($Description,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "REVIEWED SOURCE PASS: $Description"}
function Reject([scriptblock]$Action,$Pattern){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $Pattern){throw "Wrong reviewed source rejection: $failure; expected $Pattern"}}
function Load($Name){return Get-Content (Join-Path $root ($base+$Name)) -Raw|ConvertFrom-Json -AsHashtable -Depth 64}
function Replay($Mapping,$SourceRoot=$root,$Implementation='Ada',$Configuration='upstream-test'){
    Get-TargetReviewedSourceReplay -Root $SourceRoot -Specification $Mapping -Implementation $Implementation -Configuration $Configuration `
        -PolicySha256 $policyHash -ResolvedExclusions $resolved
}
foreach($name in @('api-private-bound-and-userdata-lifetimes.composite.json','calls-undump-constant-pool.equivalent.json','memerr-verifier-allocation.equivalent.json')){
    Case "actual independent source review reconstructs $name without runtime authority" {
        $m=Load $name;$r=Replay $m
        if($r.sha256 -cne $m.output_sha256 -or $r.review_status -cne 'accepted' -or $r.diagnostic_only -or
            $r.runtime_acceptance -or $r.coverage_authority){throw 'Source selection gained false authority or changed reviewed bytes'}
    }
    Case "original native C cannot select $name" {$m=Load $name;Reject {Replay $m $root ReferenceC} 'instrumented Ada'}
    Case "default configuration cannot select $name" {$m=Load $name;Reject {Replay $m $root Ada default} 'instrumented Ada'}
    Case "pending review cannot authorize $name" {$m=Load $name;$m.review.status='pending';Reject {Replay $m} 'accepted source-only'}
}
Case 'decoded-string selection rejects a widened original span' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.replacements[0].length_bytes++;Reject {Replay $m} 'exact retained operations'}
Case 'decoded-string selection cannot replace retained execution with an early return' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.replacements[0].replacement='return';Reject {Replay $m} 'exact retained operations'}
Case 'decoded-string source-only equivalent cannot invent an exclusion' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.source_exclusions=@('invented');Reject {Replay $m} 'Unsupported or widened'}
Case 'original required assertion remains a pending obligation' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.original_required_obligations=@();Reject {Replay $m} 'Unsupported or widened'}
Case 'source decision cannot grant runtime acceptance' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.runtime_acceptance=$true;Reject {Replay $m} 'accepted source-only'}
Case 'source review author cannot approve its own changed mapping' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.review.reviewer=$m.review.author;Reject {Replay $m} 'independent|review'}
Case 'feature review cannot disappear behind exact source text' {$m=Load 'calls-undump-constant-pool.equivalent.json';$m.feature_review.sha256='0'*64;Reject {Replay $m} 'hash differs'}

function Save($Fixture,$Path,$Value){
    $full=Join-Path $Fixture $Path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
    [IO.File]::WriteAllText($full,(ConvertTo-Json -InputObject $Value -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return (Get-FileHash $full).Hash.ToLowerInvariant()
}
function New-SourceFixture {
    # Negative review mutations live in a disposable source graph. None are
    # installed approvals or execution observations; original files stay intact.
    $fixture=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
    $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($base+'calls-undump-constant-pool.equivalent.json');$seen=@{}
    function Add-Paths($Value){
        if($Value -is [Collections.IDictionary]){foreach($key in $Value.Keys){Add-Paths $Value[$key]}}
        elseif($Value -is [Array]){foreach($item in $Value){Add-Paths $item}}
        elseif($Value -is [string] -and $Value -cmatch '^(?:references|tests|src|scripts|c_api|docs|experiments)/[A-Za-z0-9_./#-]+$'){
            $p=$Value.Split('#')[0];if(Test-Path -LiteralPath (Join-Path $root $p) -PathType Leaf){$queue.Enqueue($p)}
        }
    }
    while($queue.Count){$p=$queue.Dequeue();if($seen.ContainsKey($p)){continue};$seen[$p]=$true
        $full=Join-Path $fixture $p;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full));Copy-Item -LiteralPath (Join-Path $root $p) -Destination $full
        if($p.EndsWith('.json')){Add-Paths (Get-Content $full -Raw|ConvertFrom-Json -AsHashtable -Depth 64)}
    }
    return $fixture
}
Case 'synthetic approval cannot authorize actual source emission' {
    $f=New-SourceFixture;$m=Load 'calls-undump-constant-pool.equivalent.json'
    $a=Get-Content (Join-Path $f $m.review.artifact) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $a.synthetic_fixture=$true;$m.review.artifact_sha256=Save $f $m.review.artifact $a
    Reject {Replay $m $f} 'actual source-only independent decisions'
}
Case 'synthetic narrative cannot inherit an actual approval label' {
    $f=New-SourceFixture;$m=Load 'calls-undump-constant-pool.equivalent.json'
    $a=Get-Content (Join-Path $f $m.review.artifact) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $d=$a.decisions[0].review_evidence;$v=Get-Content (Join-Path $f $d.path) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $v.synthetic_fixture=$true;$d.sha256=Save $f $d.path $v;$m.review.artifact_sha256=Save $f $m.review.artifact $a
    Reject {Replay $m $f} 'actual source-only independent decisions'
}
Case 'changed public pointer counterpart invalidates the exact source approval' {
    $f=New-SourceFixture;$m=Load 'calls-undump-constant-pool.equivalent.json'
    [IO.File]::AppendAllText((Join-Path $f 'c_api/tests/pointer_identity_contract.c'),'/* synthetic changed source */')
    Reject {Replay $m $f} 'hash differs'
}
Case 'disposable generator cannot write into the pinned reference tree' {
    $source=Join-Path $root 'references/lua/testes/api.lua';$before=(Get-FileHash $source).Hash
    $p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',
        (Join-Path $PSScriptRoot 'New-ConformanceReviewedSource.ps1'),'-Manifest',
        (Join-Path $root ($base+'api-private-bound-and-userdata-lifetimes.composite.json')),'-Output',$source) `
        -Directory $root -OutputPrefix (Join-Path $temporary 'forbidden-output') -TimeoutSeconds 60
    if($p.exit_code -eq 0 -or (Get-FileHash $source).Hash -cne $before -or
        [IO.File]::ReadAllText($p.stderr_path) -notmatch 'new disposable reports artifact'){throw 'Generator changed or accepted a pinned reference destination'}
}
Case 'disposable generator cannot overwrite an existing observation artifact' {
    $output=Join-Path $temporary 'existing.lua';[IO.File]::WriteAllText($output,'preserved observation artifact')
    $before=(Get-FileHash $output).Hash
    $p=Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',
        (Join-Path $PSScriptRoot 'New-ConformanceReviewedSource.ps1'),'-Manifest',
        (Join-Path $root ($base+'calls-undump-constant-pool.equivalent.json')),'-Output',$output) `
        -Directory $root -OutputPrefix (Join-Path $temporary 'existing-output') -TimeoutSeconds 60
    if($p.exit_code -eq 0 -or (Get-FileHash $output).Hash -cne $before){throw 'Generator overwrote a prior observation artifact'}
}
Write-Output "PASS: $script:cases bounded reviewed source selection regressions; source reconstruction and explicit negative fixtures only, no Lua execution"
