param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1') -Force
$root=Split-Path -Parent $PSScriptRoot
$temporary=Join-Path $root ('reports/native-review-selftest/'+[Guid]::NewGuid().ToString('N'))
$mappingPath='tests/conformance/reviews/files-native-branches.proposal.json'
$reviewPath='tests/conformance/reviews/files-native-branches.gc-cross-review.json'
function Write-Json($Path,$Value) {
    $text=($Value|ConvertTo-Json -Depth 32).Replace("`r`n","`n")+"`n"
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
    (Get-FileHash $Path).Hash.ToLowerInvariant()
}
function Fixture {
    $directory=Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    foreach($path in @($mappingPath,$reviewPath,'references/lua/testes/files.lua',
        'tests/conformance/platform/files-native-branches.lua')) {
        $destination=Join-Path $directory $path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $destination
    }
    @{Root=$directory;
      Mapping=(Get-Content (Join-Path $directory $mappingPath) -Raw|ConvertFrom-Json -AsHashtable);
      Review=(Get-Content (Join-Path $directory $reviewPath) -Raw|ConvertFrom-Json -AsHashtable);
      Identity=@{mapping=$mappingPath;review=$reviewPath;
        mapping_sha256=(Get-FileHash (Join-Path $directory $mappingPath)).Hash.ToLowerInvariant();
        review_sha256=(Get-FileHash (Join-Path $directory $reviewPath)).Hash.ToLowerInvariant()}}
}
function Save-Review($f) {
    $f.Identity.review_sha256=Write-Json (Join-Path $f.Root $reviewPath) $f.Review
}
function Save-Mapping($f) {
    $f.Identity.mapping_sha256=Write-Json (Join-Path $f.Root $mappingPath) $f.Mapping
    # Synthetic mutations update outer identity deliberately, so rejection
    # proves the inner span/decision checks rather than only a stale file hash.
    foreach($binding in $f.Review.revision_review.bindings) {
        if($binding.path -ceq $mappingPath){$binding.sha256=$f.Identity.mapping_sha256}
    }
    Save-Review $f
}
$script:cases=0
function Reject($Name,[scriptblock]$Mutation,$Expected) {
    $f=Fixture
    & $Mutation $f
    $failure=$null
    try{[void](Assert-NativeBranchReviewBinding -Root $f.Root -Identity $f.Identity)}
    catch{$failure=$_.Exception.Message}
    if($null -eq $failure -or $failure -notmatch $Expected){throw "Native review negative failed ($Name): $failure"}
    $script:cases++
    Write-Output "NATIVE REVIEW PASS: $Name"
}
$f=Fixture
$mapping=Assert-NativeBranchReviewBinding -Root $f.Root -Identity $f.Identity
if($mapping.branches.Count -ne 3){throw 'Native mapping lost an obligation'}
$script:cases++
Write-Output 'NATIVE REVIEW PASS: copied source-bound semantic approval'
Reject 'missing review' {param($f)$f.Identity.review='missing.json'} 'missing or outside'
Reject 'stale review hash' {param($f)$f.Identity.review_sha256='0'*64} 'hash differs'
Reject 'pending semantic decision' {param($f)$f.Review.revision_review.decision='pending';Save-Review $f} 'independent semantic approval'
Reject 'self review' {param($f)$f.Review.reviewer=$f.Review.author;Save-Review $f} 'independent semantic approval'
Reject 'different author' {param($f)$f.Review.author='other';Save-Review $f} 'independent semantic approval'
Reject 'absent author on both artifacts' {param($f)$f.Review.author='';$f.Mapping.author='';Save-Mapping $f} 'independent semantic approval'
Reject 'missing approved mapping binding' {param($f)$f.Review.revision_review.bindings=@();Save-Review $f} 'does not bind'
Reject 'changed counterpart bytes' {param($f)[IO.File]::AppendAllText((Join-Path $f.Root $f.Mapping.counterpart.path),'tamper')} 'hash differs'
Reject 'changed original source' {param($f)[IO.File]::AppendAllText((Join-Path $f.Root $f.Mapping.source),'tamper')} 'hash differs'
Reject 'changed source span' {param($f)$f.Mapping.branches[0].source_spans[0].sha256='0'*64;Save-Mapping $f} 'source span differs'
Reject 'out-of-range source span' {param($f)$f.Mapping.branches[0].source_spans[0].byte_offset=-1;Save-Mapping $f} 'outside original'
Reject 'empty mapping' {param($f)$f.Mapping.branches=@();Save-Mapping $f} 'mapping is empty'
Reject 'duplicate obligation' {param($f)$f.Mapping.branches+=$f.Mapping.branches[0];Save-Mapping $f} 'distinct obligations'
Reject 'missing completion marker' {param($f)$f.Mapping.branches[0].required_marker='';Save-Mapping $f} 'distinct obligations'
$f=Fixture
$observed=($f.Mapping.branches.required_marker -join "`n")+"`n"
Assert-NativeBranchWitnesses -Mapping $f.Mapping -Output $observed
$script:cases++
foreach($kind in @('missing','duplicate')) {
    $output=if($kind -eq 'missing'){$observed.Replace($f.Mapping.branches[0].required_marker,'different marker')}
        else{$observed+$f.Mapping.branches[0].required_marker+"`n"}
    $failure=$null
    try{Assert-NativeBranchWitnesses -Mapping $f.Mapping -Output $output}
    catch{$failure=$_.Exception.Message}
    if($failure -notmatch 'reviewed completion witness'){throw "Native witness negative failed: $kind"}
    $script:cases++
    Write-Output "NATIVE REVIEW PASS: $kind reviewed marker"
}
Write-Output "PASS: $script:cases native mapping review regressions; no runtime acceptance"
