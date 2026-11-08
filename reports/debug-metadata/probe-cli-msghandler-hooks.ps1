$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$base=(Resolve-Path 'reports/cli-msghandler/346457279dd348848b95b0c6dd38c977').Path
$out=Join-Path $PWD.Path ('reports/cli-msghandler-hooks/'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($out)
$utf8=[Text.UTF8Encoding]::new($false);$rows=@()
$setup="global *;debug.sethook(function(event) local i=debug.getinfo(2,'S');if i.what=='C' then io.stdout:write(event,':C\n') end end,'cr')"
foreach($cfg in @('default','upstream-test')){
 $image=Join-Path $base ($cfg+'/image');$cwd=Join-Path $out $cfg;[void][IO.Directory]::CreateDirectory($cwd)
 $prefix=Join-Path $cwd 'observed';$id=[guid]::NewGuid().ToString('N')
 $p=Invoke-ConformanceProcess -Executable (Join-Path $image 'lua.exe') -Arguments @('-E','-e',$setup,'-e','local x=1','-e','local y=2') -Directory $cwd -OutputPrefix $prefix -TimeoutSeconds 900 -Environment @{MEMLIMIT='2147483648';LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';LUA_ADA_CONFORMANCE_RUN_ID=$id;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.allocator';PATH=$image+';'+$env:PATH}
 $rows+=@{configuration=$cfg;setup=$setup;run_id=$id;process=$p;telemetry=(Get-Content ($prefix+'.allocator.'+$p.process_id+'.json') -Raw|ConvertFrom-Json)}
 Write-Host $cfg;Get-Content $p.stdout_path;Get-Content $p.stderr_path
}
[IO.File]::WriteAllText((Join-Path $out 'index.json'),($rows|ConvertTo-Json -Depth 20).Replace("`r`n","`n")+"`n",$utf8);Write-Host $out