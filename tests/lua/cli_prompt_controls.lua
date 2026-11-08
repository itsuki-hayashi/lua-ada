-- Public CLI prompt controls. Pinned main.lua:371-421 and lua.c:554-563.
-- This setup chunk returns before the host asks for a prompt; it adds no
-- Lua activation to __index/__tostring callback inspection.
local case=...
if case=='primary-nil' or case=='secondary-nil' then
  _PROMPT=nil;_PROMPT2=nil
elseif case=='custom-string' then
  _PROMPT='alo'
elseif case=='empty-string' then
  _PROMPT=''
elseif case=='number' then
  _PROMPT=17.0
elseif case=='boolean' then
  _PROMPT=false
elseif case=='embedded-nul' then
  _PROMPT='P\0hidden'
elseif case=='global-tostring' then
  tostring=function()error('wrong global tostring',0)end
  _PROMPT=37
elseif case=='dynamic-tostring' then
  local n='X'
  _PROMPT=setmetatable({}, {__tostring=function()
    n=n..'X';return n
  end})
elseif case=='numeric-tostring' then
  _PROMPT=setmetatable({}, {__tostring=function()return 17.0 end})
elseif case=='index-value' then
  _PROMPT=nil
  setmetatable(_G,{__index=function(_,k)
    if k=='_PROMPT' then return 'index' end
  end})
elseif case=='tostring-frame' then
  _PROMPT=setmetatable({}, {__tostring=function(self)
    local d=debug.getinfo(2,'nS')
    assert(d.what=='C' and d.source=='=[C]' and d.namewhat=='')
    assert(debug.getinfo(3)==nil)
    local n,v=debug.getlocal(2,1)
    assert(n=='(C temporary)' and v==self)
    assert(debug.getlocal(2,2)==nil)
    local trace=debug.traceback('',1)
    assert(select(2,trace:gsub('%[C%]',''))==1)
    return 'frame'
  end})
elseif case=='index-frame' then
  _PROMPT=nil
  setmetatable(_G,{__index=function(t,k)
    if k=='_PROMPT' then
      assert(t==_G)
      local d=debug.getinfo(2,'nS')
      assert(d.what=='C' and d.source=='=[C]' and d.namewhat=='')
      assert(debug.getinfo(3)==nil)
      local n,v=debug.getlocal(2,1)
      -- C Lua retains its key here; Ada's public getglobal composition
      -- retains the actual global table. The manual exposes actual C
      -- temporaries, not a prescribed intermediate lookup arrangement.
      assert(n=='(C temporary)' and (v==k or v==t))
      assert(debug.getlocal(2,2)==nil)
      local trace=debug.traceback('',1)
      assert(select(2,trace:gsub('%[C%]',''))==1)
      return 'frame'
    end
  end})
elseif case=='bad-tostring' then
  _PROMPT=setmetatable({}, {__tostring=function()return {} end})
elseif case=='error-tostring' then
  _PROMPT=setmetatable({}, {__tostring=function()
    error('prompt-broken',0)
  end})
elseif case=='error-table' then
  prompt_error=setmetatable({}, {__tostring=function()
    error('wrong error tostring',0)
  end})
  _PROMPT=setmetatable({}, {__tostring=function()
    error(prompt_error,0)
  end})
elseif case=='error-boolean' then
  _PROMPT=setmetatable({}, {__tostring=function()error(false,0)end})
elseif case=='error-nul' then
  _PROMPT=setmetatable({}, {__tostring=function()
    error('prefix\0hidden',0)
  end})
elseif case=='index-error' then
  _PROMPT=nil
  setmetatable(_G,{__index=function(_,k)
    if k=='_PROMPT' then error('index-broken',0) end
  end})
elseif case=='yield-tostring' then
  _PROMPT=setmetatable({}, {__tostring=function()
    return coroutine.yield('prompt-yield')
  end})
elseif case=='retired-root' then
  prompt_weak=setmetatable({}, {__mode='v'})
  _PROMPT=setmetatable({}, {__tostring=function(self)
    _PROMPT=nil
    collectgarbage();collectgarbage()
    assert(prompt_weak[1]==self)
    return 'root'
  end})
  prompt_weak[1]=_PROMPT
elseif case=='budget' then
  prompt_started=false
  _PROMPT=setmetatable({}, {__tostring=function()
    prompt_started=true
    pcall(function()while true do end end)
    return 'caught'
  end})
elseif case=='exit-no-close' or case=='exit-close' then
  local close=case=='exit-close'
  _PROMPT=setmetatable({}, {__tostring=function()
    os.exit(37,close)
  end})
else
  error('unknown prompt case '..tostring(case))
end
