with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Assert_Argument_Tests is
   Prelude : constant String :=
     "local cases={" & ASCII.LF &
     " function()" & ASCII.LF &
     "  local ok,e=pcall(assert)" & ASCII.LF &
     "  assert(not ok and e==""bad argument #1 to " &
     "'assert' (value expected)"")" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local f=assert" & ASCII.LF &
     "  local ok,e=pcall(function()f()end)" & ASCII.LF &
     "  assert(not ok and e:find(""to 'f' %(value " &
     "expected%)$""))" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local registry=debug.getregistry()" & ASCII.LF &
     "  local loaded=rawget(registry,'_LOADED')" & ASCII.LF &
     "  local meta=getmetatable(registry)" & ASCII.LF &
     "  local calls=0" & ASCII.LF &
     "  rawset(registry,'_LOADED',nil)" & ASCII.LF &
     "  setmetatable(registry,{__index=function(_,key)" & ASCII.LF &
     "   assert(key=='_LOADED')" & ASCII.LF &
     "   calls=calls+1" & ASCII.LF &
     "   collectgarbage()" & ASCII.LF &
     "   return {_G={probe=assert}}" & ASCII.LF &
     "  end})" & ASCII.LF &
     "  local ok,e=pcall(assert)" & ASCII.LF &
     "  rawset(registry,'_LOADED',loaded)" & ASCII.LF &
     "  setmetatable(registry,meta)" & ASCII.LF &
     "  assert(not ok and calls==1 and e==""bad " &
     "argument #1 to 'probe' (value expected)"")" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local ok,e=pcall(assert,nil,nil)" & ASCII.LF &
     "  assert(not ok and type(e)=='string' and not " &
     "e:find('value expected'))" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local values=table.pack(assert(true,nil,37,nil))" & ASCII.LF &
     "  assert(values.n==4 and values[1]==true and " &
     "values[2]==nil)" & ASCII.LF &
     "  assert(values[3]==37 and values[4]==nil)" & ASCII.LF &
     " end," & ASCII.LF &
     "}" & ASCII.LF;
   procedure Check (Which : Positive);
   procedure Missing;
   procedure Alias_Name;
   procedure Registry_Callback;
   procedure Explicit_Nil;
   procedure Success_Tuple;

   procedure Check (Which : Positive) is
      State : Session;
      Result : constant Execution_Result := State.Execute
        (Prelude & "cases[" & Positive'Image (Which) & "]()");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Missing differs from false/nil and uses the actual auxiliary formatter.
   procedure Missing is
   begin
      Check (1);
   end Missing;

   --  A direct Lua alias contributes its real call-origin name.
   procedure Alias_Name is
   begin
      Check (2);
   end Alias_Name;

   --  An unnamed C-origin call drives the collecting registry continuation.
   procedure Registry_Callback is
   begin
      Check (3);
   end Registry_Callback;

   --  Explicit nil remains an assertion failure rather than a missing value.
   procedure Explicit_Nil is
   begin
      Check (4);
   end Explicit_Nil;

   --  Truthy assertions retain every return value, including trailing nils.
   procedure Success_Tuple is
   begin
      Check (5);
   end Success_Tuple;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "assert arguments: missing value",
                        Missing'Access);
      Test_Support.Add (Suite, "assert arguments: direct alias name",
                        Alias_Name'Access);
      Test_Support.Add (Suite, "assert arguments: registry callback",
                        Registry_Callback'Access);
      Test_Support.Add (Suite, "assert arguments: explicit nil",
                        Explicit_Nil'Access);
      Test_Support.Add (Suite, "assert arguments: successful nil tuple",
                        Success_Tuple'Access);
   end Register;
end Assert_Argument_Tests;
