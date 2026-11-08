-- Native-reader line baselines must work for the selected ordinary/T interval.

-- Empty_Root: An empty root remains executable before and after stripping.
do
  local f=assert(load(''));assert(select('#',f())==0)
  local stripped=assert(load(string.dump(f,true)));assert(select('#',stripped())==0)
end

-- Single_Line: Many words on one line cross every baseline interval.
do
  local function f()local x=0;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1; return debug.getinfo(1,'l').currentline,x end
  local info=debug.getinfo(f,'S');local line,x=f();assert(line==info.linedefined and x==400)
end

-- Distant_Lines: Nonperiodic absolute source jumps preserve actual currentline.
do
  local function f()
    local x=0
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
-- a preserved blank/comment source gap
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1; return debug.getinfo(1,'l').currentline,x
  end
  local line,x=f();assert(line==319 and x==400)
end

-- Child_Prototype: Child PCs use the child line table and index origin.
do
  local function outer()
    local function inner()local x=0;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1; return debug.getinfo(1,'l').currentline,x end
    return inner
  end
  local f=outer();local line,x=f();assert(line==debug.getinfo(f,'S').linedefined and x==400)
end

-- Error_Line: Error prefix lookup must also use a valid native base estimate.
do
  local function f()local x=0;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1; string.sub('x',{})end
  local info=debug.getinfo(f,'S');local ok,e=pcall(f)
  local expected=info.short_src..':'..info.linedefined..[=[: bad argument #2 to 'sub' (number expected, got table)]=]
  assert(not ok and e==expected,tostring(e))
end

-- Line_Hook: Hook event and debug currentline share the real instruction source.
do
  local function f(x)
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;
    return x
  end
  local hits=0
  debug.sethook(function(event,line)local info=debug.getinfo(2,'fl');if info.func==f then assert(event=='line' and info.currentline==line);hits=hits+1 end end,'l')
  local result=f(0);debug.sethook();assert(result==384 and hits>0)
end

-- Stripped_Info: A stripped long child has no source line table to consult.
do
  local function f()local x=0;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1;x=x+1; return debug.getinfo(1,'l').currentline,x end
  local stripped=assert(load(string.dump(f,true)));local line,x=stripped();assert(line==-1 and x==400)
end

print('debug line baseline phases OK')
