-- Malformed escapes retain the partially decoded token in diagnostics.
-- Each expected suffix is checked against the pinned native interpreter as
-- well as the Ada CLI by the ordinary differential fixture campaign.
local cases = {
  { [=['\q']=], [=[invalid escape sequence near ''\q']=] },
  { [=['\256']=], [=[decimal escape too large near ''\256'']=] },
  { [=['\x0g']=], [=[hexadecimal digit expected near ''\x0g']=] },
  { [=['\u{}']=], [=[hexadecimal digit expected near ''\u{}']=] },
  { [=['\u{80000000}']=], [=[UTF-8 value too large near ''\u{80000000']=] },
  { [=['abc\x]=], [=[hexadecimal digit expected near ''abc\x']=] },
  { [=['\x41\xg']=], [=[hexadecimal digit expected near ''A\xg']=] },
}
for i, case in ipairs(cases) do
  local f, msg = load('return ' .. case[1], '=probe')
  assert(not f and msg:sub(-#case[2]) == case[2], tostring(i) .. ': ' .. msg)
  print('escape diagnostic', i, 'OK')
end
