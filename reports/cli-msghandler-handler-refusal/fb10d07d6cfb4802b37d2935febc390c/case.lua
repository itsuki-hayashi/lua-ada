global *
local control=T.alloccount; local e; e=setmetatable({},{__tostring=function(self) assert(self==e); io.stdout:write('HANDLER_ARMED\n'); control(0); return 37 end}); error(e,0)
