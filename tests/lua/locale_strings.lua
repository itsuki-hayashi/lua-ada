-- Native locale is process state; restore each category even on failure.
local function under(category,name,body)
 local previous=assert(os.setlocale(nil,category))
 local selected=os.setlocale(name,category)
 if not selected then return false end
 local ok,err=xpcall(body,debug.traceback)
 assert(os.setlocale(previous,category));assert(ok,err)
 return true
end
local function portuguese(category,body)
 for _,name in ipairs{'ptb','pt_BR.iso88591','ISO-8859-1'}do
  if under(category,name,body)then
   print('LOCALE available '..category..' '..name);return
  end
 end
 -- This is an explicit native availability observation, not non-C coverage.
 print('LOCALE unavailable '..category)
end
local cases={
 {'C_Collation',function()
  assert(under('collate','C',function()
   assert(''<'a' and 'a'<'a\0' and 'a\0'<'a\0\0')
   assert('a\0a'<'a\0b' and 'a\0b'>'a\0a')
   assert('a\0a'<='a\0a' and 'a\0a'>='a\0a')
   assert(not ('a\0b'<='a\0a'))
   local t={'b','a\0b','a','a\0a'};table.sort(t)
   assert(t[1]=='a' and t[2]=='a\0a' and t[3]=='a\0b' and t[4]=='b')
  end))
 end},
 {'C_Classes',function()
  assert(under('ctype','C',function()
   for i=0,255 do
    local c=string.char(i)
    local alpha=i>=65 and i<=90 or i>=97 and i<=122
    assert((c:match('%a')~=nil)==alpha)
    assert((c:match('%A')~=nil)==not alpha)
    assert((c:match('%l')~=nil)==(i>=97 and i<=122))
    assert((c:match('%u')~=nil)==(i>=65 and i<=90))
    assert((c:match('%d')~=nil)==(i>=48 and i<=57))
    assert((c:match('%z')~=nil)==(i==0))
   end
   assert(('q'):match('%q')=='q' and ('Q'):match('%q')==nil)
  end))
 end},
 {'C_Case',function()
  assert(under('ctype','C',function()
   for i=0,255 do
    local c=string.char(i)
    local lower=i>=65 and i<=90 and i+32 or i
    local upper=i>=97 and i<=122 and i-32 or i
    assert(c:lower()==string.char(lower))
    assert(c:upper()==string.char(upper))
   end
  end))
 end},
 {'NonC_Collation',function()
  portuguese('collate',function()
   local accented=string.char(225)..'lo'
   assert('alo'<accented and accented<'amo')
   assert('alo\0a'<accented..'\0a')
   assert(accented..'\0a'<accented..'\0b')
   assert(accented..'\0' > accented)
   local t={'amo',accented,'alo'};table.sort(t)
   assert(t[1]=='alo' and t[2]==accented and t[3]=='amo')
   assert('alo'~=accented) -- collation never changes byte equality.
   if package.config:sub(1,1)=='\\'then
    -- The measured native Windows Portuguese collation ignores soft hyphen.
    -- Equal collation weights must not be confused with Lua byte equality.
    local a,b='ab','a'..string.char(173)..'b'
    assert(a~=b and not (a<b) and not (b<a))
    assert(a<=b and b<=a and a>=b and b>=a)
   end
  end)
 end},
 {'NonC_Classes_Case',function()
  portuguese('ctype',function()
   local lower=string.char(225,233,237,243,250)
   local upper=string.char(193,201,205,211,218)
   assert(lower:gsub('%a','x')=='xxxxx')
   assert(lower:gsub('%l','x')=='xxxxx')
   assert(upper:gsub('%u','x')=='xxxxx')
   assert(lower:upper()==upper and upper:lower()==lower)
   assert(lower:upper():lower()==lower)
   assert(('\0'..lower):upper()=='\0'..upper)
  end)
 end},
 {'Unavailable_Unchanged',function()
  local before=assert(os.setlocale(nil,'ctype'))
  assert(os.setlocale('lua-ada-no-such-locale','ctype')==nil)
  assert(os.setlocale(nil,'ctype')==before)
 end},
}
for _,case in ipairs(cases)do
 if _LOCALE_STRING_CASE==nil or _LOCALE_STRING_CASE==case[1]then
  case[2]();print('PASS locale strings '..case[1])
 end
end
