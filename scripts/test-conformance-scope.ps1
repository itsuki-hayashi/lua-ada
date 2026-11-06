param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$temporary = Join-Path $root ('reports/scope-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
foreach ($name in @('suite.json','c-api.jsonl','coverage','scopes')) {
    Copy-Item -LiteralPath (Join-Path $root "tests/conformance/$name") -Destination $temporary -Recurse
}
$definitionPath = Join-Path $temporary 'scopes/gc-io-events.json'
$originalDefinition = [IO.File]::ReadAllText($definitionPath)
$script:Cases = 0
function Test-Rejected {
    param([string] $Name, [scriptblock] $Mutate, [string] $Expected,
          [switch] $Complete)
    $definition = $originalDefinition | ConvertFrom-Json -AsHashtable -Depth 32
    & $Mutate $definition
    [IO.File]::WriteAllText($definitionPath, ($definition | ConvertTo-Json -Depth 32) + "`n")
    $errorMessage = $null
    try { Test-ConformanceScope -Root $root -InventoryDirectory $temporary `
        -RequireScopedComplete:$Complete | Out-Null }
    catch { $errorMessage = $_.Exception.Message }
    if ($null -eq $errorMessage -or $errorMessage -notmatch $Expected) {
        throw "Scope negative failed ($Name): $errorMessage; expected $Expected"
    }
    $script:Cases++
    Write-Output "SCOPE TEST PASS: $Name"
    [IO.File]::WriteAllText($definitionPath, $originalDefinition)
}
$baseline = Test-ConformanceScope -Root $root -InventoryDirectory $temporary
if ($baseline.Files -ne 4 -or $baseline.SourceAnchors -lt 762 -or
    $baseline.ApiEntries -ne 77 -or $baseline.ScopeComplete -or $baseline.FullM3Complete -or
    $baseline.StructuralInventory.SourceAnchors -lt 4490 -or
    $baseline.StructuralInventory.ApiEntries -ne 473) { throw 'Incorrect scoped foundation result' }
$script:Cases++
Write-Output 'SCOPE TEST PASS: full structural inventory and separate incomplete scope'
$apiPath = Join-Path $temporary 'scopes/gc-io-events.api.jsonl'
$originalApi = [IO.File]::ReadAllText($apiPath)
function Test-ApiRejected {
    param([string] $Name, [scriptblock] $Mutate, [string] $Expected)
    $entries = @(Get-Content -LiteralPath $apiPath | ForEach-Object {
        ConvertFrom-Json -InputObject $_ -AsHashtable -Depth 32
    })
    $entries = @(& $Mutate $entries)
    [IO.File]::WriteAllLines($apiPath, [string[]]@($entries | ForEach-Object {
        ConvertTo-Json -InputObject $_ -Compress -Depth 32
    }))
    try { Test-Rejected $Name { param($d) } $Expected }
    finally { [IO.File]::WriteAllText($apiPath, $originalApi) }
}
Test-ApiRejected 'missing scoped API record' { param($e) $e | Select-Object -Skip 1 } 'coverage set changed'
Test-ApiRejected 'duplicate scoped API record' { param($e) $e[1]=$e[0]; $e } 'Duplicate scoped API coverage'
Test-ApiRejected 'scoped API header drift' { param($e) $e[0].declaration='invented'; $e } 'anchor drift'
Test-ApiRejected 'scoped API needs behavioral invariant' { param($e) $e[0].status='passed'; $e } 'invariant missing'
Test-ApiRejected 'scoped API cannot self-review' { param($e)
    $e[0].status='passed'; $e[0].invariant='synthetic fixture'
    $e[0].review=@{author='same'; reviewer='same'; artifact='synthetic'; rationale='synthetic'; original_c_evidence='synthetic'}
    $e
} 'cannot self-review'
Test-Rejected 'missing selected file' { param($d) $d.files = @($d.files | Select-Object -Skip 1) } 'all four'
Test-Rejected 'duplicate selected file' { param($d) $d.files += $d.files[0] } 'all four'
Test-Rejected 'missing API obligation' { param($d) $d.api_ids = @($d.api_ids | Select-Object -Skip 1) } 'Missing scoped API'
Test-Rejected 'duplicate API obligation' { param($d) $d.api_ids += $d.api_ids[0] } 'Duplicate scoped API'
Test-Rejected 'invented API obligation' { param($d) $d.api_ids += 'CAPI-FAKE' } 'Unknown scoped API'
Test-Rejected 'changed source hash' { param($d) $d.files[0].sha256 = '0' * 64 } 'source hash drift'
Test-Rejected 'missing IO prerequisites' { param($d) $d.prerequisites = @('stdio') } 'prerequisites changed'
Test-Rejected 'pending independent scope review' { param($d) } 'independent review' -Complete
Test-Rejected 'self-reviewed scope' { param($d)
    $d.review.status='reviewed'; $d.review.reviewer=$d.review.author; $d.review.artifact='synthetic-fixture'
} 'independent review'
Test-Rejected 'review does not resolve runtime coverage' { param($d)
    $d.review.status='reviewed'; $d.review.reviewer='synthetic-independent-reviewer'; $d.review.artifact='synthetic-fixture'
} 'Unresolved coverage' -Complete
# An out-of-scope source partition is still structurally mandatory.
$outside = Join-Path $temporary 'coverage/strings.jsonl'
$originalOutside = [IO.File]::ReadAllText($outside)
[IO.File]::WriteAllLines($outside, @([IO.File]::ReadAllLines($outside) | Select-Object -Skip 1))
Test-Rejected 'corrupt unrelated inventory' { param($d) } 'anchor set changed|Missing source anchor'
[IO.File]::WriteAllText($outside, $originalOutside)
$failure = $null
try { Test-ConformanceInventory -Root $root -InventoryDirectory $temporary -RequireComplete | Out-Null }
catch { $failure = $_.Exception.Message }
if ($failure -notmatch 'Unresolved coverage') { throw 'Full M3 completion was weakened' }
$script:Cases++
Write-Output 'SCOPE TEST PASS: full M3 completion still rejects unresolved coverage'
$stdoutPath = Join-Path $temporary 'synthetic-process.stdout'
function Test-ProcessWitness {
    param([string] $Name, [string] $File, [string] $Output,
          [scriptblock] $Mutate = {}, [string] $Expected = '')
    [IO.File]::WriteAllText($stdoutPath, $Output)
    $process = @{ exit_code=0; timed_out=$false; capture_exceeded=$false;
        pipe_drain_failed=$false; process_tree_kill_error=$null;
        process_id=123; stdout_path=$stdoutPath }
    $telemetry = @{schema_version=1; process_id=123; run_id='synthetic'; configuration='upstream-test';
        allocator_limit_bytes=2147483648L; managed_refusals=0; outstanding_bytes=0;
        outstanding_blocks=0; shutdown_complete=$true; accounting_fault=$false}
    & $Mutate $process $telemetry
    $failure = $null
    try { Assert-ScopedProcessCompletion -File $File -Process $process -Telemetry $telemetry `
        -RunId 'synthetic' -Configuration upstream-test }
    catch { $failure = $_.Exception.Message }
    if (($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))) {
        throw "Scoped process witness failed ($Name): $failure; expected $Expected"
    }
    $script:Cases++
    Write-Output "SCOPE TEST PASS: $Name"
}
Test-ProcessWitness 'GC requires closing-state assertions' gc.lua "OK`n" -Expected 'state-close'
Test-ProcessWitness 'GC closing witness follows OK' gc.lua ">>> closing state <<<`nOK`n" -Expected 'state-close'
Test-ProcessWitness 'embedded OK cannot spoof closure order' gc.lua "ignored OK`n>>> closing state <<<`nOK`n" -Expected 'state-close'
Test-ProcessWitness 'GC rejects early return' gc.lua "testing collector`n" -Expected 'final OK'
Test-ProcessWitness 'files rejects OK without final date' files.lua "OK`n" -Expected 'date/version'
Test-ProcessWitness 'files requires final version' files.lua "test done on 01/01/2026, at 00:00:00`n" -Expected 'date/version'
Test-ProcessWitness 'balanced GC shutdown witness' gc.lua "OK`n>>> closing state <<<`n"
Test-ProcessWitness 'final files date witness' files.lua "test done on 01/01/2026, at 00:00:00`nLua 5.5`n"
Test-ProcessWitness 'successful output cannot hide timeout' events.lua "OK`n" { param($p,$t) $p.timed_out=$true } 'complete cleanly'
Test-ProcessWitness 'missing physical shutdown fails' events.lua "OK`n" { param($p,$t) $t.shutdown_complete=$false } 'shutdown'
Test-ProcessWitness 'leaked blocks fail scoped completion' events.lua "OK`n" { param($p,$t) $t.outstanding_blocks=1 } 'unbalanced'
Test-ProcessWitness 'wrong child configuration fails' events.lua "OK`n" { param($p,$t) $t.configuration='default' } 'Mismatched'
Write-Output "PASS: $script:Cases scoped inventory/process regressions"
