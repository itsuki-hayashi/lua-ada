param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceLocalsEquivalent.psm1') -Force
$base='tests/conformance/targets/remaining-upstream-compatibility/'
$legacy=Get-Content (Join-Path $root ($base+'locals-dead-table-storage.equivalent.json')) -Raw|
    ConvertFrom-Json -AsHashtable -Depth 64
$extra=@('tests/src/lua-conformance_memory.adb','tests/lua/scalar_closing_refusal.lua',
    'tests/lua/scalar_closing_mutation.lua',
    'tests/src/lua-scalar_closing_tests.ads','tests/src/lua-scalar_closing_tests.adb',
    'tests/src/lua-closing_prefix_tests.adb','tests/src/lua-execution_retirement_tests.adb',
    'src/lua-engine-stacks.ads','src/lua-engine-canonical.ads','src/lua-engine-machine.ads',
    'tests/src/lua-conformance_memory.ads','tests/src/lua-closing_prefix_tests.ads',
    'tests/src/lua-execution_retirement_tests.ads','tests/src/lua-storage-conformance.ads',
    'tests/src/lua-storage-conformance.adb','tests/src/lua-conformance_allocator.ads',
    'tests/src/lua-conformance_allocator.adb')
$paths=@($legacy.counterpart_source_snapshot.bindings.path)+$extra
$mapping=$legacy|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64
$mapping.review=@{status='pending';author='Codex /root';reviewer=$null;artifact=$null;artifact_sha256=$null}
$mapping.counterpart_source_snapshot=@{repository_revision=(&git -C $root rev-parse HEAD).Trim();
    binding_schema_version=2;pending_owner_guard_and_resetCI_changes_not_included=$false;
    bindings=@($paths|ForEach-Object{@{path=$_;sha256=(Get-FileHash (Join-Path $root $_)).Hash.ToLowerInvariant()}})}
foreach($patch in $mapping.replacements){$patch.counterpart_tests=@($paths)}
$temporary=Join-Path $root ('reports/locals-closing-successor/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Clone {return $mapping|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64}
function Case($Description,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "LOCALS SUCCESSOR PASS: $Description"}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $Pattern){throw "Wrong successor rejection: $failure; expected $Pattern"}
}
function Definition($Value,$SourceRoot=$root){Assert-TargetLocalsTableEquivalentDefinition -Root $SourceRoot -Specification $Value}
function Fixture {
    $directory=Join-Path $temporary ([guid]::NewGuid().ToString('N'))
    foreach($path in @($paths)+@($mapping.source)){
        $file=Join-Path $directory $path;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $file
    }
    return $directory
}
# Positive checks validate pending, exact source definitions only. They neither
# construct output Lua bytes nor produce an accepted approval. Negative review
# labels below are mutated inputs, never installed or actual review authority.
Case 'explicit V2 binds all39 current paths and exactly the same two original operations'{
    $r=Definition (Clone)
    if($r.counterpart_binding_version -ne 2 -or $r.counterpart_count -ne 39 -or $r.source_emission -or
        $r.planned_sha256 -cne '54481f4b2c760ef1f8efd747706a3e6eb02553f582e15210aaaab6ec72c448d8' -or
        $r.runtime_acceptance -or $r.coverage_authority){throw 'Pending definition gained source/runtime authority'}
}
Case 'V1 accepted identity remains exactly the independently reviewed dated76 tuple'{
    $hash=& (Get-Module ConformanceLocalsEquivalent) {param($s)Get-LocalsCounterpartSnapshotHash $s} $legacy.counterpart_source_snapshot
    if($hash -cne '981f4ceb94d7a272c41f3e2c29f8836c4e8abd351d36f6edf070f5a24ad01f01'){
        throw 'Dated V1 counterpart tuple changed'
    }
    Reject {Get-TargetLocalsTableEquivalentReplay -Root $root -Specification $legacy -Implementation Ada -Configuration upstream-test} 'Review file hash differs'
}
foreach($version in @('2',1,3)){
    Case "unsupported or coerced binding version $version cannot change historical meaning"{
        $m=Clone;$m.counterpart_source_snapshot.binding_schema_version=$version
        Reject {Definition $m} 'Unsupported locals counterpart binding schema'
    }
}
Case 'dropping the V2 tag cannot pass39 paths through the V1 contract'{
    $m=Clone;[void]$m.counterpart_source_snapshot.Remove('binding_schema_version')
    Reject {Definition $m} 'counterpart set'
}
foreach($path in $extra){
    Case "a current closing dependency cannot disappear: $path"{
        $m=Clone;$m.counterpart_source_snapshot.bindings=@($m.counterpart_source_snapshot.bindings|Where-Object path -CNE $path)
        Reject {Definition $m} 'snapshot is incomplete'
    }
}
Case 'the actual memory checker must also be named in each independently reviewed operation'{
    $m=Clone;$m.replacements[0].counterpart_tests=@($m.replacements[0].counterpart_tests|Where-Object{$_ -cne 'tests/src/lua-conformance_memory.adb'})
    Reject {Definition $m} 'counterpart set'
}
Case 'an extra unreviewed source cannot silently enter the closed successor'{
    $m=Clone;$m.counterpart_source_snapshot.bindings+=@{path='src/lua.adb';sha256=('0'*64)}
    Reject {Definition $m} 'snapshot is incomplete'
}
Case 'a duplicate valid dependency cannot replace the actual checker identity'{
    $m=Clone;$m.counterpart_source_snapshot.bindings[0]=$m.counterpart_source_snapshot.bindings[1]
    Reject {Definition $m} 'snapshot is incomplete'
}
foreach($path in @('tests/src/lua-conformance_memory.adb','src/lua-engine-collector.adb','src/lua-engine-stacks.adb')){
    Case "changed checker/root bytes need a fresh source decision: $path"{
        $directory=Fixture;[IO.File]::AppendAllText((Join-Path $directory $path),"-- stale source fixture`n")
        Reject {Definition (Clone) $directory} 'Review file hash differs'
    }
}
Case 'current39 source claims cannot be relabelled a renewed accepted V1 snapshot'{
    $m=Clone;[void]$m.counterpart_source_snapshot.Remove('binding_schema_version')
    $m.counterpart_source_snapshot.bindings=@($m.counterpart_source_snapshot.bindings|Where-Object path -CNotIn $extra)
    foreach($patch in $m.replacements){$patch.counterpart_tests=@($patch.counterpart_tests|Where-Object{$_ -cnotin $extra})}
    $m.review.status='accepted';$m.review.reviewer='synthetic-independent-reviewer'
    Reject {Get-TargetLocalsTableEquivalentReplay -Root $root -Specification $m -Implementation Ada -Configuration upstream-test} 'Legacy V1 locals approval is frozen'
}
Case 'a pending V2 source definition supplies no adapted byte replay'{
    Reject {Get-TargetLocalsTableEquivalentReplay -Root $root -Specification (Clone) -Implementation Ada -Configuration upstream-test} 'new independent exact source review'
}
Case 'original and revision authors still cannot approve this successor'{
    foreach($author in @('Codex /root','Codex /root/remaining_suite')){
        $m=Clone;$m.review.status='accepted';$m.review.reviewer=$author
        Reject {Get-TargetLocalsTableEquivalentReplay -Root $root -Specification $m -Implementation Ada -Configuration upstream-test} 'outside both authors'
    }
}
Case 'the expanded checker contract cannot weaken the exact zero-after count'{
    $m=Clone;$m.replacements[1].replacement=$m.replacements[1].replacement.Replace('live == 0','live >= 0')
    Reject {Definition $m} 'two exact retained operations'
}
Write-Output "PASS: $script:cases locals closing binding guards; pending/non-execution metadata only, no source emitted or approved"
