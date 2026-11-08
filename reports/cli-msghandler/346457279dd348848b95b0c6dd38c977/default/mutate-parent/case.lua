global *
local e; e=setmetatable({},{__tostring=function(self) local n,v=debug.getlocal(2,1); io.stdout:write("PARENT_ARG ",n," ",v==e and "same" or "other","\n"); io.stdout:write("SET ",debug.setlocal(2,1,37) or "nil","\n"); return false end}); error(e,0)
