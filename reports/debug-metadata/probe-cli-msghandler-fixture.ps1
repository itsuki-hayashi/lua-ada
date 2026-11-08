$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$base=(Resolve-Path 'reports/cli-msghandler/346457279dd348848b95b0c6dd38c977').Path
$out=Join-Path $PWD.Path ('reports/cli-msghandler-fixture/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($out)
$utf8=[Text.UTF8Encoding]::new($false)
$cases=@('string','table','table-name','tostring-string','tostring-number','tostring-nil','tostring-throws','tostring-nul','numeric','numeric-meta','callable-meta','raw-meta','mutate-parent','frames','weak-error','handler-yield','closer-error','exit-close','exit-no-close','memory','entered-handler-memory')
$records=@()
foreach($cfg in @('default','upstream-test')){
 $image=Join-Path $base ($cfg+'/image')
 foreach($case in $cases){
  if($cfg -eq 'default' -and $case -in @('memory','entered-handler-memory')){continue}
  $cwd=Join-Path $out ($cfg+'/'+$case);[void][IO.Directory]::CreateDirectory($cwd)
  $src=Join-Path $cwd 'controls.lua';[IO.File]::Copy((Join-Path $PWD.Path 'tests/lua/cli_message_handler_controls.lua'),$src)
  $prefix=Join-Path $cwd 'observed';$id=[guid]::NewGuid().ToString('N')
  $timeout=if($case -eq 'exit-no-close'){5}else{900}
  $p=Invoke-ConformanceProcess -Executable (Join-Path $image 'lua.exe') -Arguments @('-E','controls.lua',$case) -Directory $cwd -OutputPrefix $prefix -TimeoutSeconds $timeout -Environment @{MEMLIMIT='2147483648';LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';LUA_ADA_CONFORMANCE_RUN_ID=$id;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.allocator';PATH=$image+';'+$env:PATH}
  $t=$prefix+'.allocator.'+$p.process_id+'.json'
  $records+=[ordered]@{configuration=$cfg;case=$case;source_path=$src;source_sha256=(Get-FileHash $src).Hash.ToLowerInvariant();run_id=$id;process=$p;telemetry_path=$t;telemetry=$(if(Test-Path $t){Get-Content $t -Raw|ConvertFrom-Json -AsHashtable}else{$null});runtime_acceptance=$false}
  Write-Host ($cfg+' '+$case+' exit='+$p.exit_code+' stderr='+$p.stderr_bytes+' timeout='+$p.timed_out)
 }
}
[IO.File]::WriteAllText((Join-Path $out 'index.json'),([ordered]@{kind='native-cli-message-handler-fixture-author-observation';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';fixture_sha256=(Get-FileHash 'tests/lua/cli_message_handler_controls.lua').Hash.ToLowerInvariant();records=$records;runtime_acceptance=$false;coverage_authority=$false}|ConvertTo-Json -Depth 35).Replace("`r`n","`n")+"`n",$utf8)
[IO.File]::WriteAllText('reports/debug-metadata/cli-msghandler-fixture-latest.path',$out,$utf8)
Write-Host $out