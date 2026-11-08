-- Actual C hooks replace masks while an instruction's hook phases wait.
assert(T and type(T.sethook)=='function')

-- C_Count_To_Line: Preserve the original API count-to-line source sequence.
do
  _G.TT={}
  T.sethook([[sethook 4 0 '
    getglobal TT; pushvalue -3; append -2; pushvalue -2; append -2
  ']],'c',3)
  local a=1
  a=1
  a=1
  a=1
  a=1
  debug.sethook()
  local t=TT;local first=t[2]
  assert(t[1]=='line' and t[3]=='line' and t[4]==first+1)
  assert(t[5]=='line' and t[6]==first+2 and t[7]==nil)
  TT=nil
end

-- C_Same_Line: A direct C count callback does not advance the Lua trace PC.
do
  _G.TT={}
  local origin=debug.getinfo(1,'l').currentline
  T.sethook([[sethook 4 0 'getglobal TT;pushvalue -3;append -2;pushvalue -2;append -2']],'',2)
  local a=1;a=1;a=1;a=1;a=1
  a=2
  debug.sethook()
  local t=TT
  assert(t[1]=='line' and t[2]==origin+2)
  assert(t[3]=='line' and t[4]==origin+3)
  assert(t[5]=='line' and t[6]==origin+4 and t[7]==nil)
  TT=nil
end

-- C_Count_Removes_Line: An old line phase invokes the new count-only callback.
do
  _G.TT={}
  local origin=debug.getinfo(1,'l').currentline
  T.sethook([[sethook 8 1000 'getglobal TT;pushvalue -3;append -2;pushvalue -2;append -2']],'l',1)
  local a=1
  a=2
  debug.sethook()
  assert(TT[1]=='line' and TT[2]==origin+2 and TT[3]==nil)
  TT=nil
end

-- C_Count_Removes_All: A captured mask cannot invoke a removed hook pointer.
do
  _G.TT={}
  T.sethook([[sethook 0 0 '']],'l',1)
  local a=1
  a=2
  debug.sethook()
  assert(TT[1]==nil)
  TT=nil
end

-- C_Line_To_Count: A line callback's new interval starts on later instructions.
do
  _G.TT={}
  T.sethook([[sethook 8 3 'getglobal TT;pushvalue -3;append -2;pushvalue -2;append -2;sethook 0 0 ""']],'l',0)
  local a=1
  a=2
  a=3
  a=4
  a=5
  debug.sethook()
  assert(TT[1]=='count' and TT[2]==-1 and TT[3]==nil)
  TT=nil
end

print('C hook transitions OK')
