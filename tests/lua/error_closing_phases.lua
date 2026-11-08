-- Pcall_Replacement_Yields: Resume each error closer through the real pcall continuation.
do
  local co=coroutine.wrap(function()
    return pcall(function()
      local outer <close> =setmetatable({},{__close=function(_,e)
        coroutine.yield('outer',e);error(e+20)
      end})
      local inner <close> =setmetatable({},{__close=function(_,e)
        coroutine.yield('inner',e);error(e+1)
      end})
      error(10)
    end)
  end)
  local a,b=co();assert(a=='inner' and b==10)
  a,b=co();assert(a=='outer' and b==11)
  a,b=co();assert(a==false and b==31)
end

-- Abandoned_Tostring_Barrier: A failed native tostring no longer owns a C body or caller.
do
  local co=coroutine.wrap(function()
    return pcall(function()
      return tostring(setmetatable({},{__tostring=function()
        local x <close> =setmetatable({},{__close=function(_,e)
          assert(debug.getinfo(2,'f').func==pcall)
          coroutine.yield('closed',e)
        end})
        error(17)
      end}))
    end)
  end)
  local a,b=co();assert(a=='closed' and b==17)
  a,b=co();assert(a==false and b==17)
end

-- Pre_TBC_Local_Root: The actual scalar prefix below a closing slot survives collection.
do
  local weak=setmetatable({},{__mode='v'})
  local co=coroutine.wrap(function()
    return pcall(function()
      local x={};weak[1]=x
      local c <close> =setmetatable({},{__close=function()
        collectgarbage();assert(weak[1]~=nil);coroutine.yield('alive')
      end})
      error(17)
    end)
  end)
  assert(co()=='alive');local a,b=co();assert(a==false and b==17)
  collectgarbage();assert(weak[1]==nil)
end

-- Post_TBC_Temporary_Release: Error closing discards abandoned locals above its selected slot.
do
  local weak=setmetatable({},{__mode='v'})
  local co=coroutine.wrap(function()
    return pcall(function()
      local c <close> =setmetatable({},{__close=function()
        collectgarbage();assert(weak[1]==nil);coroutine.yield('gone')
      end})
      local x={};weak[1]=x;error(17)
    end)
  end)
  assert(co()=='gone');local a,b=co();assert(a==false and b==17)
end

-- Failed_Return_Result_Release: A failed close abandons the old return packet before outer GC.
do
  local weak=setmetatable({},{__mode='v'})
  local co=coroutine.wrap(function()
    return pcall(function()
      local outer <close> =setmetatable({},{__close=function(_,e)
        assert(e==17);collectgarbage();assert(weak[1]==nil)
        coroutine.yield('gone')
      end})
      local inner <close> =setmetatable({},{__close=function()error(17)end})
      local function result()local x={};weak[1]=x;return x end
      return result()
    end)
  end)
  assert(co()=='gone');local a,b=co();assert(a==false and b==17)
end

-- Nested_Closing_Floor: Inner protected closing retains the active outer closer's real prefix.
do
  local weak=setmetatable({},{__mode='v'})
  local co=coroutine.wrap(function()
    return pcall(function()
      local x={};weak[1]=x
      local outer <close> =setmetatable({},{__close=function()
        local a,b=pcall(function()
          local y={};weak[2]=y
          local inner <close> =setmetatable({},{__close=function()
            collectgarbage();assert(weak[1] and weak[2])
            coroutine.yield('inner')
          end})
          error(23)
        end)
        assert(a==false and b==23);collectgarbage()
        assert(weak[1] and weak[2]==nil);coroutine.yield('outer')
      end})
      error(17)
    end)
  end)
  assert(co()=='inner');assert(co()=='outer')
  local a,b=co();assert(a==false and b==17)
  collectgarbage();assert(weak[1]==nil and weak[2]==nil)
end

-- False_Normal_Close_Result: A normal closer's false result is discarded before return.
do
  local co=coroutine.wrap(function()
    return pcall(function()
      local c <close> =setmetatable({},{__close=function()
        coroutine.yield('closed');return false,99
      end})
      return 7
    end)
  end)
  assert(co()=='closed');local a,b=co();assert(a==true and b==7)
end

-- False_Error_Close_Result: A successful error closer cannot replace the error with its results.
do
  local co=coroutine.wrap(function()
    return pcall(function()
      local c <close> =setmetatable({},{__close=function(_,e)
        assert(e==17);coroutine.yield('closed');return false,99
      end})
      error(17)
    end)
  end)
  assert(co()=='closed');local a,b=co();assert(a==false and b==17)
end

print('error closing phases OK')
