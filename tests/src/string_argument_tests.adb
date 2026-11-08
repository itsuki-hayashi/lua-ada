with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body String_Argument_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Method_Self;
   procedure Method_Self is
   begin
      --  A table's colon string method diagnoses the actual bad self.
      Check
        ("do" & ASCII.LF &
         "  aaa={};setmetatable(aaa,{__index=strin" &
         "g})" & ASCII.LF &
         "  local f=assert(load([=[aaa:sub()]=],'=" &
         "string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: calling 'sub' o" &
         "n bad self (string expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "  aaa=nil" & ASCII.LF &
         "end");
   end Method_Self;

   procedure Function_Second;
   procedure Function_Second is
   begin
      --  The function form retains the second integer argument index.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub('a'," &
         "{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'sub' (number expected, got table)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Function_Second;

   procedure Method_Second;
   procedure Method_Second is
   begin
      --  A colon call removes self from the reported regular argument index.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[('a'):sub{}]=]," &
         "'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'sub' (number expected, got table)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Method_Second;

   procedure Sub_Missing_Start;
   procedure Sub_Missing_Start is
   begin
      --  Sub requires its start instead of using byte's optional default.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub('abc" &
         "')]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'sub' (number expected, got no value" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Sub_Missing_Start;

   procedure Sub_Nil_Start;
   procedure Sub_Nil_Start is
   begin
      --  An explicitly nil required start differs from an absent argument.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub('abc" &
         "',nil)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'sub' (number expected, got nil)]=]," &
         "tostring(e))" & ASCII.LF &
         "end");
   end Sub_Nil_Start;

   procedure Sub_First_Missing;
   procedure Sub_First_Missing is
   begin
      --  An absent subject is not mislabeled as a nil value.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub()]=]" &
         ",'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'sub' (string expected, got no value" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Sub_First_Missing;

   procedure Sub_Third_Type;
   procedure Sub_Third_Type is
   begin
      --  The optional end keeps its real third argument index.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub('abc" &
         "',1,false)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #3" &
         " to 'sub' (number expected, got boolean)" &
         "]=],tostring(e))" & ASCII.LF &
         "end");
   end Sub_Third_Type;

   procedure Sub_Named_Subject;
   procedure Sub_Named_Subject is
   begin
      --  String checks use the supplied raw auxiliary type name.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub(setm" &
         "etatable({},{__name='Text'}),1)]=],'=str" &
         "ing-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'sub' (string expected, got Text)]=]" &
         ",tostring(e))" & ASCII.LF &
         "end");
   end Sub_Named_Subject;

   procedure Sub_Named_Index;
   procedure Sub_Named_Index is
   begin
      --  Integer checks preserve a named wrong argument type.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.sub('abc" &
         "',setmetatable({},{__name='Position'}))]" &
         "=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'sub' (number expected, got Position" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Sub_Named_Index;

   procedure Len_Missing;
   procedure Len_Missing is
   begin
      --  Length validates its required subject through the real call origin.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.len()]=]" &
         ",'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'len' (string expected, got no value" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Len_Missing;

   procedure Len_Named;
   procedure Len_Named is
   begin
      --  Length shares the auxiliary raw type name policy.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.len(setm" &
         "etatable({},{__name='Text'}))]=],'=strin" &
         "g-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'len' (string expected, got Text)]=]" &
         ",tostring(e))" & ASCII.LF &
         "end");
   end Len_Named;

   procedure Rep_Count_Type;
   procedure Rep_Count_Type is
   begin
      --  Repeat reports its actual count argument rather than representation
      --  failure.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.rep('a'," &
         "{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'rep' (number expected, got table)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Rep_Count_Type;

   procedure Rep_Separator_Type;
   procedure Rep_Separator_Type is
   begin
      --  Repeat still validates its separator when only one repetition is
      --  needed.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.rep('a'," &
         "1,{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #3" &
         " to 'rep' (string expected, got table)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Rep_Separator_Type;

   procedure Find_Subject;
   procedure Find_Subject is
   begin
      --  Find checks its subject before its pattern and start.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.find({}," &
         "'x')]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'find' (string expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Find_Subject;

   procedure Find_Pattern;
   procedure Find_Pattern is
   begin
      --  Find reports the pattern's own string argument index.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.find('ab" &
         "c',{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'find' (string expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Find_Pattern;

   procedure Find_Start;
   procedure Find_Start is
   begin
      --  Find validates its start even for a pattern with no match.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.find('ab" &
         "c','x',{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #3" &
         " to 'find' (number expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Find_Start;

   procedure Gmatch_Subject;
   procedure Gmatch_Subject is
   begin
      --  Gmatch validates the subject before constructing an iterator.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gmatch({" &
         "},'x')]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'gmatch' (string expected, got table" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Gmatch_Subject;

   procedure Gmatch_Pattern;
   procedure Gmatch_Pattern is
   begin
      --  Gmatch reports its second string argument.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gmatch('" &
         "abc',{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'gmatch' (string expected, got table" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Gmatch_Pattern;

   procedure Gmatch_Start;
   procedure Gmatch_Start is
   begin
      --  Gmatch reports its optional initial position as an integer
      --  argument.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gmatch('" &
         "abc','x',{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #3" &
         " to 'gmatch' (number expected, got table" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Gmatch_Start;

   procedure Gmatch_Order;
   procedure Gmatch_Order is
   begin
      --  Gmatch checks the pattern before the optional initial position.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gmatch('" &
         "abc',{},false)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'gmatch' (string expected, got table" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Gmatch_Order;

   procedure Gsub_Replacement;
   procedure Gsub_Replacement is
   begin
      --  Gsub retains the replacement argument's allowed categories.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gsub('ab" &
         "c','x',false)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #3" &
         " to 'gsub' (string/function/table expect" &
         "ed, got boolean)]=],tostring(e))" & ASCII.LF &
         "end");
   end Gsub_Replacement;

   procedure Gsub_Limit;
   procedure Gsub_Limit is
   begin
      --  Gsub reports the optional maximum as the fourth argument.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gsub('ab" &
         "c','x','y',{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #4" &
         " to 'gsub' (number expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Gsub_Limit;

   procedure Gsub_Validation_Order;
   procedure Gsub_Validation_Order is
   begin
      --  Gsub validates its limit before the replacement's category.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gsub('ab" &
         "c','x',false,{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #4" &
         " to 'gsub' (number expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Gsub_Validation_Order;

   procedure Char_Representation;
   procedure Char_Representation is
   begin
      --  Char distinguishes a numeric representation failure from a wrong
      --  type.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.char(1.5" &
         ")]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'char' (number has no integer repres" &
         "entation)]=],tostring(e))" & ASCII.LF &
         "end");
   end Char_Representation;

   procedure Char_Type;
   procedure Char_Type is
   begin
      --  Char retains the auxiliary number type error.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.char(fal" &
         "se)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'char' (number expected, got boolean" &
         ")]=],tostring(e))" & ASCII.LF &
         "end");
   end Char_Type;

   procedure Char_Second;
   procedure Char_Second is
   begin
      --  Char checks copied values without retaining an indexing borrow.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.char(65," &
         "{})]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #2" &
         " to 'char' (number expected, got table)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Char_Second;

   procedure Char_Range;
   procedure Char_Range is
   begin
      --  Char reports its actual out-of-range argument after integer
      --  conversion.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.char(256" &
         ")]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'char' (value out of range)]=],tostr" &
         "ing(e))" & ASCII.LF &
         "end");
   end Char_Range;

   procedure Dump_Type;
   procedure Dump_Type is
   begin
      --  Dump requires a Lua function using its pinned special argument
      --  text.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.dump({})" &
         "]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'dump' (Lua function expected)]=],to" &
         "string(e))" & ASCII.LF &
         "end");
   end Dump_Type;

   procedure Dump_C_Function;
   procedure Dump_C_Function is
   begin
      --  Dump rejects a C function at the Lua-function argument check.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.dump(pri" &
         "nt)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'dump' (Lua function expected)]=],to" &
         "string(e))" & ASCII.LF &
         "end");
   end Dump_C_Function;

   procedure Format_Type;
   procedure Format_Type is
   begin
      --  Format validates its first value through the actual call origin.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.format(f" &
         "alse)]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'format' (string expected, got boole" &
         "an)]=],tostring(e))" & ASCII.LF &
         "end");
   end Format_Type;

   procedure Format_Missing;
   procedure Format_Missing is
   begin
      --  Format rejects a missing format instead of reading an absent slot.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.format()" &
         "]=],'=string-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and " &
         "e==[=[string-argument:1: bad argument #1" &
         " to 'format' (string expected, got no va" &
         "lue)]=],tostring(e))" & ASCII.LF &
         "end");
   end Format_Missing;

   procedure Byte_Default;
   procedure Byte_Default is
   begin
      --  Byte keeps its optional start while sub requires one.
      Check
        ("do" & ASCII.LF &
         "  assert(string.byte('abc')==97 and stri" &
         "ng.sub(123,2)=='23')" & ASCII.LF &
         "end");
   end Byte_Default;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "arguments: method self",
         Method_Self'Access);
      Test_Support.Add
        (Suite, "arguments: function second",
         Function_Second'Access);
      Test_Support.Add
        (Suite, "arguments: method second",
         Method_Second'Access);
      Test_Support.Add
        (Suite, "arguments: sub missing start",
         Sub_Missing_Start'Access);
      Test_Support.Add
        (Suite, "arguments: sub nil start",
         Sub_Nil_Start'Access);
      Test_Support.Add
        (Suite, "arguments: sub first missing",
         Sub_First_Missing'Access);
      Test_Support.Add
        (Suite, "arguments: sub third type",
         Sub_Third_Type'Access);
      Test_Support.Add
        (Suite, "arguments: sub named subject",
         Sub_Named_Subject'Access);
      Test_Support.Add
        (Suite, "arguments: sub named index",
         Sub_Named_Index'Access);
      Test_Support.Add
        (Suite, "arguments: len missing",
         Len_Missing'Access);
      Test_Support.Add
        (Suite, "arguments: len named",
         Len_Named'Access);
      Test_Support.Add
        (Suite, "arguments: rep count type",
         Rep_Count_Type'Access);
      Test_Support.Add
        (Suite, "arguments: rep separator type",
         Rep_Separator_Type'Access);
      Test_Support.Add
        (Suite, "arguments: find subject",
         Find_Subject'Access);
      Test_Support.Add
        (Suite, "arguments: find pattern",
         Find_Pattern'Access);
      Test_Support.Add
        (Suite, "arguments: find start",
         Find_Start'Access);
      Test_Support.Add
        (Suite, "arguments: gmatch subject",
         Gmatch_Subject'Access);
      Test_Support.Add
        (Suite, "arguments: gmatch pattern",
         Gmatch_Pattern'Access);
      Test_Support.Add
        (Suite, "arguments: gmatch start",
         Gmatch_Start'Access);
      Test_Support.Add
        (Suite, "arguments: gmatch order",
         Gmatch_Order'Access);
      Test_Support.Add
        (Suite, "arguments: gsub replacement",
         Gsub_Replacement'Access);
      Test_Support.Add
        (Suite, "arguments: gsub limit",
         Gsub_Limit'Access);
      Test_Support.Add
        (Suite, "arguments: gsub validation order",
         Gsub_Validation_Order'Access);
      Test_Support.Add
        (Suite, "arguments: char representation",
         Char_Representation'Access);
      Test_Support.Add
        (Suite, "arguments: char type",
         Char_Type'Access);
      Test_Support.Add
        (Suite, "arguments: char second",
         Char_Second'Access);
      Test_Support.Add
        (Suite, "arguments: char range",
         Char_Range'Access);
      Test_Support.Add
        (Suite, "arguments: dump type",
         Dump_Type'Access);
      Test_Support.Add
        (Suite, "arguments: dump c function",
         Dump_C_Function'Access);
      Test_Support.Add
        (Suite, "arguments: format type",
         Format_Type'Access);
      Test_Support.Add
        (Suite, "arguments: format missing",
         Format_Missing'Access);
      Test_Support.Add
        (Suite, "arguments: byte default",
         Byte_Default'Access);
   end Register;
end String_Argument_Tests;
