with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Sort_Argument_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Missing_Receiver;
   procedure Missing_Receiver is
   begin
      --  A missing sequence uses the actual first argument and absent-value
      --  type.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort()]=]" &
         ",'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #1 to 'sort' (table expe" &
         "cted, got no value)]=],tostring(e))" & ASCII.LF &
         "end");
   end Missing_Receiver;

   procedure Nil_Receiver;
   procedure Nil_Receiver is
   begin
      --  An explicitly nil sequence differs from an absent sequence.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort(nil)" &
         "]=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #1 to 'sort' (table expe" &
         "cted, got nil)]=],tostring(e))" & ASCII.LF &
         "end");
   end Nil_Receiver;

   procedure Number_Receiver;
   procedure Number_Receiver is
   begin
      --  The ordinary table capability gate retains its auxiliary type
      --  error.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort(7)]=" &
         "],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #1 to 'sort' (table expe" &
         "cted, got number)]=],tostring(e))" & ASCII.LF &
         "end");
   end Number_Receiver;

   procedure Named_Receiver;
   procedure Named_Receiver is
   begin
      --  A non-table receiver retains its raw auxiliary type name.
      Check
        ("do" & ASCII.LF &
         "  local previous=debug.getmetatable(fals" &
         "e);debug.setmetatable(false,{__name='Seq" &
         "uence'})" & ASCII.LF &
         "  local f=assert(load([=[table.sort(fals" &
         "e)]=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  debug.setmetatable(false,previous)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #1 to 'sort' (table expe" &
         "cted, got Sequence)]=],tostring(e))" & ASCII.LF &
         "end");
   end Named_Receiver;

   procedure Comparator_Type;
   procedure Comparator_Type is
   begin
      --  The nontrivial comparator check diagnoses its real second argument.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort({2,1" &
         "},{})]=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #2 to 'sort' (function e" &
         "xpected, got table)]=],tostring(e))" & ASCII.LF &
         "end");
   end Comparator_Type;

   procedure Named_Comparator;
   procedure Named_Comparator is
   begin
      --  Comparator validation preserves a named invalid type.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort({2,1" &
         "},setmetatable({},{__name='Ordering'}))]" &
         "=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #2 to 'sort' (function e" &
         "xpected, got Ordering)]=],tostring(e))" & ASCII.LF &
         "end");
   end Named_Comparator;

   procedure Callable_Comparator;
   procedure Callable_Comparator is
   begin
      --  A callable table still fails the pinned actual-function comparator
      --  check.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort({2,1" &
         "},setmetatable({},{__call=function()retu" &
         "rn false end}))]=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #2 to 'sort' (function e" &
         "xpected, got table)]=],tostring(e))" & ASCII.LF &
         "end");
   end Callable_Comparator;

   procedure Nested_Sort;
   procedure Nested_Sort is
   begin
      --  Sort used as a C comparator resolves its actual registry function
      --  name.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort({1,2" &
         ",3},table.sort)]=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[bad argument #" &
         "1 to 'table.sort' (table expected, got n" &
         "umber)]=],tostring(e))" & ASCII.LF &
         "end");
   end Nested_Sort;

   procedure Array_Size;
   procedure Array_Size is
   begin
      --  An oversized length reports the first argument before comparator
      --  validation.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[table.sort(setm" &
         "etatable({},{__len=function()return 2147" &
         "483647 end}))]=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: bad argument #1 to 'sort' (array too " &
         "big)]=],tostring(e))" & ASCII.LF &
         "end");
   end Array_Size;

   procedure Method_Self;
   procedure Method_Self is
   begin
      --  A method capability failure diagnoses the actual bad self.
      Check
        ("do" & ASCII.LF &
         "  string.sort=table.sort" & ASCII.LF &
         "  local f=assert(load([=[('abc'):sort()]" &
         "=],'=sort-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  string.sort=nil" & ASCII.LF &
         "  assert(not ok and e==[=[sort-argument:" &
         "1: calling 'sort' on bad self (table exp" &
         "ected, got string)]=],tostring(e))" & ASCII.LF &
         "end");
   end Method_Self;

   procedure Trivial_Empty;
   procedure Trivial_Empty is
   begin
      --  An empty interval does not validate an unused comparator.
      Check
        ("do" & ASCII.LF &
         "  local t={};table.sort(t,{});assert(#t=" &
         "=0)" & ASCII.LF &
         "end");
   end Trivial_Empty;

   procedure Trivial_Single;
   procedure Trivial_Single is
   begin
      --  A singleton retains the early return before comparator type checks.
      Check
        ("do" & ASCII.LF &
         "  local t={7};table.sort(t,{});assert(t[" &
         "1]==7)" & ASCII.LF &
         "end");
   end Trivial_Single;

   procedure Optional_Nil;
   procedure Optional_Nil is
   begin
      --  An explicit nil comparator uses the default comparison normally.
      Check
        ("do" & ASCII.LF &
         "  local t={2,1};table.sort(t,nil);assert" &
         "(t[1]==1 and t[2]==2)" & ASCII.LF &
         "end");
   end Optional_Nil;

   procedure Length_First;
   procedure Length_First is
   begin
      --  A real length callback throws before an invalid comparator is
      --  checked.
      Check
        ("do" & ASCII.LF &
         "  local marker={};local t=setmetatable({" &
         "},{__len=function()error(marker,0)end})" & ASCII.LF &
         "  local ok,e=pcall(table.sort,t,{});asse" &
         "rt(not ok and e==marker)" & ASCII.LF &
         "end");
   end Length_First;

   procedure Registry_Roots;
   procedure Registry_Roots is
   begin
      --  Failed sort captures release operands removed from all actual
      --  slots.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local load" &
         "ed,mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "});local calls=0" & ASCII.LF &
         "  local function make()local value={};we" &
         "ak[1]=value;return value end" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=" &
         "function(_,k)" & ASCII.LF &
         "    assert(k=='_LOADED' and debug.getinf" &
         "o(2,'f').func==table.sort)" & ASCII.LF &
         "    assert(debug.setlocal(2,2,nil)=='(C " &
         "temporary)')" & ASCII.LF &
         "    collectgarbage();assert(weak[1]==nil" &
         ");calls=calls+1" & ASCII.LF &
         "    return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(table.sort,{2,1},make" &
         "())" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==1 and e==""bad" &
         " argument #2 to 'table.sort' (function e" &
         "xpected, got table)"",tostring(e))" & ASCII.LF &
         "end");
   end Registry_Roots;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "sort arguments: missing receiver",
         Missing_Receiver'Access);
      Test_Support.Add
        (Suite, "sort arguments: nil receiver",
         Nil_Receiver'Access);
      Test_Support.Add
        (Suite, "sort arguments: number receiver",
         Number_Receiver'Access);
      Test_Support.Add
        (Suite, "sort arguments: named receiver",
         Named_Receiver'Access);
      Test_Support.Add
        (Suite, "sort arguments: comparator type",
         Comparator_Type'Access);
      Test_Support.Add
        (Suite, "sort arguments: named comparator",
         Named_Comparator'Access);
      Test_Support.Add
        (Suite, "sort arguments: callable comparator",
         Callable_Comparator'Access);
      Test_Support.Add
        (Suite, "sort arguments: nested sort",
         Nested_Sort'Access);
      Test_Support.Add
        (Suite, "sort arguments: array size",
         Array_Size'Access);
      Test_Support.Add
        (Suite, "sort arguments: method self",
         Method_Self'Access);
      Test_Support.Add
        (Suite, "sort arguments: trivial empty",
         Trivial_Empty'Access);
      Test_Support.Add
        (Suite, "sort arguments: trivial single",
         Trivial_Single'Access);
      Test_Support.Add
        (Suite, "sort arguments: optional nil",
         Optional_Nil'Access);
      Test_Support.Add
        (Suite, "sort arguments: length first",
         Length_First'Access);
      Test_Support.Add
        (Suite, "sort arguments: registry roots",
         Registry_Roots'Access);
   end Register;
end Sort_Argument_Tests;
