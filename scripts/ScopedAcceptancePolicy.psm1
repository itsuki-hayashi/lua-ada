Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')

function Assert-ScopedContractIndex {
    param([string] $Root, [Collections.IDictionary] $Index,
          [string[]] $Contexts, [string[]] $Files)
    if ($Index.schema_version -ne 1 -or $Index.scope -cne 'gc-io-events') { throw 'Invalid scoped contract index' }
    $review=$Index.review
    if ($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace($review.author) -or
        [string]::IsNullOrWhiteSpace($review.reviewer) -or $review.author -ceq $review.reviewer) {
        throw 'Contract index requires independent review'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($approval.kind -cne 'scoped-contract-index-approval' -or $approval.decision -cne 'accepted' -or
        $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
        $approval.scope -cne $Index.scope -or @($approval.contracts).Count -ne @($Index.contracts).Count) {
        throw 'Contract index review identity differs'
    }
    $seen=@{}
    foreach ($entry in $Index.contracts) {
        $key=$entry.context+'/'+$entry.file
        if ($entry.context -cnotin $Contexts -or $entry.file -cnotin $Files -or $seen.ContainsKey($key)) {
            throw 'Unknown/duplicate scoped contract'
        }
        $approved=@($approval.contracts | Where-Object { $_.context -ceq $entry.context -and $_.file -ceq $entry.file })
        if ($approved.Count -ne 1 -or $approved[0].decision -cne 'accepted' -or
            $approved[0].path -cne $entry.path -or $approved[0].sha256 -cne $entry.sha256) {
            throw 'Scoped contract lacks exact review binding'
        }
        $path=Resolve-ReviewedFile -Root $Root -Path $entry.path -Sha256 $entry.sha256
        $contract=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($contract.schema_version -ne 1 -or $contract.operation -cne ('file:'+$entry.file) -or
            $contract.context -cne $entry.context -or
            $contract.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294') {
            throw 'Scoped contract identifies a different operation'
        }
        $seen[$key]=@{path=$path; repository_path=$entry.path; sha256=$entry.sha256}
    }
    foreach ($context in $Contexts) {
        foreach ($file in $Files) {
            if (-not $seen.ContainsKey($context+'/'+$file)) { throw 'Incomplete scoped execution contracts' }
        }
    }
    return $seen
}

function Get-ScopedAcceptancePolicy {
    param([string] $Root, [string] $Context)
    # Structural failures always propagate. Only genuinely pending obligations
    # select observation mode; a complete ledger cannot silently lose contracts
    # or fall back to ReportOnly when its final acceptance prerequisites fail.
    $scope=Test-ConformanceScope -Root $Root
    if ($scope.UnresolvedSourceAnchors -gt 0 -or $scope.UnresolvedApiEntries -gt 0) {
        return @{acceptance=$false; contracts=@{}; full_m3_acceptance=$false}
    }
    $null=Test-ConformanceScope -Root $Root -RequireScopedComplete
    $suite=Get-Content (Join-Path $Root 'tests/conformance/suite.json') -Raw | ConvertFrom-Json -AsHashtable
    if ($Context -cnotin $suite.acceptance_contexts) { throw 'Unknown scoped acceptance context' }
    $index=Get-Content (Join-Path $Root 'tests/conformance/scopes/gc-io-events.contracts.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 64
    $all=Assert-ScopedContractIndex -Root $Root -Index $index -Contexts $suite.acceptance_contexts `
        -Files @($scope.Definition.files.path)
    $selected=@{}
    foreach ($file in $scope.Definition.files.path) { $selected[$file]=$all[$Context+'/'+$file] }
    return @{acceptance=$true; contracts=$selected; full_m3_acceptance=$false}
}

Export-ModuleMember -Function Get-ScopedAcceptancePolicy, Assert-ScopedContractIndex
