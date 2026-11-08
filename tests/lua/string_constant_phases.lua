-- Large_Prefix_Count: Repeated earlier global keys retain the same live call shape.
do
  assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);assert(true);local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for i=1,1000 do end;assert(1000<a and a<1012);debug.sethook()
end

-- Exact_Byte_Values: String keys distinguish case and embedded NUL bytes.
do
  local a,b,c,d='key','Key','key\0x','key\0y';assert(a~=b and c~=d and #c==5 and #d==5);assert(select(1,'key','key')=='key')
end

-- Long_String_Values: Repeated long literals keep their bytes through collection.
do
  local function f()return 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMN','abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMN' end;local a,b=f();collectgarbage();assert(a==b and #a==50 and a:sub(-3)=='LMN')
end

-- Function_Local_Indexes: Children keep independent constant indexes and literal order.
do
  local root='root';local function a()return 'left','right','left' end;local function b()return 'right','left','right' end;local x,y,z=a();local p,q,r=b();assert(root=='root' and x=='left' and y=='right' and z=='left' and p=='right' and q=='left' and r=='right')
end

-- Exact_Index_Keys: Indexed field lookups preserve case and NUL identity.
do
  local seen={};local t=setmetatable({},{__index=function(_,k)seen[#seen+1]=k;return k end});assert(t.key=='key' and t.Key=='Key' and t['key\0x']=='key\0x' and t['key\0y']=='key\0y');assert(#seen==4 and seen[1]~=seen[2] and seen[3]~=seen[4])
end

-- Typed_Constants: String reuse cannot collapse integer and floating constants.
do
  local function f()return '1',1,1.0,'1' end;local a,b,c,d=f();assert(a==d and type(a)=='string' and math.type(b)=='integer' and math.type(c)=='float')
end

-- Source_Anchor_Retention: A retained child keeps source anchors after key-cache growth.
do
  local src=string.rep('assert(true)\n',300).."return function()return 'kept'end";local f=assert(load(src,'=cache-lines'))();collectgarbage();local i=debug.getinfo(f,'S');assert(i.source=='=cache-lines' and i.linedefined==301 and i.lastlinedefined==301 and f()=='kept')
end

print('string constant phases OK')
