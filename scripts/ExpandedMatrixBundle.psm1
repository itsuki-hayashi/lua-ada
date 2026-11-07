Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceMatrix.psm1')

function Read-ExpandedBundleJson([string] $Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
}

function Get-ExpandedBundleHash([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-ExpandedBundleInput {
    param([string] $Original, [string] $ArtifactRoot, [string] $Sha256)
    # Reports retain the producer's absolute CI path. Rebase its reports/
    # suffix into the extracted job artifact, then verify bytes before using
    # any report or child-index identity. Never search by basename alone.
    $normalized=$Original.Replace('\','/')
    $offset=$normalized.LastIndexOf('/reports/', [StringComparison]::Ordinal)
    if ($offset -lt 0) { throw 'Bundle input is outside the recorded reports subtree' }
    $root=[IO.Path]::GetFullPath($ArtifactRoot)
    $path=[IO.Path]::GetFullPath((Join-Path $root $normalized.Substring($offset + 1)))
    $relative=[IO.Path]::GetRelativePath($root,$path)
    if ($relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        [IO.Path]::IsPathRooted($relative) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Bundle input is missing or escapes its job artifact'
    }
    if ($Sha256 -cnotmatch '^[0-9a-f]{64}$' -or (Get-ExpandedBundleHash $path) -cne $Sha256) {
        throw 'Bundle input hash differs'
    }
    return $path
}

function Get-ExpandedBundleContext([Collections.IDictionary] $Report) {
    $link=if($Report.library_type -ceq 'relocatable'){'shared'}else{$Report.library_type}
    return "$($Report.configuration)/$($Report.platform)/$($Report.profile)/$link"
}

function New-ExpandedMatrixCandidate {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][string] $ArtifactsDirectory,
          [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string] $Revision,
          [string] $Output = '',
          [string] $ConsumerMapping = 'tests/conformance/reviews/expanded-t-conformance.consumer-witness-author-proposal.json',
          [string] $AUnitMapping = 'tests/conformance/reviews/expanded-t-conformance.aunit-witness-author-proposal.json')
    $artifacts=(Resolve-Path -LiteralPath $ArtifactsDirectory).Path
    if ($Output -eq '') { $Output=Join-Path $artifacts 'expanded-matrix.candidate.json' }
    $outputPath=[IO.Path]::GetFullPath($Output)
    $bundle=Split-Path -Parent $outputPath
    $outputRelative=[IO.Path]::GetRelativePath($artifacts,$outputPath)
    if ($outputRelative -eq '..' -or $outputRelative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        [IO.Path]::IsPathRooted($outputRelative)) { throw 'Candidate output must stay within the artifact bundle' }
    if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
        $existing=Read-ExpandedBundleJson $outputPath
        if ($existing.Contains('review') -and $null -ne $existing.review) {
            throw 'Refusing to overwrite a matrix with review metadata'
        }
    }
    $suite=Read-ExpandedBundleJson (Join-Path $Root 'tests/conformance/suite.json')
    $contexts=@($suite.acceptance_contexts)
    $files=(Get-ConformanceScopePolicy expanded-t-conformance).Files
    $indices=@{}
    $indexEvidence=@()
    $observations=@{}
    $warnings=@{}
    $named=@{consumer=@{};aunit=@{}}
    function Relative([string] $Path) { return [IO.Path]::GetRelativePath($bundle,$Path).Replace('\','/') }
    function Identity([string] $Path,[string] $ArtifactRoot) {
        return @{report=(Relative $Path);sha256=(Get-ExpandedBundleHash $Path);artifact_root=(Relative $ArtifactRoot)}
    }
    $indexPaths=@(Get-ChildItem -LiteralPath $artifacts -Recurse -File -Filter index.json |
        Where-Object { $_.FullName.Replace('\','/') -cmatch '/reports/expanded-conformance/[^/]+/index\.json$' })
    foreach ($indexFile in $indexPaths) {
        $index=Read-ExpandedBundleJson $indexFile.FullName
        if ($index.scope -cne 'expanded-t-conformance' -or $index.context -cnotin $contexts -or
            $index.completed -ne $true) { throw 'Expanded batch index is incomplete or identifies another scope/context' }
        if ($indices.ContainsKey($index.context)) { throw "Duplicate expanded batch context: $($index.context)" }
        $normalized=$indexFile.FullName.Replace('\','/')
        $artifactRoot=$normalized.Substring(0,$normalized.LastIndexOf('/reports/', [StringComparison]::Ordinal))
        $indices[$index.context]=$index
        $indexEvidence+=@{context=$index.context;report=(Relative $indexFile.FullName);
            sha256=(Get-ExpandedBundleHash $indexFile.FullName);artifact_root=(Relative $artifactRoot)}
        $rows=@($index.observations)
        if (@($index.groups).Count -ne 2 -or
            (@($index.groups.kind | Sort-Object) -join '|') -cne 'files|gc-events') {
            throw 'Expanded batch requires its exact GC/events and files child indices'
        }
        foreach ($group in $index.groups) {
            $childPath=Resolve-ExpandedBundleInput -Original $group.path -ArtifactRoot $artifactRoot -Sha256 $group.sha256
            $child=Read-ExpandedBundleJson $childPath
            if ($child.scope -cne $index.scope -or $child.context -cne $index.context -or
                $child.configuration -cne $index.configuration) { throw 'Expanded child index identity differs' }
            if($group.kind -ceq 'gc-events') {
                if(-not $child.Contains('warning_regressions') -or $null -eq $child.warning_regressions) {
                    throw 'Expanded GC/events child lacks mandatory warning regressions'
                }
                $warningPath=Resolve-ExpandedBundleInput -Original $child.warning_regressions.report `
                    -ArtifactRoot $artifactRoot -Sha256 $child.warning_regressions.sha256
                $warning=Read-ExpandedBundleJson $warningPath
                if($warning.scope -cne $index.scope -or $warning.context -cne $index.context -or
                    $warning.configuration -cne $index.configuration -or
                    $warning.repository_revision -cne $Revision -or $warning.repository_dirty -ne $false) {
                    throw 'Warning index revision or context differs'
                }
                $warningIdentity=Identity $warningPath $artifactRoot
                $warningIdentity.context=$index.context
                $warnings[$index.context]=$warningIdentity
            }
            $rows+=@($child.observations)
        }
        foreach ($row in $rows) {
            $target=if($row.target -ceq 'Ada'){'ada'}elseif($row.target -ceq 'ReferenceC'){'c'}else{throw 'Unknown expanded report target'}
            $variant=if($row.Contains('variant') -and $row.variant -ceq 'constructs-branch-1'){'constructs-branch-1'}else{'primary'}
            if ($row.file -cnotin $files -or $row.context -cne $index.context -or $row.exit_code -ne 0 -or
                $row.status -cnotin @('passed','completed-with-skips') -or
                ($row.Contains('variant') -and $null -ne $row.variant -and
                 $row.variant -cnotin @('constructs-branch-0','constructs-branch-1'))) {
                throw 'Expanded observation has a wrong file, variant or failed process'
            }
            if (($row.file -cne 'constructs.lua' -and $row.Contains('variant') -and $null -ne $row.variant) -or
                ($row.file -ceq 'constructs.lua' -and
                 (-not $row.Contains('variant') -or $row.variant -cnotin @('constructs-branch-0','constructs-branch-1')))) {
                throw 'Unexpected or missing source execution variant'
            }
            $path=Resolve-ExpandedBundleInput -Original $row.report -ArtifactRoot $artifactRoot -Sha256 $row.report_sha256
            $report=Read-ExpandedBundleJson $path
            if ($report.repository_revision -cne $Revision -or $report.repository_dirty -ne $false -or
                $report.coverage_scope -cne $index.scope -or $report.acceptance_context -cne $index.context -or
                $report.target -cne $row.target -or $report.operation -cne ('file:'+$row.file) -or
                $report.status -cne $row.status -or $report.setup_error -or $report.acceptance_error) {
                throw 'Expanded report revision, context or result differs from its batch identity'
            }
            if ($row.file -ceq 'constructs.lua' -and
                $report.constructs_branch -ne $(if($variant -ceq 'primary'){0}else{1})) {
                throw 'Expanded constructs report branch differs'
            }
            $key=$index.context+'/'+$row.file+'/'+$variant+'/'+$target
            if ($observations.ContainsKey($key)) { throw "Duplicate expanded file observation: $key" }
            $observations[$key]=Identity $path $artifactRoot
        }
    }
    $missing=@($contexts | Where-Object { -not $indices.ContainsKey($_) })
    if ($missing.Count) { throw ('Missing expanded batch contexts: '+($missing -join ', ')) }

    # Core-image archives are uploaded separately from default file captures;
    # instrumented archives contain both. Use report identity, not job names,
    # so static-PIC records remain distinct even inside one uploaded archive.
    $resultPaths=@(Get-ChildItem -LiteralPath $artifacts -Recurse -File -Filter result.json |
        Where-Object { $_.FullName.Replace('\','/') -cmatch '/reports/core-image/[^/]+/result\.json$' })
    foreach ($resultFile in $resultPaths) {
        $report=Read-ExpandedBundleJson $resultFile.FullName
        if ($report.repository_revision -cne $Revision) { throw 'Named report identifies a different revision' }
        $context=Get-ExpandedBundleContext $report
        if ($context -cnotin $contexts -or $report.repository_dirty -ne $false) { throw 'Named report context is unknown or dirty' }
        $kind=if($report.Contains('consumers')){'consumer'}elseif($report.Contains('completed')){'aunit'}else{throw 'Unknown named report kind'}
        if ($named[$kind].ContainsKey($context)) { throw "Duplicate named $kind context: $context" }
        if ($kind -ceq 'aunit' -and ($report.completed -ne $true -or $report.exit_code -ne 0)) {
            throw 'Named AUnit report did not complete'
        }
        if ($kind -ceq 'consumer' -and
            (@($report.consumers).Count -eq 0 -or
             @($report.consumers | Where-Object { $_.exit_code -ne 0 -or $_.timed_out }).Count)) {
            throw 'Named public consumer campaign did not complete'
        }
        $normalized=$resultFile.FullName.Replace('\','/')
        $artifactRoot=$normalized.Substring(0,$normalized.LastIndexOf('/reports/', [StringComparison]::Ordinal))
        $identity=Identity $resultFile.FullName $artifactRoot
        $identity.context=$context
        $named[$kind][$context]=$identity
    }
    foreach ($kind in @('consumer','aunit')) {
        $missing=@($contexts | Where-Object { -not $named[$kind].ContainsKey($_) })
        if ($missing.Count) { throw "Missing named $kind contexts: $($missing -join ', ')" }
    }
    $operations=@(foreach ($context in $contexts) {
        foreach ($file in $files) {
            $entry=[ordered]@{context=$context;file=$file;contract=$null}
            foreach ($target in @('ada','c')) {
                $key="$context/$file/primary/$target"
                if (-not $observations.ContainsKey($key)) { throw "Missing expanded file observation: $key" }
                $entry[$target]=$observations[$key]
            }
            if ($file -ceq 'constructs.lua') {
                $extra=@{variant='constructs-branch-1'}
                foreach ($target in @('ada','c')) {
                    $key="$context/$file/constructs-branch-1/$target"
                    if (-not $observations.ContainsKey($key)) { throw "Missing expanded file observation: $key" }
                    $extra[$target]=$observations[$key]
                }
                $entry.supplemental=@($extra)
            }
            $entry
        }
    })
    if ($observations.Count -ne 728) { throw 'Expanded candidate must contain exactly 728 process reports' }
    function Pending-Mapping([string] $Path) {
        if ([IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('..')) { throw 'Mapping must identify a repository-relative author artifact' }
        $full=[IO.Path]::GetFullPath((Join-Path $Root $Path))
        $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$full)
        if ($relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
            [IO.Path]::IsPathRooted($relative)) { throw 'Mapping escapes the repository' }
        return @{path=$Path;sha256=(Get-ExpandedBundleHash $full);
            review=$null;review_sha256=$null;review_status='pending-independent-review'}
    }
    $contracts='tests/conformance/scopes/expanded-t-conformance.contracts.json'
    $manifest=[ordered]@{schema_version=1;scope='expanded-t-conformance';revision=$Revision;review=$null;
        diagnostic_only=$true;scoped_acceptance=$false;full_m3_acceptance=$false;
        operations=$operations;named_consumers=@($contexts | ForEach-Object { $named.consumer[$_] });
        named_aunit=@($contexts | ForEach-Object { $named.aunit[$_] });
        warning_regressions=@($contexts | ForEach-Object { $warnings[$_] });
        consumer_mapping=(Pending-Mapping $ConsumerMapping);aunit_mapping=(Pending-Mapping $AUnitMapping);
        contract_mapping=@{path=$contracts;sha256=(Get-ExpandedBundleHash (Join-Path $Root $contracts));review_status='pending'};
        collection=@{contexts=26;primary_pairs=338;supplemental_pairs=26;process_reports=728;
            named_consumer_reports=26;named_aunit_reports=26;warning_indices=26;batch_indices=$indexEvidence}}
    Assert-ScopedMatrixIndex -Manifest $manifest -Contexts $contexts
    [void][IO.Directory]::CreateDirectory($bundle)
    [IO.File]::WriteAllText($outputPath,($manifest | ConvertTo-Json -Depth 32)+"`n",[Text.UTF8Encoding]::new($false))
    return @{manifest=$outputPath;contexts=26;operations=338;supplemental_pairs=26;process_reports=728;
        scoped_acceptance=$false;full_m3_acceptance=$false}
}

Export-ModuleMember -Function New-ExpandedMatrixCandidate
