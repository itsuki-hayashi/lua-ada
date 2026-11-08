-- Source-linked public semantics; private optimizer layouts stay separate.
local k0aux <const> = 0
local k0 <const> = k0aux
local k3 <const> = 3
local k6 <const> = k3 + (k3 << k0)
local kFF0 <const> = 0xFF0
local function one(f,wanted,kind)
  local result=table.pack(f())
  assert(result.n==1 and result[1]==wanted)
  assert(math.type(result[1])==kind)
end

-- F_Zero: checkF zero retains float kind.
do
  one(function()return 0.0 end,0.0,'float')
end

-- I_Captured_Zero: checkI propagated zero retains integer kind.
do
  one(function()return k0 end,0,'integer')
end

-- I_Zero_Floor: checkI unary zero and floor division.
do
  one(function()return -k0//1 end,0,'integer')
end

-- K_Reciprocal: checkK reciprocal retains float kind.
do
  one(function()return 3^-1 end,1/3,'float')
end

-- K_Power: checkK folded power keeps its exact value.
do
  one(function()return (1 + 1)^(50 + 50) end,2^100,'float')
end

-- K_Negative_Power: checkK negative integer base produces float.
do
  one(function()return (-2)^(31 - 2) end,-0x20000000 + 0.0,'float')
end

-- F_Floor: checkF propagated power and float floor division.
do
  one(function()return (-k3^0 + 5) // 3.0 end,1.0,'float')
end

-- I_Modulo: checkI negative integer modulo.
do
  one(function()return -k3 % 5 end,2,'integer')
end

-- F_Division: checkF nested power modulo and true division.
do
  one(function()return -((2.0^8 + -(-1)) % 8)/2 * 4 - 3 end,-5.0,'float')
end

-- F_Floor_Modulo: checkF power result preserves float floor kind.
do
  one(function()return -((2^8 + -(-1)) % 8)//2 * 4 - 3 end,-7.0,'float')
end

-- I_Bitwise_Mixed: checkI mixed float operands become integer bits.
do
  one(function()return 0xF0.0 | 0xCC.0 ~ 0xAA & 0xFD end,0xF4,'integer')
end

-- I_Bitwise_Not: checkI propagated bitwise constants.
do
  one(function()return ~(~kFF0 | kFF0) end,0,'integer')
end

-- I_Bitwise_Float: checkI integral float double complement.
do
  one(function()return ~~-1024.0 end,-1024,'integer')
end

-- I_Shifts: checkI constant shifts with a negative displacement.
do
  one(function()return ((100 << k6) << -4) >> 2 end,100,'integer')
end

-- Integer_Borders: Every integer immediate boundary keeps one integer result.
do
  local a=17;local sbx=((1 << a)-1) >> 1
  local border <const> = 65535
  one(function()return border end,sbx,'integer')
  one(function()return -border end,-sbx,'integer')
  one(function()return border+1 end,sbx+1,'integer')
  one(function()return border+2 end,sbx+2,'integer')
  one(function()return -(border+1)end,-(sbx+1),'integer')
end

-- Float_Borders: Integral float immediates keep their float result kind.
do
  local a=17;local sbx=((1 << a)-1) >> 1
  local border <const> = 65535.0
  one(function()return border end,sbx+0.0,'float')
  one(function()return -border end,-sbx+0.0,'float')
  one(function()return border+1 end,sbx+1.0,'float')
  one(function()return border+2 end,sbx+2.0,'float')
  one(function()return -(border+1)end,-(sbx+1.0),'float')
end

-- Maximum_Integer: Generated hexadecimal return survives a binary round trip.
do
  local n=math.maxinteger
  local source=string.format(
    "local a = {[true] = 0X%x}; return a[true]",n)
  local f=assert(load(source))
  one(f,n,'integer')
  f=assert(load(string.dump(f)))
  one(f,n,'integer')
end

-- Minimum_Integer: Generated hexadecimal return survives a binary round trip.
do
  local n=math.mininteger
  local source=string.format(
    "local a = {[true] = 0X%x}; return a[true]",n)
  local f=assert(load(source))
  one(f,n,'integer')
  f=assert(load(string.dump(f)))
  one(f,n,'integer')
end

-- Negative_Hex: Generated hexadecimal return survives a binary round trip.
do
  local n=-1
  local source=string.format(
    "local a = {[true] = 0X%x}; return a[true]",n)
  local f=assert(load(source))
  one(f,n,'integer')
  f=assert(load(string.dump(f)))
  one(f,n,'integer')
end

-- Nested_Constants: Nested constant functions retain values and return arity.
do
  local k0 <const> = "00000000000000000000000000000000000000000000000000"
  local function f1()
    local k <const> = k0
    return function()
      return function()return k end
    end
  end
  local result=table.pack(f1())
  assert(result.n==1 and type(result[1])=='function')
  local f2=result[1]
  result=table.pack(f2())
  assert(result.n==1 and type(result[1])=='function')
  local f3=result[1]
  one(f3,k0,nil)
  for _,f in ipairs({f1,f2,f3})do
    for _,strip in ipairs({false,true})do
      local loaded=assert(load(string.dump(f,strip)))
      local returned=table.pack(loaded())
      assert(returned.n==1)
      if f==f1 then
        returned=table.pack(returned[1]())
        assert(returned.n==1 and type(returned[1])=='function')
        one(returned[1],k0,nil)
      elseif f==f2 then
        assert(type(returned[1])=='function')
        one(returned[1],k0,nil)
      else assert(returned[1]==k0 and type(returned[1])=='string')end
    end
  end
end

-- Callback_Sequence: The original eight callback arguments retain value and kind.
do
  local foo = function(f,a)
    f(100 * 1000)
    f(100.0 * 1000)
    f(-100 * 1000)
    f(-100 * 1000.0)
    f(100000)
    f(100000.0)
    f(-100000)
    f(-100000.0)
  end
  local seen={}
  local result=table.pack(foo(function(...)
    local arguments=table.pack(...)
    assert(arguments.n==1)
    seen[#seen+1]={arguments[1],math.type(arguments[1])}
  end))
  assert(result.n==0 and #seen==8)
  local values={100000,100000,-100000,-100000,100000,100000,-100000,-100000}
  for i=1,8 do
    assert(seen[i][1]==values[i])
    assert(seen[i][2]==(i%2==1 and 'integer'or'float'))
  end
end

-- Assignment_Sequence: Every repeated absent-key assignment reaches its recorder.
do
  local foo = function(t,a)
    t[a] = 1; t[a] = 1.0
    t[a] = 1; t[a] = 1.0
    t[a] = 2; t[a] = 2.0
    t[a] = 0; t[a] = 0.0
    t[a] = 1; t[a] = 1.0
    t[a] = 2; t[a] = 2.0
    t[a] = 0; t[a] = 0.0
  end
  local seen={};local key={};local proxy
  proxy=setmetatable({},{__newindex=function(...)
    local args=table.pack(...)
    assert(args.n==3 and args[1]==proxy and args[2]==key)
    seen[#seen+1]={args[3],math.type(args[3])}
  end})
  assert(select('#',foo(proxy,key))==0 and #seen==14 and next(proxy)==nil)
  local values={1,1,1,1,2,2,0,0,1,1,2,2,0,0}
  for i=1,14 do
    assert(seen[i][1]==values[i])
    assert(seen[i][2]==(i%2==1 and 'integer'or'float'))
  end
end

-- Constructor_49: Constructor boundary values and final vararg expansion.
do
  local n=49
  local ordinary="local a; return {"..string.rep("a, ",n).."}"
  local empty=table.pack(assert(load(ordinary))())
  assert(empty.n==1 and type(empty[1])=='table'and next(empty[1])==nil)
  local source="return function(...) return {"..string.rep("11,",n-1).."...} end"
  local f=assert(load(source))()
  for _,args in ipairs({table.pack(),table.pack(23),table.pack(23,nil,41.0)})do
    local returned=table.pack(f(table.unpack(args,1,args.n)))
    assert(returned.n==1 and type(returned[1])=='table')
    local t=returned[1];local count=0
    for i=1,n-1 do assert(t[i]==11 and math.type(t[i])=='integer')end
    if args.n==0 then assert(t[n]==nil and t[n+2]==nil)
    elseif args.n==1 then
      assert(t[n]==23 and math.type(t[n])=='integer'and t[n+2]==nil)
    else
      assert(t[n]==23 and math.type(t[n])=='integer')
      assert(t[n+2]==41 and math.type(t[n+2])=='float')
    end
    for k,v in pairs(t)do
      count=count+1;assert(math.type(k)=='integer'and k>=1)
      if k<n then assert(v==11 and math.type(v)=='integer')
      elseif k==n then assert(v==23 and math.type(v)=='integer')
      else assert(k==n+2 and v==41 and math.type(v)=='float')end
    end
    assert(count==n-1+(args.n==3 and 2 or args.n))
    assert(t[n+1]==nil and t[n+3]==nil)
  end
end

-- Constructor_50: Constructor boundary values and final vararg expansion.
do
  local n=50
  local ordinary="local a; return {"..string.rep("a, ",n).."}"
  local empty=table.pack(assert(load(ordinary))())
  assert(empty.n==1 and type(empty[1])=='table'and next(empty[1])==nil)
  local source="return function(...) return {"..string.rep("11,",n-1).."...} end"
  local f=assert(load(source))()
  for _,args in ipairs({table.pack(),table.pack(23),table.pack(23,nil,41.0)})do
    local returned=table.pack(f(table.unpack(args,1,args.n)))
    assert(returned.n==1 and type(returned[1])=='table')
    local t=returned[1];local count=0
    for i=1,n-1 do assert(t[i]==11 and math.type(t[i])=='integer')end
    if args.n==0 then assert(t[n]==nil and t[n+2]==nil)
    elseif args.n==1 then
      assert(t[n]==23 and math.type(t[n])=='integer'and t[n+2]==nil)
    else
      assert(t[n]==23 and math.type(t[n])=='integer')
      assert(t[n+2]==41 and math.type(t[n+2])=='float')
    end
    for k,v in pairs(t)do
      count=count+1;assert(math.type(k)=='integer'and k>=1)
      if k<n then assert(v==11 and math.type(v)=='integer')
      elseif k==n then assert(v==23 and math.type(v)=='integer')
      else assert(k==n+2 and v==41 and math.type(v)=='float')end
    end
    assert(count==n-1+(args.n==3 and 2 or args.n))
    assert(t[n+1]==nil and t[n+3]==nil)
  end
end

-- Constructor_51: Constructor boundary values and final vararg expansion.
do
  local n=51
  local ordinary="local a; return {"..string.rep("a, ",n).."}"
  local empty=table.pack(assert(load(ordinary))())
  assert(empty.n==1 and type(empty[1])=='table'and next(empty[1])==nil)
  local source="return function(...) return {"..string.rep("11,",n-1).."...} end"
  local f=assert(load(source))()
  for _,args in ipairs({table.pack(),table.pack(23),table.pack(23,nil,41.0)})do
    local returned=table.pack(f(table.unpack(args,1,args.n)))
    assert(returned.n==1 and type(returned[1])=='table')
    local t=returned[1];local count=0
    for i=1,n-1 do assert(t[i]==11 and math.type(t[i])=='integer')end
    if args.n==0 then assert(t[n]==nil and t[n+2]==nil)
    elseif args.n==1 then
      assert(t[n]==23 and math.type(t[n])=='integer'and t[n+2]==nil)
    else
      assert(t[n]==23 and math.type(t[n])=='integer')
      assert(t[n+2]==41 and math.type(t[n+2])=='float')
    end
    for k,v in pairs(t)do
      count=count+1;assert(math.type(k)=='integer'and k>=1)
      if k<n then assert(v==11 and math.type(v)=='integer')
      elseif k==n then assert(v==23 and math.type(v)=='integer')
      else assert(k==n+2 and v==41 and math.type(v)=='float')end
    end
    assert(count==n-1+(args.n==3 and 2 or args.n))
    assert(t[n+1]==nil and t[n+3]==nil)
  end
end

-- Return_Zero: A function with no explicit results returns zero values.
do
  local function f()local a=37 end
  assert(table.pack(f()).n==0)
  assert(table.pack(assert(load(string.dump(f)))()).n==0)
end

-- Return_One_Nil: One nil result remains distinct from no result after dump/load.
do
  local function f(a,b,c)return a end
  local result=table.pack(f(nil,37,41.0))
  assert(result.n==1 and result[1]==nil)
  result=table.pack(assert(load(string.dump(f)))(nil,37,41.0))
  assert(result.n==1 and result[1]==nil)
end

-- Return_Multiple: A final nil and float preserve exact result count and kinds.
do
  local function f()return 37,nil,41.0,nil end
  local result=table.pack(f())
  assert(result.n==4 and result[1]==37 and result[2]==nil)
  assert(math.type(result[1])=='integer'and result[3]==41)
  assert(math.type(result[3])=='float'and result[4]==nil)
  local loaded=table.pack(assert(load(string.dump(f)))())
  assert(loaded.n==4 and loaded[1]==37 and loaded[2]==nil)
  assert(math.type(loaded[1])=='integer'and loaded[3]==41)
  assert(math.type(loaded[3])=='float'and loaded[4]==nil)
end

-- Register_Load: Preserve valid and oversized load boundaries without invocation.
do
  local source="local a; return a("..string.rep("a, ",252).."a)"
  assert(type(assert(load(source)))=='function')
  source="local a; return a("..string.rep("a, ",253).."a)"
  local f,msg=load(source)
  assert(f==nil and string.find(msg,"too many registers"))
end

print('Code public semantics OK')
