param()
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AUnitEvidence.psm1" -Force
$directory = Join-Path (Split-Path -Parent $PSScriptRoot) ('reports/aunit-evidence-selftest/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$hash='a'*64
$revision='b'*40
function Capture($Text) {
    $path=Join-Path $directory ([guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($path,$Text)
    return @{path=$path; hash=(Get-FileHash $path).Hash.ToLowerInvariant()}
}
$output="OK sample case`n`nTotal Tests Run:   1`nSuccessful Tests:  1`nFailed Assertions: 0`nUnexpected Errors: 0`n"
$out=Capture $output
$err=Capture "Lua warning: error in __gc ((native):1: ordinary failure)`n"
$probeOut=Capture '{"configuration":"default"}'
$probeErr=Capture ''
$baseline=@{repository_revision=$revision; repository_dirty=$false; configuration='default';
    platform='windows'; profile='validation'; library_type='static'; completed=$true; exit_code=0;
    executable_sha256=$hash; library_files=@(@{sha256=$hash});
    sources=@(@{file='case.adb'; sha256=$hash}); stdout=$out.path; stdout_sha256=$out.hash;
    stderr=$err.path; stderr_sha256=$err.hash;
    configuration_probe=@{executable_sha256=$hash; stdout=$probeOut.path; stdout_sha256=$probeOut.hash;
        stderr=$probeErr.path; stderr_sha256=$probeErr.hash}}
$mapping=@{entries=@(@{case='case.adb#Case'; source_sha256=$hash; required_stdout_line='OK sample case'})}
$resolve={param($path,$expected)
    if((Get-FileHash $path).Hash.ToLowerInvariant() -cne $expected){throw 'capture hash mismatch'}
    return $path
}
$count=0
$context='default/windows/validation/static'
function Run-Case($Name,$Mutation,$Expected) {
    $r=$baseline | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
    & $Mutation $r
    $failure=$null
    try{$null=Test-NamedAUnitEvidence $r $mapping $revision $context $resolve}
    catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or
        ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "$Name failed: $failure"}
    $script:count++
    Write-Output "AUNIT EVIDENCE PASS: $Name"
}
function Replace-Out($r,$text){$c=Capture $text; $r.stdout=$c.path; $r.stdout_sha256=$c.hash}
Run-Case 'complete synthetic suite' {} ''
Run-Case 'dirty source' {param($r) $r.repository_dirty=$true} 'identity'
Run-Case 'wrong revision' {param($r) $r.repository_revision='c'*40} 'identity'
Run-Case 'wrong platform' {param($r) $r.platform='linux'} 'identity'
Run-Case 'wrong configuration' {param($r) $r.configuration='upstream-test'} 'identity'
Run-Case 'timeout' {param($r) $r.completed=$false} 'identity'
Run-Case 'nonzero exit' {param($r) $r.exit_code=1} 'identity'
Run-Case 'altered capture' {param($r) $r.stdout_sha256='f'*64} 'capture hash'
Run-Case 'missing named label' {param($r) Replace-Out $r $output.Replace('sample case','another case')} 'named case'
Run-Case 'duplicate named label' {param($r) Replace-Out $r ("OK sample case`n"+$output)} 'summary'
Run-Case 'partial suite' {param($r) Replace-Out $r $output.Replace('Run:   1','Run:   2')} 'summary'
Run-Case 'unexpected warning' {param($r) $c=Capture 'unexpected'; $r.stderr=$c.path; $r.stderr_sha256=$c.hash} 'warning differs'
Run-Case 'wrong compiled configuration' {param($r)
    $c=Capture '{"configuration":"upstream-test"}'; $r.configuration_probe.stdout=$c.path; $r.configuration_probe.stdout_sha256=$c.hash
} 'compiled configuration'
Run-Case 'stale source' {param($r) $r.sources[0].sha256='f'*64} 'source differs'
Run-Case 'no library' {param($r) $r.library_files=@()} 'library identity'
$context='default/windows/validation/shared'
Run-Case 'shared context uses relocatable build' {param($r) $r.library_type='relocatable'} ''
$context='default/windows/validation/static'
$mapping.entries[0].case=''
Run-Case 'blank named case' {} 'mapping duplicate/empty'
$mapping.entries=@()
Run-Case 'empty mapping' {} 'mapping empty'
$mapping.entries=@(@{case='case.adb#Case';source_sha256=$hash;required_stdout_line='OK sample case'})
$currentWarning="Lua warning: error in __gc ([string `"file-abort-test`"]:1: ordinary failure)`n"
$mapping.expected_stderr=$currentWarning
Run-Case 'current mapping requires actual Lua source warning' {param($r)
    $c=Capture $currentWarning; $r.stderr=$c.path; $r.stderr_sha256=$c.hash
} ''
Run-Case 'current mapping rejects historical generic source warning' {} 'warning differs'
Run-Case 'current mapping rejects unformatted Lua chunk identifier' {param($r)
    $c=Capture "Lua warning: error in __gc (file-abort-test:1: ordinary failure)`n"
    $r.stderr=$c.path;$r.stderr_sha256=$c.hash
} 'warning differs'
Run-Case 'current source warning rejects an appended diagnostic' {param($r)
    $c=Capture ($currentWarning+"unexpected diagnostic`n"); $r.stderr=$c.path; $r.stderr_sha256=$c.hash
} 'warning differs'
Run-Case 'current source warning rejects a different source name' {param($r)
    $c=Capture $currentWarning.Replace('file-abort-test','another-source'); $r.stderr=$c.path; $r.stderr_sha256=$c.hash
} 'warning differs'
$mapping.expected_stderr=''
Run-Case 'empty expected warning cannot suppress stderr verification' {} 'empty or invalid'
Write-Output "PASS: $count AUnit evidence regressions; synthetic observations only"
