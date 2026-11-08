$ErrorActionPreference='Stop'
Import-Module ./scripts/ConformanceRunner.psm1 -Force
$base=(Resolve-Path 'reports/cli-msghandler/346457279dd348848b95b0c6dd38c977').Path
$out=Join-Path $PWD.Path ('reports/cli-main-prefix/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($out)
$utf8=[Text.UTF8Encoding]::new($false);$rows=@()
$setup=@'
global *
local saved_arg=arg
saved_main=nil;saved_argv=nil
prefix_watch=setmetatable({},{__mode='v'})
function probe(label)
 local level=2
 while true do local info=debug.getinfo(level,'Sf');assert(info,'no host');if info.what=='C' then break end;level=level+1 end
 local info=debug.getinfo(level,'Sf')
 if saved_main then assert(info.func==saved_main,'changed main identity') else saved_main=info.func end
 io.stdout:write(label,':',info.what)
 for i=1,9 do
  local n,v=debug.getlocal(level,i);if not n then break end
  assert(n=='(C temporary)')
  io.stdout:write(' ',i,'=',type(v))
  if i==1 and type(v)=='number' then io.stdout:write('/',math.type(v),'/',v) end
  if i==2 and type(v)=='userdata' then if saved_argv then assert(v==saved_argv) else saved_argv=v end;io.stdout:write('/same-argv') end
 end
 io.stdout:write('\n')
 return level
end
probe('init')
setmetatable(saved_arg,{__len=function(self)probe('arg-length');return 1 end})
arg=nil;_PROMPT=nil;_PROMPT2=nil
setmetatable(_G,{__index=function(_,key)
 if key=='arg' then probe('arg-global');return saved_arg end
 if key=='_PROMPT' or key=='_PROMPT2' then
  collectgarbage();assert(prefix_watch[1]==nil)
  probe('prompt-global')
  return setmetatable({},{__tostring=function(self)probe('prompt-string');return '' end})
 end
end})
'@
foreach($cfg in @('default','upstream-test')){
 foreach($mode in @('plain','mutated')){
  $cwd=Join-Path $out ($cfg+'/'+$mode);[void][IO.Directory]::CreateDirectory($cwd)
  $image=Join-Path $base ($cfg+'/image')
  [IO.File]::WriteAllText((Join-Path $cwd 'case.lua'),"global *`nprobe('script');assert((...)=='extra');return 27`n",$utf8)
  $inputPath=Join-Path $cwd 'input';[IO.File]::WriteAllText($inputPath,"probe('repl')`n",$utf8)
  $init=$setup
  if($mode -eq 'mutated'){$init+="`nlocal level=2;while debug.getinfo(level,'S').what~='C' do level=level+1 end;debug.setlocal(level,1,false);local t={};prefix_watch[1]=t;debug.setlocal(level,2,t);t=nil`n"}
  $prefix=Join-Path $cwd observed;$id=[guid]::NewGuid().ToString('N')
  $p=Invoke-ConformanceProcess -Executable (Join-Path $image 'lua.exe') -Arguments @('-i','-e',"probe('snippet')",'case.lua','extra') -Directory $cwd -OutputPrefix $prefix -TimeoutSeconds 900 -StandardInputPath $inputPath -Environment @{LUA_INIT=$init;MEMLIMIT='2147483648';LUA_ADA_CONFORMANCE_ALLOCATOR='2147483648';LUA_ADA_CONFORMANCE_RUN_ID=$id;LUA_ADA_CONFORMANCE_TELEMETRY=$prefix+'.allocator';PATH=$image+';'+$env:PATH}
  $rows+=@{configuration=$cfg;mode=$mode;setup=$init;setup_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($init))).ToLowerInvariant();process=$p;run_id=$id;telemetry=(Get-Content ($prefix+'.allocator.'+$p.process_id+'.json') -Raw|ConvertFrom-Json)}
  Write-Host ($cfg+' '+$mode+' exit='+$p.exit_code);Get-Content $p.stdout_path;Get-Content $p.stderr_path
 }
}
[IO.File]::WriteAllText((Join-Path $out 'index.json'),($rows|ConvertTo-Json -Depth 30).Replace("`r`n","`n")+"`n",$utf8)
Write-Host $out
