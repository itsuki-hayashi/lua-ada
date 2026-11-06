with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Test_Support;

package body Lua.Debug_Uservalue_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      State : World;
      Item : Value;
   begin
      Initialize (State, (others => <>));
      begin
         --  The test supplies a real full userdata without exposing private
         --  object handles in the public Ada embedding interface. Publish it
         --  through an ordinary traced table before running any Lua code.
         Begin_Operation (State);
         Item := New_Userdata (State, 8, 2);
         Set (State, Global_Environment (State), New_String (State, "u"),
              Item);
         End_Operation (State);
         Assert (Execute (State, Source, "debug-uservalues"),
                 To_String (State.Current.Failure_Text));
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
   end Check;

   procedure Existing_Nil_Slot;
   procedure Existing_Nil_Slot is
   begin
      --  Create full userdata with two initially nil slots.
      --  Read an existing nil slot and an out-of-range slot.
      --  Only the former supplies the second true existence result.
      Check
        ("local t=table.pack(debug.getuservalue(u));assert(t.n==2 a" &
         "nd t[1]==nil and t[2]==true);local a=table.pack(debug.get" &
         "uservalue(u,3));assert(a.n==1 and a[1]==nil)");
   end Existing_Nil_Slot;

   procedure Actual_Slot_Mutation;
   procedure Actual_Slot_Mutation is
   begin
      --  Retain userdata through its ordinary global owner.
      --  Set a table value and read it through the public debug library.
      --  The operation returns the same userdata and stores the same table.
      Check
        ("local t={answer=42};assert(debug.setuservalue(u,t,2)==u);" &
         "local x,exists=debug.getuservalue(u,2);assert(x==t and ex" &
         "ists and x.answer==42)");
   end Actual_Slot_Mutation;

   procedure Invalid_Slot_Result;
   procedure Invalid_Slot_Result is
   begin
      --  Use zero, negative, and past-end uservalue indices.
      --  Get and set each invalid slot without changing valid storage.
      --  Both APIs return exactly one nil and leave the existing value intact.
      Check
        ("assert(debug.setuservalue(u,42)==u);for _,n in ipairs{0,-" &
         "1,3}do local a=table.pack(debug.getuservalue(u,n));local " &
         "b=table.pack(debug.setuservalue(u,99,n));assert(a.n==1 an" &
         "d a[1]==nil and b.n==1 and b[1]==nil)end;assert(debug.get" &
         "uservalue(u)==42)");
   end Invalid_Slot_Result;

   procedure Native_Index_Conversion;
   procedure Native_Index_Conversion is
   begin
      --  The pinned debug library converts the optional integer to C int.
      --  Address slot one through the low-bit wrap of 2^32+1.
      --  Supported 32-bit C-int ABIs observe the same actual slot.
      Check
        ("assert(debug.setuservalue(u,42,4294967297)==u);assert(deb" &
         "ug.getuservalue(u,4294967297)==42);assert(debug.getuserva" &
         "lue(u,4294967295)==nil)");
   end Native_Index_Conversion;

   procedure Nil_Default_And_Stored_Nil;
   procedure Nil_Default_And_Stored_Nil is
   begin
      --  An explicit nil optional index selects slot one.
      --  Store nil as a real value, then query its existence.
      --  Stored nil remains distinguishable from an absent uservalue.
      Check
        ("assert(debug.setuservalue(u,42,nil)==u);assert(debug.getu" &
         "servalue(u,nil)==42);assert(debug.setuservalue(u,nil)==u)" &
         ";local x,b=debug.getuservalue(u);assert(x==nil and b==tru" &
         "e)");
   end Nil_Default_And_Stored_Nil;

   procedure Invalid_Arguments;
   procedure Invalid_Arguments is
   begin
      --  Use invalid receiver, absent set value, and noninteger index.
      --  Protect each public debug call and then perform a valid mutation.
      --  Argument errors are catchable and do not damage userdata storage.
      Check
        ("assert(select('#',debug.getuservalue({}))==1);assert(debu" &
         "g.getuservalue({})==nil);assert(not pcall(debug.setuserva" &
         "lue,{},42));assert(not pcall(debug.setuservalue,u));asser" &
         "t(not pcall(debug.getuservalue,u,false));assert(not pcall" &
         "(debug.setuservalue,u,42,1.5));assert(debug.setuservalue(" &
         "u,7)==u and debug.getuservalue(u)==7)");
   end Invalid_Arguments;

   procedure Traced_Uservalue;
   procedure Traced_Uservalue is
   begin
      --  A table has only a weak observation and its userdata slot owner.
      --  Collect before and after removing that actual slot edge.
      --  The table survives while owned and disappears after replacement.
      Check
        ("local w=setmetatable({},{__mode='v'});do local t={answer=" &
         "42};w[1]=t;debug.setuservalue(u,t)end;collectgarbage();as" &
         "sert(w[1] and w[1].answer==42);debug.setuservalue(u,nil);" &
         "collectgarbage();assert(w[1]==nil)");
   end Traced_Uservalue;

   procedure Metatable_Bypass;
   procedure Metatable_Bypass is
   begin
      --  Install index/newindex handlers that fail if called.
      --  Read and write uservalues through debug operations.
      --  Raw userdata slots operate independently of its metatable.
      Check
        ("debug.setmetatable(u,{__index=function()error('index')end" &
         ",__newindex=function()error('newindex')end});assert(debug" &
         ".setuservalue(u,42)==u);assert(debug.getuservalue(u)==42)");
   end Metatable_Bypass;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "debug userdata: existing nil returns two values",
         Existing_Nil_Slot'Access);
      Test_Support.Add
        (Suite, "debug userdata: mutate actual slot",
         Actual_Slot_Mutation'Access);
      Test_Support.Add
        (Suite, "debug userdata: invalid slot result count",
         Invalid_Slot_Result'Access);
      Test_Support.Add
        (Suite, "debug userdata: native integer index conversion",
         Native_Index_Conversion'Access);
      Test_Support.Add
        (Suite, "debug userdata: nil optional index and stored nil",
         Nil_Default_And_Stored_Nil'Access);
      Test_Support.Add
        (Suite, "debug userdata: argument failures are protected",
         Invalid_Arguments'Access);
      Test_Support.Add
        (Suite, "debug userdata: actual uservalue is traced",
         Traced_Uservalue'Access);
      Test_Support.Add
        (Suite, "debug userdata: uservalue operations bypass handlers",
         Metatable_Bypass'Access);
   end Register;
end Lua.Debug_Uservalue_Tests;
