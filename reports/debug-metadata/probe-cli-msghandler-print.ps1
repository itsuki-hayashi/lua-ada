$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$base=(Resolve-Path 'reports/cli-msghandler/346457279dd348848b95b0c6dd38c977').Path
$out=Join-Path $PWD.Path ('reports/cli-msghandler-print/'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($out)
$utf8=[Text.UTF8Encoding]::new($false);$rows=@()
foreach($cfg in @('default','upstream-test')){
 $image=Join-Path $base ($cfg+'/image');$cwd=Join-Path $out $cfg;[void][IO.Directory]::CreateDirectory($cwd)
 $inputPath=Join-Path $cwd 'input';[IO.File]::WriteAllText($inputPath,"return 1`n",$utf8)
 $setup="global *;_PROMPT='';_PROMPT2='';print=function() error(setmetatable({},{__tostring=function() io.write('BAD_META');return 'BAD_MESSAGE' end}),0) end"
 $prefix=Join-Path $cwd 'observed';$id=[guid]::NewGuid().ToString('N')
 $p=Invoke-ConformanceProcess -Executable (Join-Path $image 'lua.exe') -Arguments @('-E','-i','-e',$setup) -Directory $cwd -OutputPrefix $prefix -TimeoutSeconds 900 -StandardInputPath $inputPath -Environment @{MEMLIMIT='2147483648';LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';LUA_ADA_CONFORMANCE_RUN_ID=$id;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.allocator';PATH=$image+';'+$env:PATH}
 $rows+=@{configuration=$cfg;setup=$setup;run_id=$id;process=$p;sidecar=(Get-Content ($prefix+'.allocator.'+$p.process_id+'.json') -Raw|ConvertFrom-Json)}
 Write-Host $cfg;Get-Content $p.stdout_path;Get-Content $p.stderr_path
}
[IO.File]::WriteAllText((Join-Path $out 'index.json'),($rows|ConvertTo-Json -Depth 20).Replace("`r`n","`n")+"`n",$utf8);Write-Host $out