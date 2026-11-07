param()
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/ScopedAcceptancePolicy.psm1" -Force
Import-Module "$PSScriptRoot/ConformanceScope.psm1"
$root=Split-Path -Parent $PSScriptRoot
$directory=Join-Path $root ('reports/contract-index-selftest/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$files=@('events.lua','gc.lua','gengc.lua','files.lua')
$context='default/windows/validation/static'
function Save($path,$value){[IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false));return (Get-FileHash $path).Hash.ToLowerInvariant()}
$entries=@(foreach($file in $files){
    $contract=@{schema_version=1;operation="file:$file";context=$context;reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294'}
    @{file=$file;context=$context;path="$file.json";sha256=(Save (Join-Path $directory "$file.json") $contract)}
})
$approval=@{schema_version=1;kind='scoped-contract-index-approval';scope='gc-io-events';decision='accepted';
    author='fixture-author';reviewer='fixture-reviewer';contracts=@($entries | ForEach-Object {$v=$_.Clone();$v.decision='accepted';$v})}
$approvalHash=Save (Join-Path $directory 'review.json') $approval
$baseline=@{schema_version=1;scope='gc-io-events';contracts=$entries;
    review=@{status='accepted';author='fixture-author';reviewer='fixture-reviewer';artifact='review.json';artifact_sha256=$approvalHash}}
$count=0
function Case($Name,$Mutate,$Expected){
    $index=$baseline | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable
    & $Mutate $index
    $failure=$null
    try{$null=Assert-ScopedContractIndex -Root $directory -Index $index -Contexts @($context) -Files $files}
    catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "$Name failed: $failure"}
    $script:count++;Write-Output "CONTRACT POLICY PASS: $Name"
}
Case 'complete independently bound synthetic index' {} ''
Case 'self review' {param($i)$i.review.reviewer=$i.review.author} 'independent review'
Case 'pending review' {param($i)$i.review.status='pending'} 'independent review'
Case 'stale review hash' {param($i)$i.review.artifact_sha256='f'*64} 'hash differs'
Case 'unknown context' {param($i)$i.contracts[0].context='default/linux/validation/static'} 'Unknown/duplicate'
Case 'unknown file' {param($i)$i.contracts[0].file='all.lua'} 'Unknown/duplicate'
Case 'missing contract' {param($i)$i.contracts=@($i.contracts | Select-Object -Skip 1)} 'identity differs'
Case 'duplicate contract' {param($i)$i.contracts[1]=$i.contracts[0].Clone()} 'Unknown/duplicate'
Case 'unreviewed contract hash' {param($i)$i.contracts[0].sha256='f'*64} 'exact review binding'
Case 'unreviewed contract path' {param($i)$i.contracts[0].path='other.json'} 'exact review binding'
# The selected mode must track actual unresolved obligations. After promotion
# this same check requires validated contracts, never a diagnostic fallback.
$scope=Test-ConformanceScope -Root $root
$pending=$scope.UnresolvedSourceAnchors -gt 0 -or $scope.UnresolvedApiEntries -gt 0
$policy=Get-ScopedAcceptancePolicy -Root $root -Context $context
if($policy.acceptance -eq $pending -or $policy.full_m3_acceptance -or
    ($pending -and $policy.contracts.Count -ne 0) -or
    (-not $pending -and $policy.contracts.Count -ne 4)){throw 'Scope selected wrong acceptance policy'}
$count++
Write-Output "PASS: $count scoped contract policy regressions; no runtime acceptance"
