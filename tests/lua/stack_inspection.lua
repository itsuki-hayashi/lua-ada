local cases={
 function()
  local a,b,c,d,e=T.stacklevel()
  for _,v in ipairs{a,b,c,d,e}do assert(math.type(v)=='integer')end
  assert(a>=0 and b>0 and c>=0 and d>0 and e~=0)
 end,
 function()
  local pos,top=0,nil
  local text='return 121'
  local function read()
   pos=pos+1
   local current=T.stacklevel()
   if top then assert(current==top)else top=current end
   return text:sub(pos,pos)
  end
  assert(assert(load(read))()==121)
 end,
 function()
  local text=string.dump(assert(load('return 37')))
  local pos,top=0,nil
  local function read()
   pos=pos+1
   local current=T.stacklevel()
   if top then assert(current==top)else top=current end
   return text:sub(pos,pos)
  end
  assert(assert(load(read))()==37)
 end,
 function()
  local _,_,before=T.stacklevel()
  local observed
  local ok,e=pcall(function()
   local _,_,inside=T.stacklevel()
   observed=inside
   error('expected',0)
  end)
  assert(not ok and e=='expected' and observed>before)
  local _,_,after=T.stacklevel()
  assert(before==after)
 end,
}
for i,f in ipairs(cases)do f();print('PASS: stack inspection '..i)end
