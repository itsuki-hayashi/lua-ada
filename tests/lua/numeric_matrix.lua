-- Deterministic differential arithmetic corpus, using only the M1 base.
-- Cases cover operand types and IEEE boundaries; expected values come from
-- the pinned C interpreter, rather than reimplementing the arithmetic oracle.
local values = {
  0, 1, -1, 3, -7, 9223372036854775807, -9223372036854775807-1,
  1.5, -1.5, 1e308, 1e-308, 1/0, -1/0
}
local operations = {
  function(a,b) return a+b end,
  function(a,b) return a-b end,
  function(a,b) return a*b end,
  function(a,b) return a/b end,
  function(a,b) return a//b end,
  function(a,b) return a%b end,
  function(a,b) return a^b end,
  function(a,b) return a&b end,
  function(a,b) return a|b end,
  function(a,b) return a~b end,
  function(a,b) return a<<b end,
  function(a,b) return a>>b end,
  function(a,b) return a<b end,
  function(a,b) return a==b end
}
for operation,f in ipairs(operations) do
  for left,a in ipairs(values) do
    for right,b in ipairs(values) do
      local ok,result = pcall(f,a,b)
      if ok then print(operation,left,right,result)
      else print(operation,left,right,false) end
    end
  end
end
