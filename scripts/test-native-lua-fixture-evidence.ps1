param([string] $Compiler='', [string] $ReferenceInterpreter='', [string] $ReferenceRuntimeDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'NativeLuaFixtures.psm1')
Import-Module (Join-Path $PSScriptRoot 'NativeLuaFixtureEvidence.psm1')
$directory=Join-Path $root ('reports/native-fixture-evidence-selftest/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0;$script:Serial=0
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "NATIVE FIXTURE EVIDENCE TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 64|ConvertFrom-Json -AsHashtable -Depth 64)}
function Save-Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,(ConvertTo-Json $Value -Depth 64).Replace("`r`n","`n")+"`n",$utf8)}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
$image=@{toolchain=@{compiler_sha256=('1'*64)};launcher_basename='lua.exe'}
$report=@{acceptance_context='default/windows/validation/static';target='ReferenceC';process=@{executable='unused';executable_sha256=('2'*64)}}
function Replay($Report,$Image){Assert-NativeLuaFixtureEvidence -Root $root -ArtifactRoot $root -ImagePayload (Join-Path $directory 'image') -Image $Image -Report $Report}
Case 'missing native linkage cannot be replaced by raw successful process metadata'{
    $report.status='passed';$report.native_fixture_records=@()
    Reject {Replay $report $image} 'requires its exact same-image'
}
Case 'duplicate native linkage receipts fail before owner or compiler lookup'{
    $r=Clone $report;$r.native_fixture_linkage=@(@{path='unused';sha256=('3'*64)},@{path='unused';sha256=('3'*64)})
    Reject {Replay $r $image} 'requires its exact same-image'
}
Case 'linkage transport rejects a path outside reports before parsing its claims'{
    $r=Clone $report;$r.native_fixture_linkage=@(@{path=(Join-Path $root 'alire.toml');sha256=('3'*64)})
    Reject {Replay $r $image} 'outside reports'
}
if($Compiler -ne ''){
    if(-not $IsWindows -or $ReferenceInterpreter -eq '' -or $ReferenceRuntimeDirectory -eq ''){
        throw 'Actual fixture replay regressions require Windows and explicit compiler/oracle/runtime paths'
    }
    # Compile the five original C fixtures, but launch no Lua interpreter or
    # native lifetime driver. The containing report/image are explicitly
    # synthetic test structures. Only source/transport/import replay is tested.
    $fixture=Join-Path $directory 'fixtures';[void][IO.Directory]::CreateDirectory($fixture)
    $hostImage=Join-Path $fixture 'lua.exe';[IO.File]::Copy($ReferenceInterpreter,$hostImage)
    $built=Build-NativeLuaFixtures -Root $root -HostPath $hostImage -RuntimeDirectory $ReferenceRuntimeDirectory -Compiler $Compiler `
        -Implementation ReferenceC -LibraryType shared -Platform windows -Configuration default -FixtureDirectory $fixture -RecordDirectory (Join-Path $directory 'linkage')
    $runtimeRelative='build/conformance/default/lib/libconformance_lua.dll'
    $payload=Join-Path $directory 'image';$runtimeCopy=Join-Path $payload $runtimeRelative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $runtimeCopy))
    [IO.File]::Copy((Join-Path $ReferenceRuntimeDirectory 'libconformance_lua.dll'),$runtimeCopy)
    $image=@{synthetic_fixture=$true;toolchain=@{compiler_sha256=$built.evidence.plan.compiler.sha256;dlltool_sha256=$built.evidence.plan.pe_import.tool.sha256};
        launcher_basename='lua.exe';paths=@{c_runtime='build/conformance/default/lib'};
        files=@(@{path=$runtimeRelative;sha256=$built.evidence.plan.owner.sha256})}
    $report=@{synthetic_fixture=$true;acceptance_context='default/windows/validation/static';target='ReferenceC';
        process=@{executable=$hostImage;executable_sha256=$built.evidence.plan.host.sha256};native_fixture_records=$built.records;native_fixture_linkage=@($built.identity)}
    function Mutate([scriptblock]$Change,[string]$Expected){
        $r=Clone $report;$value=Clone $built.evidence;$i=Clone $image
        &$Change $value $r $i
        $script:Serial++;$path=Join-Path $directory ("mutated-$script:Serial.json");Save-Json $path $value
        $r.native_fixture_linkage=@(@{path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant()})
        Reject {Replay $r $i} $Expected
    }
    Case 'actual compiled original fixtures replay their source tool exports dependency graph and aliases without Lua execution'{
        $result=Replay $report $image
        Assert-True ($result.verified -and $result.modules -eq 5 -and $result.artifacts -eq 10 -and -not $result.runtime_acceptance) 'Structural replay promoted or narrowed its observations'
    }
    Case 'stale frozen compiler and dlltool hashes reject an otherwise exact receipt'{
        Mutate {param($v,$r,$i) $i.toolchain.compiler_sha256='0'*64} 'context compiler'
        Mutate {param($v,$r,$i) $i.toolchain.dlltool_sha256='0'*64} 'frozen dlltool'
    }
    Case 'a shared receipt cannot substitute an arbitrary runtime DLL outside the frozen image'{
        Mutate {param($v,$r,$i) $i.files[0].sha256='0'*64} 'different frozen runtime'
    }
    Case 'archive fallback and extra compile transforms fail exact invocation reconstruction'{
        Mutate {param($v,$r,$i) $v.modules[0].compile.arguments+=@('-L','elsewhere','-llua')} 'tool identity invocation'
        Mutate {param($v,$r,$i) $v.plan.link_arguments=@('liblua.a')} 'link arguments differ'
    }
    Case 'a default fixture cannot borrow a T compiler invocation'{
        Mutate {param($v,$r,$i) $v.modules[0].compile.arguments=@('-DLUA_USER_H=<ltests.h>')+$v.modules[0].compile.arguments} 'tool identity invocation'
    }
    Case 'missing modules duplicate aliases and stale helper bindings remain failures'{
        Mutate {param($v,$r,$i) $v.modules=@($v.modules|Select-Object -Skip 1)} 'module or alias set'
        Mutate {param($v,$r,$i) $v.artifacts[1]=Clone $v.artifacts[0]} 'source or artifact binding'
        Mutate {param($v,$r,$i) $v.source_bindings[0].sha256='0'*64} 'Review file hash differs'
    }
    Case 'receipt authority flags and synthetic receipt labels never discharge actual linkage observations'{
        Mutate {param($v,$r,$i) $v.runtime_acceptance=$true} 'context compiler'
        Mutate {param($v,$r,$i) $v.synthetic_fixture=$true} 'context compiler'
    }
    Case 'invented parsed-owner metadata cannot replace actual module import replay'{
        Mutate {param($v,$r,$i) $v.modules[0].binding.owner_sha256='0'*64} 'recorded owner facts'
    }
    Case 'an edited import definition fails reconstruction even when its transport hash is updated'{
        $path=$built.evidence.plan.pe_import.definition.path;$bytes=[IO.File]::ReadAllBytes($path)
        try{
            [IO.File]::AppendAllText($path,"invented_export`n",$utf8)
            Mutate {param($v,$r,$i) $v.plan.pe_import.definition.sha256=(Get-FileHash $path).Hash.ToLowerInvariant()} 'does not reconstruct'
        }finally{[IO.File]::WriteAllBytes($path,$bytes)}
    }
    Case 'changed original copied source bytes fail before successful compile metadata can count'{
        $path=Join-Path $fixture 'libs/lib1.c';$bytes=[IO.File]::ReadAllBytes($path)
        try{
            [IO.File]::AppendAllText($path,"`n/* changed copied source */`n",$utf8)
            Reject {Replay $report $image} 'artifact bytes or path differ'
        }finally{[IO.File]::WriteAllBytes($path,$bytes)}
    }
}
Write-Output "PASS: $script:Cases native fixture evidence regressions; no Lua execution, runtime lifetime or conformance acceptance"
