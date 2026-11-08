-- Native-paired label no-op ordering and semantic last-token boundaries.

-- Trailing_Newline: Adjacent duplicate labels retain the last consumed delimiter line.
do
  local source="::L::\n::L::\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- Blank_Tail: Extra blank lines at EOF do not move the completed semantic error.
do
  local source="::L::\n::L::\n\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- Comment_Tail: A trailing line comment does not replace the consumed token line.
do
  local source="::L::\n::L:: -- tail\n\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- Long_Comment_Tail: A scanned multiline comment cannot move the semantic error to EOF.
do
  local source="::L::\n::L:: --[[\n\n]]\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- Split_Label: The error uses the closing delimiter while the cited definition uses its opener.
do
  local source="::L::\n::\nL\n::\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:4: label 'L' already defined on line 2]=],tostring(e))
end

-- Semicolon_Tail: A consumed no-op semicolon participates in the native last-token line.
do
  local source="::L::\n::L::\n;\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:3: label 'L' already defined on line 2]=],tostring(e))
end

-- Triple_Run: The final label in an adjacent run is defined before earlier labels.
do
  local source="::L::\n::X::\n::L::\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:3: label 'L' already defined on line 3]=],tostring(e))
end

-- Separated_Definition: A prior completed run remains visible to a later duplicate.
do
  local source="::L::\nlocal x=0\n::L::\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:3: label 'L' already defined on line 1]=],tostring(e))
end

-- Nested_Shadow: An active outer label still prevents an inner duplicate.
do
  local source="::L::\ndo\n::L::\nend\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:3: label 'L' already defined on line 1]=],tostring(e))
end

-- Following_Return: An unconsumed real statement does not supply the semantic line.
do
  local source="::L::\n::L::\nreturn"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- Following_String: A following multiline lookahead token does not replace last consumed line.
do
  local source="::L::\n::L::\n[=[\ntext\n]=]"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- CRLF_Tail: A CRLF boundary preserves the same native semantic source line.
do
  local source="::L::\r\n::L::\r\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: label 'L' already defined on line 2]=],tostring(e))
end

-- Malformed_Later_Label: A later malformed adjacent label fails before deferred repeat checks.
do
  local source="::L::\n::L::\n::oops\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:4: '::' expected near <eof>]=],tostring(e))
end

-- Ordinary_Expectation: Unrelated syntax errors retain the current scanned token line.
do
  local source="local\n"
  local f,e=load(source,'=label-boundary')
  assert(f==nil and e==[=[label-boundary:2: <name> expected near <eof>]=],tostring(e))
end

-- Backward_Run: All adjacent valid labels are visible to later backward gotos.
do
  local function f()local n=0;::A:: ::B:: n=n+1;if n<3 then goto A end;return n end
  assert(f()==3)
end

-- Disjoint_Blocks: A label leaves visibility when its actual block closes.
do
  local function f()do ::L:: end do ::L:: end return 7 end;assert(f()==7)
end

-- Function_Scope: A function owns its own independent label namespace.
do
  local function f()::L:: local function g()::L:: return 7 end return g()end;assert(f()==7)
end

-- Terminal_Run: Every terminal label in a no-op run stays outside closed local scope.
do
  local function f()goto A;local x=7;::A:: ; ::B:: end;assert(select('#',f())==0)
end

-- Reader_Precedence: A real reader reaches the malformed later label before repeat checks.
do
  local parts={'::L::','\n','::L::','\n','::oops','\n'};local calls=0
  local f,e=load(function()calls=calls+1;return parts[calls]end,'=label-reader')
  assert(f==nil and e=="label-reader:4: '::' expected near <eof>" and calls==#parts+1,tostring(e))
end

print('label diagnostic phases OK')
