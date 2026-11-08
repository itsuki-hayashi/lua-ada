local case = ...
if case == 'first' then
  local t = setmetatable({}, {__len = function() return 37, 51, nil end})
  local result = table.pack(#t)
  assert(result.n == 1 and result[1] == 37)
elseif case == 'empty' then
  local t = setmetatable({}, {__len = function() end})
  local result = table.pack(#t)
  assert(result.n == 1 and result[1] == nil)
elseif case == 'failure' then
  local t = setmetatable({}, {__len = function() error(17, 0) end})
  local ok, message = pcall(function() return #t end)
  assert(not ok and message == 17)
  assert(#setmetatable({}, {__len = function() return 23 end}) == 23)
else
  error('unknown length result case')
end
print('PASS: length-result-' .. case)
