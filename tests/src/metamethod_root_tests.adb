with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Metamethod_Root_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Concat;
   procedure Concat is
   begin
      --  Concatenation relinquishes helper copies after actual operands
      --  and parameters are dropped.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__concat=function(x,y)clear();x,y=ni" &
         "l,nil;collectgarbage();assert(weak[1]==nil and w" &
         "eak[2]==nil);return ""joined""end};local function " &
         "f()local a=setmetatable({},mt);local b=setmetata" &
         "ble({},mt);weak[1]=a;weak[2]=b;return a..b end;a" &
         "ssert(f()==""joined"")");
   end Concat;

   procedure Add;
   procedure Add is
   begin
      --  Arithmetic relinquishes helper copies after actual operands and
      --  parameters are dropped.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__add=function(x,y)clear();x,y=nil,n" &
         "il;collectgarbage();assert(weak[1]==nil and weak" &
         "[2]==nil);return 31 end};local function f()local" &
         " a=setmetatable({},mt);local b=setmetatable({},m" &
         "t);weak[1]=a;weak[2]=b;return a+b end;assert(f()" &
         "==31)");
   end Add;

   procedure Length;
   procedure Length is
   begin
      --  Unary length relinquishes its duplicated private arguments after
      --  the handler owns them.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__len=function(x,y)clear();x,y=nil,n" &
         "il;collectgarbage();assert(weak[1]==nil);return " &
         "31 end};local function f()local a=setmetatable({" &
         "},mt);weak[1]=a;return #a end;assert(f()==31)");
   end Length;

   procedure Index;
   procedure Index is
   begin
      --  An index helper relinquishes its receiver once the real handler
      --  owns the argument.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__index=function(x,k)clear();x,k=nil" &
         ",nil;collectgarbage();assert(weak[1]==nil);retur" &
         "n 31 end};local function f()local a=setmetatable" &
         "({},mt);weak[1]=a;return a.key end;assert(f()==3" &
         "1)");
   end Index;

   procedure Newindex;
   procedure Newindex is
   begin
      --  A setter relinquishes receiver and value copies after the real
      --  handler owns them.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__newindex=function(x,k,v)clear();x," &
         "k,v=nil,nil,nil;collectgarbage();assert(weak[1]=" &
         "=nil and weak[2]==nil)end};local function f()loc" &
         "al a=setmetatable({},mt);local b={};weak[1]=a;we" &
         "ak[2]=b;a.key=b;return ""joined""end;assert(f()==""" &
         "joined"")");
   end Newindex;

   procedure Yield;
   procedure Yield is
   begin
      --  A suspended metamethod retains only its actual surviving operand
      --  edges.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__concat=function(x,y)clear();x,y=ni" &
         "l,nil;coroutine.yield();return ""joined""end};loca" &
         "l co=coroutine.create(function()local a=setmetat" &
         "able({},mt);local b=setmetatable({},mt);weak[1]=" &
         "a;weak[2]=b;return a..b end);assert(coroutine.re" &
         "sume(co));collectgarbage();assert(weak[1]==nil a" &
         "nd weak[2]==nil);local ok,v=coroutine.resume(co)" &
         ";assert(ok and v==""joined"")");
   end Yield;

   procedure Error;
   procedure Error is
   begin
      --  A message handler sees no stale request or operand roots after
      --  the body drops them.
      Check
        ("  local weak=setmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    for i=1,40 do local n,v=debug.getlocal(3,i);" &
         "if not n then break end" & ASCII.LF &
         "      if v==weak[1] or v==weak[2] then debug.set" &
         "local(3,i,nil)end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local mt={__concat=function(x,y)clear();x,y=ni" &
         "l,nil;error(""marker"",0)end};local function f()lo" &
         "cal a=setmetatable({},mt);local b=setmetatable({" &
         "},mt);weak[1]=a;weak[2]=b;return a..b end;local " &
         "ok,e=xpcall(f,function(e)collectgarbage();assert" &
         "(weak[1]==nil and weak[2]==nil);return e end);as" &
         "sert(not ok and e==""marker"")");
   end Error;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "metamethod roots: Concat",
         Concat'Access);
      Test_Support.Add
        (Suite, "metamethod roots: Add",
         Add'Access);
      Test_Support.Add
        (Suite, "metamethod roots: Length",
         Length'Access);
      Test_Support.Add
        (Suite, "metamethod roots: Index",
         Index'Access);
      Test_Support.Add
        (Suite, "metamethod roots: Newindex",
         Newindex'Access);
      Test_Support.Add
        (Suite, "metamethod roots: Yield",
         Yield'Access);
      Test_Support.Add
        (Suite, "metamethod roots: Error",
         Error'Access);
   end Register;
end Metamethod_Root_Tests;
