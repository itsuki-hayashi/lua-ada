-- The parameter prevents constant folding: NOT itself runs under refusal.
-- Values and functions are prepared before arming the actual test provider.
local function invert(x)
  T.alloccount(0)
  local result=not x
  T.alloccount()
  return result
end
local cases={
  {name='false',value=false,want=true},
  {name='nil',want=true},
  {name='zero',value=0,want=false},
  {name='empty string',value='',want=false},
  {name='table',value=setmetatable({},{__len=function()error('length')end}),want=false},
  {name='function',value=function()end,want=false},
}
for _,case in ipairs(cases)do
  assert(invert(case.value)==case.want)
  print('PASS: primitive NOT '..case.name)
end
print('PASS: scalar NOT under refusal')
