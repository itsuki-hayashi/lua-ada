-- Empty_Removal_Creates_Map
do
  assert(debug.getregistry()._HOOKKEY==nil);debug.sethook();local t=debug.getregistry()._HOOKKEY;assert(type(t)=='table' and getmetatable(t)==t and t.__mode=='k')
end

-- Thread_Mapping
do
  local co=coroutine.create(function()end);local h=function()end;debug.sethook(co,h,'l');local t=debug.getregistry()._HOOKKEY;assert(t[co]==h and debug.gethook(co)==h);debug.sethook(co);assert(t[co]==nil and select('#',debug.gethook(co))==1)
end

-- Replace_Callback
do
  local n=0;local co=coroutine.create(function()local x=1 end);local old=function()error('stale hook')end;local new=function()n=n+1 end;debug.sethook(co,old,'l');debug.getregistry()._HOOKKEY[co]=new;assert(debug.gethook(co)==new);assert(coroutine.resume(co));assert(n>0)
end

-- Remove_Callback_Entry
do
  local co=coroutine.create(function()local x=1 end);debug.sethook(co,function()error('removed hook')end,'l',3);debug.getregistry()._HOOKKEY[co]=nil;local t=table.pack(debug.gethook(co));assert(t.n==3 and t[1]==nil and t[2]=='l' and t[3]==3);assert(coroutine.resume(co))
end

-- Nonfunction_Callback
do
  local co=coroutine.create(function()local x=1 end);debug.sethook(co,function()end,'l');local value=setmetatable({},{__call=function()error('called table')end});debug.getregistry()._HOOKKEY[co]=value;local t=table.pack(debug.gethook(co));assert(t.n==3 and t[1]==value and t[2]=='l');assert(coroutine.resume(co))
end

-- Disabled_Callback_Retention
do
  local co=coroutine.create(function()end);local h=function()end;debug.sethook(co,h,'');assert(debug.getregistry()._HOOKKEY[co]==h);local t=table.pack(debug.gethook(co));assert(t.n==1 and t[1]==nil)
end

-- Replaced_Closure_Collection
do
  local weak=setmetatable({},{__mode='v'});local co=coroutine.create(function()end);do local old=function()end;weak[1]=old;debug.sethook(co,old,'l')end;local new=function()end;debug.getregistry()._HOOKKEY[co]=new;collectgarbage();collectgarbage();assert(weak[1]==nil and debug.gethook(co)==new)
end

-- Thread_Callback_Ephemeron
do
  local weak=setmetatable({},{__mode='v'});do local co=coroutine.create(function()end);local h=(function(t)return function()return t end end)(co);weak[1]=co;weak[2]=h;debug.sethook(co,h,'l')end;collectgarbage();collectgarbage();assert(weak[1]==nil and weak[2]==nil)
end

-- Active_Callback_Root
do
  local weak=setmetatable({},{__mode='v'});local n=0;local co=coroutine.create(assert(load('local x=1\nx=2\nx=3')));local next=function()n=n+1 end;do local h=function()debug.getregistry()._HOOKKEY[coroutine.running()]=next;collectgarbage();assert(weak[1]~=nil)end;weak[1]=h;debug.sethook(co,h,'l')end;assert(coroutine.resume(co));collectgarbage();collectgarbage();assert(n>0 and weak[1]==nil)
end

-- Inherited_Controls
do
  local h=function()end;debug.sethook(h,'c',7);local co=coroutine.create(function()local x=1 end);debug.sethook();local t=table.pack(debug.gethook(co));assert(t.n==3 and t[1]==nil and t[2]=='c' and t[3]==7);assert(debug.getregistry()._HOOKKEY[co]==nil);assert(coroutine.resume(co))
end

-- Inherited_Callback_Entry
do
  local n=0;debug.sethook(function()end,'l');local co=coroutine.create(assert(load('local x=1\nx=2')));debug.sethook();debug.getregistry()._HOOKKEY[co]=function()n=n+1 end;assert(coroutine.resume(co));assert(n>0)
end

-- Invalid_Replacement_Preserves
do
  local co=coroutine.create(function()end);local h=function()end;debug.sethook(co,h,'cr',5);assert(not pcall(debug.sethook,co,{},'l'));local f,m,c=debug.gethook(co);assert(f==h and m=='cr' and c==5);assert(debug.getregistry()._HOOKKEY[co]==h)
end

-- Independent_Thread_Entries
do
  local a=coroutine.create(function()end);local b=coroutine.create(function()end);local x,y,z=function()end,function()end,function()end;debug.sethook(a,x,'l');debug.sethook(b,y,'c');debug.getregistry()._HOOKKEY[a]=z;assert(debug.gethook(a)==z and debug.gethook(b)==y)
end

print('hook registry phases OK')
