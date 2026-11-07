param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module "$PSScriptRoot/ExpandedMatrixBundle.psm1" -Force
Import-Module "$PSScriptRoot/ConformanceScope.psm1"
$directory=Join-Path $root ('reports/expanded-bundle-selftest/'+[guid]::NewGuid().ToString('N'))
$repository=Join-Path $directory 'repository'
$artifacts=Join-Path $directory 'artifacts'
[void][IO.Directory]::CreateDirectory("$repository/tests/conformance/reviews")
[void][IO.Directory]::CreateDirectory("$repository/tests/conformance/scopes")
$suite=Get-Content "$root/tests/conformance/suite.json" -Raw | ConvertFrom-Json -AsHashtable
$contexts=@($suite.acceptance_contexts)
$files=(Get-ConformanceScopePolicy expanded-t-conformance).Files
$revision='a'*40
function Save([string] $Path,$Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Compress -Depth 32)+"`n")
    return (Get-FileHash $Path).Hash.ToLowerInvariant()
}
$null=Save "$repository/tests/conformance/suite.json" @{acceptance_contexts=$contexts}
foreach($name in @('consumer','aunit')) {
    $null=Save "$repository/tests/conformance/reviews/expanded-t-conformance.$name-witness-author-proposal.json" @{
        kind='synthetic-author-mapping';coverage_authority=$false;runtime_acceptance=$false}
}
$null=Save "$repository/tests/conformance/scopes/expanded-t-conformance.contracts.json" @{
    scope='expanded-t-conformance';review=@{status='pending'};contracts=@()}
$batchPaths=@()
$namedPaths=@()
foreach($context in $contexts) {
    $parts=$context.Split('/')
    $job=Join-Path $artifacts ('files-'+$context.Replace('/','-'))
    $batch=Join-Path $job 'reports/expanded-conformance/run/index.json'
    $observations=@()
    $groups=@{files=@();'gc-events'=@()}
    foreach($file in $files) {
        $branches=if($file -ceq 'constructs.lua'){@(0,1)}else{@(0)}
        foreach($branch in $branches) {
            foreach($target in @('Ada','ReferenceC')) {
                $path=Join-Path $job "reports/expanded-conformance/run/$target-$file-$branch.json"
                # These deliberately incomplete report bodies test collection
                # and identities only. Diagnostic replay/acceptance would
                # reject them; no fabricated capture or execution is asserted.
                $report=@{repository_revision=$revision;repository_dirty=$false;
                    coverage_scope='expanded-t-conformance';acceptance_context=$context;
                    target=$target;operation="file:$file";status='passed';setup_error=$null;
                    acceptance_error=$null;constructs_branch=$branch}
                $row=@{file=$file;target=$target;context=$context;report=$path;report_sha256=(Save $path $report);
                    exit_code=0;status='passed';variant=$(if($file -ceq 'constructs.lua'){"constructs-branch-$branch"}else{$null})}
                if($file -ceq 'files.lua'){$groups.files+=$row}
                elseif($file -cin @('events.lua','gc.lua','gengc.lua')){$groups['gc-events']+=$row}
                else{$observations+=$row}
            }
        }
    }
    $groupRows=@(foreach($name in @('files','gc-events')) {
        $path=Join-Path $job "reports/expanded-conformance/run/$name/index.json"
        $child=@{scope='expanded-t-conformance';context=$context;
            configuration=$parts[0];observations=$groups[$name]}
        if($name -ceq 'gc-events') {
            $warningPath=Join-Path $job 'reports/expanded-conformance/run/gc-events/warnings/index.json'
            $child.warning_regressions=@{report=$warningPath;sha256=(Save $warningPath @{
                scope='expanded-t-conformance';context=$context;configuration=$parts[0];
                repository_revision=$revision;repository_dirty=$false})}
        }
        @{kind=$name;path=$path;sha256=(Save $path $child)}
    })
    $null=Save $batch @{scope='expanded-t-conformance';context=$context;configuration=$parts[0];
        completed=$true;groups=$groupRows;observations=$observations}
    $batchPaths+=$batch
    $namedJob=Join-Path $artifacts ('named-'+$context.Replace('/','-'))
    foreach($kind in @('consumer','aunit')) {
        $path=Join-Path $namedJob "reports/core-image/$kind/result.json"
        $report=@{repository_revision=$revision;repository_dirty=$false;configuration=$parts[0];
            platform=$parts[1];profile=$parts[2];library_type=$(if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]})}
        if($kind -ceq 'consumer'){$report.consumers=@(@{exit_code=0;timed_out=$false})}
        else{$report.completed=$true;$report.exit_code=0}
        $null=Save $path $report
        $namedPaths+=@{kind=$kind;path=$path;context=$context}
    }
}
$count=0
function Case([string] $Name,[scriptblock] $Action,[string] $Expected='') {
    $failure=$null
    try { & $Action | Out-Null } catch { $failure=$_.Exception.Message }
    if(($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))) {
        throw "Bundle case failed ($Name): $failure; expected $Expected"
    }
    $script:count++
    Write-Output "EXPANDED BUNDLE PASS: $Name"
}
function Build { New-ExpandedMatrixCandidate -Root $repository -ArtifactsDirectory $artifacts -Revision $revision }
Case 'all26contexts become338pairs plus26supplements without review authority' {
    $result=Build
    $manifest=Get-Content $result.manifest -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if($manifest.operations.Count -ne 338 -or $manifest.collection.process_reports -ne 728 -or
        $manifest.named_consumers.Count -ne 26 -or $manifest.named_aunit.Count -ne 26 -or
        $manifest.review -ne $null -or $manifest.scoped_acceptance -or $manifest.full_m3_acceptance -or
        $manifest.consumer_mapping.review -ne $null -or
        $manifest.warning_regressions.Count -ne 26 -or
        @($manifest.operations | Where-Object {$null -ne $_.contract}).Count) {
        throw 'Candidate fabricated authority or wrong cardinality'
    }
}
$first=$batchPaths[0]
$saved=[IO.File]::ReadAllText($first)
try {
    [IO.File]::Move($first,"$first.saved")
    Case 'missing context cannot be silently omitted' { Build } 'Missing expanded batch contexts'
} finally { [IO.File]::Move("$first.saved",$first) }
$duplicate=Join-Path (Split-Path -Parent (Split-Path -Parent $first)) 'duplicate/index.json'
try {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $duplicate))
    [IO.File]::WriteAllText($duplicate,$saved)
    Case 'duplicate context cannot select newest report by timestamp' { Build } 'Duplicate expanded batch context'
} finally { [IO.File]::Delete($duplicate) }
$index=$saved | ConvertFrom-Json -AsHashtable -Depth 64
$reportPath=$index.observations[0].report
$savedReport=[IO.File]::ReadAllText($reportPath)
try {
    [IO.File]::WriteAllText($reportPath,$savedReport+" `n")
    Case 'altered report bytes reject before interpretation' { Build } 'input hash differs'
} finally { [IO.File]::WriteAllText($reportPath,$savedReport) }
try {
    $report=$savedReport | ConvertFrom-Json -AsHashtable -Depth 64
    $report.repository_revision='b'*40
    $index.observations[0].report_sha256=Save $reportPath $report
    $null=Save $first $index
    Case 'rehashed report with another revision rejects' { Build } 'report revision, context'
} finally { [IO.File]::WriteAllText($reportPath,$savedReport);[IO.File]::WriteAllText($first,$saved) }
$missingNamed=($namedPaths | Where-Object kind -CEQ consumer | Select-Object -First 1).path
try {
    [IO.File]::Move($missingNamed,"$missingNamed.saved")
    Case 'named consumer context required separately from file completion' { Build } 'Missing named consumer contexts'
} finally { [IO.File]::Move("$missingNamed.saved",$missingNamed) }
try {
    $index=$saved | ConvertFrom-Json -AsHashtable -Depth 64
    $index.completed=$false
    $null=Save $first $index
    Case 'partial batch index cannot become a matrix row' { Build } 'index is incomplete'
} finally { [IO.File]::WriteAllText($first,$saved) }
$index=$saved | ConvertFrom-Json -AsHashtable -Depth 64
$gcGroup=$index.groups | Where-Object kind -CEQ 'gc-events'
$childPath=$gcGroup.path
$savedChild=[IO.File]::ReadAllText($childPath)
try {
    $child=$savedChild | ConvertFrom-Json -AsHashtable -Depth 64
    $child.Remove('warning_regressions')
    $gcGroup.sha256=Save $childPath $child
    $null=Save $first $index
    Case 'missing child warning index cannot disappear during collection' { Build } 'mandatory warning regressions'
} finally { [IO.File]::WriteAllText($childPath,$savedChild);[IO.File]::WriteAllText($first,$saved) }
Case 'candidate output cannot escape artifact bundle' {
    New-ExpandedMatrixCandidate -Root $repository -ArtifactsDirectory $artifacts -Revision $revision `
        -Output (Join-Path $directory 'outside.json')
} 'output must stay'
$output=Join-Path $artifacts 'expanded-matrix.candidate.json'
$savedOutput=[IO.File]::ReadAllText($output)
try {
    $null=Save $output @{review=@{status='accepted'}}
    Case 'collector cannot overwrite independent review metadata' { Build } 'Refusing to overwrite'
} finally { [IO.File]::WriteAllText($output,$savedOutput) }
Write-Output "PASS: $count matrix-bundle regressions; synthetic index collection only, no runtime acceptance"
