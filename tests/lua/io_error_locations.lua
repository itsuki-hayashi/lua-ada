-- Auxiliary IO failures use the actual immediate public caller's location.
local path='missing-io-parent-72bc472c12e74b2787889d993035891f/file'
local detail="cannot open file '"..path.."' (No such file or directory)"
local function caught(f,...)
  local ok,msg=pcall(f,...)
  assert(not ok and type(msg)=='string')
  return msg
end
local function named(operation,name)
  return assert(load('return function(path)\n  io.'..operation..'(path)\nend',name))()
end

-- case: Output_Named
do
  local f=named('output','@io-output-site.lua')
  assert(caught(f,path)=='io-output-site.lua:2: '..detail)
end

-- case: Input_Named
do
  local f=named('input','@io-input-site.lua')
  assert(caught(f,path)=='io-input-site.lua:2: '..detail)
end

-- case: Output_C_Caller
do
  assert(caught(io.output,path)==detail)
end

-- case: Input_C_Caller
do
  assert(caught(io.input,path)==detail)
end

-- case: Stripped_Caller
do
  local f=named('output','@io-stripped-site.lua')
  local stripped=assert(load(string.dump(f,true)))
  assert(caught(stripped,path)==detail)
end

-- case: Binary_Source_Name
do
  local f=named('output','@io-source'..string.char(0)..'hidden')
  assert(caught(f,path)=='io-source:2: '..detail)
end

-- case: Returned_File_Error
do
  local result=table.pack(io.open(path,'r'))
  assert(result.n==3 and result[1]==nil)
  assert(result[2]==path..': No such file or directory')
  assert(result[3]==2 and math.type(result[3])=='integer')
end

print('IO error locations OK')
