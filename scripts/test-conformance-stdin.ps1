param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$directory=Join-Path $root ('reports/stdin-selftests/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$shell=(Get-Command pwsh -ErrorAction Stop).Source
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "STDIN TEST PASS: $Name"}
function Run([string]$Name,[string]$Source,[string]$InputPath,[int]$Seconds=10,[long]$Limit=67108864){
    $scriptPath=Join-Path $directory ($Name+'.ps1')
    [IO.File]::WriteAllText($scriptPath,$Source,$utf8)
    return Invoke-ConformanceProcess -Executable $shell -Arguments @('-NoProfile','-File',$scriptPath) `
        -Directory $directory -OutputPrefix (Join-Path $directory $Name) -TimeoutSeconds $Seconds `
        -StandardInputPath $InputPath -InputLimitBytes $Limit
}
$binary=Join-Path $directory 'binary-input.dat'
[IO.File]::WriteAllBytes($binary,[byte[]](0,255,195,40,10,13,0,17))
Case 'actual binary stdin preserves NUL invalid UTF8 and CRLF with exact snapshot hash'{
    $p=Run binary '$r=[Console]::OpenStandardInput();$w=[Console]::OpenStandardOutput();$r.CopyTo($w);$w.Flush()' $binary
    $expected=(Get-FileHash $binary).Hash.ToLowerInvariant()
    Assert-True ($p.exit_code -eq 0 -and -not $p.timed_out -and -not $p.pipe_drain_failed) 'Binary stdin child failed'
    Assert-True ($p.stdout_sha256 -ceq $expected -and $p.standard_input.sha256 -ceq $expected -and
        $p.standard_input.bytes -eq 8 -and $p.standard_input.write_completed -and $p.standard_input.eof_sent) 'Binary input bytes or completion were changed'
    # The retained input is a separate immutable observation, not a link to
    # a producer file which a later author/debug run could overwrite.
    [IO.File]::WriteAllBytes($binary,[byte[]](1,2,3))
    Assert-True ((Get-FileHash $p.standard_input.path).Hash.ToLowerInvariant() -ceq $expected) 'A changed producer rewrote actual consumed bytes'
}
Case 'actual empty stdin sends EOF and retains its zero byte identity'{
    $empty=Join-Path $directory 'empty.dat';[IO.File]::WriteAllBytes($empty,[byte[]]@())
    $p=Run empty '$r=[Console]::OpenStandardInput();if($r.ReadByte() -ne -1){exit 7}' $empty
    Assert-True ($p.exit_code -eq 0 -and $p.standard_input.bytes -eq 0 -and $p.standard_input.write_completed -and
        $p.standard_input.eof_sent -and -not $p.pipe_drain_failed) 'Empty file was mistaken for absent stdin or EOF was withheld'
}
$large=Join-Path $directory 'large.dat'
[byte[]]$bytes=[byte[]]::new(8*1024*1024)
[byte[]]$block=0..255
for($offset=0;$offset -lt $bytes.Length;$offset+=$block.Length){[Array]::Copy($block,0,$bytes,$offset,$block.Length)}
[IO.File]::WriteAllBytes($large,$bytes)
Case 'actual simultaneous pipes drain output before a child reads a large binary input'{
    $p=Run pressure '$w=[Console]::OpenStandardOutput();$prefix=[byte[]]::new(1024*1024);$w.Write($prefix);$w.Flush();$r=[Console]::OpenStandardInput();$r.CopyTo($w);$w.Flush()' $large
    Assert-True ($p.exit_code -eq 0 -and -not $p.timed_out -and -not $p.pipe_drain_failed -and $p.standard_input.write_completed) 'Input/output pipe pressure deadlocked or lost bytes'
    $out=[IO.File]::ReadAllBytes($p.stdout_path)
    Assert-True ($out.Length -eq 9*1024*1024) 'Output/input pressure truncated a stream'
    $payload=[byte[]]::new(8*1024*1024);[Array]::Copy($out,1024*1024,$payload,0,$payload.Length)
    $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant()
    Assert-True ($digest -ceq $p.standard_input.sha256) 'Raw input was transcoded under pipe pressure'
}
Case 'a child which never reads stdin cannot block the wall timeout'{
    $p=Run blocked 'Start-Sleep -Seconds 30' $large -Seconds 1
    Assert-True ($p.timed_out -and $p.elapsed_milliseconds -lt 15000 -and -not $p.standard_input.write_completed) 'Blocked stdin bypassed bounded termination'
    Assert-True ((Get-ConformanceOutcome -Process $p).status -ceq 'timed-out') 'Blocked input was called passing execution'
}
Case 'early successful exit cannot count an incomplete stdin write as delivered'{
    $p=Run early 'exit 0' $large
    Assert-True ($p.exit_code -eq 0 -and $p.pipe_drain_failed -and -not $p.standard_input.write_completed) 'Partial input became complete process evidence'
    Assert-True (-not (Get-ConformanceOutcome -Process $p).execution_completed) 'Incomplete input was accepted from exit zero'
}
Case 'missing and oversized input fail before a child can supply a success marker'{
    foreach($selection in @(@{path=(Join-Path $directory 'absent.dat');limit=67108864;name='missing'},@{path=$large;limit=1024;name='too-large'})){
        $failure=$null;try{Run $selection.name 'Write-Output "fabricated success"' $selection.path -Limit $selection.limit|Out-Null}catch{$failure=$_.Exception.Message}
        Assert-True ($null -ne $failure -and -not (Test-Path (Join-Path $directory ($selection.name+'.stdout')))) 'An invalid input launched or produced execution evidence'
    }
}
Write-Output "PASS: $script:Cases actual stdin transport regressions; process transport only, no Lua/runtime acceptance"
