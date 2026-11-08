global *
local callable; local e; callable=setmetatable({},{__call=function(self,v) assert(self==callable and v==e); return "MM_CALLABLE" end}); e=setmetatable({},{__tostring=callable}); error(e,0)
