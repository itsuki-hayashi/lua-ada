param()
$ErrorActionPreference = 'Stop'
$root=Split-Path -Parent $PSScriptRoot
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
$requireLaunchContext=$false
function Run-Case($Name,$Mutation,$Expected) {
    $r=$baseline | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
    & $Mutation $r
    $failure=$null
    try{$null=Test-NamedAUnitEvidence $r $mapping $revision $context $resolve -RequireLaunchContext:$requireLaunchContext -Root $root}
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
$mapping.Remove('expected_stderr')
$requireLaunchContext=$true
Run-Case 'full target cannot reuse a historical report lacking launch context' {} 'lacks bound launch context'
# These receipts are fabricated protocol fixtures. No Alire, compiler, Ada
# test or accepted build observation is produced by the replay tests below.
$baseline.schema_version=2;$baseline.repository_root='C:/captured/lua-ada'
$baseline.executable='C:/captured/lua-ada/tests/bin/static/test_runner.exe'
$baseline.configuration_probe.executable='C:/captured/lua-ada/tests/bin/static/lua-configuration_probe.exe'
function New-LaunchCapture($Executable) {
    $value=@{schema_version=1;kind='aunit-process-launch';repository_root='C:/captured/lua-ada';
        selected_environment_directory='C:/captured/lua-ada/tests';observed_environment_directory='C:/captured/lua-ada/tests';
        working_directory='C:/captured/lua-ada';executable=$Executable;executable_sha256=$hash;
        arguments=@();process_id=123;completed=$true;exit_code=0;runtime_acceptance=$false;coverage_authority=$false;
        source_bindings=@(foreach($path in @('scripts/AUnitLaunch.psm1','scripts/run-aunit-in-context.ps1')){
            @{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $root $path)).Hash.ToLowerInvariant()}
        })}
    $capture=Capture (ConvertTo-Json -InputObject $value -Depth 12)
    return @{path=$capture.path;sha256=$capture.hash}
}
$baseline.launch_receipt=New-LaunchCapture $baseline.executable
$baseline.configuration_probe.launch_receipt=New-LaunchCapture $baseline.configuration_probe.executable
function Mutate-Launch($Report,[string]$Kind,[scriptblock]$Mutation) {
    $child=if($Kind -ceq 'probe'){$Report.configuration_probe}else{$Report}
    $value=Get-Content -LiteralPath $child.launch_receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 12
    &$Mutation $value
    $capture=Capture (ConvertTo-Json -InputObject $value -Depth 12)
    $child.launch_receipt=@{path=$capture.path;sha256=$capture.hash}
}
Run-Case 'full target validates both bound launch receipts across captured path spellings' {} ''
Run-Case 'full target rejects a missing main process receipt' {param($r)$r.Remove('launch_receipt')} 'lacks bound launch context'
Run-Case 'full target rejects a missing configuration process receipt' {param($r)$r.configuration_probe.Remove('launch_receipt')} 'lacks bound launch context'
Run-Case 'full target rejects the actual regression nested executable CWD' {param($r)
    Mutate-Launch $r main {param($v)$v.working_directory='C:/captured/lua-ada/tests'}
} 'directory differs'
Run-Case 'full target rejects a root environment for the configuration probe' {param($r)
    Mutate-Launch $r probe {param($v)$v.observed_environment_directory='C:/captured/lua-ada'}
} 'directory differs'
Run-Case 'full target rejects a receipt for another executable' {param($r)
    Mutate-Launch $r main {param($v)$v.executable_sha256='0'*64}
} 'process identity'
Run-Case 'full target rejects stale launcher source' {param($r)
    Mutate-Launch $r main {param($v)$v.source_bindings[0].sha256='0'*64}
} 'source binding differs'
Run-Case 'full target rejects extra runner arguments' {param($r)
    Mutate-Launch $r main {param($v)$v.arguments=@('--skip-fixtures')}
} 'arguments or completion differs'
Run-Case 'full target rejects a test executable from another library path' {param($r)
    $r.executable=$r.executable.Replace('/static/','/relocatable/')
} 'selected build path'
Run-Case 'full target rejects tampered launch receipt bytes' {param($r)$r.launch_receipt.sha256='0'*64} 'capture hash mismatch'
Write-Output "PASS: $count AUnit evidence regressions; synthetic observations only"
