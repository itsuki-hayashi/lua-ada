global *
debug.setmetatable(0,{__tostring=function() io.stdout:write("NUM_MM\n"); return "BAD_NUM" end}); error(37,0)
