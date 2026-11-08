global *
local function inner() error("E_STRING",0) end; local function outer() inner(); return 1 end; outer()
