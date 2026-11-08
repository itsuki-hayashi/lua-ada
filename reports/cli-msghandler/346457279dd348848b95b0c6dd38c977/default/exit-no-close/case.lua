global *
error(setmetatable({},{__tostring=function() io.stdout:write("EXIT_HANDLER\n"); os.exit(37,false) end}),0)
