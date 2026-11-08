-- Ordinary public tail controls retained from the provider campaign.
local cases={
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
}
for _,case in ipairs(cases)do
  case[2]();print('PASS tail public '..case[1])
end
print('Canonical tail public OK')
