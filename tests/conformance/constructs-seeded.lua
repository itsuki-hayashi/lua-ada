-- Execute the unchanged source with a reproducible choice of its generated
-- short-circuit template. Both actual random outcomes have separate reports;
-- this wrapper never replaces math.random or changes a tested assertion.
local branch = assert(tonumber(arg[1]))
assert(branch == 0 or branch == 1)
math.randomseed(branch == 0 and 4 or 0, 0)
dofile("constructs.lua")
