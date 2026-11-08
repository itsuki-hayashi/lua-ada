-- First-party public B-mode witness; MIT, see ../../../../LICENSE.
-- This is neither an adapted upstream file nor an exclusion decision.
-- The caller keeps every dump alive while its loaded function is used.
assert(type(T) == 'table' and type(T.testC) == 'function')

local N = 1000
local source = {}
for i = 1, N do source[i] = 'X = X + 1; ' end
source[#source + 1] = string.format("Y = '%s'", string.rep('a', N))
source = assert(load(table.concat(source), 'name1'))
source = string.dump(source, true)
assert(#source > N * 4 * 4 + N)
collectgarbage(); collectgarbage()
local before = collectgarbage('count') * 1024
local code = T.testC('loadstring 2 name B; return 1', source)
collectgarbage()
local after = collectgarbage('count') * 1024
assert(after > before)
X = 0
code()
assert(X == N and Y == string.rep('a', N))
X = nil; Y = nil

-- A complete dump also retains its actual line table. Neither the private
-- allocation observation nor a source inspection replaces this execution.
source = {'X = 0'}
for i = 2, 300 do source[i] = 'X = X + 1' end
source[#source + 1] = 'X = X + {}'
source = string.dump(assert(load(table.concat(source, '\n'), 'name1')))
code = T.testC('loadstring 2 name B; return 1', source)
local ok, message = pcall(code)
assert(not ok and type(message) == 'string' and message:find(':301:', 1, true))
X = nil
print('API FIXED BUFFER PUBLIC OK')
