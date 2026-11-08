-- Native-paired function-statement defining stores and actual line events.

-- Field_Store: A failed function field definition is attributed to its opening keyword.
do
  function_store_target={}
  local f=assert(load([=[function function_store_target.x.y()
 return 7
end]=],'=function-store'))
  local ok,e=pcall(f);function_store_target=nil
  assert(not ok and e==[=[function-store:1: attempt to index a nil value (field 'x')]=],tostring(e))
end

-- Method_Store: An implicit-self method definition retains the opening store line.
do
  function_store_target={}
  local f=assert(load([=[function function_store_target.x:y()
 return self
end]=],'=function-store'))
  local ok,e=pcall(f);function_store_target=nil
  assert(not ok and e==[=[function-store:1: attempt to index a nil value (field 'x')]=],tostring(e))
end

-- Empty_Store: An empty function body still stores on the definition's first line.
do
  function_store_target={}
  local f=assert(load([=[function function_store_target.x.y()
end]=],'=function-store'))
  local ok,e=pcall(f);function_store_target=nil
  assert(not ok and e==[=[function-store:1: attempt to index a nil value (field 'x')]=],tostring(e))
end

-- Keyword_Line: A split keyword and target uses the keyword line rather than target line.
do
  function_store_target={}
  local f=assert(load([=[function
 function_store_target.x.y()
 return 7
end]=],'=function-store'))
  local ok,e=pcall(f);function_store_target=nil
  assert(not ok and e==[=[function-store:1: attempt to index a nil value (field 'x')]=],tostring(e))
end

-- Assignment_End: An ordinary anonymous-function assignment retains its closing RHS line.
do
  function_store_target={}
  local f=assert(load([=[function_store_target.x.y = function()
 return 7
end]=],'=function-store'))
  local ok,e=pcall(f);function_store_target=nil
  assert(not ok and e==[=[function-store:3: attempt to index a nil value (field 'x')]=],tostring(e))
end

-- Target_Read: A target-prefix read still fails before closure construction.
do
  function_store_target=nil
  local f=assert(load([=[function function_store_target.x.y()
 return 7
end]=],'=function-store'))
  local ok,e=pcall(f);function_store_target=nil
  assert(not ok and e==[=[function-store:1: attempt to index a nil value (global 'function_store_target')]=],tostring(e))
end

-- Field_Events: Closure construction stays on end while the actual field store moves to start.
do
  local storeline,stored;function_store_target={x=setmetatable({},{__newindex=function(t,k,v)
    storeline=debug.getinfo(2,'l').currentline;stored=v;rawset(t,k,v)
  end})}
  local function f()
    function function_store_target.x.y()
      return 7
    end
  end
  local info=debug.getinfo(f,'S');local lines={}
  debug.sethook(function(_,line)if debug.getinfo(2,'f').func==f then lines[#lines+1]=line end end,'l')
  f();debug.sethook();function_store_target=nil
  assert(storeline==info.linedefined+1 and stored()==7)
  local expected={info.linedefined+1,info.linedefined+3,info.linedefined+1,info.lastlinedefined}
  assert(#lines==#expected);for i,v in ipairs(expected)do assert(lines[i]==v,table.concat(lines,','))end
end

-- Global_Events: A real global newindex callback observes the opening definition store.
do
  local storeline,stored;local env=setmetatable({},{__index=_G,__newindex=function(t,k,v)
    storeline=debug.getinfo(2,'l').currentline;stored=v;rawset(t,k,v)
  end})
  local f
  do
    local _ENV=env
    f=function()
      function function_store_created()
        return 7
      end
    end
  end
  local info=debug.getinfo(f,'S');local lines={}
  debug.sethook(function(_,line)if debug.getinfo(2,'f').func==f then lines[#lines+1]=line end end,'l')
  f();debug.sethook()
  assert(storeline==info.linedefined+1 and stored==env.function_store_created and stored()==7)
  local expected={info.linedefined+3,info.linedefined+1,info.lastlinedefined}
  assert(#lines==#expected);for i,v in ipairs(expected)do assert(lines[i]==v,table.concat(lines,','))end
end

-- Local_Events: A recursive local definition retains its distinct closing-line initialization.
do
  local function f()
    local function created()
      return 7
    end
    return created
  end
  local info=debug.getinfo(f,'S');local lines={}
  debug.sethook(function(_,line)if debug.getinfo(2,'f').func==f then lines[#lines+1]=line end end,'l')
  local stored=f();debug.sethook();assert(stored()==7)
  local expected={info.linedefined+3,info.linedefined+4}
  assert(#lines==#expected);for i,v in ipairs(expected)do assert(lines[i]==v,table.concat(lines,','))end
end

-- Explicit_Global_Store: A split global directive stores on its GLOBAL keyword line.
do
  local observed;local env=setmetatable({},{__newindex=function(t,k,v)
    observed=debug.getinfo(2,'l').currentline;rawset(t,k,v)
  end})
  local f=assert(load('global\n function\n created\n ()\n return 7\n end','=explicit-global','t',env))
  f();assert(observed==1 and env.created()==7)
end

-- Explicit_Global_Metadata: Global function metadata uses its actual parenthesis line.
do
  local env={};local f=assert(load('global\n function\n created\n ()\n return 7\n end','=explicit-global','t',env))
  f();local info=debug.getinfo(env.created,'S')
  assert(info.linedefined==4 and info.lastlinedefined==6 and env.created()==7)
end

-- Ordinary_Metadata: A split ordinary function retains keyword-based child metadata.
do
  local env={};local f=assert(load('function\n created\n ()\n return 7\n end','=ordinary-function','t',env))
  f();local info=debug.getinfo(env.created,'S')
  assert(info.linedefined==1 and info.lastlinedefined==5 and env.created()==7)
end

print('function store phases OK')
