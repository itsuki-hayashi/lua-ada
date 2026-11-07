with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Comparison_Branch_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Live_Count_Assertion;
   procedure Live_Count_Assertion is
   begin
      --  A live count assertion consumes comparison branches directly.
      Check
        ("local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for" &
         " i=1,1000 do end;assert(1000<a and a<1012);debug.sethook(" &
         ")");
   end Live_Count_Assertion;

   procedure Live_Period_Four;
   procedure Live_Period_Four is
   begin
      --  The upstream period-four bound includes its live assertion words.
      Check
        ("local a=0;debug.sethook(function()a=a+1 end,'',4);a=0;for" &
         " i=1,1000 do end;assert(250<a and a<255);debug.sethook()");
   end Live_Period_Four;

   procedure Live_Sparse_Period;
   procedure Live_Sparse_Period is
   begin
      --  An unexpired sparse period cannot fire inside the assertion.
      Check
        ("local a=0;debug.sethook(function()a=a+1 end,'',4000);a=0;" &
         "for i=1,1000 do end;assert(a==0);debug.sethook()");
   end Live_Sparse_Period;

   procedure Equal_Branches;
   procedure Equal_Branches is
   begin
      --  Equal comparisons feed both short-circuit outcomes correctly.
      Check
        ("local a,b=1,2;local x=a==b and 13;local y=a==a and 17;loc" &
         "al z=a==b or 19;local q=a==a or 23;assert(x==false and y=" &
         "=17 and z==19 and q==true)");
   end Equal_Branches;

   procedure Not_Equal_Branches;
   procedure Not_Equal_Branches is
   begin
      --  Negated equality inverts the actual comparison branch flag.
      Check
        ("local a,b=1,2;local x=a~=b and 13;local y=a~=a and 17;loc" &
         "al z=a~=b or 19;local q=a~=a or 23;assert(x==13 and y==fa" &
         "lse and z==true and q==23)");
   end Not_Equal_Branches;

   procedure Less_Branches;
   procedure Less_Branches is
   begin
      --  Less-than comparisons retain true and false branch values.
      Check
        ("local a,b=1,2;local x=a<b and 13;local y=b<a and 17;local" &
         " z=a<b or 19;local q=b<a or 23;assert(x==13 and y==false " &
         "and z==true and q==23)");
   end Less_Branches;

   procedure Less_Equal_Branches;
   procedure Less_Equal_Branches is
   begin
      --  Less-equal comparison preserves equality and ordered outcomes.
      Check
        ("local a,b=1,2;local x=a<=a and 13;local y=b<=a and 17;loc" &
         "al z=a<=b or 19;local q=b<=a or 23;assert(x==13 and y==fa" &
         "lse and z==true and q==23)");
   end Less_Equal_Branches;

   procedure Greater_Branches;
   procedure Greater_Branches is
   begin
      --  Greater-than lowering swaps operands before its real branch.
      Check
        ("local a,b=1,2;local x=b>a and 13;local y=a>b and 17;local" &
         " z=b>a or 19;local q=a>b or 23;assert(x==13 and y==false " &
         "and z==true and q==23)");
   end Greater_Branches;

   procedure Greater_Equal_Branches;
   procedure Greater_Equal_Branches is
   begin
      --  Greater-equal lowering retains the swapped equality predicate.
      Check
        ("local a,b=1,2;local x=a>=a and 13;local y=a>=b and 17;loc" &
         "al z=b>=a or 19;local q=a>=b or 23;assert(x==13 and y==fa" &
         "lse and z==true and q==23)");
   end Greater_Equal_Branches;

   procedure Standalone_Boolean;
   procedure Standalone_Boolean is
   begin
      --  Standalone comparisons materialize actual booleans on both paths.
      Check
        ("local a,b=1,2;assert((a<b)==true and (b<a)==false);assert" &
         "((a~=a)==false and (a~=b)==true)");
   end Standalone_Boolean;

   procedure Preserved_Right_Value;
   procedure Preserved_Right_Value is
   begin
      --  A selected right operand keeps its table identity or nil value.
      Check
        ("local a,b=1,2;local t={};local x=a<b and t;local y=b<a or" &
         " t;local z=a<b and nil;assert(x==t and y==t and z==nil)");
   end Preserved_Right_Value;

   procedure Skipped_Right_Effects;
   procedure Skipped_Right_Effects is
   begin
      --  A selected left comparison prevents all right-side effects.
      Check
        ("local n=0;local function f()n=n+1;error('must skip')end;l" &
         "ocal a,b=1,2;local x=b<a and f();local y=a<b or f();asser" &
         "t(x==false and y==true and n==0)");
   end Skipped_Right_Effects;

   procedure Metamethod_Ordering;
   procedure Metamethod_Ordering is
   begin
      --  A comparison handler runs once before the selected right call.
      Check
        ("local order='';local mt={__lt=function()order=order..'c';" &
         "return true end};local a,b=setmetatable({},mt),setmetatab" &
         "le({},mt);local function f()order=order..'r';return 9 end" &
         ";local x=a<b and f();assert(x==9 and order=='cr')");
   end Metamethod_Ordering;

   procedure Yielding_Comparison;
   procedure Yielding_Comparison is
   begin
      --  A suspended comparison resumes its real branch and right value.
      Check
        ("local co=coroutine.create(function()local mt={__lt=functi" &
         "on()coroutine.yield('cmp');return true end};local a,b=set" &
         "metatable({},mt),setmetatable({},mt);return a<b and 9 end" &
         ");local ok,v=coroutine.resume(co);assert(ok and v=='cmp')" &
         ";collectgarbage();ok,v=coroutine.resume(co);assert(ok and" &
         " v==9)");
   end Yielding_Comparison;

   procedure Failing_Comparison;
   procedure Failing_Comparison is
   begin
      --  A comparison error prevents the right operand from executing.
      Check
        ("local n=0;local function f()local mt={__lt=function()erro" &
         "r(91)end};local a,b=setmetatable({},mt),setmetatable({},m" &
         "t);local function rhs()n=n+1 end;return a<b and rhs()end;" &
         "local ok,e=pcall(f);assert(not ok and e==91 and n==0)");
   end Failing_Comparison;

   procedure NaN_Booleans;
   procedure NaN_Booleans is
   begin
      --  Unordered numeric comparisons still produce proper booleans.
      Check
        ("local a=0/0;local b=1;local x=a<b and 7;local y=a>=b or 9" &
         ";local z=a~=a and 11;assert(x==false and y==9 and z==11)");
   end NaN_Booleans;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "comparison branch: Live_Count_Assertion",
         Live_Count_Assertion'Access);
      Test_Support.Add
        (Suite, "comparison branch: Live_Period_Four",
         Live_Period_Four'Access);
      Test_Support.Add
        (Suite, "comparison branch: Live_Sparse_Period",
         Live_Sparse_Period'Access);
      Test_Support.Add
        (Suite, "comparison branch: Equal_Branches",
         Equal_Branches'Access);
      Test_Support.Add
        (Suite, "comparison branch: Not_Equal_Branches",
         Not_Equal_Branches'Access);
      Test_Support.Add
        (Suite, "comparison branch: Less_Branches",
         Less_Branches'Access);
      Test_Support.Add
        (Suite, "comparison branch: Less_Equal_Branches",
         Less_Equal_Branches'Access);
      Test_Support.Add
        (Suite, "comparison branch: Greater_Branches",
         Greater_Branches'Access);
      Test_Support.Add
        (Suite, "comparison branch: Greater_Equal_Branches",
         Greater_Equal_Branches'Access);
      Test_Support.Add
        (Suite, "comparison branch: Standalone_Boolean",
         Standalone_Boolean'Access);
      Test_Support.Add
        (Suite, "comparison branch: Preserved_Right_Value",
         Preserved_Right_Value'Access);
      Test_Support.Add
        (Suite, "comparison branch: Skipped_Right_Effects",
         Skipped_Right_Effects'Access);
      Test_Support.Add
        (Suite, "comparison branch: Metamethod_Ordering",
         Metamethod_Ordering'Access);
      Test_Support.Add
        (Suite, "comparison branch: Yielding_Comparison",
         Yielding_Comparison'Access);
      Test_Support.Add
        (Suite, "comparison branch: Failing_Comparison",
         Failing_Comparison'Access);
      Test_Support.Add
        (Suite, "comparison branch: NaN_Booleans",
         NaN_Booleans'Access);
   end Register;
end Comparison_Branch_Tests;
