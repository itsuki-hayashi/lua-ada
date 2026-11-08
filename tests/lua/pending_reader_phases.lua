-- Native-paired reader demand at real token and semantic boundaries.

-- Extended_Name: A prefix ending inside a name cannot finalize that name.
do
  local pieces={'local ret','urned=37;return returned'}
  local calls=0
  local f,e=load(function()calls=calls+1;return pieces[calls]end)
  assert(f and f()==37 and calls==3,tostring(e))
end

-- Extended_Number: A numeric spelling may continue in another reader piece.
do
  local pieces={'return 0x1','p+2'}
  local calls=0
  local f,e=load(function()calls=calls+1;return pieces[calls]end)
  assert(f and f()==4 and calls==3,tostring(e))
end

-- Split_Escape: A short string's hexadecimal escape remains pending.
do
  local pieces={[[return '\x]],[[41']]}
  local calls=0
  local f,e=load(function()calls=calls+1;return pieces[calls]end)
  assert(f and f()=='A' and calls==3,tostring(e))
end

-- Split_Long_String: Long delimiter bytes may cross reader pieces.
do
  local pieces={'return [=','[value]', '=]'}
  local calls=0
  local f,e=load(function()calls=calls+1;return pieces[calls]end)
  assert(f and f()=='value' and calls==4,tostring(e))
end

-- Split_Comment: A comment cannot manufacture EOF or consume a following line.
do
  local pieces={'--[','[not code]',']\nreturn 9'}
  local calls=0
  local f,e=load(function()calls=calls+1;return pieces[calls]end)
  assert(f and f()==9 and calls==4,tostring(e))
end

-- Pending_Error_Object: An unfinished token still requests the real reader.
do
  local marker={};local calls=0
  local ok,f,e=pcall(load,function()
    calls=calls+1
    if calls==1 then return 'return 1e' end
    error(marker,0)
  end)
  assert(ok and f==nil and e==marker and calls==2)
end

-- Definite_Escape: An invalid escape wins before a later reader failure.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    if calls==1 then return [[return '\qX]] end
    error('read after invalid escape',0)
  end,'=reader-invalid')
  assert(f==nil and calls==1 and
    e==[[reader-invalid:1: invalid escape sequence near ''\q']],tostring(e))
end

-- Delimiter_Demand: A consumed token requires its real following byte.
do
  local marker={};local calls=0
  local ok,f,e=pcall(load,function()
    calls=calls+1
    if calls==1 then return 'local <close> a,b;' end
    error(marker,0)
  end)
  assert(ok and f==nil and e==marker and calls==2)
end

-- One_Byte_Text: Token, comment, escape and operator boundaries use one grammar.
do
  local source="-- comment\nlocal s='\\x41';local n=0x1p+2;return s,n//2"
  local calls=0
  local f,e=load(function()
    calls=calls+1;return source:sub(calls,calls)
  end)
  assert(f and calls==#source+1,tostring(e))
  local a,b=f();assert(a=='A' and b==2)
end

-- One_Byte_Binary: A binary signature is never sent through the text probe.
do
  local source=string.dump(function()return 37,nil,41 end)
  local calls=0
  local f,e=load(function()
    calls=calls+1;return source:sub(calls,calls)
  end,nil,'b')
  assert(f and calls==#source,tostring(e))
  local a,b,c=f();assert(a==37 and b==nil and c==41)
end

-- Actual_Empty_End: Empty input supplies genuine EOF and forbids another call.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    if calls==1 then return 'return 8' elseif calls==2 then return '' end
    error('read after empty input',0)
  end)
  assert(f and f()==8 and calls==2,tostring(e))
end

print('pending reader phases OK')
