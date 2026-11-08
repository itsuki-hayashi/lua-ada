$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$out=Join-Path $PWD.Path ('reports/cli-msghandler-initial-ada/'+[guid]::NewGuid().ToString('N'));$image=Join-Path $out 'image';[void][IO.Directory]::CreateDirectory($image)
$source='C:/Users/Itsuki/.codex/worktrees/remaining-c-api/lua-ada/reports/cli-interrupt-build/ef0a24e1e0d640cf82e8e53cb046f8b1/frozen-default-cli/lua_ada.exe'
$hash=(Get-FileHash $source).Hash.ToLowerInvariant();if($hash -cne '95c4efb24a594f466b28d0c272e09ca589857cf5396679bc4756d70bf19db1d9'){throw 'Wrong peer image'}
$exe=Join-Path $image 'lua_ada.exe';[IO.File]::Copy($source,$exe)
if((Get-FileHash $exe).Hash.ToLowerInvariant() -cne $hash){throw 'Image freeze failed'}
$cases=@('string','table','table-name','tostring-string','tostring-number','tostring-nil','tostring-throws','tostring-nul','numeric','numeric-meta','callable-meta','raw-meta','mutate-parent','frames','weak-error','handler-yield','closer-error','exit-close','exit-no-close','hooks')
$rows=@()
foreach($case in $cases){
 $cwd=Join-Path $out $case;[void][IO.Directory]::CreateDirectory($cwd)
 [IO.File]::Copy((Join-Path $PWD.Path 'tests/lua/cli_message_handler_controls.lua'),(Join-Path $cwd 'controls.lua'))
 if($case -eq 'hooks'){$arguments=@('-E','-e',"global *;debug.sethook(function(event) local i=debug.getinfo(2,'S');if i.what=='C' then io.stdout:write(event,':C\n') end end,'cr')",'-e','local x=1','-e','local y=2')}
 else{$arguments=@('-E','controls.lua',$case)}
 $p=Invoke-ConformanceProcess -Executable $exe -Arguments $arguments -Directory $cwd -OutputPrefix (Join-Path $cwd observed) -TimeoutSeconds 900 -Environment @{PATH=$image+';'+$env:PATH} -CaptureLimitBytes 1048576
 $rows+=@{case=$case;process=$p;ada_allocator_telemetry='not supplied by product CLI';runtime_acceptance=$false}
 Write-Host ($case+' exit='+$p.exit_code+' stderr='+$p.stderr_bytes+' timeout='+$p.timed_out)
 if($case -eq 'hooks'){Get-Content $p.stdout_path}
}
[IO.File]::WriteAllText((Join-Path $out index.json),([ordered]@{kind='temporary-cli-handler-author-diagnostics';image_sha256=$hash;source_owner='Runtime temporary combined helper/interrupt snapshot; not final source';records=$rows;runtime_acceptance=$false}|ConvertTo-Json -Depth 25).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Host $out