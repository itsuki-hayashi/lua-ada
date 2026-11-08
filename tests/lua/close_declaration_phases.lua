-- Native-paired closing declaration semantic-token and reader boundaries.

-- Prefix_Newline: A trailing LF does not move the completed closing declaration error.
do
  local source="local <close> a,b\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Blank_Tail: Blank EOF lines preserve the last consumed variable's source line.
do
  local source="local <close> a,b\n\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Comment_Tail: A scanned line comment is not the semantic declaration token.
do
  local source="local <close> a,b --tail\n\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Long_Comment_Tail: A multiline trailing comment does not become the semantic error line.
do
  local source="local <close> a,b --[[\n\n]]\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Semicolon_Lookahead: An unconsumed semicolon differs from the no-op label run's consumed semicolon.
do
  local source="local <close> a,b\n;\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Next_Name_Line: The second variable's own consumed line supplies the duplicate-closing error.
do
  local source="local <close> a,\n b\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:2: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Explicit_Attributes: Explicit closing attributes use the same completed semantic check.
do
  local source="local a<close>,b<close>\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Split_Attributes: A split attribute reports the consumed closing angle rather than the name.
do
  local source="local a<close>,\n b<\n close\n >\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:4: multiple to-be-closed variables in local list]=],tostring(e))
end

-- CRLF_Tail: CRLF input retains the consumed declaration line.
do
  local source="local <close> a,b\r\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:1: multiple to-be-closed variables in local list]=],tostring(e))
end

-- Incomplete_Attribute: An unfinished attribute still wins as a continuable syntax error.
do
  local source="local <close> a,\nb<\n"
  local f,e=load(source,'=close-declaration')
  assert(f==nil and e==[=[close-declaration:3: <name> expected near <eof>]=],tostring(e))
end

-- Single_Closing: A single explicit closer retains its actual once-only handler lifetime.
do
  local count=0
  do local a<close>,b=setmetatable({},{__close=function()count=count+1 end}),7;assert(b==7)end
  assert(count==1)
end

-- Attribute_Override: An explicit const overrides a prefixed closing default for that name.
do
  local <close> a,b<const> = nil,7;assert(b==7)
end

-- Reader_Stop: A real reader stops at the completed semantic declaration failure.
do
  local calls=0
  local f,e=load(function()
    calls=calls+1
    if calls==1 then return 'local <close> a,b'
    elseif calls==2 then return ';more'
    else error('unexpected reader continuation')end
  end,'=close-reader')
  assert(f==nil and e=='close-reader:1: multiple to-be-closed variables in local list' and calls==2,tostring(e))
end

print('close declaration phases OK')
