global *
error(setmetatable({},{__tostring=function() io.stdout:write("MM_ENTER\n"); error("MM_THROW",0) end}),0)
