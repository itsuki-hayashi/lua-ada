assert(T and T.alloccount and T.totalmem)
local function deep(n)if n>0 then deep(n-1)end end
local code='pcall 0 1 0;pushstatus;return 2'
local function check_zero(bytes)
  local function sel(n,...arg)return arg[n]+arg.n end
  local function f()return sel(2.0,20,30)end
  collectgarbage();collectgarbage();deep(4)
  if bytes then T.totalmem(T.totalmem())else T.alloccount(0)end
  local a,b=T.testC(code,f)
  T.alloccount();T.totalmem(0)
  assert(a==32 and b=='OK')
end
local cases={
  {'Optimized_Vararg_Count',function()check_zero(false)end},
  {'Optimized_Vararg_Bytes',function()check_zero(true)end},
  {'Tail_Tuple',function()
    local marker={}
    local function leaf(a,b,c,d)return a,b,c,d end
    local function relay(a,b,c,d)return leaf(a,b,c,d)end
    deep(4);T.alloccount(0)
    local a,b,c,d=relay(37,nil,marker,nil)
    T.alloccount()
    assert(a==37 and b==nil and c==marker and d==nil)
  end},
  {'Tail_Chain',function()
    local marker={}
    local function relay(n,a,b,c)
      if n==0 then return a,b,c end
      return relay(n-1,a,b,c)
    end
    deep(4);T.alloccount(0)
    local a,b,c=relay(32,37,nil,marker)
    T.alloccount()
    assert(a==37 and b==nil and c==marker)
  end},
  {'Tail_Weak_Argument',function()
    local weak=setmetatable({},{__mode='v'})
    local function leaf(keep)
      collectgarbage();collectgarbage();assert(weak[1]==nil);return keep
    end
    local function relay(keep,old)return leaf(keep)end
    local function start()
      local old={};weak[1]=old;return relay(37,old)
    end
    assert(start()==37)
  end},
  {'Tail_Hook_Mutation',function()
    local hits=0
    local function leaf(a)return a end
    local function relay(a)return leaf(a)end
    debug.sethook(function(event)
      if event=='tail call' and debug.getinfo(2,'f').func==leaf then
        hits=hits+1;debug.sethook();assert(debug.setlocal(2,1,42))
        collectgarbage()
      end
    end,'c')
    local value=relay(11)
    debug.sethook();assert(value==42 and hits==1)
  end},
  {'Tail_Hook_Error',function()
    local marker={}
    local function leaf(a)return a end
    local function relay(a)return leaf(a)end
    debug.sethook(function(event)
      if event=='tail call' and debug.getinfo(2,'f').func==leaf then
        debug.sethook();collectgarbage();error(marker,0)
      end
    end,'c')
    local ok,e=pcall(relay,37)
    debug.sethook();assert(not ok and e==marker)
    assert(relay(41)==41)
  end},
  {'Tail_Yield',function()
    local function leaf(a,b)
      local value=coroutine.yield(a);return value,b
    end
    local function relay(a,b)return leaf(a,b)end
    local co=coroutine.create(function()return relay(37,nil)end)
    local ok,a=coroutine.resume(co);assert(ok and a==37)
    local r=table.pack(coroutine.resume(co,41))
    assert(r.n==3 and r[1] and r[2]==41 and r[3]==nil)
    assert(coroutine.status(co)=='dead')
  end},
  {'Tail_Close_Error',function()
    local marker,closed={},false
    local function leaf(e)error(e,0)end
    local function relay(e)return leaf(e)end
    local function outer()
      local x <close> = setmetatable({},{__close=function(self,e)
        assert(e==marker);collectgarbage();closed=true
      end})
      return relay(marker)
    end
    local ok,e=pcall(outer)
    assert(not ok and e==marker and closed)
  end},
  {'Tail_Refusal_Recovery',function()
    local names={}
    for i=1,150 do names[i]='v'..i end
    local large=assert(load('return function(payload)local '..
      table.concat(names,',')..';return payload end'))()
    local marker={value=37}
    local function relay(payload)return large(payload)end
    local function f()return relay(marker)end
    deep(4);T.alloccount(0)
    local a,b=T.testC(code,f)
    T.alloccount()
    -- Existing physical capacity can suffice. Otherwise the actual
    -- protected call must report its memory failure and recover cleanly.
    if b=='not enough memory' then assert(a=='not enough memory')
    else assert(b=='OK' and a==marker)end
    assert(f()==marker and marker.value==37)
  end},
}
for _,case in ipairs(cases)do
  if _TAIL_OWNERSHIP_CASE==nil or _TAIL_OWNERSHIP_CASE==case[1]then
    case[2]();print('PASS tail ownership '..case[1])
  end
end
