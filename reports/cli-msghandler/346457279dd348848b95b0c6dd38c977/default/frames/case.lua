global *
local e
e=setmetatable({},{__tostring=function(self)
  assert(self==e)
  local p=debug.getinfo(2,"Sf")
  io.stdout:write("PARENT ",p.what," ",p.func==tostring and "tostring" or "anonymous","\n")
  local n,v=debug.getlocal(2,1)
  io.stdout:write("ARG ",n or "nil"," ",v==e and "same" or "other","\n")
  io.stdout:write("YIELDABLE ",coroutine.isyieldable() and "yes" or "no","\n")
  collectgarbage()
  for level=1,9 do
    local info=debug.getinfo(level,"nSl")
    if not info then break end
    io.stdout:write("FRAME ",level," ",info.what," ",info.namewhat," ",info.name or "-"," ",info.short_src," ",info.currentline,"\n")
  end
  io.stdout:write(debug.traceback("IN_CALLBACK",1),"\n")
  return "FRAME_MESSAGE"
end})
local function inner() error(e,0) end
local function outer() inner(); return 1 end
outer()
