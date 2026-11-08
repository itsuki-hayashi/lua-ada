with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Assignment_Phase_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Local_Environment;
   procedure Local_Environment is
   begin
      --  The RHS replaces a captured local environment before the store.
      --  A simple global target still refers to that live binding, so the
      --  replacement receives the value rather than an eager old snapshot.
      Check ("local old,new={},{};local function f()local _ENV=old;" &
        "x=(function()_ENV=new;return 41 end)()end;f();" &
        "assert(old.x==nil and new.x==41)");
   end Local_Environment;

   procedure Upvalue_Environment;
   procedure Upvalue_Environment is
   begin
      --  The same environment reference belongs to an enclosing function.
      --  Mutating its shared cell during the RHS must be visible when the
      --  inner function finally stores its short-string global field.
      Check ("local old,new={},{};do local _ENV=old;local function f()" &
        "x=(function()_ENV=new;return 42 end)()end;f()end;" &
        "assert(old.x==nil and new.x==42)");
   end Upvalue_Environment;

   procedure Local_Table_And_Key;
   procedure Local_Table_And_Key is
   begin
      --  Simple local table/key operands remain live until their store.
      --  The RHS changes both cells; neither is a computed address value
      --  that should have been copied before that callback ran.
      Check ("local old,new={},{};local t,k=old,1;t[k]=(function()" &
        "t=new;k=2;return 43 end)();assert(old[1]==nil and new[2]==43)");
   end Local_Table_And_Key;

   procedure Upvalue_Integer_Table;
   procedure Upvalue_Integer_Table is
   begin
      --  An upvalue table with a non-short-string key is materialized before
      --  the RHS. Preserve that captured receiver when the RHS changes the
      --  original cell; this differs deliberately from a short field key.
      Check ("local old,new={},{};local t=old;local function f()" &
        "t[1]=(function()t=new;return 44 end)()end;f();" &
        "assert(old[1]==44 and new[1]==nil)");
   end Upvalue_Integer_Table;

   procedure Upvalue_String_Table;
   procedure Upvalue_String_Table is
   begin
      --  A small short-string key can address the actual upvalue directly.
      --  Its table value is read at store time, after a nested RHS callback
      --  replaces that shared cell.
      Check ("local old,new={},{};local t=old;local function f()" &
        "t.x=(function()t=new;return 45 end)()end;f();" &
        "assert(old.x==nil and new.x==45)");
   end Upvalue_String_Table;

   procedure Upvalue_After_Key_Callback;
   procedure Upvalue_After_Key_Callback is
   begin
      --  The nonconstant key callback runs before forcing an upvalue table.
      --  It changes that upvalue, so the captured receiver is its new value
      --  even though later RHS effects cannot replace the captured receiver.
      Check ("local old,new={},{};local t=old;local function key()" &
        "t=new;return 1 end;local function f()t[key()]=46 end;f();" &
        "assert(old[1]==nil and new[1]==46)");
   end Upvalue_After_Key_Callback;

   procedure Parallel_Environment_Conflict;
   procedure Parallel_Environment_Conflict is
   begin
      --  A later LHS rebinds the environment before an earlier global store
      --  executes in reverse order. That explicit conflict requires a real
      --  pre-RHS snapshot even if the RHS also changes the environment cell.
      Check ("local old,new,third={},{},{};do local _ENV=old;" &
        "x,_ENV=(function()_ENV=third;return 47,new end)()end;" &
        "assert(old.x==47 and new.x==nil and third.x==nil)");
   end Parallel_Environment_Conflict;

   procedure Parallel_Table_Key_Conflict;
   procedure Parallel_Table_Key_Conflict is
   begin
      --  Both receiver and key of an earlier target conflict with later
      --  local LHS targets. Preserve their original values before the RHS,
      --  then perform the ordinary reverse-order stores.
      Check ("local old,new={},{};local t,k=old,1;" &
        "t[k],t,k=48,new,2;assert(old[1]==48 and new[2]==nil " &
        "and t==new and k==2)");
   end Parallel_Table_Key_Conflict;

   procedure Computed_Table_Order;
   procedure Computed_Table_Order is
   begin
      --  A computed base is evaluated before its key and RHS. Both later
      --  callbacks replace the source variable, but the actual computed
      --  table remains the receiver; metamethod delivery happens last.
      Check ("local trace='';local old=setmetatable({},{__newindex=" &
        "function(_,k,v)trace=trace..'s';assert(k==1 and v==49)end});" &
        "local new={};local t=old;local function base()trace=trace..'b';" &
        "return t end;local function key()trace=trace..'k';t=new;return 1 " &
        "end;local function rhs()trace=trace..'r';return 49 end;" &
        "base()[key()]=rhs();assert(trace=='bkrs' and new[1]==nil)");
   end Computed_Table_Order;

   procedure Computed_Table_Root;
   procedure Computed_Table_Root is
   begin
      --  The saved address is the only strong owner while the RHS collects.
      --  It survives that safe point and is released after the store; a weak
      --  observer must not keep this dead temporary alive afterward.
      Check ("local w=setmetatable({},{__mode='v'});local function base()" &
        "local t={};w[1]=t;return t end;base().x=(function()" &
        "collectgarbage();" &
        "assert(w[1]~=nil);return 50 end)();collectgarbage();" &
        "assert(w[1]==nil)");
   end Computed_Table_Root;

   procedure Computed_Key_Root;
   procedure Computed_Key_Root is
   begin
      --  A computed object key survives collection while the RHS executes.
      --  The target then owns it until its entries are cleared, after which
      --  the weak observer sees reclamation rather than a stale key register.
      Check ("local w=setmetatable({},{__mode='v'});local t={};" &
        "local function key()local k={};w[1]=k;return k end;" &
        "t[key()]=(function()collectgarbage();assert(w[1]~=nil);" &
        "return 51 end)();assert(t[w[1]]==51);for k in pairs(t)do " &
        "t[k]=nil end;collectgarbage();assert(w[1]==nil)");
   end Computed_Key_Root;

   procedure Local_Arithmetic_Operand;
   procedure Local_Arithmetic_Operand is
   begin
      --  A local arithmetic operand can be read from its original register.
      --  A later operand callback updates that register through a capture;
      --  copying the old value early would change the observable sum.
      Check ("local x=1;local function rhs()x=3;return 4 end;" &
        "assert(x+rhs()==7)");
   end Local_Arithmetic_Operand;

   procedure Indexed_Arithmetic_Operand;
   procedure Indexed_Arithmetic_Operand is
   begin
      --  An indexed arithmetic operand is discharged before its RHS call.
      --  Replacing the source table afterward cannot replace the scalar
      --  value already obtained from that table field.
      Check ("local t={x=1};local function rhs()t={x=3};return 4 end;" &
        "assert(t.x+rhs()==5)");
   end Indexed_Arithmetic_Operand;

   procedure Concat_Local_Snapshot;
   procedure Concat_Local_Snapshot is
   begin
      --  Concat discharges its left value into the contiguous operand range
      --  before its RHS, unlike arithmetic's direct local register operand.
      --  Retain that snapshot while the RHS callback changes the local cell.
      Check ("local x='old';local function rhs()x='new';return 'r' end;" &
        "assert(x..rhs()=='oldr')");
   end Concat_Local_Snapshot;

   procedure Multiline_Index_Phases;
   procedure Multiline_Index_Phases is
   begin
      --  Discharge the left index at the operator, the right index at its
      --  last token, then perform the operation and final assignment store.
      --  These are db.lua's generated large-gap trace phases, with small gaps.
      Check ("local co=coroutine.create(assert(load('local b={10}\n" &
        "a=b[1]\n+\nb[1]\nb=4\n')));local t={};debug.sethook(co," &
        "function(e,l)t[#t+1]=l end,'l');assert(coroutine.resume(co));" &
        "local want={1,3,4,3,4,5};assert(#t==#want);" &
        "for i=1,#t do assert(t[i]==want[i])end");
   end Multiline_Index_Phases;

   procedure Store_Current_Line;
   procedure Store_Current_Line is
   begin
      --  A multiline store invokes a Lua handler after the final RHS token.
      --  Inspect its real caller to verify error/debug attribution follows
      --  the store phase rather than the target's opening token.
      Check ("local t=setmetatable({},{__newindex=function(self,k,v)" &
        "assert(debug.getinfo(2,'l').currentline==2);rawset(self,k,v)end});" &
        "local f=assert(load('t.x=\n52\n','=store-phase','t',{t=t}));" &
        "f();assert(t.x==52)");
   end Store_Current_Line;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "assignment: live local environment",
                        Local_Environment'Access);
      Test_Support.Add (Suite, "assignment: live upvalue environment",
                        Upvalue_Environment'Access);
      Test_Support.Add (Suite, "assignment: live local table and key",
                        Local_Table_And_Key'Access);
      Test_Support.Add (Suite, "assignment: captured integer-key upvalue",
                        Upvalue_Integer_Table'Access);
      Test_Support.Add (Suite, "assignment: live string-key upvalue",
                        Upvalue_String_Table'Access);
      Test_Support.Add (Suite, "assignment: key callback precedes capture",
                        Upvalue_After_Key_Callback'Access);
      Test_Support.Add (Suite, "assignment: parallel environment conflict",
                        Parallel_Environment_Conflict'Access);
      Test_Support.Add (Suite, "assignment: parallel table and key conflicts",
                        Parallel_Table_Key_Conflict'Access);
      Test_Support.Add (Suite, "assignment: computed target effect order",
                        Computed_Table_Order'Access);
      Test_Support.Add (Suite, "assignment: computed table root lifetime",
                        Computed_Table_Root'Access);
      Test_Support.Add (Suite, "assignment: computed key root lifetime",
                        Computed_Key_Root'Access);
      Test_Support.Add (Suite, "assignment: live local arithmetic operand",
                        Local_Arithmetic_Operand'Access);
      Test_Support.Add (Suite, "assignment: captured indexed operand",
                        Indexed_Arithmetic_Operand'Access);
      Test_Support.Add (Suite, "assignment: concat local snapshot",
                        Concat_Local_Snapshot'Access);
      Test_Support.Add (Suite, "assignment: multiline index phases",
                        Multiline_Index_Phases'Access);
      Test_Support.Add (Suite, "assignment: store current line",
                        Store_Current_Line'Access);
   end Register;
end Assignment_Phase_Tests;
