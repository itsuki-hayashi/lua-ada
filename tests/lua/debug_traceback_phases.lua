-- Hook_Origin
do
  local n=0;local co=coroutine.create(function()local x=1 end);debug.sethook(co,function()local i=debug.getinfo(1,'n');assert(i.namewhat=='hook' and i.name=='?');local t=debug.traceback();assert(t:match("\n[^\n]+: in hook '%?'"));n=n+1 end,'l');assert(coroutine.resume(co));assert(n>0)
end

-- Local_Call_Name
do
  local function f()local t=debug.traceback();return t end;local t=f();assert(t:match("\n[^\n]+: in local 'f'"))
end

-- Anonymous_Coroutine
do
  local co=coroutine.create(assert(load('return function() coroutine.yield() end','@trace.lua'))());assert(coroutine.resume(co));local t=debug.traceback(co);assert(t:find("[C]: in field 'yield'",1,true));assert(t:find('trace.lua:1: in function <trace.lua:1>',1,true))
end

-- Native_Registry_Name
do
  local ok,t=(function()return pcall end)()(debug.traceback);assert(ok);assert(t:find("[C]: in function 'pcall'",1,true))
end

-- Replaced_Public_Loaded
do
  local f=assert(load('return function()coroutine.yield()end','@module.lua'))();local old=package.loaded;old.traceprobe={entry=f};package.loaded={};local co=coroutine.create(f);assert(coroutine.resume(co));local t=debug.traceback(co);package.loaded=old;old.traceprobe=nil;assert(t:find("function 'traceprobe.entry'",1,true))
end

-- Empty_Registry_Field
do
  local f=assert(load('return function()coroutine.yield()end','@module.lua'))();package.loaded.traceprobe={['']=f};local co=coroutine.create(f);assert(coroutine.resume(co));local t=debug.traceback(co);package.loaded.traceprobe=nil;assert(t:find("function 'traceprobe.'",1,true))
end

-- Tail_Marker
do
  local function f()local t=debug.traceback();return t end;local co=coroutine.create(function()return f()end);local ok,t=coroutine.resume(co);assert(ok);assert(t:find('\n\t(...tail calls...)',1,true))
end

-- Negative_Level
do
  assert(debug.traceback(nil,-1)=='stack traceback:');assert(debug.traceback('hi',-9)=='hi\nstack traceback:')
end

-- Level_Zero
do
  local t=debug.traceback(nil,0);assert(t:find("[C]: in field 'traceback'",1,true));assert(not t:find("'debug.traceback'",1,true))
end

-- Stripped_Location
do
  local f=assert(load(string.dump(function()coroutine.yield()end,true)));local co=coroutine.create(f);assert(coroutine.resume(co));local t=debug.traceback(co);assert(t:match('\n\t%?: in function <%?:%d+>'));assert(not t:find('?:0:',1,true))
end

-- Deep_Stack
do
  local function f(n)if n==0 then local t=debug.traceback();return t else return(f(n-1))end end;local co=coroutine.create(f);local ok,t=coroutine.resume(co,30);assert(ok);local _,n=t:gsub('\n','');assert(n==22);assert(t:find('\n\t...\t(skipping 9 levels)',1,true))
end

-- Short_Stack_Boundary
do
  local function f(n)if n==0 then local t=debug.traceback();return t else return(f(n-1))end end;local co=coroutine.create(f);local ok,t=coroutine.resume(co,21);assert(ok);local _,n=t:gsub('\n','');assert(n==22 and not t:find('skipping',1,true));co=coroutine.create(f);ok,t=coroutine.resume(co,22);assert(ok);local _,n=t:gsub('\n','');assert(n==22 and t:find('(skipping 1 levels)',1,true))
end

-- Unknown_Native
do
  local p=pcall;_G.pcall=nil;local ok,t=(function()return p end)()(debug.traceback);_G.pcall=p;assert(ok);assert(t:find('\n\t[C]: in ?',1,true))
end

-- Hook_Tail_Fallback
do
  local n=0;local function capture()local i=debug.getinfo(1,'nt');assert(i.istailcall and i.namewhat=='' and i.name==nil);n=n+1 end;local co=coroutine.create(function()local x=1 end);debug.sethook(co,function()return capture()end,'l');assert(coroutine.resume(co));assert(n>0)
end

-- Hook_Descendant_Name
do
  local n=0;local function child()local i=debug.getinfo(1,'n');assert(i.namewhat=='upvalue' and i.name=='child');n=n+1 end;local co=coroutine.create(function()local x=1 end);debug.sethook(co,function()child()end,'l');assert(coroutine.resume(co));assert(n>0)
end

print('debug traceback phases OK')
