$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$root=$PWD.Path;$utf8=[Text.UTF8Encoding]::new($false)
$out=Join-Path $root ('reports/cli-msghandler/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($out)
$cases=@(
 @{name='string';code='local function inner() error("E_STRING",0) end; local function outer() inner(); return 1 end; outer()'},
 @{name='table';code='error({},0)'},
 @{name='table-name';code='error(setmetatable({},{__name="Widget"}),0)'},
 @{name='tostring-string';code='local e; e=setmetatable({},{__tostring=function(self) assert(self==e); io.stdout:write("MM_ENTER\n"); return "MM_STRING" end}); error(e,0)'},
 @{name='tostring-number';code='error(setmetatable({},{__tostring=function() io.stdout:write("MM_ENTER\n"); return 37 end}),0)'},
 @{name='tostring-nil';code='error(setmetatable({},{__tostring=function() io.stdout:write("MM_ENTER\n"); return nil end}),0)'},
 @{name='tostring-throws';code='error(setmetatable({},{__tostring=function() io.stdout:write("MM_ENTER\n"); error("MM_THROW",0) end}),0)'},
 @{name='tostring-nul';code='error(setmetatable({},{__tostring=function() return "MM\0TAIL" end}),0)'},
 @{name='numeric';code='error(37,0)'},
 @{name='numeric-meta';code='debug.setmetatable(0,{__tostring=function() io.stdout:write("NUM_MM\n"); return "BAD_NUM" end}); error(37,0)'},
 @{name='callable-meta';code='local callable; local e; callable=setmetatable({},{__call=function(self,v) assert(self==callable and v==e); return "MM_CALLABLE" end}); e=setmetatable({},{__tostring=callable}); error(e,0)'},
 @{name='raw-meta';code='local mt=setmetatable({},{__index=function() io.stdout:write("META_INDEX\n"); return function() return "BAD_META" end end}); error(setmetatable({},mt),0)'},
 @{name='mutate-parent';code='local e; e=setmetatable({},{__tostring=function(self) local n,v=debug.getlocal(2,1); io.stdout:write("PARENT_ARG ",n," ",v==e and "same" or "other","\n"); io.stdout:write("SET ",debug.setlocal(2,1,37) or "nil","\n"); return false end}); error(e,0)'},
 @{name='compile-before-args';setup='local e=setmetatable({},{__tostring=function() io.stdout:write("TOSTRING\n"); return "ARG_MM" end}); arg=nil; setmetatable(_G,{__index=function(t,k) if k=="arg" then io.stdout:write("ARG_LOOKUP\n"); error(e,0) end end}); io.stdout:write("READY\n")';code='local ='},
 @{name='arg-lookup-before-handler';setup='local e=setmetatable({},{__tostring=function() io.stdout:write("TOSTRING\n"); return "ARG_MM" end}); arg=nil; setmetatable(_G,{__index=function(t,k) if k=="arg" then io.stdout:write("ARG_LOOKUP\n"); error(e,0) end end}); io.stdout:write("READY\n")';code='io.stdout:write("SCRIPT_RAN\n")'},
 @{name='arg-length-before-handler';setup='local e=setmetatable({},{__tostring=function() io.stdout:write("TOSTRING\n"); return "ARG_MM" end}); arg=setmetatable({},{__len=function() io.stdout:write("ARG_LENGTH\n"); error(e,0) end}); io.stdout:write("READY\n")';code='io.stdout:write("SCRIPT_RAN\n")'},
 @{name='exit-close';code='error(setmetatable({},{__tostring=function() io.stdout:write("EXIT_HANDLER\n"); os.exit(37,true) end}),0)'},
 @{name='exit-no-close';timeout=5;code='error(setmetatable({},{__tostring=function() io.stdout:write("EXIT_HANDLER\n"); os.exit(37,false) end}),0)'},
 @{name='memory';t_only=$true;code='local control=T.alloccount; local rep=string.rep; io.stdout:write("ARMED\n"); control(0); rep("x",100000)'},
 @{name='memory-in-numeric-handler';t_only=$true;code='local control=T.alloccount; io.stdout:write("ARMED\n"); control(0); error(37,0)'}
)
$frames=@'
local e
e=setmetatable({},{__tostring=function(self)
  assert(self==e)
  local p=debug.getinfo(2,"Sf")
  io.stdout:write("PARENT ",p.what," ",p.func==tostring and "tostring" or "anonymous","\n")
  local n,v=debug.getlocal(2,1)
  io.stdout:write("ARG ",n or "nil"," ",v==e and "same" or "other","\n")
  io.stdout:write("YIELDABLE ",coroutine.isyieldable() and "yes" or "no","\n")
  collectgarbage()
  for level=1,9 do
    local info=debug.getinfo(level,"nSl")
    if not info then break end
    io.stdout:write("FRAME ",level," ",info.what," ",info.namewhat," ",info.name or "-"," ",info.short_src," ",info.currentline,"\n")
  end
  io.stdout:write(debug.traceback("IN_CALLBACK",1),"\n")
  return "FRAME_MESSAGE"
end})
local function inner() error(e,0) end
local function outer() inner(); return 1 end
outer()
'@
$cases+=@{name='frames';code=$frames}
$records=@();$images=@()
foreach($cfg in @('default','upstream-test')){
 $image=Join-Path $out ($cfg+'/image');[void][IO.Directory]::CreateDirectory($image)
 $sourceExe='C:/Users/Itsuki/workspace/lua-ada/build/conformance/'+$cfg+'/bin/lua.exe'
 $sourceDll='C:/Users/Itsuki/workspace/lua-ada/build/conformance/'+$cfg+'/lib/libconformance_lua.dll'
 foreach($source in @($sourceExe,$sourceDll)){
  $hash=(Get-FileHash $source).Hash.ToLowerInvariant();$destination=Join-Path $image (Split-Path $source -Leaf)
  [IO.File]::Copy($source,$destination,$false)
  if((Get-FileHash $source).Hash.ToLowerInvariant() -ne $hash -or (Get-FileHash $destination).Hash.ToLowerInvariant() -ne $hash){throw 'Image changed while freezing'}
  $images+=[ordered]@{configuration=$cfg;source=$source;path=$destination;sha256=$hash}
 }
 foreach($case in $cases){
  if($case.ContainsKey('t_only') -and $cfg -eq 'default'){continue}
  $cwd=Join-Path $out ($cfg+'/'+$case.name);[void][IO.Directory]::CreateDirectory($cwd)
  $source=Join-Path $cwd 'case.lua';[IO.File]::WriteAllText($source,"global *`n"+$case.code+"`n",$utf8)
  $arguments=@('-E');if($case.ContainsKey('setup')){$arguments+=@('-e',("global *`n"+$case.setup))};$arguments+=@('case.lua')
  $prefix=Join-Path $cwd 'observed';$id=[guid]::NewGuid().ToString('N')
  $timeout=if($case.ContainsKey('timeout')){$case.timeout}else{900}
  $p=Invoke-ConformanceProcess -Executable (Join-Path $image 'lua.exe') -Arguments $arguments -Directory $cwd -OutputPrefix $prefix -TimeoutSeconds $timeout -Environment @{MEMLIMIT='2147483648';LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';LUA_ADA_CONFORMANCE_RUN_ID=$id;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.allocator';PATH=$image+';'+$env:PATH}
  $telemetry=$prefix+'.allocator.'+$p.process_id+'.json'
  $records+=[ordered]@{configuration=$cfg;case=$case.name;source_path=$source;source_sha256=(Get-FileHash $source).Hash.ToLowerInvariant();run_id=$id;process=$p;telemetry_path=$telemetry;telemetry=$(if(Test-Path $telemetry){Get-Content $telemetry -Raw|ConvertFrom-Json -AsHashtable}else{$null});interpretation='raw native observation only; not an Ada pass or source authority'}
  Write-Host ($cfg+' '+$case.name+' exit='+$p.exit_code+' stderr='+$p.stderr_bytes+' timeout='+$p.timed_out)
 }
}
[IO.File]::WriteAllText((Join-Path $out 'index.json'),([ordered]@{kind='native-cli-message-handler-author-observations';reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';images=$images;records=$records;runtime_acceptance=$false;coverage_authority=$false;source_adaptation_authority=$false}|ConvertTo-Json -Depth 40).Replace("`r`n","`n")+"`n",$utf8)
[IO.File]::WriteAllText((Join-Path $root 'reports/debug-metadata/cli-msghandler-latest.path'),$out,$utf8)
Write-Host $out
