param([string] $ReferenceInterpreter = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceFileProtocols.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$temporary = Join-Path $root ('reports/file-protocol-selftests/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Cases = 0; $script:Serial = 0; $script:LuaCases = 0
$relative = 'tests/conformance/targets/remaining-upstream-compatibility/file-completion.author-proposal.json'

# The default tests are synthetic parser/capture fixtures, not executions of
# upstream sources. Review labels in the disposable root have no coverage or
# runtime authority. Optional C processes execute only synthetic tiny chunks to
# verify that the wrapper observes, rather than fabricates, return/yield values.
function Case([string] $Name, [scriptblock] $Action) {
    & $Action; $script:Cases++; Write-Output "FILE PROTOCOL TEST PASS: $Name"
}
function Assert-True([bool] $Value, [string] $Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock] $Action, [string] $Expected) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"
}
function Write-Json([string] $Path, [object] $Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 48).Replace("`r`n","`n") + "`n",$utf8)
    return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function New-Capture([string] $Output, [string] $ErrorText = '') {
    $script:Serial++; $prefix = Join-Path $temporary "capture-$script:Serial"
    [IO.File]::WriteAllText("$prefix.stdout",$Output,$utf8)
    [IO.File]::WriteAllText("$prefix.stderr",$ErrorText,$utf8)
    return @{stdout_path="$prefix.stdout";stderr_path="$prefix.stderr";exit_code=0;timed_out=$false;
        capture_exceeded=$false;pipe_drain_failed=$false;abnormal_exit_kind=$null;process_tree_kill_error=$null}
}
function Full-Output([string] $File) {
    $d = Get-TargetFileProtocolDefinition $File
    $out = if ($File -ceq 'big.lua') { "target file phase big.lua: yielded b`nOK`ntarget file phase big.lua: returned a`n" }
        elseif ($File -ceq 'main.lua') { "testing warnings`ntesting Ctrl C`ndone`ndone (with 10 kills)`nOK`n" }
        else { $d.source_marker + "`n" + (@($d.phases | ForEach-Object { "target file phase ${File}: $_`n" }) -join '') }
    return $out + "target file completion ${File}: complete`n"
}
function Error-Output([string] $File) {
    if ($File -ceq 'api.lua') { return "Lua warning: #This should be a single warning`nLua warning: #This should be another one`n" }
    if ($File -ceq 'memerr.lua') { return "1`n2`n3`n" }
    return ''
}
function New-ManifestFixture {
    $fixture = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    $m = Get-Content (Join-Path $root $relative) -Raw | ConvertFrom-Json -AsHashtable -Depth 48
    foreach ($identity in @($m.wrapper,$m.orchestrator) + @($m.files | ForEach-Object source)) {
        $destination = Join-Path $fixture $identity.path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy((Join-Path $root $identity.path),$destination)
    }
    $m.synthetic_fixture = $true
    $null = Write-Json (Join-Path $fixture $relative) $m
    return @{root=$fixture;manifest=$m;path=(Join-Path $fixture $relative)}
}
function Add-SyntheticSourceReview([Collections.IDictionary] $Fixture) {
    $m = $Fixture.manifest
    $narrative = @{schema_version=1;synthetic_fixture=$true;target=$m.target;reviewer='synthetic-independent-reviewer';
        decision='accepted';runtime_acceptance=$false;coverage_authority=$false}
    $narrativePath = 'tests/conformance/synthetic-source-review.json'
    $narrativeHash = Write-Json (Join-Path $Fixture.root $narrativePath) $narrative
    $approval = @{schema_version=1;kind='target-file-completion-approval';synthetic_fixture=$true;target=$m.target;
        author='synthetic-author';reviewer='synthetic-independent-reviewer';decision='accepted';
        wrapper_sha256=$m.wrapper.sha256;orchestrator_sha256=$m.orchestrator.sha256;
        review_evidence=@{path=$narrativePath;sha256=$narrativeHash};decisions=@()}
    foreach ($item in $m.files) {
        $payload = ConvertTo-Json -InputObject $item -Compress -Depth 32
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($payload))).ToLowerInvariant()
        $approval.decisions += @{file=$item.file;source_sha256=$item.source.sha256;protocol_sha256=$hash;
            decision='accepted';rationale='Synthetic source-binding regression only; no runtime or coverage authority.'}
    }
    $path = 'tests/conformance/synthetic-source-approval.json'
    $approvalHash = Write-Json (Join-Path $Fixture.root $path) $approval
    $m.review = @{status='accepted';author=$approval.author;reviewer=$approval.reviewer;artifact=$path;artifact_sha256=$approvalHash}
    $null = Write-Json $Fixture.path $m
    return @{path=$path;approval=$approval}
}

Case 'all 17 author protocols bind exact original byte spans, including Latin-1 strings' {
    $result = Read-TargetFileProtocolManifest -Root $root -Path $relative
    Assert-True ($result.manifest.files.Count -eq 17 -and -not $result.manifest.runtime_acceptance -and
        -not $result.manifest.coverage_authority) 'Author proposal gained acceptance'
    Assert-True ($null -eq (Get-TargetFileProtocolDefinition 'events.lua')) 'Historical retained file gained a new protocol'
}
Case 'pending author proposal cannot authorize final File acceptance' {
    Reject { Read-TargetFileProtocolManifest -Root $root -Path $relative -RequireReview } 'accepted independent review'
}
foreach ($file in @('api','attrib','big','calls','code','cstack','db','errors','literals','locals','main','memerr',
    'nextvar','sort','strings','vararg','verybig' | ForEach-Object { $_ + '.lua' })) {
    Case "synthetic $file completion requires its return phase and source marker" {
        $p = New-Capture (Full-Output $file) (Error-Output $file)
        $r = Assert-TargetFileCompletion -File $file -Configuration upstream-test -Process $p
        Assert-True ($r.source_completed -and -not $r.coverage_authority -and -not $r.runtime_acceptance) 'Capture gained authority'
    }
}
foreach ($file in @('api.lua','code.lua','memerr.lua')) {
    Case "default $file early return stays an observed T omission" {
        $p = New-Capture "target file completion ${file}: T absent`n"
        $r = Assert-TargetFileCompletion -File $file -Configuration default -Process $p
        Assert-True (-not $r.source_completed) 'T absence passed the instrumented body'
        Reject { Assert-TargetFileCompletion -File $file -Configuration upstream-test -Process $p } 'terminal return witness'
    }
}
Case 'OK plus exit zero without the terminal return observation fails' {
    $p = New-Capture "OK`n"
    Reject { Assert-TargetFileCompletion calls.lua upstream-test $p } 'terminal return witness'
}
Case 'missing wrong duplicate and reordered return phases fail' {
    foreach ($output in @(
        (Full-Output 'attrib.lua').Replace("target file phase attrib.lua: returned 27`n",''),
        (Full-Output 'attrib.lua').Replace('returned 27','returned 28'),
        ((Full-Output 'attrib.lua') + "target file phase attrib.lua: returned 27`n"),
        "OK`ntarget file completion attrib.lua: complete`ntarget file phase attrib.lua: returned 27`n")) {
        Reject { Assert-TargetFileCompletion attrib.lua upstream-test (New-Capture $output) } 'return or yield phase'
    }
}
Case 'big must yield before OK then return after OK' {
    $out = Full-Output 'big.lua'
    foreach ($changed in @($out.Replace('yielded b','yielded a'),
        "OK`ntarget file phase big.lua: yielded b`ntarget file phase big.lua: returned a`ntarget file completion big.lua: complete`n",
        "target file phase big.lua: yielded b`ntarget file phase big.lua: returned a`nOK`ntarget file completion big.lua: complete`n")) {
        Reject { Assert-TargetFileCompletion big.lua upstream-test (New-Capture $changed) } 'yield phase|between yield and return'
    }
}
Case 'continued API warning fragments must form both exact complete warnings' {
    foreach ($errors in @('',"Lua warning: #This should be a single warning`n",
        "Lua warning: #This should be a`nLua warning: single warning`nLua warning: #This should be another one`n")) {
        Reject { Assert-TargetFileCompletion api.lua upstream-test (New-Capture (Full-Output api.lua) $errors) } 'continued warning protocol'
    }
}
Case 'memerr progress starts at one, stays consecutive, and rejects warning camouflage' {
    foreach ($errors in @('',"0`n1`n","1`n3`n","1`n2`n2`n","1`nLua warning: hidden`n")) {
        Reject { Assert-TargetFileCompletion memerr.lua upstream-test (New-Capture (Full-Output memerr.lua) $errors) } 'progress'
    }
}
Case 'main must finish both original interrupt subprocesses and warnings before OK' {
    foreach ($out in @((Full-Output main.lua).Replace("done`n",''),
        (Full-Output main.lua).Replace('with 10 kills','with 1 kills'),
        (Full-Output main.lua).Replace("testing warnings`n",''))) {
        Reject { Assert-TargetFileCompletion main.lua upstream-test (New-Capture $out) } 'subprocess completion'
    }
}
Case 'timeouts abnormal exits and unexpected stderr cannot pass a terminal marker' {
    $p = New-Capture (Full-Output errors.lua); $p.timed_out = $true
    Reject { Assert-TargetFileCompletion errors.lua upstream-test $p } 'finish cleanly'
    $p = New-Capture (Full-Output errors.lua); $p.exit_code = 1
    Reject { Assert-TargetFileCompletion errors.lua upstream-test $p } 'finish cleanly'
    Reject { Assert-TargetFileCompletion errors.lua upstream-test (New-Capture (Full-Output errors.lua) 'RESOURCE_ERROR') } 'Unexpected target'
}
Case 'original source wrapper and semantic span tampering each fail' {
    $f = New-ManifestFixture
    [IO.File]::AppendAllText((Join-Path $f.root $f.manifest.files[0].source.path),'tamper',$utf8)
    Reject { Read-TargetFileProtocolManifest $f.root $relative } 'hash differs'
    $f = New-ManifestFixture
    [IO.File]::AppendAllText((Join-Path $f.root $f.manifest.wrapper.path),'tamper',$utf8)
    Reject { Read-TargetFileProtocolManifest $f.root $relative } 'hash differs'
    $f = New-ManifestFixture; $f.manifest.files[0].source_links[0].start_byte--
    $null = Write-Json $f.path $f.manifest
    Reject { Read-TargetFileProtocolManifest $f.root $relative } 'span hash'
}
Case 'changed entry operations marker phases or duplicate primaries fail' {
    foreach ($field in @('entry','source_marker')) {
        $f = New-ManifestFixture; $f.manifest.files[0][$field] = 'unreviewed'
        $null = Write-Json $f.path $f.manifest
        Reject { Read-TargetFileProtocolManifest $f.root $relative } 'definition differs'
    }
    $f = New-ManifestFixture; $f.manifest.files[2].phases = @('returned a')
    $null = Write-Json $f.path $f.manifest
    Reject { Read-TargetFileProtocolManifest $f.root $relative } 'phases'
    $f = New-ManifestFixture; $f.manifest.files[1] = $f.manifest.files[0]
    $null = Write-Json $f.path $f.manifest
    Reject { Read-TargetFileProtocolManifest $f.root $relative } 'duplicated'
}
Case 'self review cannot install source-only completion authority' {
    $f = New-ManifestFixture
    $f.manifest.review.status = 'accepted'; $f.manifest.review.reviewer = $f.manifest.review.author
    $null = Write-Json $f.path $f.manifest
    Reject { Read-TargetFileProtocolManifest $f.root $relative -RequireReview } 'accepted independent review'
}
Case 'synthetic independent source review binds every protocol without executing Lua' {
    $f = New-ManifestFixture; $null = Add-SyntheticSourceReview $f
    $r = Read-TargetFileProtocolManifest $f.root $relative -RequireReview
    Assert-True (-not $r.manifest.runtime_acceptance -and -not $r.manifest.coverage_authority) 'Source review became runtime acceptance'
}
Case 'changed semantic source mapping cannot reuse an earlier source review' {
    $f = New-ManifestFixture; $null = Add-SyntheticSourceReview $f
    $f.manifest.files[0].source_links[0].rationale = 'Changed semantic mapping after source review'
    $null = Write-Json $f.path $f.manifest
    Reject { Read-TargetFileProtocolManifest $f.root $relative -RequireReview } 'approval decision differs'
}
Case 'missing duplicate and stale reviewed source decisions each fail' {
    foreach ($change in @('missing','duplicate','stale')) {
        $f = New-ManifestFixture; $a = Add-SyntheticSourceReview $f
        if ($change -ceq 'missing') { $a.approval.decisions = @($a.approval.decisions | Select-Object -Skip 1) }
        elseif ($change -ceq 'duplicate') { $a.approval.decisions[1] = $a.approval.decisions[0] }
        else { $a.approval.decisions[0].source_sha256 = '0' * 64 }
        $f.manifest.review.artifact_sha256 = Write-Json (Join-Path $f.root $a.path) $a.approval
        $null = Write-Json $f.path $f.manifest
        Reject { Read-TargetFileProtocolManifest $f.root $relative -RequireReview } 'approval source set|approval decision'
    }
}
Case 'report cannot claim the wrapper ran when its actual entry arguments differ' {
    $f = New-ManifestFixture; $m = Read-TargetFileProtocolManifest $f.root $relative
    $p = New-Capture (Full-Output attrib.lua)
    $wrapper = Join-Path $f.root $f.manifest.wrapper.path
    $p.arguments = @('-e','setup','direct-source.lua')
    $report = @{operation='file:attrib.lua';requested_configuration='upstream-test';execution_disposition='unchanged';process=$p;
        file_completion_protocol=@{file='attrib.lua';entry='dump';manifest_path=$relative;manifest_sha256=$m.sha256;
            wrapper_artifact=$wrapper;wrapper_sha256=$f.manifest.wrapper.sha256;chunk_path='attrib.lua';
            executed_sha256=($f.manifest.files | Where-Object file -CEQ attrib.lua).source.sha256;
            runtime_acceptance=$false;coverage_authority=$false}}
    Reject { Assert-TargetFileProtocolBinding -Root $f.root -Report $report -WrapperPath $wrapper } 'executed entry point'
    $p.arguments = @('-e',"T=nil; print('OK')",$wrapper,'attrib.lua','attrib.lua')
    Reject { Assert-TargetFileProtocolBinding -Root $f.root -Report $report -WrapperPath $wrapper } 'executed entry point'
}
Case 'full source binding replays captured returns and requires the execution contract identity' {
    $f = New-ManifestFixture; $null = Add-SyntheticSourceReview $f
    $m = Read-TargetFileProtocolManifest $f.root $relative
    $p = New-Capture (Full-Output attrib.lua)
    $wrapper = Join-Path $f.root $f.manifest.wrapper.path
    $setup = "assert(_soft==nil and _port==nil and _U==nil and _nomsg==nil); warn('@on'); " +
        "assert(type(T)=='table' and type(T.checkmemory)=='function'); T.checkmemory(); dofile('equivalent-source-profile-witness.lua')"
    $p.arguments = @('-e',$setup,$wrapper,'attrib.lua','attrib.lua')
    $identity = @{file='attrib.lua';entry='dump';manifest_path=$relative;manifest_sha256=$m.sha256;
        wrapper_artifact=$wrapper;wrapper_sha256=$f.manifest.wrapper.sha256;chunk_path='attrib.lua';
        executed_sha256=($f.manifest.files | Where-Object file -CEQ attrib.lua).source.sha256;
        runtime_acceptance=$false;coverage_authority=$false;disposition='complete';source_completed=$true;
        terminal_witness='target file completion attrib.lua: complete'}
    $report = @{operation='file:attrib.lua';requested_configuration='upstream-test';execution_disposition='unchanged';
        process=$p;file_completion_protocol=$identity;synthetic_fixture=$true}
    $contract = @{file_completion_protocol_sha256=$m.sha256;file_completion_wrapper_sha256=$f.manifest.wrapper.sha256}
    $result = Assert-TargetFileProtocolBinding -Root $f.root -Report $report -WrapperPath $wrapper -Contract $contract -RequireReview
    Assert-True (-not $result.runtime_acceptance) 'Source binding gained runtime acceptance'
    Reject { Assert-TargetFileProtocolBinding -Root $f.root -Report $report -WrapperPath $wrapper -Contract @{} -RequireReview } 'contract does not bind'
    $identity.executed_sha256 = '0' * 64
    Reject { Assert-TargetFileProtocolBinding -Root $f.root -Report $report -WrapperPath $wrapper } 'selected chunk hash'
    $identity.executed_sha256 = ($f.manifest.files | Where-Object file -CEQ attrib.lua).source.sha256
    $identity.source_completed = $false
    Reject { Assert-TargetFileProtocolBinding -Root $f.root -Report $report -WrapperPath $wrapper } 'Recorded completion result'
}

if ($ReferenceInterpreter -ne '') {
    function Run-Chunk([string] $Name, [string] $Source) {
        $script:Serial++; $path = Join-Path $temporary "chunk-$script:Serial.lua"
        [IO.File]::WriteAllText($path,$Source,$utf8)
        $program = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
        $lib = Join-Path (Split-Path -Parent (Split-Path -Parent $program)) 'lib'
        $environment = @{PATH=$lib + [IO.Path]::PathSeparator + $env:PATH;
            LD_LIBRARY_PATH=$lib + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH;
            DYLD_LIBRARY_PATH=$lib + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH}
        return Invoke-ConformanceProcess -Executable $ReferenceInterpreter `
            -Arguments @((Join-Path $root 'tests/conformance/target-file-completion.lua'),$Name,$path) `
            -Directory $temporary -OutputPrefix (Join-Path $temporary "lua-$script:Serial") -TimeoutSeconds 15 -Environment $environment
    }
    Case 'real wrapper rejects wrong attrib return after an OK print' {
        $p = Run-Chunk attrib.lua "print('OK'); return 28"
        Assert-True ($p.exit_code -ne 0) 'Wrapper accepted wrong returned 27'
        $script:LuaCases++
    }
    Case 'real wrapper distinguishes big suspension from early return and extra yield' {
        foreach ($source in @("return 'b'","coroutine.yield('b'); print('OK'); coroutine.yield('a')")) {
            $p = Run-Chunk big.lua $source
            Assert-True ($p.exit_code -ne 0) 'Wrapper confused yield and return'
            $script:LuaCases++
        }
        $p = Run-Chunk big.lua "coroutine.yield('b'); print('OK'); return 'a'"
        $null = Assert-TargetFileCompletion big.lua default $p
        $script:LuaCases++
    }
    Case 'real wrapper checks calls identity and preserves strip and dump execution' {
        $p = Run-Chunk calls.lua "deep=function() end; print('OK'); return function() end"
        Assert-True ($p.exit_code -ne 0) 'Wrapper accepted wrong deep function'
        $script:LuaCases++
        $p = Run-Chunk attrib.lua "print('OK'); return 27"
        $null = Assert-TargetFileCompletion attrib.lua default $p
        $script:LuaCases++
        $p = Run-Chunk verybig.lua "print('OK'); return 10"
        $null = Assert-TargetFileCompletion verybig.lua default $p
        $script:LuaCases++
    }
    Case 'real wrapper rejects extra missing nil and wrong-type return values' {
        foreach ($item in @(
            @{file='attrib.lua';source="print('OK'); return 27, nil"},
            @{file='attrib.lua';source="print('OK'); return"},
            @{file='attrib.lua';source="print('OK'); return 27.0"},
            @{file='literals.lua';source="print('OK'); return nil"},
            @{file='calls.lua';source="deep=true; print('OK'); return deep"},
            @{file='calls.lua';source="deep=function() end; print('OK'); return deep, nil"},
            @{file='verybig.lua';source="print('OK'); return 10, false"},
            @{file='api.lua';source='return nil'},
            @{file='code.lua';source='return nil'},
            @{file='memerr.lua';source='return nil'},
            @{file='locals.lua';source="print('OK'); return 5, nil"},
            @{file='locals.lua';source="print('OK'); return 5, function() end, false"}
        )) {
            $p = Run-Chunk $item.file $item.source
            Assert-True ($p.exit_code -ne 0) "Wrapper accepted wrong return protocol for $($item.file)"
            $script:LuaCases++
        }
        $p = Run-Chunk locals.lua "print('OK'); return 5, function() end"
        $null = Assert-TargetFileCompletion locals.lua default $p
        $script:LuaCases++
    }
}
Write-Output "PASS: $script:Cases file completion regressions; $script:LuaCases synthetic Lua chunk processes; no upstream coverage acceptance"
if ($ReferenceInterpreter -eq '') { Write-Output 'NOT RUN: optional C wrapper execution checks (ReferenceInterpreter not supplied)' }
