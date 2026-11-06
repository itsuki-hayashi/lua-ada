with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Lua.Runtime_Configuration;
with Ada.Strings.Fixed;
with Test_Support;

package body Lua.Window_Execution_Tests is
   LF : constant Character := Character'Val (10);

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Overlapping_Collection;
   procedure Overlapping_Collection is
   begin
      --  A wide parent calls a smaller child which collects with a live
      --  table.
      --  Clearing the parent dead tail must not clear overlapping child
      --  registers.
      Check
        ("local weak=setmetatable({},{__mode='v'})" & LF &
         "local function child()" & LF &
         "local keep={answer=42};weak[1]=keep;collectgarbage()" & LF &
         "assert(weak[1]==keep);return keep end" & LF &
         "local function parent()" & LF &
         "do local t={1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1," & LF &
         "1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1," & LF &
         "1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1," & LF &
         "1,1,1,1,1,1,1,1,1,1,1}" & LF &
         "assert(#t==80)end" & LF &
         "local keep=child();collectgarbage();return keep end" & LF &
         "assert(parent().answer==42)");
   end Overlapping_Collection;

   procedure Discarded_Arguments;
   procedure Discarded_Arguments is
   begin
      --  Pass an object as an excess argument to a zero-parameter function.
      --  Once the callee owns the call window, discarded argument packets do
      --  not root it.
      Check
        ("local weak=setmetatable({},{__mode='v'})" & LF &
         "local function make()local t={};weak[1]=t;return t end" & LF &
         "local function discard()collectgarbage()" & LF &
         "assert(weak[1]==nil)end" & LF &
         "discard(make())");
   end Discarded_Arguments;

   procedure Hidden_Argument_Root;
   procedure Hidden_Argument_Root is
   begin
      --  Keep an otherwise unreachable table only in unnamed varargs.
      --  Collection traces the hidden prefix below the shifted register
      --  base.
      Check
        ("local weak=setmetatable({},{__mode='v'})" & LF &
         "local function make()local t={answer=42}" & LF &
         "weak[1]=t;return t end" & LF &
         "local function hidden(head,...)" & LF &
         "collectgarbage();assert(head==17)" & LF &
         "local t,a,b=...;assert(t==weak[1] and t.answer==42)" & LF &
         "assert(a==nil and b==99)end" & LF &
         "hidden(17,make(),nil,99)");
   end Hidden_Argument_Root;

   procedure Named_First_Argument;
   procedure Named_First_Argument is
   begin
      --  Create a named vararg table whose first extra is an object.
      --  Construction reads the first extra before replacing its stack slot
      --  with the table.
      Check
        ("local weak=setmetatable({},{__mode='v'})" & LF &
         "local function make()local t={answer=42}" & LF &
         "weak[1]=t;return t end" & LF &
         "local function named(head,...values)" & LF &
         "assert(type(values)=='table')" & LF &
         "collectgarbage();assert(head==17 and values.n==3)" & LF &
         "assert(values[1]==weak[1] and values[1].answer==42)" & LF &
         "assert(values[2]==nil and values[3]==99)end" & LF &
         "named(17,make(),nil,99)");
   end Named_First_Argument;

   procedure Hidden_Debug_Mutation;
   procedure Hidden_Debug_Mutation is
   begin
      --  Change a hidden vararg through negative debug local indexing.
      --  Later GETVARG and expansion read the same physical argument slot.
      Check
        ("local function hidden(...)" & LF &
         "local name,old=debug.getlocal(1,-1)" & LF &
         "assert(name=='(vararg)' and old==17)" & LF &
         "assert(debug.setlocal(1,-1,42)=='(vararg)')" & LF &
         "local first,second=...;assert(first==42 and second==99)end" & LF &
         "hidden(17,99)");
   end Hidden_Debug_Mutation;

   procedure Named_Debug_Boundary;
   procedure Named_Debug_Boundary is
   begin
      --  Force a named vararg table to escape before negative debug
      --  inspection.
      --  An actual table is not hidden vararg storage; named syntax alone
      --  can optimize away.
      Check
        ("local function named(...values)" & LF &
         "assert(type(values)=='table')" & LF &
         "assert(debug.getlocal(1,-1)==nil)" & LF &
         "assert(values[1]==17 and values.n==2)end" & LF &
         "named(17,99)");
   end Named_Debug_Boundary;

   procedure Generic_Iterator_Window;
   procedure Generic_Iterator_Window is
   begin
      --  Run an allocating iterator with a fourth closing value.
      --  TFORCALL preserves function/state/closer while using the actual
      --  copied call area.
      Check
        ("local closed=false;local state={limit=4}" & LF &
         "local closer=setmetatable({},{__close=function(_,e)" & LF &
         "assert(e==nil);closed=true end})" & LF &
         "local function iter(s,k)collectgarbage()" & LF &
         "assert(s==state)" & LF &
         "if k<s.limit then return k+1,{value=k+1}end end" & LF &
         "local sum=0" & LF &
         "for k,v in iter,state,0,closer do sum=sum+k+v.value end" & LF &
         "assert(sum==20 and closed)");
   end Generic_Iterator_Window;

   procedure Native_Tail_Frame;
   procedure Native_Tail_Frame is
   begin
      --  Inspect a Lua caller while its native tail target invokes a
      --  metamethod.
      --  The Lua-to-native tail continuation preserves the actual caller
      --  until return.
      Check
        ("local tailer" & LF &
         "local value=setmetatable({},{__tostring=function()" & LF &
         "local seen=false" & LF &
         "for level=1,12 do local info=debug.getinfo(level,'f')" & LF &
         "if info and info.func==tailer then seen=true end end" & LF &
         "assert(seen);return 'ok' end})" & LF &
         "tailer=function(v)return tostring(v)end" & LF &
         "assert(tailer(value)=='ok')");
   end Native_Tail_Frame;

   procedure Native_Tail_Suspension;
   procedure Native_Tail_Suspension is
   begin
      --  Tail-call coroutine.yield and resume with multiple values.
      --  The retained native-tail phase returns resumed values once without
      --  losing nils.
      Check
        ("local function tailer(...)return coroutine.yield(...)end" & LF &
         "local co=coroutine.create(function()" & LF &
         "local a,b,c=tailer(17,nil,99)" & LF &
         "assert(a==42 and b==nil and c==7);return a,b,c end)" & LF &
         "local ok,a,b,c=coroutine.resume(co)" & LF &
         "assert(ok and a==17 and b==nil and c==99)" & LF &
         "local done,x,y,z=coroutine.resume(co,42,nil,7)" & LF &
         "assert(done and x==42 and y==nil and z==7)" & LF &
         "assert(coroutine.status(co)=='dead')");
   end Native_Tail_Suspension;

   procedure Open_Result_Window;
   procedure Open_Result_Window is
   begin
      --  Return enough results to extend a caller beyond maxstacksize.
      --  Open adjustment uses the shared growing arena and fixed adjustment
      --  discards its tail.
      Check
        ("local function many()" & LF &
         "return table.unpack({1,2,3,4,5,6,7,8})end" & LF &
         "local function identity(...)collectgarbage();return...end" & LF &
         "local t=table.pack(identity(many()))" & LF &
         "assert(t.n==8 and t[1]==1 and t[8]==8)" & LF &
         "local x,y=many();assert(x==1 and y==2)");
   end Open_Result_Window;

   procedure Deep_Pure_Lua;
   procedure Deep_Pure_Lua is
      Universe : Session;
      Result : Execution_Result;
      Depth : constant Natural :=
        Lua.Runtime_Configuration.Maximum_Stack / 16;
      Count : constant String := Ada.Strings.Fixed.Trim
        (Depth'Image, Ada.Strings.Both);
   begin
      --  Pure Lua recursion consumes actual overlapping register windows,
      --  not a minimum twenty-slot native reservation for every Lua frame.
      --  Scale depth with the selected native configuration: one sixteenth
      --  fits both real Lua window layouts but exceeds the old summed floor.
      --  Keep bounded Ada-session defaults unchanged elsewhere.
      Universe.Set_Execution_Policy (Lua_Compatible);
      Result := Universe.Execute
        ("local function deep(n) if n==0 then return 0 end;" &
         "return 1+deep(n-1) end;assert(deep(" & Count & ")==" &
         Count & ")");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Deep_Pure_Lua;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "windows: overlapping collection",
         Overlapping_Collection'Access);
      Test_Support.Add
        (Suite, "windows: discarded arguments",
         Discarded_Arguments'Access);
      Test_Support.Add
        (Suite, "windows: hidden argument root",
         Hidden_Argument_Root'Access);
      Test_Support.Add
        (Suite, "windows: named first argument",
         Named_First_Argument'Access);
      Test_Support.Add
        (Suite, "windows: hidden debug mutation",
         Hidden_Debug_Mutation'Access);
      Test_Support.Add
        (Suite, "windows: named debug boundary",
         Named_Debug_Boundary'Access);
      Test_Support.Add
        (Suite, "windows: generic iterator window",
         Generic_Iterator_Window'Access);
      Test_Support.Add
        (Suite, "windows: native tail frame",
         Native_Tail_Frame'Access);
      Test_Support.Add
        (Suite, "windows: native tail suspension",
         Native_Tail_Suspension'Access);
      Test_Support.Add
        (Suite, "windows: open result window",
         Open_Result_Window'Access);
      Test_Support.Add
        (Suite, "windows: deep pure Lua", Deep_Pure_Lua'Access);
   end Register;
end Lua.Window_Execution_Tests;
