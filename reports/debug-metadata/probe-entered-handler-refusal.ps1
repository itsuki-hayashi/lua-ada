$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$base='reports/cli-msghandler/346457279dd348848b95b0c6dd38c977'
$cfg='upstream-test'
$image=(Resolve-Path ($base+'/'+$cfg+'/image')).Path
$out=Join-Path $PWD.Path ('reports/cli-msghandler-handler-refusal/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($out)
$source=Join-Path $out 'case.lua'
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($source,"global *`nlocal control=T.alloccount; local e; e=setmetatable({},{__tostring=function(self) assert(self==e); io.stdout:write('HANDLER_ARMED\n'); control(0); return 37 end}); error(e,0)`n",$utf8)
$id=[guid]::NewGuid().ToString('N');$prefix=Join-Path $out 'observed'
$p=Invoke-ConformanceProcess -Executable (Join-Path $image 'lua.exe') -Arguments @('-E','case.lua') -Directory $out -OutputPrefix $prefix -TimeoutSeconds 900 -Environment @{MEMLIMIT='2147483648';LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';LUA_ADA_CONFORMANCE_RUN_ID=$id;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.allocator';PATH=$image+';'+$env:PATH}
$t=$prefix+'.allocator.'+$p.process_id+'.json'
$r=[ordered]@{kind='native-cli-entered-handler-refusal-author-observation';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';configuration=$cfg;source=$source;source_sha256=(Get-FileHash $source).Hash.ToLowerInvariant();image=$image;run_id=$id;process=$p;telemetry_path=$t;telemetry=(Get-Content $t -Raw|ConvertFrom-Json);runtime_acceptance=$false;coverage_authority=$false}
[IO.File]::WriteAllText((Join-Path $out 'index.json'),($r|ConvertTo-Json -Depth 30).Replace("`r`n","`n")+"`n",$utf8)
Write-Host $out
Get-Content ($prefix+'.stdout')
Get-Content ($prefix+'.stderr')
Get-Content $t
