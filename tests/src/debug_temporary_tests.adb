with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Debug_Temporary_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Pending_Arithmetic_Value;
   procedure Pending_Arithmetic_Value is
   begin
      --  A computed left operand remains pending while the RHS calls Lua.
      --  Its first temporary immediately follows the two named parameters.
      Check
        ("local f,g;f=function()local n,v=debug.getlocal(2,3);asser" &
         "t(n=='(temporary)' and v==1);return 20 end;g=function(a,b" &
         ")return(a+1)+f()end;assert(g(0,0)==21)");
   end Pending_Arithmetic_Value;

   procedure Pending_Arithmetic_Write;
   procedure Pending_Arithmetic_Write is
   begin
      --  Editing the caller's pending temporary changes the actual operand.
      --  The arithmetic instruction must consume that same register.
      Check
        ("local f,g;f=function()assert(debug.setlocal(2,3,10)=='(te" &
         "mporary)');return 20 end;g=function(a,b)return(a+1)+f()en" &
         "d;assert(g(0,0)==30)");
   end Pending_Arithmetic_Write;

   procedure Child_Callee_Excluded;
   procedure Child_Callee_Excluded is
   begin
      --  The child's function and argument slots are not caller temporaries.
      --  Both getlocal and setlocal stop before the actual child call base.
      Check
        ("local f,g;f=function(x)assert(x==9);assert(debug.getlocal" &
         "(2,4)==nil);assert(debug.setlocal(2,4,99)==nil);assert(de" &
         "bug.getlocal(2,5)==nil);return 20 end;g=function(a,b)retu" &
         "rn(a+1)+f(9)end;assert(g(0,0)==21)");
   end Child_Callee_Excluded;

   procedure Nested_Computed_Value;
   procedure Nested_Computed_Value is
   begin
      --  Nested arithmetic reuses its still-empty result span.
      --  The RHS observes the completed left subtree in the first temporary.
      Check
        ("local f,g;f=function()local n,v=debug.getlocal(2,3);asser" &
         "t(n=='(temporary)' and v==2);debug.setlocal(2,3,7);return" &
         " 20 end;g=function(a,b)return((a+1)*2)+f()end;assert(g(0," &
         "0)==27)");
   end Nested_Computed_Value;

   procedure Direct_Local_No_Hole;
   procedure Direct_Local_No_Hole is
   begin
      --  A direct local remains a live operand without reserving a nil hole.
      --  The callee is excluded, while editing the real parameter affects add.
      Check
        ("local f,g;f=function()assert(debug.getlocal(2,3)==nil);as" &
         "sert(debug.setlocal(2,1,7)=='a');return 20 end;g=function" &
         "(a,b)return a+f()end;assert(g(0,0)==27)");
   end Direct_Local_No_Hole;

   procedure Unary_Call_No_Hole;
   procedure Unary_Call_No_Hole is
   begin
      --  A unary operand call uses the result slot as its actual call base.
      --  No pending computed value exists before that callee slot.
      Check
        ("local f,g;f=function()assert(debug.getlocal(2,3)==nil);re" &
         "turn 20 end;g=function(a,b)return -f()end;assert(g(0,0)==" &
         "-20)");
   end Unary_Call_No_Hole;

   procedure Indexed_Pending_Value;
   procedure Indexed_Pending_Value is
   begin
      --  An indexed scalar is materialized before the RHS executes.
      --  Debug writes target that real pending value, not its address inputs.
      Check
        ("local f,g;f=function()local n,v=debug.getlocal(2,3);asser" &
         "t(n=='(temporary)' and v==1);debug.setlocal(2,3,10);retur" &
         "n 20 end;g=function(a,b)return a[1]+f()end;assert(g({1},0" &
         ")==30)");
   end Indexed_Pending_Value;

   procedure Earlier_Result_Preserved;
   procedure Earlier_Result_Preserved is
   begin
      --  An earlier return-list result remains live below the next expression.
      --  Only the next pending operand is edited; the prefix result survives.
      Check
        ("local f,g;f=function()local n,v=debug.getlocal(2,3);asser" &
         "t(n=='(temporary)' and v==99);local n,v=debug.getlocal(2," &
         "4);assert(n=='(temporary)' and v==1);assert(debug.getloca" &
         "l(2,5)==nil);debug.setlocal(2,4,10);return 20 end;g=funct" &
         "ion(a,b)return 99,(a+1)+f()end;local x,y=g(0,0);assert(x=" &
         "=99 and y==30)");
   end Earlier_Result_Preserved;

   procedure Suspended_Pending_Value;
   procedure Suspended_Pending_Value is
   begin
      --  Suspension retains actual parent/child scalar call windows.
      --  Collect and edit the caller's pending operand before resuming it.
      Check
        ("local function f()coroutine.yield();return 20 end;local c" &
         "o=coroutine.create(function(a,b)return(a+1)+f()end);asser" &
         "t(coroutine.resume(co,0,0));collectgarbage();local n,v=de" &
         "bug.getlocal(co,2,3);assert(n=='(temporary)' and v==1);as" &
         "sert(debug.getlocal(co,2,4)==nil);assert(debug.setlocal(c" &
         "o,2,3,10)=='(temporary)');local ok,v=coroutine.resume(co)" &
         ";assert(ok and v==30)");
   end Suspended_Pending_Value;

   procedure Vararg_Shifted_Window;
   procedure Vararg_Shifted_Window is
   begin
      --  VARARGPREP may move the physical register base of a vararg frame.
      --  Use the real child call base and adjusted parent base for its bound.
      Check
        ("local f,g;f=function()local n,v=debug.getlocal(2,2);asser" &
         "t(n=='(vararg table)' and v==nil);local n,v=debug.getloca" &
         "l(2,3);assert(n=='(temporary)' and v==1);assert(debug.get" &
         "local(2,4)==nil);debug.setlocal(2,3,10);return 20 end;g=f" &
         "unction(a,...)return(a+1)+f()end;assert(g(0,7,8)==30)");
   end Vararg_Shifted_Window;

   procedure Managed_Pending_Value;
   procedure Managed_Pending_Value is
   begin
      --  The edited operand remains a real root across collection.
      --  Its actual metamethod identity must be consumed after the RHS.
      Check
        ("local new=setmetatable({},{__add=function()return'new'end" &
         "});local f,g;f=function()local n,v=debug.getlocal(2,3);as" &
         "sert(n=='(temporary)' and type(v)=='table');debug.setloca" &
         "l(2,3,new);collectgarbage();return 20 end;g=function(a,b)" &
         "return a[1]+f()end;local old=setmetatable({},{__add=funct" &
         "ion()return'old'end});assert(g({old},0)=='new')");
   end Managed_Pending_Value;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "debug temporary: Pending_Arithmetic_Value",
         Pending_Arithmetic_Value'Access);
      Test_Support.Add
        (Suite, "debug temporary: Pending_Arithmetic_Write",
         Pending_Arithmetic_Write'Access);
      Test_Support.Add
        (Suite, "debug temporary: Child_Callee_Excluded",
         Child_Callee_Excluded'Access);
      Test_Support.Add
        (Suite, "debug temporary: Nested_Computed_Value",
         Nested_Computed_Value'Access);
      Test_Support.Add
        (Suite, "debug temporary: Direct_Local_No_Hole",
         Direct_Local_No_Hole'Access);
      Test_Support.Add
        (Suite, "debug temporary: Unary_Call_No_Hole",
         Unary_Call_No_Hole'Access);
      Test_Support.Add
        (Suite, "debug temporary: Indexed_Pending_Value",
         Indexed_Pending_Value'Access);
      Test_Support.Add
        (Suite, "debug temporary: Earlier_Result_Preserved",
         Earlier_Result_Preserved'Access);
      Test_Support.Add
        (Suite, "debug temporary: Suspended_Pending_Value",
         Suspended_Pending_Value'Access);
      Test_Support.Add
        (Suite, "debug temporary: Vararg_Shifted_Window",
         Vararg_Shifted_Window'Access);
      Test_Support.Add
        (Suite, "debug temporary: Managed_Pending_Value",
         Managed_Pending_Value'Access);
   end Register;
end Debug_Temporary_Tests;
