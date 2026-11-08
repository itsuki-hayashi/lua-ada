-- Native-paired identity, live cells and guarded reader transfers.

-- Reader_Identity: The actual load activation stays visible during the reader.
do
  local calls=0
  local f,e=load(function()
    local i=debug.getinfo(2,'fSu')
    assert(i.func==load and i.what=='C' and i.nparams==0 and i.isvararg)
    calls=calls+1;if calls==1 then return 'return 37' end
  end)
  assert(f and f()==37 and calls==2,tostring(e))
end

-- Mutable_Reader: Each refill reads the current actual reader argument cell.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    assert(debug.setlocal(2,1,function()calls=calls+1;return nil end))
    return 'return 41'
  end)
  assert(f and f()==41 and calls==2,tostring(e))
end

-- Retired_Reader_Root: Replacing the actual reader removes its obsolete root.
do
  local weak=setmetatable({},{__mode='v'})
  local function make_reader()
    local function old()
      assert(debug.setlocal(2,1,function()
        collectgarbage();assert(weak[1]==nil);return nil
      end))
      return 'return 43'
    end
    weak[1]=old;return old
  end
  local f,e=load(make_reader());assert(f and f()==43,tostring(e))
end

-- Mutable_Environment: load_aux reads argument four after reader callbacks.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    if calls==1 then
      assert(debug.setlocal(2,4,{value=47}))
      return 'return value'
    end
  end,'=reader-env','t',{value=7})
  assert(f and f()==47 and calls==2,tostring(e))
end

-- Text_Mode_Stop: Mode selection rejects text before another reader callback.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1;if calls==1 then return 'return 37' end
    error('read after text mode rejection',0)
  end,nil,'b')
  assert(f==nil and calls==1 and
    e=="attempt to load a text chunk (mode is 'b')",tostring(e))
end

-- Binary_Mode_Stop: The signature selects binary before text parsing or refill.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1;if calls==1 then return '\27' end
    error('read after binary mode rejection',0)
  end,nil,'t')
  assert(f==nil and calls==1 and
    e=="attempt to load a binary chunk (mode is 't')",tostring(e))
end

-- Binary_Trailing: A complete binary prototype leaves unrelated bytes unread.
do
  local source=string.dump(function()return 53 end)..'unread trailing bytes'
  local calls=0
  local f,e=load(function()
    calls=calls+1;if calls==1 then return source end
    error('read after binary prototype',0)
  end,nil,'b')
  assert(f and f()==53 and calls==1,tostring(e))
end

-- Reader_Yield: The parser guard rejects suspension across its live C body.
do
  local thread=coroutine.create(function()
    return load(function()coroutine.yield('wrong suspension')end)
  end)
  local ok,f,e=coroutine.resume(thread)
  assert(ok and f==nil and e=='attempt to yield across a C-call boundary',
    tostring(e))
  assert(coroutine.status(thread)=='dead')
end

-- Protected_Nil_Error: A nil reader error uses Lua's exact fallback and arity.
do
  local result=table.pack(pcall(load,function()error(nil,0)end))
  assert(result.n==3 and result[1]==true and
    result[2]==nil and result[3]=='<no error object>')
end

-- Return_Hook_Result: A load return hook can replace the actual result slot.
do
  local replacement=function()return 59 end
  local calls,hits=0,0
  debug.sethook(function(event)
    if event=='return' then local i=debug.getinfo(2,'fr')
      if i.func==load then
        hits=hits+1;assert(i.ntransfer==1)
        assert(debug.setlocal(2,i.ftransfer,replacement))
      end
    end
  end,'r')
  local f=load(function()
    calls=calls+1;if calls==1 then return 'return 1' end
  end)
  debug.sethook();assert(f==replacement and f()==59 and hits==1)
end

-- Return_Hook_Nil_Tuple: Failed load retains both editable return slots.
do
  local hits=0
  debug.sethook(function(event)
    if event=='return' then local i=debug.getinfo(2,'fr')
      if i.func==load then
        hits=hits+1;assert(i.ntransfer==2)
        assert(debug.setlocal(2,i.ftransfer,false))
        assert(debug.setlocal(2,i.ftransfer+1,nil))
      end
    end
  end,'r')
  local result=table.pack(load(function()return 'local = x' end))
  debug.sethook()
  assert(result.n==2 and result[1]==false and result[2]==nil and hits==1)
end

-- Single_Public_Call: The portal adds no public call or return event.
do
  local calls,entries,returns=0,0,0
  debug.sethook(function(event)
    local i=debug.getinfo(2,'f')
    if i.func==load then
      if event=='call' then entries=entries+1
      elseif event=='return' then returns=returns+1 end
    end
  end,'cr')
  local f=load(function()
    calls=calls+1;if calls==1 then return 'return 61' end
  end)
  debug.sethook()
  assert(f and f()==61 and entries==1 and returns==1)
end

-- Nested_Reader_Load: A reader can stream another load on the same driver.
do
  local outer,inner=0,0
  local f,e=load(function()
    outer=outer+1
    if outer==1 then
      local g,m=load(function()
        inner=inner+1;if inner==1 then return 'return 67' end
      end)
      assert(g and g()==67,tostring(m));return 'return 71'
    end
  end)
  assert(f and f()==71 and outer==2 and inner==2,tostring(e))
end

-- Inherited_Handler: Reader errors use the actual surrounding message handler.
do
  local original,replacement={},{};local calls=0
  local ok,f,e=xpcall(function()
    return load(function()error(original,0)end)
  end,function(value)
    calls=calls+1;assert(value==original);return replacement
  end)
  assert(ok and f==nil and e==replacement and calls==1)
end

-- Numeric_Chunk_Name: Numeric names are strings in the actual reader-visible CI.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    local _,value=debug.getlocal(2,2)
    assert(type(value)=='string' and value=='37')
    if calls==1 then return 'return 73' end
  end,37)
  assert(f and f()==73 and calls==2,tostring(e))
  assert(debug.getinfo(f,'S').source=='37')
end

-- Numeric_Mode: Numeric mode coercion is visible before signature rejection.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    local _,value=debug.getlocal(2,3)
    assert(type(value)=='string' and value=='42')
    return 'return 79'
  end,nil,42)
  assert(f==nil and calls==1 and
    e=="attempt to load a text chunk (mode is '42')",tostring(e))
end

-- Retired_Extra_Argument: Replaced extra arguments leave no stale phase root.
do
  local weak=setmetatable({},{__mode='v'})
  local function make_extra()local value={};weak[1]=value;return value end
  local calls=0
  local f,e=load(function()
    calls=calls+1
    if calls==1 then
      assert(debug.setlocal(2,5,nil))
      collectgarbage();assert(weak[1]==nil);return 'return 83'
    end
  end,nil,'t',_ENV,make_extra())
  assert(f and f()==83 and calls==2,tostring(e))
end

print('reader portal phases OK')
