-- Authored setup retained from native-paired CLI argument diagnostics.
-- Setup returns before the CLI-only child loads its selected script.
local case = ...
if case == "unchanged-strings" then
  case_name="unchanged-strings";;check_dynamic_arg=function(v) assert(v.n==3 and v[1]=='a' and v[2]=='b' and v[3]=='c') end
elseif case == "numeric-slot" then
  case_name="numeric-slot";arg[1]=100;check_dynamic_arg=function(v) assert(v.n==3 and type(v[1])=='number' and math.type(v[1])=='integer' and v[1]==100 and v[2]=='b' and v[3]=='c') end
elseif case == "boolean-slot" then
  case_name="boolean-slot";arg[2]=false;check_dynamic_arg=function(v) assert(v.n==3 and v[1]=='a' and v[2]==false and v[3]=='c') end
elseif case == "replace-table" then
  case_name="replace-table";arg={11,true,"text"};check_dynamic_arg=function(v) assert(v.n==3 and v[1]==11 and v[2]==true and v[3]=='text') end
elseif case == "replace-empty" then
  case_name="replace-empty";arg={};check_dynamic_arg=function(v) assert(v.n==0) end
elseif case == "mixed-object-identity" then
  case_name="mixed-object-identity";want={};fn=function()end;co=coroutine.create(function()end);u=io.stdout;arg={want,fn,co,u};check_dynamic_arg=function(v) assert(v.n==4 and v[1]==want and v[2]==fn and v[3]==co and v[4]==u);assert(type(v[1])=='table' and type(v[2])=='function' and type(v[3])=='thread' and type(v[4])=='userdata') end
elseif case == "metalen-holes" then
  case_name="metalen-holes";len_calls=0;arg=setmetatable({[1]="left",[3]="right"},{__len=function(self) len_calls=len_calls+1;return 4 end});check_dynamic_arg=function(v) assert(len_calls==1 and v.n==4 and v[1]=='left' and v[2]==nil and v[3]=='right' and v[4]==nil) end
elseif case == "raw-indexing" then
  case_name="raw-indexing";index_calls=0;arg=setmetatable({[1]="first"},{__len=function()return 3 end,__index=function()index_calls=index_calls+1;error("ARG INDEX RAN",0)end});check_dynamic_arg=function(v) assert(index_calls==0 and v.n==3 and v[1]=='first' and v[2]==nil and v[3]==nil) end
elseif case == "metalen-number-string" then
  case_name="metalen-number-string";len_calls=0;arg=setmetatable({7,8},{__len=function()len_calls=len_calls+1;return "2" end});check_dynamic_arg=function(v) assert(len_calls==1 and v.n==2 and v[1]==7 and v[2]==8) end
elseif case == "metalen-float-integer" then
  case_name="metalen-float-integer";len_calls=0;arg=setmetatable({7,8},{__len=function()len_calls=len_calls+1;return 2.0 end});check_dynamic_arg=function(v) assert(len_calls==1 and v.n==2 and v[1]==7 and v[2]==8) end
elseif case == "metalen-mutates-values" then
  case_name="metalen-mutates-values";len_calls=0;arg=setmetatable({1,2},{__len=function(self)len_calls=len_calls+1;self[1]=17;self[2]=false;return 2 end});check_dynamic_arg=function(v) assert(len_calls==1 and v.n==2 and v[1]==17 and v[2]==false) end
elseif case == "metalen-replaces-global-gc" then
  case_name="metalen-replaces-global-gc";len_calls=0;local t={};t[1]=t;weak=setmetatable({t},{__mode="v"});setmetatable(t,{__len=function(self)len_calls=len_calls+1;arg={99};collectgarbage();assert(weak[1]==self);self[2]=false;return 3 end});arg=t;t=nil;check_dynamic_arg=function(v) assert(len_calls==1 and v.n==3 and v[1]==weak[1] and type(v[1])=='table' and v[2]==false and v[3]==nil);assert(arg[1]==99);collectgarbage();assert(weak[1]==v[1]) end
elseif case == "global-handler" then
  case_name="global-handler";arg=nil;arg_hits=0;setmetatable(_G,{__index=function(_,key)if key=="arg" then arg_hits=arg_hits+1;return {41,false}end end});check_dynamic_arg=function(v) assert(arg_hits==1 and v.n==2 and v[1]==41 and v[2]==false) end
elseif case == "non-table-number" then
  case_name="non-table-number";arg=1;check_dynamic_arg=function(v) error('SCRIPT INCORRECTLY ENTERED',0) end
elseif case == "non-table-nil" then
  case_name="non-table-nil";arg=nil;check_dynamic_arg=function(v) error('SCRIPT INCORRECTLY ENTERED',0) end
elseif case == "metalen-fraction" then
  case_name="metalen-fraction";arg=setmetatable({},{__len=function()return 2.5 end});check_dynamic_arg=function(v) error('SCRIPT INCORRECTLY ENTERED',0) end
elseif case == "metalen-table-result" then
  case_name="metalen-table-result";arg=setmetatable({},{__len=function()return {} end});check_dynamic_arg=function(v) error('SCRIPT INCORRECTLY ENTERED',0) end
elseif case == "metalen-error" then
  case_name="metalen-error";arg=setmetatable({},{__len=function()error("ARG LENGTH FAILURE",0)end});check_dynamic_arg=function(v) error('SCRIPT INCORRECTLY ENTERED',0) end
elseif case == "metalen-yield" then
  case_name="metalen-yield";arg=setmetatable({},{__len=function()coroutine.yield("BAD")end});check_dynamic_arg=function(v) error('SCRIPT INCORRECTLY ENTERED',0) end
elseif case == "arg-zero-does-not-retarget" then
  case_name="arg-zero-does-not-retarget";arg[0]="wrong-script.lua";check_dynamic_arg=function(v) assert(v.n==3 and v[1]=='a' and arg[0]=='wrong-script.lua');assert(debug.getinfo(2,'S').source=='@selected script.lua') end
elseif case == "negative-index-does-not-retarget" then
  case_name="negative-index-does-not-retarget";arg[-1]="wrong-script.lua";check_dynamic_arg=function(v) assert(v.n==3 and v[1]=='a' and arg[-1]=='wrong-script.lua');assert(debug.getinfo(2,'S').source=='@selected script.lua') end
elseif case == "length-real-c-frame" then
  case_name="length-real-c-frame";length_ran=false;arg=setmetatable({31,false},{__len=function(self)local d=debug.getinfo(2,'Sfn');assert(d.what=='C' and type(d.func)=='function' and d.namewhat=='');local found_code,found_self=false,false;local kinds={};for i=1,100 do local n,v=debug.getlocal(2,i);if not n then break end;kinds[#kinds+1]=type(v);if type(v)=='function' and debug.getinfo(v,'S').source=='@selected script.lua' then found_code=true end;if v==self then found_self=true end end;assert(found_code and found_self);io.write('FRAME length: C, compiled=',tostring(found_code),', original=',tostring(found_self),'; cells=',table.concat(kinds,','),'\n');length_ran=true;return 2 end});check_dynamic_arg=function(v) assert(length_ran and v.n==2 and v[1]==31 and v[2]==false) end
elseif case == "global-real-c-frame" then
  case_name="global-real-c-frame";lookup_ran=false;local original=_G;arg=nil;setmetatable(_G,{__index=function(self,key)assert(self==original and key=='arg');local d=debug.getinfo(2,'Sfn');assert(d.what=='C' and type(d.func)=='function' and d.namewhat=='');local found_code,found_self=false,false;local kinds={};for i=1,100 do local n,v=debug.getlocal(2,i);if not n then break end;kinds[#kinds+1]=type(v);if type(v)=='function' and debug.getinfo(v,'S').source=='@selected script.lua' then found_code=true end;if v==self then found_self=true end end;assert(found_code);io.write('FRAME global: C, compiled=',tostring(found_code),', original=',tostring(found_self),'; cells=',table.concat(kinds,','),'\n');lookup_ran=true;return {43,false}end});check_dynamic_arg=function(v) assert(lookup_ran and v.n==2 and v[1]==43 and v[2]==false) end
elseif case == "syntax-before-length" then
  case_name="syntax-before-length";arg=setmetatable({},{__len=function()io.write('LENGTH CALLBACK RAN\n');error('BAD LENGTH ORDER',0)end});check_dynamic_arg=function(v) error('SYNTAX SCRIPT ENTERED',0) end
elseif case == "missing-file-before-length" then
  case_name="missing-file-before-length";arg=setmetatable({},{__len=function()io.write('LENGTH CALLBACK RAN\n');error('BAD LENGTH ORDER',0)end});check_dynamic_arg=function(v) error('MISSING SCRIPT ENTERED',0) end
elseif case == "loaded-initial-environment" then
  case_name="loaded-initial-environment";local old=_G;environment_switched=false;arg=setmetatable({51,false},{__len=function(self)local r=debug.getregistry();r[2]=setmetatable({},{__index=function(_,k)error('WRONG NEW ENV '..k,0)end});environment_switched=true;collectgarbage();return 2 end});check_dynamic_arg=function(v) assert(environment_switched and _G==old and v.n==2 and v[1]==51 and v[2]==false) end
elseif case == "length-exit-close" then
  case_name="length-exit-close";arg=setmetatable({},{__len=function()local c <close> = setmetatable({},{__close=function()io.write('PASS: cli-dynamic-arg-length-exit-close\n')end});os.exit(37,true)end});check_dynamic_arg=function(v) error('EXIT CALLBACK WAS NOT CALLED',0) end
elseif case == "length-refusal-recovery" then
  case_name="length-refusal-recovery";assert(type(T)=='table','REAL T REQUIRED');local function deep(n)if n>0 then return 1+deep(n-1)end;return 0 end;assert(deep(8)==8);local function allocate()return{}end;assert(pcall(allocate));fault_seen=false;arg=setmetatable({71,false},{__len=function(self)T.alloccount(0);local ok,msg=pcall(allocate);T.alloccount();assert(not ok and msg=='not enough memory');fault_seen=true;collectgarbage();self[1]=72;return 2 end});check_dynamic_arg=function(v) assert(fault_seen and v.n==2 and v[1]==72 and v[2]==false);assert(type({})=='table') end
elseif case == "refused-script-entry" then
  case_name="refused-script-entry";assert(type(T)=='table','REAL T REQUIRED');local function deep(n)if n>0 then return 1+deep(n-1)end;return 0 end;assert(deep(8)==8);length_ran=false;arg=setmetatable({81,false},{__len=function(self)length_ran=true;T.alloccount(0);return 2 end});check_dynamic_arg=function(v) assert(length_ran and v.n==2 and v[1]==81 and v[2]==false);assert(type({})=='table') end
else error("unknown CLI argument case " .. tostring(case)) end
