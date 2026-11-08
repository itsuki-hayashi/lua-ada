global *
local mt=setmetatable({},{__index=function() io.stdout:write("META_INDEX\n"); return function() return "BAD_META" end end}); error(setmetatable({},mt),0)
