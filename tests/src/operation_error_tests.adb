with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Operation_Error_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Temporary_Right;
   procedure Temporary_Right is
   begin
      --  A convertible left operand reports the actual invalid right type.
      Check
        ("  local f=assert(load([=[return 1 .. {}]=],'=con" &
         "cat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value]=]," &
         "tostring(e))");
   end Temporary_Right;

   procedure Nil_Local;
   procedure Nil_Local is
   begin
      --  A nil local retains its real operand binding and source.
      Check
        ("  local f=assert(load([=[local x;return x .. 'a'" &
         "]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a nil value (loca" &
         "l 'x')]=],tostring(e))");
   end Nil_Local;

   procedure Stripped_Operand;
   procedure Stripped_Operand is
   begin
      --  Missing debug data keeps unknown source and no invented local
      --  name.
      Check
        ("  local f=assert(load([=[local x;return x .. 'a'" &
         "]=],'=concat'))" & ASCII.LF &
         "  f=assert(load(string.dump(f,true)))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[?:" &
         "?: attempt to concatenate a nil value]=],tostrin" &
         "g(e))");
   end Stripped_Operand;

   procedure Boolean_Global;
   procedure Boolean_Global is
   begin
      --  A failed global load keeps its current global name.
      Check
        ("  local f=assert(load([=[bad_concat=false;return" &
         " 'a' .. bad_concat]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a boolean value (" &
         "global 'bad_concat')]=],tostring(e))");
   end Boolean_Global;

   procedure First_Invalid_Left;
   procedure First_Invalid_Left is
   begin
      --  Two invalid operands report the first rather than the second.
      Check
        ("  local f=assert(load([=[local x={};return x .. " &
         "true]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (lo" &
         "cal 'x')]=],tostring(e))");
   end First_Invalid_Left;

   procedure Captured_Right;
   procedure Captured_Right is
   begin
      --  A captured concatenation operand reports its real upvalue.
      Check
        ("  local f=assert(load([=[local x={};return (func" &
         "tion()return 'a'..x end)()]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (up" &
         "value 'x')]=],tostring(e))");
   end Captured_Right;

   procedure Field_Right;
   procedure Field_Right is
   begin
      --  A loaded table field retains its field provenance.
      Check
        ("  local f=assert(load([=[local t={x={}};return '" &
         "a'..t.x]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (fi" &
         "eld 'x')]=],tostring(e))");
   end Field_Right;

   procedure Integer_Field;
   procedure Integer_Field is
   begin
      --  Integer table lookup uses the actual integer-index description.
      Check
        ("  local f=assert(load([=[local t={{}};return 'a'" &
         "..t[1]]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (fi" &
         "eld 'integer index')]=],tostring(e))");
   end Integer_Field;

   procedure Right_Fold;
   procedure Right_Fold is
   begin
      --  A grouped CONCAT reports the actual failing rightmost pair.
      Check
        ("  local f=assert(load([=[local a={};local b={};r" &
         "eturn a..'x'..b]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (lo" &
         "cal 'b')]=],tostring(e))");
   end Right_Fold;

   procedure Intermediate_Result;
   procedure Intermediate_Result is
   begin
      --  A later fold resolves the real overwritten register after a
      --  handler.
      Check
        ("  local f=assert(load([=[local b=setmetatable({}" &
         ",{__concat=function()return {}end});return 'x'.." &
         "b..'y']=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (lo" &
         "cal 'b')]=],tostring(e))");
   end Intermediate_Result;

   procedure Named_Type;
   procedure Named_Type is
   begin
      --  Raw string __name controls the diagnostic type description.
      Check
        ("  local f=assert(load([=[local x=setmetatable({}" &
         ",{__name='Box'});return 1 .. x]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a Box value (loca" &
         "l 'x')]=],tostring(e))");
   end Named_Type;

   procedure Nul_Type;
   procedure Nul_Type is
   begin
      --  Diagnostic use of a counted __name stops at its C-string NUL
      --  boundary.
      Check
        ("  local f=assert(load([=[local x=setmetatable({}" &
         ",{__name='A\0B'});return 1 .. x]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a A value (local " &
         "'x')]=],tostring(e))");
   end Nul_Type;

   procedure Nonstring_Type;
   procedure Nonstring_Type is
   begin
      --  A nonstring __name preserves the primitive table category.
      Check
        ("  local f=assert(load([=[local x=setmetatable({}" &
         ",{__name=false});return 1 .. x]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to concatenate a table value (lo" &
         "cal 'x')]=],tostring(e))");
   end Nonstring_Type;

   procedure Call_Nul_Type;
   procedure Call_Nul_Type is
   begin
      --  The shared type diagnostic obeys the same NUL boundary for call
      --  errors.
      Check
        ("  local f=assert(load([=[local x=setmetatable({}" &
         ",{__name='A\0B'});x()]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:1: attempt to call a A value (local 'x')]=]" &
         ",tostring(e))");
   end Call_Nul_Type;

   procedure Multiline_Operand;
   procedure Multiline_Operand is
   begin
      --  The failure source is the current CONCAT line.
      Check
        ("  local f=assert(load([=[local x={}" & ASCII.LF &
         "local y='a'" & ASCII.LF &
         "return y..x]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:3: attempt to concatenate a table value (lo" &
         "cal 'x')]=],tostring(e))");
   end Multiline_Operand;

   procedure Grouped_Source_Line;
   procedure Grouped_Source_Line is
   begin
      --  A merged right-associated run retains its inner CONCAT source
      --  line.
      Check
        ("  local f=assert(load([=[local a={};local b={};l" &
         "ocal c={}" & ASCII.LF &
         "return a .." & ASCII.LF &
         "b .." & ASCII.LF &
         "c]=],'=concat'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[co" &
         "ncat:3: attempt to concatenate a table value (lo" &
         "cal 'b')]=],tostring(e))");
   end Grouped_Source_Line;

   procedure Capture_Before_RHS;
   procedure Capture_Before_RHS is
   begin
      --  The left value is captured before a later callback mutates its
      --  binding.
      Check
        ("  local x='old';local function rhs()x='new';retu" &
         "rn 'right'end" & ASCII.LF &
         "  local result=x..rhs();assert(result=='oldright" &
         "' and x=='new')");
   end Capture_Before_RHS;

   procedure Active_Destination;
   procedure Active_Destination is
   begin
      --  Concatenation cannot overwrite its destination binding before RHS
      --  evaluation.
      Check
        ("  local x='old';local y='right'" & ASCII.LF &
         "  x='left'..(function()assert(x=='old' and y=='r" &
         "ight');return y end)()" & ASCII.LF &
         "  assert(x=='leftright' and y=='right')");
   end Active_Destination;

   procedure Right_Run_Order;
   procedure Right_Run_Order is
   begin
      --  All right-associated operand expressions precede the first
      --  handler.
      Check
        ("  local events={};local mt" & ASCII.LF &
         "  mt={__concat=function(x,y)events[#events+1]=x." &
         "id..y.id;return setmetatable({id='r'},mt)end}" & ASCII.LF &
         "  local a=setmetatable({id='a'},mt);local b=setm" &
         "etatable({id='b'},mt)" & ASCII.LF &
         "  local function rhs()events[#events+1]='c';retu" &
         "rn setmetatable({id='c'},mt)end" & ASCII.LF &
         "  local result=a..b..rhs();assert(result.id=='r'" &
         " and table.concat(events,',')=='c,bc,ar')");
   end Right_Run_Order;

   procedure Parenthesized_Left_Order;
   procedure Parenthesized_Left_Order is
   begin
      --  A parenthesized left concatenation finishes before the outer RHS.
      Check
        ("  local events={};local mt" & ASCII.LF &
         "  mt={__concat=function(x,y)events[#events+1]=x." &
         "id..y.id;return setmetatable({id='r'},mt)end}" & ASCII.LF &
         "  local a=setmetatable({id='a'},mt);local b=setm" &
         "etatable({id='b'},mt)" & ASCII.LF &
         "  local function rhs()events[#events+1]='c';retu" &
         "rn setmetatable({id='c'},mt)end" & ASCII.LF &
         "  local result=(a..b)..rhs();assert(result.id=='" &
         "r' and table.concat(events,',')=='ab,c,rc')");
   end Parenthesized_Left_Order;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "operation error: Temporary_Right",
         Temporary_Right'Access);
      Test_Support.Add
        (Suite, "operation error: Nil_Local",
         Nil_Local'Access);
      Test_Support.Add
        (Suite, "operation error: Stripped_Operand",
         Stripped_Operand'Access);
      Test_Support.Add
        (Suite, "operation error: Boolean_Global",
         Boolean_Global'Access);
      Test_Support.Add
        (Suite, "operation error: First_Invalid_Left",
         First_Invalid_Left'Access);
      Test_Support.Add
        (Suite, "operation error: Captured_Right",
         Captured_Right'Access);
      Test_Support.Add
        (Suite, "operation error: Field_Right",
         Field_Right'Access);
      Test_Support.Add
        (Suite, "operation error: Integer_Field",
         Integer_Field'Access);
      Test_Support.Add
        (Suite, "operation error: Right_Fold",
         Right_Fold'Access);
      Test_Support.Add
        (Suite, "operation error: Intermediate_Result",
         Intermediate_Result'Access);
      Test_Support.Add
        (Suite, "operation error: Named_Type",
         Named_Type'Access);
      Test_Support.Add
        (Suite, "operation error: Nul_Type",
         Nul_Type'Access);
      Test_Support.Add
        (Suite, "operation error: Nonstring_Type",
         Nonstring_Type'Access);
      Test_Support.Add
        (Suite, "operation error: Call_Nul_Type",
         Call_Nul_Type'Access);
      Test_Support.Add
        (Suite, "operation error: Multiline_Operand",
         Multiline_Operand'Access);
      Test_Support.Add
        (Suite, "operation error: Grouped_Source_Line",
         Grouped_Source_Line'Access);
      Test_Support.Add
        (Suite, "operation error: Capture_Before_RHS",
         Capture_Before_RHS'Access);
      Test_Support.Add
        (Suite, "operation error: Active_Destination",
         Active_Destination'Access);
      Test_Support.Add
        (Suite, "operation error: Right_Run_Order",
         Right_Run_Order'Access);
      Test_Support.Add
        (Suite, "operation error: Parenthesized_Left_Order",
         Parenthesized_Left_Order'Access);
   end Register;
end Operation_Error_Tests;
