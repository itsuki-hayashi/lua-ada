param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1') -Force
$temporary = Join-Path $root ('reports/target-context-selftests/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$utf8 = [Text.UTF8Encoding]::new($false)
$script:Cases = 0
# Every tiny binary and build/image label below is a synthetic transport
# fixture. No compiler, Lua interpreter, AUnit case or C consumer is executed.
function Case([string] $Name,[scriptblock] $Action) { & $Action; $script:Cases++; Write-Output "TARGET CONTEXT TEST PASS: $Name" }
function Assert-True([bool] $Value,[string] $Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock] $Action,[string] $Expected) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"
}
function Save([Collections.IDictionary] $Fixture) {
    [IO.File]::WriteAllText((Join-Path $Fixture.directory 'image.json'),
        (ConvertTo-Json -InputObject $Fixture.image -Depth 40).Replace("`r`n","`n") + "`n",$utf8)
}
function New-Fixture {
    $directory = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    $files = @()
    foreach ($path in @('tests/bin/static/conformance_runner.exe','build/conformance/default/bin/lua.exe',
        'lib/validation/static/liblua.a','build/conformance/default/lib/libconformance_lua.dll',
        'reports/core-image/synthetic/result.json','reports/core-image/synthetic/empty.stderr')) {
        $full = Join-Path $directory ('payload/' + $path)
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
        [IO.File]::WriteAllText($full,$(if($path.EndsWith('.stderr')){''}else{'synthetic artifact bytes'}),$utf8)
        $files += @{path=$path;bytes=(Get-Item $full).Length;sha256=(Get-FileHash $full).Hash.ToLowerInvariant();
            unix_mode=$(if($IsWindows){0}else{[int][IO.File]::GetUnixFileMode($full)})}
    }
    $image = @{schema_version=1;kind='immutable-target-context-image';target='remaining-upstream-compatibility';
        context='default/windows/validation/static';revision=('a'*40);reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        repository_dirty=$false;synthetic_fixture=$true;runtime_acceptance=$false;coverage_authority=$false;launcher_basename='lua.exe';
        files=$files;build_witnesses=@();paths=@{ada_launcher=$files[0].path;c_oracle=$files[1].path;
            ada_runtime='lib/validation/static';c_runtime='build/conformance/default/lib'}}
    $fixture = @{directory=$directory;image=$image}
    Save $fixture; return $fixture
}
function Replay([Collections.IDictionary] $Fixture) {
    Assert-TargetContextImage -ImageDirectory $Fixture.directory -Context default/windows/validation/static -Revision ('a'*40)
}

Case '26 context builds feed exactly three ten-file shards plus Aggregate and Heavy' {
    $p = Get-TargetContextPlan -Root $root
    Assert-True ($p.contexts.Count -eq 26 -and $p.partitions.Count -eq 130 -and -not $p.runtime_acceptance) 'Wrong target workflow cardinality'
    foreach ($context in $p.contexts) {
        $parts = @($p.partitions | Where-Object context -CEQ $context.context)
        $shards = @($parts | Where-Object operation -CEQ file)
        $files = @($shards | ForEach-Object files)
        Assert-True ($parts.Count -eq 5 -and $shards.Count -eq 3 -and
            @($shards | Where-Object { $_.files.Count -ne 10 }).Count -eq 0 -and
            $files.Count -eq 30 -and @($files | Sort-Object -Unique).Count -eq 30 -and
            @($shards | Where-Object constructs_supplement -EQ $true).Count -eq 1) 'Shard lost or duplicated an original primary'
    }
    Assert-True (@($p.contexts | Where-Object configuration -CEQ upstream-test).Count -eq 7) 'Instrumented contexts were narrowed'
}
Case 'synthetic artifact bytes and empty stderr survive replay without acceptance' {
    $f = New-Fixture; $r = Replay $f
    Assert-True ($r.manifest.synthetic_fixture -and -not $r.runtime_acceptance -and -not $r.coverage_authority) 'Image replay gained authority'
    Reject { Assert-TargetContextImage -ImageDirectory $f.directory -Context $f.image.context -Revision $f.image.revision -RequireActual } 'actual clean build'
}
Case 'runtime and oracle bytes cannot drift after the build snapshot' {
    foreach ($index in @(0,1,2,3)) {
        $f = New-Fixture
        [IO.File]::AppendAllText((Join-Path $f.directory ('payload/' + $f.image.files[$index].path)),'changed',$utf8)
        Reject { Replay $f } 'artifact bytes differ'
    }
}
Case 'different revision context basename and fake acceptance are rejected' {
    foreach ($field in @('revision','context','launcher_basename','runtime_acceptance','coverage_authority')) {
        $f = New-Fixture
        $f.image[$field] = if ($field -cin @('runtime_acceptance','coverage_authority')) { $true } else { 'wrong' }
        Save $f
        Reject { Replay $f } 'identity differs'
    }
}
Case 'duplicate aliases missing interpreters and empty interpreter payloads fail' {
    $f = New-Fixture; $copy = $f.image.files[0].Clone(); $copy.path = $copy.path.ToUpperInvariant(); $f.image.files += $copy
    Save $f; Reject { Replay $f } 'allowed generated artifact|duplicated'
    $f = New-Fixture; $f.image.files = @($f.image.files | Select-Object -Skip 1)
    Save $f; Reject { Replay $f } 'omits its interpreter'
    $f = New-Fixture; $path = Join-Path $f.directory ('payload/' + $f.image.files[0].path)
    [IO.File]::WriteAllText($path,'',$utf8); $f.image.files[0].bytes=0; $f.image.files[0].sha256=(Get-FileHash $path).Hash.ToLowerInvariant()
    Save $f; Reject { Replay $f } 'omits its interpreter'
}
Case 'path traversal aliases source writes and generated input masquerades fail' {
    foreach ($path in @('../src/engine.adb','lib/../../src/engine.adb','lib/./a.dll',
        'src/lua-engine.adb','references/lua/lua.c','config/lua_ada_config.gpr','build/conformance/x/source.c')) {
        $f = New-Fixture; $f.image.files[0].path = $path
        Save $f; Reject { Replay $f } 'allowed generated artifact|escapes or aliases'
    }
}
Case 'only exact disposable native stdin and CLI source evidence paths survive image replay' {
    $f=New-Fixture;$id='f'*32
    $paths=@("reports/core-image/$id/file-stdin/stdin-source.lua")
    foreach($name in @('arguments','-script','empty','source-name','shebang','bom','cli_lib','cli_init','large-source','prompt-controls')){
        $paths+="reports/core-image/$id/cli-fixtures/$name.lua"
    }
    foreach($role in @('api','oracle')){foreach($name in @('lib1','lib11','lib2','lib21','lib22')){
        $paths+="reports/core-image/$id/native-module-$role-fixtures/libs/$name.c"
    }}
    foreach($path in $paths){
        $full=Join-Path $f.directory ('payload/'+$path);[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
        [IO.File]::WriteAllText($full,'synthetic transport bytes only; no compiled fixture or execution',$utf8)
        $f.image.files+=@{path=$path;bytes=(Get-Item $full).Length;sha256=(Get-FileHash $full).Hash.ToLowerInvariant();
            unix_mode=$(if($IsWindows){0}else{[int][IO.File]::GetUnixFileMode($full)})}
    }
    Save $f;$null=Replay $f
    foreach($path in @("reports/core-image/$id/native-module-api-fixtures/libs/runtime.c",
        "reports/core-image/$id/native-module-api-fixtures/libs/lib1.adb",
        "reports/core-image/$id/file-stdin/runtime.lua",'reports/core-image/not-a-guid/file-stdin/stdin-source.lua',
        "reports/core-image/$id/cli-fixtures/runtime.lua",'reports/core-image/not-a-guid/cli-fixtures/prompt-controls.lua',
        "reports/core-image/$id/cli-fixtures/prompt-controls.adb","reports/core-image/$id/cli-fixtures/subdir/prompt-controls.lua",
        "build/conformance/$id/native-module-api-fixtures/libs/lib1.c")){
        $changed=New-Fixture;$changed.image.files[0].path=$path;Save $changed
        Reject {Replay $changed} 'allowed generated artifact'
    }
}
Case 'invalid numeric identities and missing runtime directories fail' {
    $f = New-Fixture; $f.image.files[0].bytes = '24'; Save $f
    Reject { Replay $f } 'file identity'
    $f = New-Fixture; $f.image.files[0].unix_mode = 65535; Save $f
    Reject { Replay $f } 'file identity'
    $f = New-Fixture; $f.image.paths.ada_runtime = 'lib/missing'; Save $f
    Reject { Replay $f } 'omits its runtime'
}
Case 'restored live files are checked against the same frozen bytes' {
    $f = New-Fixture; $live = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    foreach ($file in $f.image.files) {
        $source = Join-Path $f.directory ('payload/' + $file.path); $target = Join-Path $live $file.path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target)); [IO.File]::Copy($source,$target)
    }
    $null = Assert-TargetContextImage -ImageDirectory $f.directory -Context $f.image.context -Revision $f.image.revision -RestoredRoot $live
    [IO.File]::AppendAllText((Join-Path $live $f.image.files[0].path),'mutated',$utf8)
    Reject { Assert-TargetContextImage -ImageDirectory $f.directory -Context $f.image.context -Revision $f.image.revision -RestoredRoot $live } 'artifact bytes differ'
}
Write-Output "PASS: $script:Cases target plan/image regressions; synthetic byte fixtures only, no compiled runtime or conformance acceptance"
