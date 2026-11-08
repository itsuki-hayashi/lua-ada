global *
local e; e=setmetatable({},{__tostring=function(self) assert(self==e); io.stdout:write("MM_ENTER\n"); return "MM_STRING" end}); error(e,0)
