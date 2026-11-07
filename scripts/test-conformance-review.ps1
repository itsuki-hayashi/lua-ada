param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path $root ('reports/review-binding-selftest/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases = 0
# Content-addressed counterparts must retain their reviewed bytes after a
# Windows checkout. Exercise Git's actual checkout conversion with autocrlf
# enabled; hashing normalized text in the validator would hide this defect.
$checkoutFixture = Join-Path $temporary 'checkout'
[void][IO.Directory]::CreateDirectory($checkoutFixture)
Copy-Item -LiteralPath (Join-Path $root '.gitattributes') -Destination $checkoutFixture
$luaBytes = "assert(true)`nassert(1 == 1)`n"
[IO.File]::WriteAllText((Join-Path $checkoutFixture 'counterpart.lua'), $luaBytes, [Text.UTF8Encoding]::new($false))
& git -C $checkoutFixture init --quiet
if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize checkout regression' }
& git -C $checkoutFixture -c core.autocrlf=true add .gitattributes counterpart.lua
if ($LASTEXITCODE -ne 0) { throw 'Cannot stage checkout regression' }
$checkoutOutput = (Join-Path $checkoutFixture 'materialized').Replace('\', '/') + '/'
& git -C $checkoutFixture -c core.autocrlf=true checkout-index --all --prefix=$checkoutOutput
if ($LASTEXITCODE -ne 0) { throw 'Cannot materialize checkout regression' }
if ((Get-FileHash -LiteralPath (Join-Path $checkoutFixture 'counterpart.lua')).Hash -cne
    (Get-FileHash -LiteralPath (Join-Path $checkoutOutput 'counterpart.lua')).Hash) {
    throw 'Autocrlf checkout changed reviewed Lua counterpart bytes'
}
$script:cases++
Write-Output 'PASS: autocrlf checkout preserves reviewed Lua counterpart bytes'
# Reproduce the original missing-rule failure as a control, so this regression
# cannot pass merely because Git ignored autocrlf or reused the input file.
$attributes = Join-Path $checkoutFixture '.gitattributes'
$withoutLua = [IO.File]::ReadAllText($attributes).Replace("*.lua text eol=lf`n", '')
[IO.File]::WriteAllText($attributes, $withoutLua, [Text.UTF8Encoding]::new($false))
$controlOutput = (Join-Path $checkoutFixture 'without-lua-rule').Replace('\', '/') + '/'
& git -C $checkoutFixture -c core.autocrlf=true checkout-index --all --prefix=$controlOutput
if ($LASTEXITCODE -ne 0) { throw 'Cannot materialize checkout control' }
if ((Get-FileHash -LiteralPath (Join-Path $checkoutFixture 'counterpart.lua')).Hash -ceq
    (Get-FileHash -LiteralPath (Join-Path $controlOutput 'counterpart.lua')).Hash) {
    throw 'Missing Lua EOL rule failed to reproduce byte mismatch'
}
$script:cases++
Write-Output 'PASS: missing Lua EOL rule reproduces autocrlf byte mismatch'
function Hash-Text([string] $Text) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}
function Write-Json([string] $Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32) + "`n")
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function New-Fixture {
    $directory = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    [IO.File]::WriteAllText((Join-Path $directory 'source.lua'), 'ab')
    [IO.File]::WriteAllText((Join-Path $directory 'counterpart.lua'), 'assert(true)')
    $narrativeHash = Write-Json (Join-Path $directory 'narrative.json') @{reviewer='fixture-reviewer';status='changes-required'}
    $review = @{status='accepted';author='fixture-author';reviewer='fixture-reviewer';artifact='approval.json';artifact_sha256=''}
    $replacement = @{id='one';start_byte=0;length_bytes=1;source_sha256=(Hash-Text 'a');replacement='X';counterpart_tests=@('counterpart.lua#named-case')}
    $spec = @{id='synthetic';source='source.lua';source_sha256=(Hash-Text 'ab');configuration='default';platform='synthetic';disposition='native-platform-equivalent';review=$review;replacements=@($replacement)}
    $approval = @{schema_version=1;kind='equivalent-approval';author='fixture-author';reviewer='fixture-reviewer';decision='accepted';
        equivalent=@{id='synthetic';source='source.lua';source_sha256=(Hash-Text 'ab');configuration='default';platform='synthetic';disposition='native-platform-equivalent';generated_sha256=(Hash-Text 'Xb')};
        decisions=@(@{id='one';start_byte=0;length_bytes=1;source_sha256=(Hash-Text 'a');replacement_sha256=(Hash-Text 'X');
            author='fixture-author';reviewer='fixture-reviewer';decision='accepted';rationale='Synthetic review binding only';
            review_evidence=@{path='narrative.json';sha256=$narrativeHash};
            counterparts=@(@{path='counterpart.lua#named-case';sha256=(Hash-Text 'assert(true)')})})}
    $spec.review.artifact_sha256 = Write-Json (Join-Path $directory 'approval.json') $approval
    $operation = @{file='events.lua';context='default/windows/validation/static';c=@{sha256=('1'*64)};ada=@{sha256=('2'*64)};contract=@{sha256=('3'*64)}}
    $matrix = @{scope='gc-io-events';revision=('a'*40);operations=@($operation);review=@{status='accepted';author='fixture-author';reviewer='fixture-reviewer';artifact='matrix-approval.json';artifact_sha256=''}}
    $matrixApproval = @{schema_version=1;kind='matrix-approval';author='fixture-author';reviewer='fixture-reviewer';decision='accepted';scope='gc-io-events';revision=('a'*40);
        review_evidence=@{path='narrative.json';sha256=$narrativeHash};
        operations=@(@{file='events.lua';context='default/windows/validation/static';decision='accepted';c_report_sha256=('1'*64);ada_report_sha256=('2'*64);contract_sha256=('3'*64)})}
    $matrix.review.artifact_sha256=Write-Json (Join-Path $directory 'matrix-approval.json') $matrixApproval
    @{Root=$directory;Spec=$spec;Approval=$approval;Matrix=$matrix;MatrixApproval=$matrixApproval}
}
function Save-Approval($Fixture) {
    $Fixture.Spec.review.artifact_sha256=Write-Json (Join-Path $Fixture.Root 'approval.json') $Fixture.Approval
}
function Reject([string] $Name, [scriptblock] $Mutation, [string] $Expected, [switch] $Matrix) {
    $fixture=New-Fixture
    & $Mutation $fixture
    $failure=$null
    try {
        if ($Matrix) { Assert-MatrixReviewBinding -Root $fixture.Root -Manifest $fixture.Matrix }
        else { Assert-EquivalentReviewBinding -Root $fixture.Root -Specification $fixture.Spec -GeneratedSha256 (Hash-Text 'Xb') }
    } catch { $failure=$_.Exception.Message }
    if ($null -eq $failure -or $failure -notmatch $Expected) { throw "Review binding negative failed ($Name): $failure" }
    $script:cases++
    Write-Output "REVIEW TEST PASS: $Name"
}
$fixture=New-Fixture
Assert-EquivalentReviewBinding -Root $fixture.Root -Specification $fixture.Spec -GeneratedSha256 (Hash-Text 'Xb')
Assert-MatrixReviewBinding -Root $fixture.Root -Manifest $fixture.Matrix
$script:cases+=2
Write-Output 'REVIEW TEST PASS: content-bound synthetic equivalent and matrix decisions'
$mixed=New-Fixture
$mixed.Approval.decisions[0].author='fixture-reviewer'
$mixed.Approval.decisions[0].reviewer='fixture-cross-reviewer'
$mixed.Approval.decisions[0].review_evidence=@{path='cross-review.json';sha256=(Write-Json (Join-Path $mixed.Root 'cross-review.json') @{reviewer='fixture-cross-reviewer'})}
Save-Approval $mixed
Assert-EquivalentReviewBinding -Root $mixed.Root -Specification $mixed.Spec -GeneratedSha256 (Hash-Text 'Xb')
$script:cases++
Write-Output 'REVIEW TEST PASS: reviewer-authored repair has a separately bound cross-review'
Reject 'missing approval artifact' {param($f) $f.Spec.review.artifact='missing.json'} 'missing or outside'
Reject 'approval path outside repository' {param($f) $f.Spec.review.artifact='../missing.json'} 'missing or outside'
Reject 'stale approval hash' {param($f) $f.Spec.review.artifact_sha256='0'*64} 'hash differs'
Reject 'pending decision despite accepted metadata' {param($f) $f.Approval.decision='pending';Save-Approval $f} 'identity or decision'
Reject 'wrong approval reviewer' {param($f) $f.Approval.reviewer='other';Save-Approval $f} 'identity or decision'
Reject 'different original source' {param($f) $f.Approval.equivalent.source_sha256='0'*64;Save-Approval $f} 'approval differs'
Reject 'different generated bytes' {param($f) $f.Approval.equivalent.generated_sha256='0'*64;Save-Approval $f} 'generated bytes'
Reject 'different platform' {param($f) $f.Approval.equivalent.platform='other';Save-Approval $f} 'platform'
Reject 'missing span decision' {param($f) $f.Approval.decisions=@();Save-Approval $f} 'decision set'
Reject 'duplicated span decision' {param($f) $f.Approval.decisions+= $f.Approval.decisions[0];Save-Approval $f} 'decision set'
Reject 'changed span offset' {param($f) $f.Approval.decisions[0].start_byte=1;Save-Approval $f} 'span differs'
Reject 'changed replacement bytes' {param($f) $f.Spec.replacements[0].replacement='Y'} 'replacement differs'
Reject 'span self review' {param($f) $f.Approval.decisions[0].reviewer='fixture-author';Save-Approval $f} 'independent acceptance'
Reject 'span not accepted' {param($f) $f.Approval.decisions[0].decision='pending';Save-Approval $f} 'independent acceptance'
Reject 'missing narrative' {param($f) $f.Approval.decisions[0].review_evidence.path='missing.json';Save-Approval $f} 'missing or outside'
Reject 'changed narrative hash' {param($f) $f.Approval.decisions[0].review_evidence.sha256='0'*64;Save-Approval $f} 'hash differs'
Reject 'narrative reviewer mismatch' {param($f) $f.Approval.decisions[0].review_evidence.sha256=Write-Json (Join-Path $f.Root 'narrative.json') @{reviewer='other'};Save-Approval $f} 'different reviewer'
Reject 'missing counterpart decision' {param($f) $f.Approval.decisions[0].counterparts=@();Save-Approval $f} 'counterpart set'
Reject 'changed counterpart bytes' {param($f) [IO.File]::WriteAllText((Join-Path $f.Root 'counterpart.lua'),'assert(false)')} 'hash differs'
Reject 'changed counterpart case anchor' {param($f) $f.Spec.replacements[0].counterpart_tests=@('counterpart.lua#different')} 'counterpart missing'
Reject 'matrix approval stale hash' {param($f) $f.Matrix.review.artifact_sha256='0'*64} 'hash differs' -Matrix
Reject 'matrix revision differs' {param($f) $f.Matrix.revision='b'*40} 'identity or operation set' -Matrix
Reject 'matrix missing operation' {param($f) $f.Matrix.operations=@()} 'identity or operation set' -Matrix
Reject 'matrix wrong context' {param($f) $f.Matrix.operations[0].context='default/linux/validation/static'} 'missing or duplicated' -Matrix
Reject 'matrix C report differs' {param($f) $f.Matrix.operations[0].c.sha256='4'*64} 'report or contract' -Matrix
Reject 'matrix Ada report differs' {param($f) $f.Matrix.operations[0].ada.sha256='4'*64} 'report or contract' -Matrix
Reject 'matrix contract differs' {param($f) $f.Matrix.operations[0].contract.sha256='4'*64} 'report or contract' -Matrix
Write-Output "PASS: $script:cases review-artifact binding regressions; synthetic authority only"
