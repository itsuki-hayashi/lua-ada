param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path $root ('reports/aunit-launch-selftest/'+[guid]::NewGuid().ToString('N'))
foreach($path in @('scripts','tests/lua')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $path))}
foreach($name in @('AUnitLaunch.psm1','run-aunit-in-context.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $fixture "scripts/$name")
}
Import-Module (Join-Path $fixture 'scripts/AUnitLaunch.psm1') -Force
$script:cases=0
function Case($Name,[scriptblock]$Action){&$Action;$script:cases++;Write-Output "AUNIT LAUNCH PASS: $Name"}
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,$Pattern){
    $failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message}
    Assert ($null -ne $failure -and $failure -match $Pattern) "Wrong failure: $failure; expected $Pattern"
}
$pwsh=(Get-Command pwsh -ErrorAction Stop).Source
$hash=(Get-FileHash -LiteralPath $pwsh).Hash.ToLowerInvariant()
$probe=Join-Path $fixture 'probe.ps1';$output=Join-Path $fixture 'observed.json'
[IO.File]::WriteAllText((Join-Path $fixture 'tests/lua/fixture.txt'),'repository fixture')
[IO.File]::WriteAllText($probe,@'
param([string]$Output)
$ErrorActionPreference='Stop'
$fixture=[IO.File]::ReadAllText('tests/lua/fixture.txt')
@{directory=(Get-Location).ProviderPath;fixture=$fixture;environment=$env:LUA_ADA_AUNIT_LAUNCH_TEST} |
    ConvertTo-Json | Set-Content -LiteralPath $Output
'@)
$arguments=@('-NoProfile','-File',$probe,$output)
$receiptPath=Join-Path $fixture 'launch.json'
$oldEnvironment=$env:LUA_ADA_AUNIT_LAUNCH_TEST
$env:LUA_ADA_AUNIT_LAUNCH_TEST='nested-test-environment-sentinel'
try {
    Push-Location (Join-Path $fixture 'tests')
    try {
        Case 'actual child resolves a repository-relative fixture and retains inherited environment' {
            $script:receipt=Invoke-AUnitContextProcess -RepositoryRoot $fixture -Executable $pwsh `
                -ExecutableSha256 $hash -ReceiptPath $receiptPath -Arguments $arguments
            $observed=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
            Assert ($receipt.completed -and $receipt.exit_code -eq 0) 'actual child failed'
            Assert ($observed.directory -ceq $fixture -and $observed.fixture -ceq 'repository fixture' -and
                $observed.environment -ceq 'nested-test-environment-sentinel') 'fixture CWD or inherited environment differs'
            Assert-AUnitLaunchReceipt -Receipt $receipt -Root $fixture -CapturedRepositoryRoot $fixture `
                -Executable $pwsh -ExecutableSha256 $hash -ExpectedArguments $arguments
        }
        Case 'changed executable bytes reject before execution' {
            Reject {Invoke-AUnitContextProcess -RepositoryRoot $fixture -Executable $pwsh `
                -ExecutableSha256 ('0'*64) -ReceiptPath $receiptPath -Arguments $arguments} 'hash differs before launch'
        }
        Case 'nonzero actual child cannot discharge successful evidence' {
            $bad=Join-Path $fixture 'nonzero.ps1';[IO.File]::WriteAllText($bad,'exit 7')
            $r=Invoke-AUnitContextProcess -RepositoryRoot $fixture -Executable $pwsh -ExecutableSha256 $hash `
                -ReceiptPath (Join-Path $fixture 'nonzero.json') -Arguments @('-NoProfile','-File',$bad)
            Assert ($r.exit_code -eq 7) 'child exit code was lost'
            Reject {Assert-AUnitLaunchReceipt -Receipt $r -Root $fixture -CapturedRepositoryRoot $fixture `
                -Executable $pwsh -ExecutableSha256 $hash -ExpectedArguments @('-NoProfile','-File',$bad)} 'completion differs'
        }
        Case 'actual timeout is killed and remains incomplete' {
            $slow=Join-Path $fixture 'slow.ps1';[IO.File]::WriteAllText($slow,'Start-Sleep -Seconds 10')
            $r=Invoke-AUnitContextProcess -RepositoryRoot $fixture -Executable $pwsh -ExecutableSha256 $hash `
                -ReceiptPath (Join-Path $fixture 'timeout.json') -Arguments @('-NoProfile','-File',$slow) -TimeoutMilliseconds 100
            Assert (-not $r.completed) 'timeout was reported complete'
        }
    } finally {Pop-Location}
    Case 'selecting the root environment instead of the nested test crate rejects' {
        Push-Location $fixture
        try {Reject {Invoke-AUnitContextProcess -RepositoryRoot $fixture -Executable $pwsh `
            -ExecutableSha256 $hash -ReceiptPath $receiptPath -Arguments $arguments} 'nested test environment directory'}
        finally {Pop-Location}
    }
    foreach($field in @('working_directory','selected_environment_directory','observed_environment_directory')) {
        Case "$field drift rejects an otherwise successful child" {
            $r=$receipt|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable -Depth 12
            $r[$field]=if($field -ceq 'working_directory'){Join-Path $fixture 'tests'}else{$fixture}
            Reject {Assert-AUnitLaunchReceipt -Receipt $r -Root $fixture -CapturedRepositoryRoot $fixture `
                -Executable $pwsh -ExecutableSha256 $hash -ExpectedArguments $arguments} 'directory differs'
        }
    }
    Case 'changed source binding rejects the captured launch' {
        $r=$receipt|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable -Depth 12
        $r.source_bindings[0].sha256='0'*64
        Reject {Assert-AUnitLaunchReceipt -Receipt $r -Root $fixture -CapturedRepositoryRoot $fixture `
            -Executable $pwsh -ExecutableSha256 $hash -ExpectedArguments $arguments} 'source binding differs'
    }
    Case 'extra executable arguments cannot be omitted from replay' {
        Reject {Assert-AUnitLaunchReceipt -Receipt $receipt -Root $fixture -CapturedRepositoryRoot $fixture `
            -Executable $pwsh -ExecutableSha256 $hash} 'arguments or completion differs'
    }
} finally {$env:LUA_ADA_AUNIT_LAUNCH_TEST=$oldEnvironment}
Write-Output "PASS: $script:cases AUnit launch regressions; actual PowerShell children only, no Alire or AUnit coverage claim"
