local seen=0;local function inspect(expected,result)return function(...)local i=debug.getinfo(1,'n');assert(i.namewhat=='metamethod' and i.name==expected);seen=seen+1;return result end end;

-- Index_Field
do
  seen=0
  local t=setmetatable({},{__index=inspect('index',7)});assert(t.x==7 and seen==1)
end

-- Index_Integer
do
  seen=0
  local t=setmetatable({},{__index=inspect('index',7)});assert(t[1]==7 and seen==1)
end

-- Index_Register
do
  seen=0
  local t=setmetatable({},{__index=inspect('index',7)});local k='x';assert(t[k]==7 and seen==1)
end

-- Index_Environment
do
  seen=0
  local env=setmetatable({},{__index=inspect('index',7)});local function make()local _ENV=env;return function()return missing end end;assert(make()()==7 and seen==1)
end

-- Newindex_Field
do
  seen=0
  local t=setmetatable({},{__newindex=inspect('newindex')});t.x=7;assert(seen==1)
end

-- Newindex_Integer
do
  seen=0
  local t=setmetatable({},{__newindex=inspect('newindex')});t[1]=7;assert(seen==1)
end

-- Newindex_Register
do
  seen=0
  local t=setmetatable({},{__newindex=inspect('newindex')});local k='x';t[k]=7;assert(seen==1)
end

-- Newindex_Environment
do
  seen=0
  local env=setmetatable({},{__newindex=inspect('newindex')});local function make()local _ENV=env;return function()missing=7 end end;make()();assert(seen==1)
end

-- Add_Registers
do
  seen=0
  local a=setmetatable({},{__add=inspect('add',7)});local b={};assert(a+b==7 and seen==1)
end

-- Add_Immediate
do
  seen=0
  local a=setmetatable({},{__add=inspect('add',7)});assert(a+1==7 and seen==1)
end

-- Add_Constant
do
  seen=0
  local a=setmetatable({},{__add=inspect('add',7)});assert(a+5.5==7 and seen==1)
end

-- Subtract
do
  seen=0
  local a=setmetatable({},{__sub=inspect('sub',7)});assert(a - 1==7 and seen==1)
end

-- Multiply
do
  seen=0
  local a=setmetatable({},{__mul=inspect('mul',7)});assert(a * 1==7 and seen==1)
end

-- Modulo
do
  seen=0
  local a=setmetatable({},{__mod=inspect('mod',7)});assert(a % 1==7 and seen==1)
end

-- Power
do
  seen=0
  local a=setmetatable({},{__pow=inspect('pow',7)});assert(a ^ 1==7 and seen==1)
end

-- Divide
do
  seen=0
  local a=setmetatable({},{__div=inspect('div',7)});assert(a / 1==7 and seen==1)
end

-- Floor_Divide
do
  seen=0
  local a=setmetatable({},{__idiv=inspect('idiv',7)});assert(a // 1==7 and seen==1)
end

-- Bit_And
do
  seen=0
  local a=setmetatable({},{__band=inspect('band',7)});assert(a & 1==7 and seen==1)
end

-- Bit_Or
do
  seen=0
  local a=setmetatable({},{__bor=inspect('bor',7)});assert(a | 1==7 and seen==1)
end

-- Bit_Xor
do
  seen=0
  local a=setmetatable({},{__bxor=inspect('bxor',7)});assert(a ~ 1==7 and seen==1)
end

-- Shift_Left
do
  seen=0
  local a=setmetatable({},{__shl=inspect('shl',7)});assert(a << 1==7 and seen==1)
end

-- Shift_Right
do
  seen=0
  local a=setmetatable({},{__shr=inspect('shr',7)});assert(a >> 1==7 and seen==1)
end

-- Unary_Minus
do
  seen=0
  local a=setmetatable({},{__unm=inspect('unm',7)});assert(-a==7 and seen==1)
end

-- Bit_Not
do
  seen=0
  local a=setmetatable({},{__bnot=inspect('bnot',7)});assert(~a==7 and seen==1)
end

-- Length
do
  seen=0
  local a=setmetatable({},{__len=inspect('len',7)});assert(#a==7 and seen==1)
end

-- Concatenate
do
  seen=0
  local a=setmetatable({},{__concat=inspect('concat',7)});assert(a..a==7 and seen==1)
end

-- Equal
do
  seen=0
  local mt={__eq=inspect('eq',true)};local a,b=setmetatable({},mt),setmetatable({},mt);assert(a==b and seen==1)
end

-- Less
do
  seen=0
  local mt={__lt=inspect('lt',true)};local a,b=setmetatable({},mt),setmetatable({},mt);assert(a<b and seen==1)
end

-- Less_Equal
do
  seen=0
  local mt={__le=inspect('le',true)};local a,b=setmetatable({},mt),setmetatable({},mt);assert(a<=b and seen==1)
end

-- Less_Immediate
do
  seen=0
  local a=setmetatable({},{__lt=inspect('lt',true)});assert(a<1 and seen==1)
end

-- Greater_Immediate
do
  seen=0
  local a=setmetatable({},{__lt=inspect('lt',true)});assert(1<a and seen==1)
end

-- Less_Equal_Immediate
do
  seen=0
  local a=setmetatable({},{__le=inspect('le',true)});assert(a<=1 and seen==1)
end

-- Greater_Equal_Immediate
do
  seen=0
  local a=setmetatable({},{__le=inspect('le',true)});assert(1<=a and seen==1)
end

-- Close_Scope
do
  seen=0
  do local x <close> =setmetatable({},{__close=inspect('close')})end;assert(seen==1)
end

-- Close_Return
do
  seen=0
  local function f()local x <close> =setmetatable({},{__close=inspect('close')});return 7 end;assert(f()==7 and seen==1)
end

-- Close_Error
do
  seen=0
  local got;local function f()local x <close> =setmetatable({},{__close=function()got=debug.getinfo(1,'n')end});error('boom')end;assert(not pcall(f));assert(got.namewhat=='' and got.name==nil)
end

-- Close_Coroutine
do
  seen=0
  local got;local co=coroutine.create(function()local x <close> =setmetatable({},{__close=function()got=debug.getinfo(1,'n')end});coroutine.yield()end);assert(coroutine.resume(co));assert(coroutine.close(co));assert(got.namewhat=='' and got.name==nil)
end

-- Close_Tail_Replacement
do
  seen=0
  local got;local function child()got=debug.getinfo(1,'nt')end;do local x <close> =setmetatable({},{__close=function()return child()end})end;assert(got.istailcall and got.namewhat=='' and got.name==nil)
end

-- Close_Descendant
do
  seen=0
  local got;local function child()got=debug.getinfo(1,'n')end;do local x <close> =setmetatable({},{__close=function()child()end})end;assert(got.namewhat=='upvalue' and got.name=='child')
end

-- Close_Traceback
do
  seen=0
  local function f(...)local x <close> =setmetatable({},{__close=function()error('@x123')end})end;local ok,msg=xpcall(f,debug.traceback);assert(not ok and msg:find("in metamethod 'close'",1,true))
end

-- Finalizer_Origin
do
  seen=0
  local got;setmetatable({},{__gc=function()got=debug.getinfo(1,'n')end});collectgarbage();assert(got and got.namewhat=='metamethod' and got.name=='__gc')
end

-- Finalizer_Descendant
do
  seen=0
  local got;local function child()got=debug.getinfo(1,'n')end;setmetatable({},{__gc=function()child()end});collectgarbage();assert(got and got.namewhat=='upvalue' and got.name=='child')
end

-- Finalizer_Tail_Replacement
do
  seen=0
  local got;local function child()got=debug.getinfo(1,'nt')end;setmetatable({},{__gc=function()return child()end});collectgarbage();assert(got and got.istailcall and got.namewhat=='' and got.name==nil)
end

-- Finalizer_Cache_Reset
do
  seen=0
  local got;setmetatable({},{__gc=function()got=debug.getinfo(1,'n')end});collectgarbage();assert(got and got.name=='__gc');local function f()local i=debug.getinfo(1,'n');assert(i.namewhat=='local' and i.name=='f')end;for i=1,5 do f()end
end

print('metamethod name phases OK')
