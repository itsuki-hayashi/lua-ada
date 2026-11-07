with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Loop_Close_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Empty_Numeric_Every_Instruction;
   procedure Empty_Numeric_Every_Instruction is
   begin
      --  An empty loop executes its real FORLOOP once per iteration.
      Check
        ("local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for" &
         " i=1,1000 do end;local n=a;debug.sethook();assert(1000<n " &
         "and n<1012)");
   end Empty_Numeric_Every_Instruction;

   procedure Empty_Numeric_Period_Four;
   procedure Empty_Numeric_Period_Four is
   begin
      --  Count periods follow the actual loop words without a no-op close.
      Check
        ("local a=0;debug.sethook(function()a=a+1 end,'',4);a=0;for" &
         " i=1,1000 do end;local n=a;debug.sethook();assert(250<n a" &
         "nd n<255)");
   end Empty_Numeric_Period_Four;

   procedure Empty_Numeric_Sparse_Count;
   procedure Empty_Numeric_Sparse_Count is
   begin
      --  A sparse count period remains unexpired across an empty loop.
      Check
        ("local a=0;debug.sethook(function()a=a+1 end,'',1500);a=0;" &
         "for i=1,1000 do end;local n=a;debug.sethook();assert(n==0" &
         ")");
   end Empty_Numeric_Sparse_Count;

   procedure Captured_Numeric_Cells;
   procedure Captured_Numeric_Cells is
   begin
      --  Captured controls detach before the next iteration and collection.
      Check
        ("local t={};for i=1,5 do t[i]=function()return i end;colle" &
         "ctgarbage()end;collectgarbage();for i=1,5 do assert(t[i](" &
         ")==i)end");
   end Captured_Numeric_Cells;

   procedure Captured_Generic_Cells;
   procedure Captured_Generic_Cells is
   begin
      --  Generic control captures retain their own iteration values.
      Check
        ("local t={};for i,v in ipairs({11,22,33})do t[i]=function(" &
         ")return i,v end;collectgarbage()end;collectgarbage();for " &
         "i=1,3 do local k,v=t[i]();assert(k==i and v==i*11)end");
   end Captured_Generic_Cells;

   procedure Reused_Uncaptured_Register;
   procedure Reused_Uncaptured_Register is
   begin
      --  A previous captured control cannot mark a new loop's reused slot.
      Check
        ("local t={};for i=1,2 do t[i]=function()return i end end;l" &
         "ocal a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for " &
         "i=1,1000 do end;local n=a;debug.sethook();assert(1000<n a" &
         "nd n<1012);assert(t[1]()==1 and t[2]()==2)");
   end Reused_Uncaptured_Register;

   procedure Shadowed_Control_Cell;
   procedure Shadowed_Control_Cell is
   begin
      --  A captured body-local shadow remains distinct from loop control.
      Check
        ("local t={};for i=1,3 do local i=i*10;t[#t+1]=function()re" &
         "turn i end;collectgarbage()end;for i=1,3 do assert(t[i]()" &
         "==i*10)end");
   end Shadowed_Control_Cell;

   procedure Transitive_Control_Capture;
   procedure Transitive_Control_Capture is
   begin
      --  An intermediate child captures a control used by its own child.
      Check
        ("local t={};for i=1,3 do t[i]=function()return function()r" &
         "eturn i end end end;collectgarbage();for i=1,3 do assert(" &
         "t[i]()()==i)end");
   end Transitive_Control_Capture;

   procedure Suppressed_Hook_Count_Phase;
   procedure Suppressed_Hook_Count_Phase is
   begin
      --  Suppressed Lua hook words still decrement and reset the period.
      Check
        ("local a=0;debug.sethook(function()a=a+1;local x=1 end,''," &
         "4);a=0;for i=1,1000 do end;local n=a;debug.sethook();asse" &
         "rt(330<n and n<340)");
   end Suppressed_Hook_Count_Phase;

   procedure Suppressed_Hook_Larger_Period;
   procedure Suppressed_Hook_Larger_Period is
   begin
      --  A longer hook body shifts the next callback without reentry.
      Check
        ("local a=0;debug.sethook(function()a=a+1;local x,y,z,q=1,2" &
         ",3,4 end,'',7);a=0;for i=1,1000 do end;local n=a;debug.se" &
         "thook();assert(165<n and n<172)");
   end Suppressed_Hook_Larger_Period;

   procedure Immediate_Add_Minimum;
   procedure Immediate_Add_Minimum is
   begin
      --  The signed immediate minimum reaches the real add fallback.
      Check
        ("local n=0;local x;x=setmetatable({},{__add=function(a,b)a" &
         "ssert(a==x and b==-127);n=n+1;return 9 end});local y=x+-1" &
         "27;assert(y==9 and n==1)");
   end Immediate_Add_Minimum;

   procedure Immediate_Add_Maximum;
   procedure Immediate_Add_Maximum is
   begin
      --  The signed immediate maximum reaches the real add fallback.
      Check
        ("local n=0;local x;x=setmetatable({},{__add=function(a,b)a" &
         "ssert(a==x and b==128);n=n+1;return 9 end});local y=x+128" &
         ";assert(y==9 and n==1)");
   end Immediate_Add_Maximum;

   procedure Outside_Add_Immediate;
   procedure Outside_Add_Immediate is
   begin
      --  An integer beyond the byte range keeps its register operand.
      Check
        ("local n=0;local x;x=setmetatable({},{__add=function(a,b)a" &
         "ssert(a==x and b==129);n=n+1;return 9 end});local y=x+129" &
         ";assert(y==9 and n==1)");
   end Outside_Add_Immediate;

   procedure Immediate_Add_Wrap;
   procedure Immediate_Add_Wrap is
   begin
      --  Immediate arithmetic retains Lua integer wrap and numeric type.
      Check
        ("local n=math.maxinteger;assert(n+1==math.mininteger);asse" &
         "rt(math.type(2.0+1)=='float');assert(('2'+1)==3)");
   end Immediate_Add_Wrap;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "loop close: Empty_Numeric_Every_Instruction",
         Empty_Numeric_Every_Instruction'Access);
      Test_Support.Add
        (Suite, "loop close: Empty_Numeric_Period_Four",
         Empty_Numeric_Period_Four'Access);
      Test_Support.Add
        (Suite, "loop close: Empty_Numeric_Sparse_Count",
         Empty_Numeric_Sparse_Count'Access);
      Test_Support.Add
        (Suite, "loop close: Captured_Numeric_Cells",
         Captured_Numeric_Cells'Access);
      Test_Support.Add
        (Suite, "loop close: Captured_Generic_Cells",
         Captured_Generic_Cells'Access);
      Test_Support.Add
        (Suite, "loop close: Reused_Uncaptured_Register",
         Reused_Uncaptured_Register'Access);
      Test_Support.Add
        (Suite, "loop close: Shadowed_Control_Cell",
         Shadowed_Control_Cell'Access);
      Test_Support.Add
        (Suite, "loop close: Transitive_Control_Capture",
         Transitive_Control_Capture'Access);
      Test_Support.Add
        (Suite, "loop close: Suppressed_Hook_Count_Phase",
         Suppressed_Hook_Count_Phase'Access);
      Test_Support.Add
        (Suite, "loop close: Suppressed_Hook_Larger_Period",
         Suppressed_Hook_Larger_Period'Access);
      Test_Support.Add
        (Suite, "loop close: Immediate_Add_Minimum",
         Immediate_Add_Minimum'Access);
      Test_Support.Add
        (Suite, "loop close: Immediate_Add_Maximum",
         Immediate_Add_Maximum'Access);
      Test_Support.Add
        (Suite, "loop close: Outside_Add_Immediate",
         Outside_Add_Immediate'Access);
      Test_Support.Add
        (Suite, "loop close: Immediate_Add_Wrap",
         Immediate_Add_Wrap'Access);
   end Register;
end Loop_Close_Tests;
