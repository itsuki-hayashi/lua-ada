param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceTransforms.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$directory=Join-Path $root ('reports/attrib-windows-proposal-selftest/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$manifestPath=Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/attrib-windows-equivalence.author-proposal.json'
$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$packet=Get-Content (Join-Path $root $manifest.authoring_observation.path) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$bytes=[IO.File]::ReadAllBytes((Join-Path $root $manifest.source));$script:Cases=0
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "ATTRIB WINDOWS PROPOSAL TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48)}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
Case 'ten source-bound native expectation replacements reconstruct the exact proposed bytes'{
    $output=Get-ConformancePatchedBytes -SourceBytes $bytes -Replacements $manifest.replacements
    Assert-True ($manifest.replacements.Count -eq 10 -and (Get-ConformanceHash $output) -ceq 'a56021013a850cf69feb421e5385ac0e5f8e6b5841d107c9c7a55ed5ea172dca' -and
        (Get-ConformanceHash $output) -ceq $manifest.output_sha256 -and (Get-ConformanceHash $bytes) -ceq $manifest.source_sha256) 'Original or generated native mapping identity differs'
    $text=[Text.Encoding]::UTF8.GetString($output)
    Assert-True ($text.Contains('assert(ext == ("libs"..dirsep.."P1/init.lua"))') -and -not $text.Contains('assert(ext == D"P1/init.lua")')) 'Mixed native subpackage template was normalized incorrectly'
}
Case 'each patch is exactly one original expected literal and binds a distinct counterpart case'{
    $source=[Text.Encoding]::Latin1.GetString($bytes)
    $counterpart=[IO.File]::ReadAllText((Join-Path $root $packet.counterpart.path))
    foreach($change in $manifest.replacements){
        Assert-True ($source.Substring($change.start_byte,$change.length_bytes) -ceq $change.original_text -and
            $change.original_text -cmatch '^"libs/[^"\r\n]+"$' -and $change.counterpart_tests.Count -eq 1) 'Mapping widened beyond its original expectation literal'
        $name=$change.counterpart_tests[0].Split('#')[1]
        Assert-True ([regex]::Matches($counterpart,'check\("'+[regex]::Escape($name)+'",').Count -eq 1) 'Native counterpart case missing or duplicated'
    }
}
Case 'helper spans and every assertion or T identifier survive the exact transformation'{
    $output=Get-ConformancePatchedBytes -SourceBytes $bytes -Replacements $manifest.replacements
    $old=@(Get-ConformanceTokens -Bytes $bytes);$new=@(Get-ConformanceTokens -Bytes $output)
    foreach($name in @('assert','T')){Assert-True (@($old|Where-Object{ -not $_.IsString -and $_.Text -ceq $name }).Count -eq
        @($new|Where-Object{ -not $_.IsString -and $_.Text -ceq $name }).Count) 'An assertion or T identifier disappeared'}
    Assert-True ($packet.preserved_helper_spans.Count -eq 3 -and $packet.source_preservation.exclusions.Count -eq 0) 'Helper or exclusion protocol differs'
    foreach($helper in $packet.preserved_helper_spans){
        $span=[byte[]]::new($helper.length_bytes);[Array]::Copy($bytes,$helper.start_byte,$span,0,$span.Length)
        Assert-True ((Get-ConformanceHash $span) -ceq $helper.source_sha256) 'Original helper hash differs'
        foreach($change in $manifest.replacements){Assert-True (-not ($change.start_byte -lt $helper.start_byte+$helper.length_bytes -and
            $change.start_byte+$change.length_bytes -gt $helper.start_byte)) 'A path mapping overlaps an original helper'}
    }
}
Case 'shifted widened and stale original spans fail byte reconstruction'{
    foreach($field in @('start_byte','length_bytes','source_sha256')){
        $m=Clone $manifest
        if($field -ceq 'source_sha256'){$m.replacements[0][$field]='0'*64}else{$m.replacements[0][$field]++}
        Reject {Get-ConformancePatchedBytes -SourceBytes $bytes -Replacements $m.replacements} 'original span hash differs'
    }
}
Case 'pending source proposal cannot enter production replay or imply runtime applicability'{
    Assert-True ($manifest.review.status -ceq 'pending' -and -not $manifest.runtime_acceptance -and -not $manifest.coverage_authority -and
        $packet.execution_evidence.Count -eq 0 -and $packet.review_status -ceq 'pending') 'Author proposal acquired approval or execution authority'
    Reject {Get-ConformanceEquivalentReplay -Root $root -Specification $manifest} 'not independent and accepted'
    $m=Clone $manifest;$m.review.status='accepted';$m.review.reviewer=$m.review.author
    Reject {Get-ConformanceEquivalentReplay -Root $root -Specification $m} 'not independent and accepted'
}
Case 'diagnostic producer emits exact bytes while keeping its pending review explicit'{
    $shell=(Get-Command pwsh -ErrorAction Stop).Source;$output=Join-Path $directory 'attrib.lua'
    $process=Invoke-ConformanceProcess -Executable $shell -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'New-ConformanceEquivalent.ps1'),
        '-Manifest',$manifestPath,'-Output',$output,'-AllowUnreviewedDiagnostics') -Directory $root -OutputPrefix (Join-Path $directory 'producer') -TimeoutSeconds 30
    $observed=Get-Content $process.stdout_path -Raw|ConvertFrom-Json -AsHashtable
    Assert-True ($process.exit_code -eq 0 -and $process.stderr_bytes -eq 0 -and $observed.diagnostic_only -and $observed.review_status -ceq 'pending' -and
        (Get-FileHash $output).Hash.ToLowerInvariant() -ceq $manifest.output_sha256) 'Diagnostic producer changed bytes or approval state'
}
Write-Output "PASS: $script:Cases Windows attrib source proposal regressions; no Lua execution, native applicability approval or conformance acceptance"
