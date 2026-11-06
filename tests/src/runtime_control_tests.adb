with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Runtime_Control_Tests is
   procedure Check (Source : String; Compatible : Boolean := False);
   procedure Hook_Empty_Configuration;
   procedure Hook_Negative_Count_Reflection;
   procedure Hook_Mask_Nul_Boundary;
   procedure Collection_Option_Nul_Boundary;
   procedure Debug_Info_Option_Nul_Boundary;
   procedure Collection_Stop_Result;
   procedure Collection_Nil_Default;
   procedure Collection_Restart_Result;
   procedure Disabled_Hook_Result;
   procedure Debug_Iterator_Native_Frame;
   procedure Yieldability_After_Completion;
   procedure Closing_Quota_Abort;
   procedure Weak_Mode_Nul_Boundary;
   procedure Debug_Split_Function_Lines;
   procedure Hook_Implicit_Return_Line;
   procedure Debug_Tail_Frame;
   procedure Close_Logical_Caller;
   procedure Debug_Literal_Source;
   procedure Debug_File_Source;
   procedure Debug_Snippet_Source;
   procedure Debug_Minimum_Vararg_Index;
   procedure Debug_Hook_Count_Range;
   procedure Debug_Traceback_Level_Range;
   procedure Policy_Restores_Bounds;
   procedure Set_Limits_Selects_Bounded;
   procedure Reset_Selects_Bounded;
   procedure Coroutine_Quota_Abort;
   procedure Stopped_GC_Across_Chunks;
   procedure Reset_Lifecycle_State;
   procedure Independent_Thread_Universes;
   procedure Table_Callback_Not_Yieldable;
   procedure Load_Reader_Not_Yieldable;
   procedure Require_Not_Yieldable;
   procedure Xpcall_Handler_Not_Yieldable;
   procedure Debug_Parameter_Name;
   procedure Debug_Invalid_Local;
   procedure Debug_Native_Upvalue;
   procedure Debug_Native_Cell_Write;
   procedure Debug_Call_Name;
   procedure Debug_Method_Name;
   procedure Hook_Backward_Line;
   procedure Hook_Tail_Call;
   procedure Hook_Collection_Roots;
   procedure Hook_No_Reentrant_Yield;
   procedure Weak_Mode_Change;
   procedure Weak_String_Keys;
   procedure Close_Generic_Break;
   procedure Close_Error_Not_Yieldable;
   procedure Coroutine_Close_Main_Error;
   procedure Native_Call_Overflow;
   procedure Thread_Identity;
   procedure Main_Identity;
   procedure Resume_Packets;
   procedure Nested_States;
   procedure Resume_Active;
   procedure Resume_Dead;
   procedure Wrap_Error_Value;
   procedure Pcall_Suspension;
   procedure Xpcall_Suspension;
   procedure Gsub_Not_Yieldable;
   procedure Metamethod_Yield;
   procedure Close_Nil_False;
   procedure Close_Invalid_Initializer;
   procedure Close_Reverse_Order;
   procedure Close_Break;
   procedure Close_Goto;
   procedure Close_Return_Values;
   procedure Close_Return_Call;
   procedure Close_Error_Replacement;
   procedure Close_Suspension;
   procedure Close_Abandoned;
   procedure Close_Wrap_Failure;
   procedure Close_Dead_Error_Once;
   procedure Close_Self;
   procedure Close_Generic_For;
   procedure Close_Generic_Empty;
   procedure Backward_Cells;
   procedure Shared_Capture_Cell;
   procedure Debug_Upvalue_Mutation;
   procedure Debug_Load_Environment;
   procedure Debug_Current_Local;
   procedure Debug_Suspended_Local;
   procedure Debug_Source_Range;
   procedure Hook_Trace;
   procedure Hook_Suppression;
   procedure Hook_Per_Thread;
   procedure Weak_Values;
   procedure Weak_Keys;
   procedure Ephemeron_Cycle;
   procedure Ephemeron_Fixed_Point;
   procedure Coroutine_Closure_Graph;
   procedure Surviving_Capture;
   procedure Collection_Control;
   procedure Collection_Unsupported;
   procedure Hook_Error_Recovery;
   procedure Close_Normal_Yield;
   procedure Close_Explicit_Not_Yieldable;
   procedure Semantic_Result_Overflow;
   procedure Debug_Traceback;

   procedure Check (Source : String; Compatible : Boolean := False) is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Every case receives an independent environment and heap. Assertions
      --  inside the source are behavioral observations, not private VM probes.
      if Compatible then
         Universe.Set_Execution_Policy (Lua_Compatible);
      end if;
      Result := Universe.Execute (Source, "runtime-control");
      Assert (Result.Status = Succeeded,
              Result.Status'Image & ": " & To_String (Result.Error.Message));
   end Check;

   procedure Thread_Identity is
      --  A fresh coroutine is an identity value and a valid table key.
      --  Create two coroutines and address a table by one.
      --  Type and equality distinguish them from tables and each other.
   begin
      Check
        ("local a=coroutine.create(function()end);" &
         " local b=coroutine.create(function()end);" &
         " local t={[a]=42};" &
         " assert(type(a)=='thread' and a~=b and t[a]==42 and " &
         "t[b]==nil)");
   end Thread_Identity;

   procedure Main_Identity is
      --  The host chunk runs in the session main thread.
      --  Query identity twice and inspect its status/yieldability.
      --  The main identity is stable and cannot yield.
   begin
      Check
        ("local a,b=coroutine.running();" &
         " assert(b and a==coroutine.running());" &
         " assert(coroutine.status(a)=='running');" &
         " assert(not coroutine.isyieldable() and not " &
         "coroutine.isyieldable(a));" &
         " assert(not pcall(coroutine.yield))");
   end Main_Identity;

   procedure Resume_Packets is
      --  A yielding body exchanges packets containing nil holes.
      --  Resume it initially and then pass three resume results.
      --  All values and result counts survive the transfer.
   begin
      Check
        ("local co=coroutine.create(function(a) local x,y," &
         "z=coroutine.yield(a,nil,3); return x,y,z end);" &
         " local r=table.pack(coroutine.resume(co,1));" &
         " assert(r.n==4 and r[1] and r[2]==1 and r[3]==nil and " &
         "r[4]==3); r=table.pack(coroutine.resume(co,4,nil,6));" &
         " assert(r.n==4 and r[2]==4 and r[3]==nil and r[4]==6)");
   end Resume_Packets;

   procedure Nested_States is
      --  A resumer remains active while a child is running.
      --  Inspect both states from a nested resume.
      --  The parent is normal until the child yields.
   begin
      Check
        ("local parent; local child=coroutine.create(function() " &
         "assert(coroutine.status(parent)=='normal');" &
         " return 9 end); parent=coroutine.create(function() " &
         "assert(coroutine.status(child)=='suspended');" &
         " local ok,v=coroutine.resume(child);" &
         " assert(ok and v==9 and coroutine.status(child)" &
         "=='dead') end); assert(coroutine.resume(parent))");
   end Nested_States;

   procedure Resume_Active is
      --  A running coroutine cannot resume itself.
      --  Attempt self-resume inside its body.
      --  The operation returns false without corrupting that body.
   begin
      Check
        ("local co; co=coroutine.create(function() local ok," &
         "e=coroutine.resume(co);" &
         " assert(not ok and type(e)=='string'); return 42 end);" &
         " local ok,v=coroutine.resume(co); assert(ok and v==42)");
   end Resume_Active;

   procedure Resume_Dead is
      --  Completion retires the body permanently.
      --  Resume a completed coroutine a second time.
      --  It returns a dead-coroutine error.
   begin
      Check
        ("local co=coroutine.create(function() return 7 end);" &
         " assert(coroutine.resume(co));" &
         " local ok,e=coroutine.resume(co);" &
         " assert(not ok and e:find('dead'))");
   end Resume_Dead;

   procedure Wrap_Error_Value is
      --  Wrapped coroutines raise arbitrary Lua error values.
      --  Raise a table inside a wrapped body under pcall.
      --  Identity is retained instead of stringifying the error.
   begin
      Check
        ("local e={}; local w=coroutine.wrap(function()error(e)" &
         "end); local ok,v=pcall(w); assert(not ok and v==e)");
   end Wrap_Error_Value;

   procedure Pcall_Suspension is
      --  A protected boundary may remain suspended.
      --  Yield inside pcall, then resume into an error.
      --  The resumed pcall returns false/error and the coroutine completes.
   begin
      Check
        ("local co=coroutine.create(function() return " &
         "pcall(function() coroutine.yield(7);" &
         " error(8) end) end); local ok,v=coroutine.resume(co);" &
         " assert(ok and v==7); local a,b,c=coroutine.resume(co);" &
         " assert(a and b==false and c==8)");
   end Pcall_Suspension;

   procedure Xpcall_Suspension is
      --  An error handler belongs to its protected activation.
      --  Suspend the protected function before raising.
      --  The handler transforms the resumed error once.
   begin
      Check
        ("local co=coroutine.create(function() return " &
         "xpcall(function() coroutine.yield(1);" &
         " error(8) end,function(e)return e+1 end) end);" &
         " assert(coroutine.resume(co));" &
         " local a,b,c=coroutine.resume(co);" &
         " assert(a and b==false and c==9)");
   end Xpcall_Suspension;

   procedure Gsub_Not_Yieldable is
      --  A native pattern replacement is a non-yieldable call.
      --  Ask yieldability and attempt yielding in its callback.
      --  The callback sees false and the failure remains protected.
   begin
      Check
        ("local co=coroutine.create(function() return " &
         "pcall(string.gsub,'a','.',function() assert(not " &
         "coroutine.isyieldable()); coroutine.yield() end) end);" &
         " local a,b,c=coroutine.resume(co);" &
         " assert(a and b==false and type(c)=='string')");
   end Gsub_Not_Yieldable;

   procedure Metamethod_Yield is
      --  Arithmetic metamethods may suspend normally.
      --  Yield within __add and resume with its return value.
      --  The suspended destination receives the final scalar.
   begin
      Check
        ("local t=setmetatable({},{__add=function() local " &
         "x=coroutine.yield(10); return x+1 end});" &
         " local co=coroutine.create(function()return t+t end);" &
         " local a,b=coroutine.resume(co); assert(a and b==10);" &
         " a,b=coroutine.resume(co,20); assert(a and b==21)");
   end Metamethod_Yield;

   procedure Close_Nil_False is
      --  Nil and false require no closing callback.
      --  Leave a block containing both closing declarations.
      --  The block exits successfully.
   begin
      Check
        ("do local x <close> = nil; local y <close> = false end");
   end Close_Nil_False;

   procedure Close_Invalid_Initializer is
      --  A truthy closing initializer must define __close.
      --  Initialize a closing variable with an ordinary table under pcall.
      --  Initialization raises a controlled error naming the variable.
   begin
      Check
        ("local ok,e=pcall(function()local bad <close> = {} end);" &
         " assert(not ok and e:find('bad') and " &
         "e:find('non%-closable'))");
   end Close_Invalid_Initializer;

   procedure Close_Reverse_Order is
      --  Two live closers share one lexical block.
      --  Exit normally and record their callbacks.
      --  The most recent declaration closes first.
   begin
      Check
        ("local s=''; local function c(n)return setmetatable({}," &
         "{__close=function()s=s..n end})end;" &
         " do local a <close> = c('a');" &
         " local b <close> = c('b') end; assert(s=='ba')");
   end Close_Reverse_Order;

   procedure Close_Break is
      --  Loop exit must close its live body bindings.
      --  Break on the first iteration with a closer.
      --  The close callback runs exactly once.
   begin
      Check
        ("local n=0; while true do local x <close> = " &
         "setmetatable({},{__close=function() n=n+1 end});" &
         " break end; assert(n==1)");
   end Close_Break;

   procedure Close_Goto is
      --  A jump out of a declaration lifetime requires cleanup.
      --  Jump backward before a closing declaration.
      --  Every dynamic binding closes before its replacement.
   begin
      Check
        ("local n=0; local i=0; ::again:: i=i+1;" &
         " do local x <close> = setmetatable({}," &
         "{__close=function()n=n+1 end});" &
         " if i<3 then goto again end end; assert(n==3)");
   end Close_Goto;

   procedure Close_Return_Values is
      --  Return packets must remain rooted during cleanup.
      --  Collect in a closer while a new table is being returned.
      --  The caller receives the live original table.
   begin
      Check
        ("local function f() local x <close> = setmetatable({}," &
         "{__close=function()collectgarbage()end});" &
         " return {answer=42},nil,9 end; local a,b,c=f();" &
         " assert(a.answer==42 and b==nil and c==9)");
   end Close_Return_Values;

   procedure Close_Return_Call is
      --  A return call with live closers cannot erase its frame.
      --  Call another function in a return expression.
      --  Its results are evaluated before cleanup and then returned.
   begin
      Check
        ("local n=0; local function f() local x <close> = " &
         "setmetatable({},{__close=function()n=n+1 end});" &
         " return (function()assert(n==0);return 42 end)() end;" &
         " assert(f()==42 and n==1)");
   end Close_Return_Call;

   procedure Close_Error_Replacement is
      --  An inner closer can replace the active error.
      --  Raise one value, then fail in the inner close handler.
      --  The outer handler and pcall receive the replacement.
   begin
      Check
        ("local got; local function c(f)return setmetatable({}," &
         "{__close=f})end;" &
         " local ok,e=pcall(function() local a <close> = " &
         "c(function(_,e)got=e end);" &
         " local b <close> = c(function(_,e)assert(e==1);" &
         "error(2)end); error(1) end);" &
         " assert(not ok and e==2 and got==2)");
   end Close_Error_Replacement;

   procedure Close_Suspension is
      --  Yield preserves live closing bindings.
      --  Suspend, inspect a counter, then explicitly close.
      --  Cleanup runs only on close and never executes the remainder.
   begin
      Check
        ("local n=0; local co=coroutine.create(function()local x " &
         "<close> = setmetatable({},{__close=function()n=n+1 end}" &
         "); coroutine.yield(); n=100 end);" &
         " assert(coroutine.resume(co)); assert(n==0);" &
         " assert(coroutine.close(co));" &
         " assert(n==1 and coroutine.status(co)=='dead')");
   end Close_Suspension;

   procedure Close_Abandoned is
      --  Abandoning a suspended coroutine must not invoke __close.
      --  Drop its only strong reference and collect.
      --  Weak reachability clears it while the close counter stays zero.
   begin
      Check
        ("local n=0; local w=setmetatable({},{__mode='v'});" &
         " do local co=coroutine.create(function()local x " &
         "<close> = setmetatable({},{__close=function()n=n+1 end}" &
         "); coroutine.yield()end); w[1]=co;" &
         " assert(coroutine.resume(co)) end; collectgarbage();" &
         " assert(w[1]==nil and n==0)");
   end Close_Abandoned;

   procedure Close_Wrap_Failure is
      --  wrap owns error cleanup before raising to its caller.
      --  Raise from a wrapped body with a live closer.
      --  The closer runs and the original error is retained.
   begin
      Check
        ("local n=0; local w=coroutine.wrap(function() local x " &
         "<close> = setmetatable({},{__close=function()n=n+1 end}" &
         "); error(17) end); local ok,e=pcall(w);" &
         " assert(not ok and e==17 and n==1)");
   end Close_Wrap_Failure;

   procedure Close_Dead_Error_Once is
      --  A failed raw coroutine retains its error until close.
      --  Close it twice after an unprotected failure.
      --  The first close returns false/error and the second succeeds.
   begin
      Check
        ("local co=coroutine.create(function()error(17)end);" &
         " assert(not coroutine.resume(co));" &
         " local a,b=coroutine.close(co);" &
         " assert(not a and b==17); assert(coroutine.close(co))");
   end Close_Dead_Error_Once;

   procedure Close_Self is
      --  Closing the running child abandons its Lua continuation.
      --  Close itself with a live closer.
      --  The resumer succeeds and code after close is never reached.
   begin
      Check
        ("local n=0; local co=coroutine.create(function()local x " &
         "<close> = setmetatable({},{__close=function()n=n+1 end}" &
         "); coroutine.close(); error('unreachable')end);" &
         " assert(coroutine.resume(co));" &
         " assert(n==1 and coroutine.status(co)=='dead')");
   end Close_Self;

   procedure Close_Generic_For is
      --  The fourth iterator result lives around the whole loop.
      --  Run three iterations and inspect its close counter.
      --  It remains open in every body and closes once at loop exit.
   begin
      Check
        ("local n=0; local c=setmetatable({},{__close=function()" &
         "n=n+1 end}); local function iter(_,i)i=i+1;" &
         "if i<=3 then return i end end;" &
         " for i in iter,nil,0,c do assert(n==0) end;" &
         " assert(n==1)");
   end Close_Generic_For;

   procedure Close_Generic_Empty is
      --  An empty iterator still owns its fourth closing value.
      --  Return nil on the first iterator call.
      --  The fourth value closes even though no body executes.
   begin
      Check
        ("local n=0; local c=setmetatable({},{__close=function()" &
         "n=n+1 end}); for i in function()end,nil,nil,c do " &
         "error('unreachable')end; assert(n==1)");
   end Close_Generic_Empty;

   procedure Backward_Cells is
      --  A backward jump can re-enter a declaration.
      --  Retain closures from each pass through that declaration.
      --  Fresh cells preserve the earlier captured values.
   begin
      Check
        ("local a={};local i=0; ::again:: local x=i;" &
         " a[#a+1]=function()return x end; i=i+1;" &
         "if i<3 then goto again end;" &
         " assert(a[1]()==0 and a[2]()==1 and a[3]()==2);" &
         " assert(debug.upvalueid(a[1],1)~=debug.upvalueid(a[2]," &
         "1))");
   end Backward_Cells;

   procedure Shared_Capture_Cell is
      --  Two closures capture one mutable binding.
      --  Update it through one closure and inspect both upvalue IDs.
      --  Both functions share the actual cell and mutation.
   begin
      Check
        ("local x=1; local a=function()x=x+1 end;" &
         "local b=function()return x end;" &
         "assert(debug.upvalueid(a,1)==debug.upvalueid(b,1));a();" &
         "assert(b()==2)");
   end Shared_Capture_Cell;

   procedure Debug_Upvalue_Mutation is
      --  Debug writes must modify the captured binding itself.
      --  Read its name/value and replace it through setupvalue.
      --  The closure immediately observes the replacement.
   begin
      Check
        ("local x=1;local f=function()return x end;" &
         "local n,v=debug.getupvalue(f,1);" &
         "assert(n=='x' and v==1);" &
         "assert(debug.setupvalue(f,1,42)=='x');assert(f()==42)");
   end Debug_Upvalue_Mutation;

   procedure Debug_Load_Environment is
      --  A loaded chunk owns its initial environment cell.
      --  Replace its first upvalue with an explicit table.
      --  Later execution uses that environment.
   begin
      Check
        ("local f=assert(load('return answer'));" &
         "assert(debug.setupvalue(f,1,{answer=42})=='_ENV');" &
         "assert(f()==42)");
   end Debug_Load_Environment;

   procedure Debug_Current_Local is
      --  Active lexical declarations are actual mutable cells.
      --  Change a local through setlocal in the current Lua frame.
      --  getlocal names it and subsequent source reads the new value.
   begin
      Check
        ("local function f() local answer=1;" &
         " local n,v=debug.getlocal(1,1);" &
         " assert(n=='answer' and v==1);" &
         " assert(debug.setlocal(1,1,42)=='answer');" &
         "assert(answer==42)end;f()");
   end Debug_Current_Local;

   procedure Debug_Suspended_Local is
      --  A suspended body retains its active local cells.
      --  Read and change one through the explicit-thread form.
      --  Its resumed body observes the debug mutation.
   begin
      Check
        ("local co=coroutine.create(function()local answer=1;" &
         "coroutine.yield();return answer end);" &
         "assert(coroutine.resume(co));" &
         "local n,v=debug.getlocal(co,1,1);" &
         "assert(n=='answer' and v==1);" &
         "assert(debug.setlocal(co,1,1,42)=='answer');" &
         "local ok,x=coroutine.resume(co);assert(ok and x==42)");
   end Debug_Suspended_Local;

   procedure Debug_Source_Range is
      --  Function definitions retain their original source range.
      --  Query getinfo on a Lua closure.
      --  Its type, parameter count and range come from the prototype.
   begin
      Check
        ("local function f(a,...)return a end;" &
         "local i=debug.getinfo(f);" &
         "assert(i.what=='Lua' and i.nparams==1 and i.isvararg " &
         "and i.linedefined==1 and i.lastlinedefined==1 and " &
         "i.func==f)");
   end Debug_Source_Range;

   procedure Hook_Trace is
      --  A thread owns its call/line/return hook state.
      --  Resume a two-line body through one yield.
      --  The logical trace contains each call and return exactly once.
   begin
      Check
        ("local t={};local co=coroutine.create(function()" &
         Character'Val (10) &
         "coroutine.yield(1)" &
         Character'Val (10) &
         "return 2" &
         Character'Val (10) &
         "end);debug.sethook(co,function(e)t[#t+1]=e end,'clr');" &
         "assert(coroutine.resume(co));" &
         "assert(coroutine.resume(co));" &
         "assert(table.concat(t,',')" &
         "=='call,line,call,return,line,return')");
   end Hook_Trace;

   procedure Hook_Suppression is
      --  A hook callback itself must not be hooked recursively.
      --  Count hook calls while the hook invokes a Lua helper.
      --  The callback finishes and hooks can be disabled safely.
   begin
      Check
        ("local n=0;local function helper()return 1 end;" &
         "debug.sethook(function()n=n+helper() end,'',3);" &
         "local a=1+2;debug.sethook();assert(n>0 and a==3)");
   end Hook_Suppression;

   procedure Hook_Per_Thread is
      --  Installing a hook on a child must not affect the main thread.
      --  Inspect both hook registrations.
      --  The function, canonical mask and count belong to the child.
   begin
      Check
        ("local co=coroutine.create(function()end);" &
         "local h=function()end;debug.sethook(co,h,'lrc',7);" &
         "local a,b,c=debug.gethook(co);" &
         "assert(a==h and b=='crl' and c==7);" &
         "assert(debug.gethook()==nil)");
   end Hook_Per_Thread;

   procedure Weak_Values is
      --  A weak-value table cannot retain unreachable identities.
      --  Collect after dropping the only strong value reference.
      --  The entry disappears while numeric and string values survive.
   begin
      Check
        ("local t=setmetatable({},{__mode='v'});do local x={};" &
         "t.x=x end;t.s='bytes';t.n=42;collectgarbage();" &
         "assert(t.x==nil and t.s=='bytes' and t.n==42)");
   end Weak_Values;

   procedure Weak_Keys is
      --  A weak-key entry disappears with its unreachable key.
      --  Create a key/value edge then leave its lexical scope.
      --  Collection removes the entry.
   begin
      Check
        ("local t=setmetatable({},{__mode='k'});do local k={};" &
         "t[k]=42 end;collectgarbage();assert(next(t)==nil)");
   end Weak_Keys;

   procedure Ephemeron_Cycle is
      --  An ephemeron value cannot keep its own weak key alive.
      --  Store a value pointing back to an otherwise unreachable key.
      --  The key/value cycle disappears together.
   begin
      Check
        ("local t=setmetatable({},{__mode='k'});do local k={};" &
         "t[k]={key=k} end;collectgarbage();assert(next(t)==nil)");
   end Ephemeron_Cycle;

   procedure Ephemeron_Fixed_Point is
      --  Reachable keys can expose values that are keys elsewhere.
      --  Build two ephemeron tables in opposite traversal order.
      --  The fixed point retains the whole reachable chain.
   begin
      Check
        ("local a=setmetatable({},{__mode='k'});" &
         "local b=setmetatable({},{__mode='k'});local first={};" &
         "do local middle={};local last={answer=42};" &
         "a[first]=middle;b[middle]=last end;collectgarbage();" &
         "assert(b[a[first]].answer==42)");
   end Ephemeron_Fixed_Point;

   procedure Coroutine_Closure_Graph is
      --  A coroutine and its captured closure can form a cycle.
      --  Retain only a weak reference to that suspended graph.
      --  Collection reclaims the entire graph.
   begin
      Check
        ("local w=setmetatable({},{__mode='v'});do local co;" &
         "co=coroutine.create(function()local f=function()return " &
         "co end;coroutine.yield(f)end);w[1]=co;" &
         "coroutine.resume(co) end;collectgarbage();" &
         "assert(w[1]==nil)");
   end Coroutine_Closure_Graph;

   procedure Surviving_Capture is
      --  A closure can outlive the coroutine that created it.
      --  Retain the closure but only weakly retain its wrapper.
      --  Collection frees the wrapper and preserves mutable capture.
   begin
      Check
        ("local w=setmetatable({},{__mode='v'});local f;" &
         "do local co=coroutine.wrap(function()local x=1;" &
         "coroutine.yield(function()x=x+1;return x end)end);" &
         "w[1]=co;f=co()end;collectgarbage();" &
         "assert(w[1]==nil and f()==2 and f()==3)");
   end Surviving_Capture;

   procedure Collection_Control is
      --  Collector controls expose real automatic-collection state.
      --  Stop, explicitly collect, and restart.
      --  Explicit collection works while stopped and restart restores running.
   begin
      Check
        ("assert(collectgarbage('isrunning'));" &
         "collectgarbage('stop');" &
         "assert(not collectgarbage('isrunning'));" &
         "collectgarbage();" &
         "assert(not collectgarbage('isrunning'));" &
         "collectgarbage('restart');" &
         "assert(collectgarbage('isrunning'))");
   end Collection_Control;

   procedure Collection_Unsupported is
      --  Deferred collector accounting must not return fake numbers.
      --  Request count and generational modes under pcall.
      --  Both requests raise explicit unsupported-option errors.
   begin
      Check
        ("local ok,e=pcall(collectgarbage,'count');" &
         "assert(not ok and e:find('unsupported'));" &
         "assert(not pcall(collectgarbage,'generational'))");
   end Collection_Unsupported;

   procedure Hook_Error_Recovery is
      --  A hook error must unwind its suppression continuation.
      --  Fail in a child hook then disable and close that thread.
      --  The scheduler reports the error and remains usable.
   begin
      Check
        ("local co=coroutine.create(function()return 1 end);" &
         "debug.sethook(co,function()error(17)end,'c');" &
         "local ok,e=coroutine.resume(co);" &
         "assert(not ok and e==17);debug.sethook(co);" &
         "assert(not coroutine.close(co));" &
         "assert(coroutine.close(co));assert(1+1==2)");
   end Hook_Error_Recovery;

   procedure Close_Normal_Yield is
      --  A normal block-exit close handler may yield.
      --  Suspend inside cleanup and resume to finish the close.
      --  The close executes once and preserves the return result.
   begin
      Check
        ("local co=coroutine.create(function()local x <close> = " &
         "setmetatable({},{__close=function()coroutine.yield(7)" &
         "end});return 42 end);local a,b=coroutine.resume(co);" &
         "assert(a and b==7);a,b=coroutine.resume(co);" &
         "assert(a and b==42)");
   end Close_Normal_Yield;

   procedure Close_Explicit_Not_Yieldable is
      --  Explicit close runs its callbacks in a closing phase.
      --  Attempt to yield from a suspended coroutine close handler.
      --  close returns false/error and leaves the coroutine dead.
   begin
      Check
        ("local co=coroutine.create(function()local x <close> = " &
         "setmetatable({},{__close=function()assert(not " &
         "coroutine.isyieldable());coroutine.yield()end});" &
         "coroutine.yield()end);assert(coroutine.resume(co));" &
         "local ok,e=coroutine.close(co);" &
         "assert(not ok and type(e)=='string' and " &
         "coroutine.status(co)=='dead')");
   end Close_Explicit_Not_Yieldable;

   procedure Semantic_Result_Overflow is
      --  Lua stack capacity bounds large multi-result packets.
      --  Unpack a million values in a compatible coroutine.
      --  resume returns a catchable semantic error, not a host abort.
   begin
      Check
        ("local co=coroutine.create(function()return " &
         "table.unpack({},1,1000000)end);" &
         "local ok,e=coroutine.resume(co);" &
         "assert(not ok and e:find('stack overflow'))",
         Compatible => True);
   end Semantic_Result_Overflow;

   procedure Debug_Traceback is
      --  Traceback traverses a suspended thread without executing it.
      --  Build a traceback and query its status afterward.
      --  The string names a traceback and the thread stays suspended.
   begin
      Check
        ("local co=coroutine.create(function()coroutine.yield()" &
         "end);assert(coroutine.resume(co));" &
         "local s=debug.traceback(co);" &
         "assert(type(s)=='string' and s:find('stack traceback'))" &
         ";assert(coroutine.status(co)=='suspended')");
   end Debug_Traceback;


   procedure Table_Callback_Not_Yieldable is
      --  Table library metamethod calls retain a native boundary.
      --  Attempt to yield from an indexing callback during concat.
      --  The coroutine sees a protected error instead of suspension.
   begin
      Check
        ("local t=setmetatable({},{__len=function()return 1 end," &
         "__index=function()assert(not coroutine.isyieldable());" &
         "coroutine.yield()end});" &
         " local co=coroutine.create(function()return " &
         "pcall(table.concat,t)end);" &
         "local a,b,c=coroutine.resume(co);" &
         "assert(a and b==false and type(c)=='string')");
   end Table_Callback_Not_Yieldable;

   procedure Load_Reader_Not_Yieldable is
      --  A reader runs inside load's non-yieldable protected compiler call.
      --  Yielding becomes load's nil/message pair; outer pcall succeeds.
      --  C Lua protects reader failures inside compilation, unlike require.
   begin
      Check
        ("local co=coroutine.create(function()return " &
         "load(function() assert(not coroutine.isyieldable());" &
         "coroutine.yield()end)end);" &
         "local ok,f,e=coroutine.resume(co);" &
         "assert(ok and f==nil and type(e)=='string')");
   end Load_Reader_Not_Yieldable;

   procedure Require_Not_Yieldable is
      --  The Lua-only package loader preserves native yield restrictions.
      --  Install a preload loader that attempts to yield.
      --  require fails without suspending its enclosing native operation.
   begin
      Check
        ("package.preload.x=function()assert(not " &
         "coroutine.isyieldable());coroutine.yield()end;" &
         "local co=coroutine.create(function()return " &
         "pcall(require,'x')end);local a,b=coroutine.resume(co);" &
         "assert(a and b==false)");
   end Require_Not_Yieldable;

   procedure Xpcall_Handler_Not_Yieldable is
      --  An xpcall error handler has a non-yieldable boundary.
      --  Check yieldability while transforming an error.
      --  The handler sees false and returns its transformed value.
   begin
      Check
        ("local co=coroutine.create(function()return " &
         "xpcall(function()error(7)end,function(e)assert(not " &
         "coroutine.isyieldable());return e+1 end)end);" &
         "local a,b,c=coroutine.resume(co);" &
         "assert(a and b==false and c==8)");
   end Xpcall_Handler_Not_Yieldable;

   procedure Debug_Parameter_Name is
      --  A function-only query has parameter names but no values.
      --  Query the first and an out-of-range parameter.
      --  getlocal returns the real name and exactly one nil when absent.
   begin
      Check
        ("local function f(answer)return answer end;" &
         "assert(debug.getlocal(f,1)=='answer');" &
         "assert(select('#',debug.getlocal(f,2))==1 and " &
         "debug.getlocal(f,2)==nil)");
   end Debug_Parameter_Name;

   procedure Debug_Invalid_Local is
      --  An absent active local is distinct from no return values.
      --  Query beyond the live declaration range.
      --  getlocal returns one nil.
   begin
      Check
        ("assert(select('#',debug.getlocal(1,999))==1 and " &
         "debug.getlocal(1,999)==nil)");
   end Debug_Invalid_Local;

   procedure Debug_Native_Upvalue is
      --  A native iterator owns actual traced upvalue cells.
      --  Inspect its name/value/identity and advance the iterator.
      --  The state cell changes value without changing identity.
   begin
      Check
        ("local f=string.gmatch('ab','.');" &
         "local n,v=debug.getupvalue(f,3);assert(n=='' and v==0);" &
         "local id=debug.upvalueid(f,3);assert(f()=='a');" &
         "assert(debug.upvalueid(f,3)==id);" &
         "local _,v=debug.getupvalue(f,3);assert(v==1)");
   end Debug_Native_Upvalue;

   procedure Debug_Native_Cell_Write is
      --  Debug writes to native state affect its next invocation.
      --  Change the next-position upvalue of a gmatch iterator.
      --  The iterator reads the changed cell.
   begin
      Check
        ("local f=string.gmatch('abc','.');" &
         "assert(debug.setupvalue(f,3,1)=='');assert(f()=='b')");
   end Debug_Native_Cell_Write;

   procedure Debug_Call_Name is
      --  Call names belong to the source call site.
      --  Query a function invoked by a lexical name.
      --  getinfo reports that name and its local classification.
   begin
      Check
        ("local function named()local i=debug.getinfo(1,'n');" &
         "assert(i.name=='named' and i.namewhat=='local')end;" &
         "named()");
   end Debug_Call_Name;

   procedure Debug_Method_Name is
      --  Method calls carry their field name and calling convention.
      --  Inspect a method from inside its body.
      --  getinfo reports the method name at that call site.
   begin
      Check
        ("local t={};function t:run()local i=debug.getinfo(1,'n')" &
         ";assert(i.name=='run' and i.namewhat=='method')end;" &
         "t:run()");
   end Debug_Method_Name;

   procedure Hook_Backward_Line is
      --  A backward branch can revisit the same source line.
      --  Install a line hook around a one-line counted loop.
      --  Events recur instead of being suppressed by line equality.
   begin
      Check
        ("local n=0;local co=coroutine.create(function()local " &
         "x=0;for i=1,4 do x=x+i end;return x end);" &
         "debug.sethook(co,function(e)if e=='line'then n=n+1 end " &
         "end,'l');local a,b=coroutine.resume(co);" &
         "assert(a and b==10 and n>=4)");
   end Hook_Backward_Line;

   procedure Hook_Tail_Call is
      --  A tail call replaces the caller while preserving hook identity.
      --  Tail-call a leaf under a call hook.
      --  The trace includes the tail-call event.
   begin
      Check
        ("local found=false;local function leaf()return 42 end;" &
         "local co=coroutine.create(function()return leaf()end);" &
         "debug.sethook(co,function(e)if e=='tail call'then " &
         "found=true end end,'c');local a,b=coroutine.resume(co);" &
         "assert(a and b==42 and found)");
   end Hook_Tail_Call;

   procedure Hook_Collection_Roots is
      --  A hook and its captures stay live across collections.
      --  Collect inside a hook capturing a table.
      --  The captured table remains valid and the body completes.
   begin
      Check
        ("local t={answer=42};" &
         "local co=coroutine.create(function()return 1 end);" &
         "debug.sethook(co,function()collectgarbage();" &
         "assert(t.answer==42)end,'c');" &
         "assert(coroutine.resume(co))");
   end Hook_Collection_Roots;

   procedure Hook_No_Reentrant_Yield is
      --  Lua hook callbacks cannot yield through their native hook call.
      --  Attempt to yield from a line hook.
      --  resume reports an error and does not suspend the hook.
   begin
      Check
        ("local co=coroutine.create(function()return 42 end);" &
         "debug.sethook(co,function()coroutine.yield()end,'l');" &
         "local ok,e=coroutine.resume(co);" &
         "assert(not ok and type(e)=='string' and " &
         "coroutine.status(co)=='dead')");
   end Hook_No_Reentrant_Yield;

   procedure Weak_Mode_Change is
      --  Weakness is read from the current metatable at collection.
      --  Change a strong table to weak values before collecting.
      --  The newly weak entry stops retaining its object.
   begin
      Check
        ("local m={};local t=setmetatable({},m);do local v={};" &
         "t[1]=v end;m.__mode='v';collectgarbage();" &
         "assert(t[1]==nil)");
   end Weak_Mode_Change;

   procedure Weak_String_Keys is
      --  Lua strings keep value semantics in weak tables.
      --  Store freshly concatenated string keys and values.
      --  Collection preserves both strings.
   begin
      Check
        ("local t=setmetatable({},{__mode='kv'});" &
         "t['a'..'b']='c'..'d';collectgarbage();" &
         "assert(t.ab=='cd')");
   end Weak_String_Keys;

   procedure Close_Generic_Break is
      --  Breaking a generic loop exits its outer closing scope.
      --  Break before the iterator naturally terminates.
      --  The fourth closing value runs once.
   begin
      Check
        ("local n=0;local c=setmetatable({},{__close=function()" &
         "n=n+1 end});for i in function()return 1 end,nil,nil,c " &
         "do assert(n==0);break end;assert(n==1)");
   end Close_Generic_Break;

   procedure Close_Error_Not_Yieldable is
      --  Error unwinding closes without allowing suspension.
      --  Ask yieldability inside an error-path closer.
      --  The callback sees false and the original error is protected.
   begin
      Check
        ("local ok,e=pcall(function()local x <close> = " &
         "setmetatable({},{__close=function()assert(not " &
         "coroutine.isyieldable())end});error(7)end);" &
         "assert(not ok and e==7)");
   end Close_Error_Not_Yieldable;

   procedure Coroutine_Close_Main_Error is
      --  The main thread cannot close itself.
      --  Invoke close with its stable identity under pcall.
      --  The diagnostic identifies the main thread.
   begin
      Check
        ("local m=coroutine.running();" &
         "local ok,e=pcall(coroutine.close,m);" &
         "assert(not ok and e:find('main'))");
   end Coroutine_Close_Main_Error;

   procedure Native_Call_Overflow is
      --  Nested native resume chains have a separate semantic limit.
      --  Recursively create and invoke wrapped child coroutines.
      --  The semantic native-depth error is catchable and recoverable.
   begin
      Check
        ("local function f()return coroutine.wrap(f)()end;" &
         "local ok,e=pcall(f);" &
         "assert(not ok and e:find('stack overflow'));" &
         "assert(2+2==4)",
         Compatible => True);
   end Native_Call_Overflow;

   procedure Policy_Restores_Bounds is
      --  Configure a deliberately tiny budget, then opt into compatibility.
      --  Work beyond that budget succeeds until the owner restores Bounded.
      --  This protects saved quotas from being overwritten by policy changes.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Instructions := 100;
      Universe.Set_Limits (Bounds);
      Universe.Set_Execution_Policy (Lua_Compatible);
      Result := Universe.Execute ("local n=0; for i=1,100 do n=n+1 end");
      Assert (Result.Status = Succeeded, "compatible work");
      Universe.Set_Execution_Policy (Bounded);
      Result := Universe.Execute ("while true do end");
      Assert (Result.Status = Resource_Error, "restored bounded quota");
   end Policy_Restores_Bounds;

   procedure Set_Limits_Selects_Bounded is
      --  An explicit limits call must revoke compatible execution.
      --  Run an endless loop after configuring a short instruction budget.
      --  The host receives an abort, then can execute another chunk.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Universe.Set_Execution_Policy (Lua_Compatible);
      Bounds.Instructions := 100;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("while true do end");
      Assert (Result.Status = Resource_Error, "explicit host limit");
      Result := Universe.Execute ("assert(2+2==4)");
      Assert (Result.Status = Succeeded, "session recovery");
   end Set_Limits_Selects_Bounded;

   procedure Reset_Selects_Bounded is
      --  Reset must restore the embedding default, including source quotas.
      --  Exceed that default using one long comment after compatible reset.
      --  The source is rejected as a host resource failure before execution.
      Universe : Session;
      Result : Execution_Result;
      Source : constant String (1 .. 1_000_001) := [others => ' '];
   begin
      Universe.Set_Execution_Policy (Lua_Compatible);
      Universe.Reset;
      Result := Universe.Execute (Source);
      Assert (Result.Status = Resource_Error, "reset bounded default");
   end Reset_Selects_Bounded;

   procedure Coroutine_Quota_Abort is
      --  A resume cannot hide host exhaustion under pcall or restart work.
      --  Abort an endless child with a live closer and inspect recovery.
      --  The chain dies, no cleanup callback runs, and the session is usable.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Instructions := 1_000;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("closed=0; co=coroutine.create(function() local x <close> =" &
         "setmetatable({},{__close=function()closed=closed+1 end});" &
         "while true do end end);pcall(coroutine.resume,co)");
      Assert (Result.Status = Resource_Error, "uncatchable child quota");
      Result := Universe.Execute
        ("assert(closed==0 and coroutine.status(co)=='dead')");
      Assert (Result.Status = Succeeded, "abort chain recovery");
   end Coroutine_Quota_Abort;

   procedure Stopped_GC_Across_Chunks is
      --  Stopping collection applies to automatic chunk boundaries too.
      --  Retain a value only weakly, execute another chunk, then collect.
      --  Explicit collection clears it while automatic collection stays off.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute
        ("collectgarbage('stop'); w=setmetatable({},{__mode='v'});" &
         "do local x={};w[1]=x end");
      Assert (Result.Status = Succeeded, "weak stopped setup");
      Result := Universe.Execute
        ("assert(w[1]~=nil);collectgarbage();assert(w[1]==nil);" &
         "assert(not collectgarbage('isrunning'))");
      Assert (Result.Status = Succeeded, "explicit stopped collection");
   end Stopped_GC_Across_Chunks;

   procedure Reset_Lifecycle_State is
      --  A fresh environment must discard hooks and collector mutations.
      --  Reset after disabling collection and installing a silent hook.
      --  The restored libraries have no hook and automatic collection is on.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute
        ("collectgarbage('stop');debug.sethook(function()end,'l')");
      Assert (Result.Status = Succeeded, "mutated lifecycle setup");
      Universe.Reset;
      Result := Universe.Execute
        ("assert(debug.gethook()==nil);" &
         "assert(collectgarbage('isrunning'))");
      Assert (Result.Status = Succeeded, "reset lifecycle defaults");
   end Reset_Lifecycle_State;

   procedure Independent_Thread_Universes is
      --  Thread registries and hook/metatable state belong to one session.
      --  Store a main-thread identity in one universe and query another.
      --  No Lua thread handle or global leaks across session ownership.
      First : Session;
      Second : Session;
      Result : Execution_Result;
   begin
      Result := First.Execute ("saved=coroutine.running()");
      Assert (Result.Status = Succeeded, "first identity");
      Result := Second.Execute ("assert(saved==nil); saved=42");
      Assert (Result.Status = Succeeded, "independent globals");
      Result := First.Execute ("assert(type(saved)=='thread')");
      Assert (Result.Status = Succeeded, "first identity retained");
   end Independent_Thread_Universes;

   procedure Debug_Literal_Source is
      --  A literal chunk name starts with an equals sign.
      --  Inspect the source identifier of a dynamically loaded closure.
      --  The source is retained and short_src omits the marker.
   begin
      Check
        ("local f=assert(load('return 1','=literal'));" &
         "local i=debug.getinfo(f,'S');" &
         "assert(i.source=='=literal' and i.short_src=='literal')");
   end Debug_Literal_Source;

   procedure Debug_File_Source is
      --  A file chunk name retains its file identity.
      --  Inspect a long file identifier beyond the debug buffer width.
      --  short_src preserves the final 56 bytes with an ellipsis.
   begin
      Check
        ("local name='@'..string.rep('x',80)..'tail.lua';" &
         "local f=assert(load('return 1',name));" &
         "local i=debug.getinfo(f,'S');" &
         "assert(i.source==name and " &
         "i.short_src=='...'..name:sub(-56))");
   end Debug_File_Source;

   procedure Debug_Snippet_Source is
      --  Raw chunk names render as quoted source snippets.
      --  Inspect a short raw name and a name containing a newline.
      --  The first line is kept and truncated content has an ellipsis.
   begin
      Check
        ("local f=assert(load('return 1','raw'));" &
         "assert(debug.getinfo(f,'S')" &
         ".short_src=='[string ""raw""]');" &
         "f=assert(load('return 1','first\nsecond'));" &
         "assert(debug.getinfo(f,'S')" &
         ".short_src=='[string ""first...""]')");
   end Debug_Snippet_Source;

   procedure Debug_Minimum_Vararg_Index is
      --  The smallest integer is a valid out-of-range local index.
      --  Read a negative vararg index without negating that minimum.
      --  The query returns nil rather than an internal overflow.
   begin
      Check
        ("local function f(...)assert(debug.getlocal(1," &
         "math.mininteger)==nil)end;f(1)");
   end Debug_Minimum_Vararg_Index;

   procedure Debug_Hook_Count_Range is
      --  Oversized hook counts cannot fit the private counter.
      --  Attempt installation under pcall and inspect the hook state.
      --  A controlled range error leaves the previous registration intact.
   begin
      Check
        ("local h=function()end;" &
         "local ok,e=pcall(debug.sethook,h,'',math.maxinteger);" &
         "assert(not ok and e:find('range') and not " &
         "e:find('internal Ada'));assert(debug.gethook()==nil)");
   end Debug_Hook_Count_Range;

   procedure Debug_Traceback_Level_Range is
      --  Oversized traceback levels cannot be represented safely.
      --  Request an extreme level under pcall.
      --  A controlled diagnostic replaces any Ada range exception.
   begin
      Check
        ("local ok,e=pcall(debug.traceback,'message'," &
         "math.maxinteger);" &
         "assert(not ok and e:find('range') and not " &
         "e:find('internal Ada'))");
   end Debug_Traceback_Level_Range;

   procedure Debug_Split_Function_Lines is
      --  Function names and parentheses can start on later lines.
      --  Compile a split declaration and query its definition range.
      --  The function keyword line and closing end line are retained.
   begin
      Check
        ("local f=assert(load('return function\n(x)\nreturn x\nen" &
         "d'))();local i=debug.getinfo(f,'S');assert(i.linedefine" &
         "d==1 and i.lastlinedefined==4)");
   end Debug_Split_Function_Lines;

   procedure Hook_Implicit_Return_Line is
      --  A function without an explicit return ends at its end token.
      --  Record line events in a two-line body.
      --  The implicit return reports the closing end line.
   begin
      Check
        ("local t={};local co=coroutine.create(assert(load('retur" &
         "n function()\nlocal x=1\nend'))());debug.sethook(co,fun" &
         "ction(e,l)if e=='line'then t[#t+1]=l end end,'l');" &
         "assert(coroutine.resume(co));" &
         "assert(t[1]==2 and t[2]==3 and #t==2)");
   end Hook_Implicit_Return_Line;

   procedure Debug_Tail_Frame is
      --  Tail replacement is retained as real frame metadata.
      --  Inspect the leaf of a tail call from a coroutine.
      --  The active leaf reports istailcall instead of a fabricated caller.
   begin
      Check
        ("local function leaf()return debug.getinfo(1,'t')" &
         ".istailcall end;" &
         "local co=coroutine.create(function()return leaf()end);" &
         "local a,b=coroutine.resume(co);assert(a and b)");
   end Debug_Tail_Frame;

   procedure Close_Logical_Caller is
      --  Normal cleanup continues the owning Lua activation.
      --  Inspect the caller from an ordinary __close handler.
      --  Internal protection and scheduler phases are hidden.
   begin
      Check
        ("local what;do local x <close> = setmetatable({}," &
         "{__close=function()what=debug.getinfo(2,'S').what end})" &
         "end;assert(what=='main')");
   end Close_Logical_Caller;

   procedure Debug_Iterator_Native_Frame is
      --  The exported ipairs iterator is a genuine native Lua function.
      --  Inspect its frame while its indexing metamethod runs.
      --  Internal indexing continuations stay hidden, the iterator stays C.
   begin
      Check
        ("local t=setmetatable({},{__index=function()" &
         "assert(debug.getinfo(2,'S').what=='C');" &
         "return nil end});local f,s,i=ipairs(t);" &
         " assert(f(s,i)==nil)");
   end Debug_Iterator_Native_Frame;

   procedure Yieldability_After_Completion is
      --  C Lua queries the yield boundary, independently of dead status.
      --  Compare normal completion, failed native callbacks and repeated
      --  close.
      --  Retained error frames and a finished closing phase cannot force
      --  false.
   begin
      Check
        ("local co=coroutine.create(function()end);" &
         "assert(coroutine.isyieldable(co));" &
         "assert(coroutine.resume(co));" &
         "assert(coroutine.status(co)=='dead' and " &
         "coroutine.isyieldable(co));assert(coroutine.close(co));" &
         "assert(coroutine.isyieldable(co));" &
         "co=coroutine.create(function()string.gsub('a','.'," &
         "function()error(7)end)end);" &
         "assert(not coroutine.resume(co));" &
         "assert(coroutine.isyieldable(co));" &
         "assert(not coroutine.close(co));" &
         "assert(coroutine.isyieldable(co))");
   end Yieldability_After_Completion;

   procedure Closing_Quota_Abort is
      --  A host quota abort abandons cleanup without restarting callbacks.
      --  Exhaust the budget in an explicit close handler, then inspect it.
      --  The child is dead, its closing phase is gone, and the host recovers.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Instructions := 1_000;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("co=coroutine.create(function()local x <close> = " &
         "setmetatable({},{__close=function()while true do end end});" &
         "coroutine.yield()end);assert(coroutine.resume(co));" &
         "pcall(coroutine.close,co)");
      Assert (Result.Status = Resource_Error, "closing quota abort");
      Result := Universe.Execute
        ("assert(coroutine.status(co)=='dead');" &
         "assert(coroutine.isyieldable(co));assert(coroutine.close(co))");
      Assert (Result.Status = Succeeded, "abandoned close phase recovered");
   end Closing_Quota_Abort;

   procedure Weak_Mode_Nul_Boundary is
      --  Pinned Lua scans __mode flags with C-string semantics.
      --  Place v after a NUL, with either no prefix or a weak-key prefix.
      --  The unreachable value stays strong; bytes after NUL add no flags.
   begin
      Check
        ("local z=string.char(0);" &
         "for _,mode in ipairs{z..'v','k'..z..'v'} do local " &
         "t=setmetatable({},{__mode=mode});do local x={};" &
         "t[1]=x end;collectgarbage();assert(t[1]~=nil)end");
   end Weak_Mode_Nul_Boundary;

   procedure Collection_Stop_Result is
      --  Stopping the collector has an integer status result.
      --  Capture the result packet without scalar padding.
      --  Exactly one integer zero is returned, matching the C oracle.
   begin
      Check
        ("local t=table.pack(collectgarbage('stop'));" &
         "assert(t.n==1 and t[1]==0 and math.type(t[1])" &
         "=='integer');assert(not collectgarbage('isrunning'))");
   end Collection_Stop_Result;

   procedure Collection_Restart_Result is
      --  Restarting the collector also returns its integer status.
      --  Stop first, then capture the restart packet.
      --  Exactly one integer zero is returned and collection is running.
   begin
      Check
        ("collectgarbage('stop');" &
         "local t=table.pack(collectgarbage('restart'));" &
         "assert(t.n==1 and t[1]==0 and math.type(t[1])" &
         "=='integer');assert(collectgarbage('isrunning'))");
   end Collection_Restart_Result;

   procedure Disabled_Hook_Result is
      --  A disabled hook has a one-result nil packet.
      --  Query a new thread and a thread whose hook has been removed.
      --  No mask/count padding is exposed by gethook.
   begin
      Check
        ("local co=coroutine.create(function()end);" &
         "local t=table.pack(debug.gethook(co));" &
         "assert(t.n==1 and t[1]==nil);" &
         "debug.sethook(co,function()end,'l');debug.sethook(co);" &
         "t=table.pack(debug.gethook(co));" &
         "assert(t.n==1 and t[1]==nil)");
   end Disabled_Hook_Result;

   procedure Collection_Nil_Default is
      --  An explicit nil option selects the same default as no argument.
      --  Capture both the result count and value rather than scalar padding.
      --  The completed collection returns one integer zero, matching C Lua.
   begin
      Check
        ("local t=table.pack(collectgarbage(nil));" &
         "assert(t.n==1 and t[1]==0 and math.type(t[1])" &
         "=='integer')");
   end Collection_Nil_Default;

   procedure Hook_Empty_Configuration is
      --  An empty effective hook configuration disables the hook.
      --  Install a function with empty and unknown-only masks at count zero.
      --  gethook reports exactly one nil, matching C lua_sethook.
   begin
      Check
        ("local co=coroutine.create(function()end);" &
         "local h=function()end;" &
         "for _,m in ipairs{'','?'} do debug.sethook(co,h,m,0);" &
         "local t=table.pack(debug.gethook(co));" &
         "assert(t.n==1 and t[1]==nil)end");
   end Hook_Empty_Configuration;

   procedure Hook_Negative_Count_Reflection is
      --  Negative counts disable count events but remain reflected.
      --  Install a call hook with a negative requested interval.
      --  The function and call mask remain, and gethook returns negative
      --  seven.
   begin
      Check
        ("local co=coroutine.create(function()end);" &
         "local h=function()end;debug.sethook(co,h,'c',-7);" &
         "local f,m,n=debug.gethook(co);" &
         "assert(f==h and m=='c' and n==-7);" &
         "assert(select('#',debug.gethook(co))==3)");
   end Hook_Negative_Count_Reflection;

   procedure Hook_Mask_Nul_Boundary is
      --  C Lua scans hook masks as C strings.
      --  Place line flags after NUL with empty or call-only prefixes.
      --  Only prefix flags are active and reflected.
   begin
      Check
        ("local co=coroutine.create(function()end);" &
         "local h=function()end;local z=string.char(0);" &
         "debug.sethook(co,h,z..'l');" &
         "assert(debug.gethook(co)==nil);" &
         "debug.sethook(co,h,'c'..z..'l');" &
         "local f,m,n=debug.gethook(co);" &
         "assert(f==h and m=='c' and n==0)");
   end Hook_Mask_Nul_Boundary;

   procedure Collection_Option_Nul_Boundary is
      --  Collector option names use the same C-string boundary as C Lua.
      --  Append ignored bytes after a NUL to stop and restart options.
      --  The named operations succeed with their real zero status.
   begin
      Check
        ("local z=string.char(0);" &
         "assert(collectgarbage('stop'..z..'invalid')==0);" &
         "assert(not collectgarbage('isrunning'));" &
         "assert(collectgarbage('restart'..z..'invalid')==0);" &
         "assert(collectgarbage('isrunning'))");
   end Collection_Option_Nul_Boundary;

   procedure Debug_Info_Option_Nul_Boundary is
      --  Debug info options stop at the C-string terminator.
      --  Request source data followed by NUL and an invalid suffix.
      --  The source fields appear and unrequested line data remains absent.
   begin
      Check
        ("local f=function()end;" &
         "local i=debug.getinfo(f,'S'..string.char(0)..'?');" &
         "assert(i.what=='Lua' and i.currentline==nil)");
   end Debug_Info_Option_Nul_Boundary;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "control: Thread_Identity",
         Thread_Identity'Access);
      Test_Support.Add
        (Suite, "control: Main_Identity",
         Main_Identity'Access);
      Test_Support.Add
        (Suite, "control: Resume_Packets",
         Resume_Packets'Access);
      Test_Support.Add
        (Suite, "control: Nested_States",
         Nested_States'Access);
      Test_Support.Add
        (Suite, "control: Resume_Active",
         Resume_Active'Access);
      Test_Support.Add
        (Suite, "control: Resume_Dead",
         Resume_Dead'Access);
      Test_Support.Add
        (Suite, "control: Wrap_Error_Value",
         Wrap_Error_Value'Access);
      Test_Support.Add
        (Suite, "control: Pcall_Suspension",
         Pcall_Suspension'Access);
      Test_Support.Add
        (Suite, "control: Xpcall_Suspension",
         Xpcall_Suspension'Access);
      Test_Support.Add
        (Suite, "control: Gsub_Not_Yieldable",
         Gsub_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Metamethod_Yield",
         Metamethod_Yield'Access);
      Test_Support.Add
        (Suite, "control: Close_Nil_False",
         Close_Nil_False'Access);
      Test_Support.Add
        (Suite, "control: Close_Invalid_Initializer",
         Close_Invalid_Initializer'Access);
      Test_Support.Add
        (Suite, "control: Close_Reverse_Order",
         Close_Reverse_Order'Access);
      Test_Support.Add
        (Suite, "control: Close_Break",
         Close_Break'Access);
      Test_Support.Add
        (Suite, "control: Close_Goto",
         Close_Goto'Access);
      Test_Support.Add
        (Suite, "control: Close_Return_Values",
         Close_Return_Values'Access);
      Test_Support.Add
        (Suite, "control: Close_Return_Call",
         Close_Return_Call'Access);
      Test_Support.Add
        (Suite, "control: Close_Error_Replacement",
         Close_Error_Replacement'Access);
      Test_Support.Add
        (Suite, "control: Close_Suspension",
         Close_Suspension'Access);
      Test_Support.Add
        (Suite, "control: Close_Abandoned",
         Close_Abandoned'Access);
      Test_Support.Add
        (Suite, "control: Close_Wrap_Failure",
         Close_Wrap_Failure'Access);
      Test_Support.Add
        (Suite, "control: Close_Dead_Error_Once",
         Close_Dead_Error_Once'Access);
      Test_Support.Add
        (Suite, "control: Close_Self",
         Close_Self'Access);
      Test_Support.Add
        (Suite, "control: Close_Generic_For",
         Close_Generic_For'Access);
      Test_Support.Add
        (Suite, "control: Close_Generic_Empty",
         Close_Generic_Empty'Access);
      Test_Support.Add
        (Suite, "control: Backward_Cells",
         Backward_Cells'Access);
      Test_Support.Add
        (Suite, "control: Shared_Capture_Cell",
         Shared_Capture_Cell'Access);
      Test_Support.Add
        (Suite, "control: Debug_Upvalue_Mutation",
         Debug_Upvalue_Mutation'Access);
      Test_Support.Add
        (Suite, "control: Debug_Load_Environment",
         Debug_Load_Environment'Access);
      Test_Support.Add
        (Suite, "control: Debug_Current_Local",
         Debug_Current_Local'Access);
      Test_Support.Add
        (Suite, "control: Debug_Suspended_Local",
         Debug_Suspended_Local'Access);
      Test_Support.Add
        (Suite, "control: Debug_Source_Range",
         Debug_Source_Range'Access);
      Test_Support.Add
        (Suite, "control: Hook_Trace",
         Hook_Trace'Access);
      Test_Support.Add
        (Suite, "control: Hook_Suppression",
         Hook_Suppression'Access);
      Test_Support.Add
        (Suite, "control: Hook_Per_Thread",
         Hook_Per_Thread'Access);
      Test_Support.Add
        (Suite, "control: Weak_Values",
         Weak_Values'Access);
      Test_Support.Add
        (Suite, "control: Weak_Keys",
         Weak_Keys'Access);
      Test_Support.Add
        (Suite, "control: Ephemeron_Cycle",
         Ephemeron_Cycle'Access);
      Test_Support.Add
        (Suite, "control: Ephemeron_Fixed_Point",
         Ephemeron_Fixed_Point'Access);
      Test_Support.Add
        (Suite, "control: Coroutine_Closure_Graph",
         Coroutine_Closure_Graph'Access);
      Test_Support.Add
        (Suite, "control: Surviving_Capture",
         Surviving_Capture'Access);
      Test_Support.Add
        (Suite, "control: Collection_Control",
         Collection_Control'Access);
      Test_Support.Add
        (Suite, "control: Collection_Unsupported",
         Collection_Unsupported'Access);
      Test_Support.Add
        (Suite, "control: Hook_Error_Recovery",
         Hook_Error_Recovery'Access);
      Test_Support.Add
        (Suite, "control: Close_Normal_Yield",
         Close_Normal_Yield'Access);
      Test_Support.Add
        (Suite, "control: Close_Explicit_Not_Yieldable",
         Close_Explicit_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Semantic_Result_Overflow",
         Semantic_Result_Overflow'Access);
      Test_Support.Add
        (Suite, "control: Debug_Traceback",
         Debug_Traceback'Access);
      Test_Support.Add
        (Suite, "control: Table_Callback_Not_Yieldable",
         Table_Callback_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Load_Reader_Not_Yieldable",
         Load_Reader_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Require_Not_Yieldable",
         Require_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Xpcall_Handler_Not_Yieldable",
         Xpcall_Handler_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Debug_Parameter_Name",
         Debug_Parameter_Name'Access);
      Test_Support.Add
        (Suite, "control: Debug_Invalid_Local",
         Debug_Invalid_Local'Access);
      Test_Support.Add
        (Suite, "control: Debug_Native_Upvalue",
         Debug_Native_Upvalue'Access);
      Test_Support.Add
        (Suite, "control: Debug_Native_Cell_Write",
         Debug_Native_Cell_Write'Access);
      Test_Support.Add
        (Suite, "control: Debug_Call_Name",
         Debug_Call_Name'Access);
      Test_Support.Add
        (Suite, "control: Debug_Method_Name",
         Debug_Method_Name'Access);
      Test_Support.Add
        (Suite, "control: Hook_Backward_Line",
         Hook_Backward_Line'Access);
      Test_Support.Add
        (Suite, "control: Hook_Tail_Call",
         Hook_Tail_Call'Access);
      Test_Support.Add
        (Suite, "control: Hook_Collection_Roots",
         Hook_Collection_Roots'Access);
      Test_Support.Add
        (Suite, "control: Hook_No_Reentrant_Yield",
         Hook_No_Reentrant_Yield'Access);
      Test_Support.Add
        (Suite, "control: Weak_Mode_Change",
         Weak_Mode_Change'Access);
      Test_Support.Add
        (Suite, "control: Weak_String_Keys",
         Weak_String_Keys'Access);
      Test_Support.Add
        (Suite, "control: Close_Generic_Break",
         Close_Generic_Break'Access);
      Test_Support.Add
        (Suite, "control: Close_Error_Not_Yieldable",
         Close_Error_Not_Yieldable'Access);
      Test_Support.Add
        (Suite, "control: Coroutine_Close_Main_Error",
         Coroutine_Close_Main_Error'Access);
      Test_Support.Add
        (Suite, "control: Native_Call_Overflow",
         Native_Call_Overflow'Access);
      Test_Support.Add
        (Suite, "control: Policy_Restores_Bounds",
         Policy_Restores_Bounds'Access);
      Test_Support.Add
        (Suite, "control: Set_Limits_Selects_Bounded",
         Set_Limits_Selects_Bounded'Access);
      Test_Support.Add
        (Suite, "control: Reset_Selects_Bounded",
         Reset_Selects_Bounded'Access);
      Test_Support.Add
        (Suite, "control: Coroutine_Quota_Abort",
         Coroutine_Quota_Abort'Access);
      Test_Support.Add
        (Suite, "control: Stopped_GC_Across_Chunks",
         Stopped_GC_Across_Chunks'Access);
      Test_Support.Add
        (Suite, "control: Reset_Lifecycle_State",
         Reset_Lifecycle_State'Access);
      Test_Support.Add
        (Suite, "control: Independent_Thread_Universes",
         Independent_Thread_Universes'Access);
      Test_Support.Add
        (Suite, "control: Debug_Literal_Source",
         Debug_Literal_Source'Access);
      Test_Support.Add
        (Suite, "control: Debug_File_Source",
         Debug_File_Source'Access);
      Test_Support.Add
        (Suite, "control: Debug_Snippet_Source",
         Debug_Snippet_Source'Access);
      Test_Support.Add
        (Suite, "control: Debug_Minimum_Vararg_Index",
         Debug_Minimum_Vararg_Index'Access);
      Test_Support.Add
        (Suite, "control: Debug_Hook_Count_Range",
         Debug_Hook_Count_Range'Access);
      Test_Support.Add
        (Suite, "control: Debug_Traceback_Level_Range",
         Debug_Traceback_Level_Range'Access);
      Test_Support.Add
        (Suite, "control: Debug_Split_Function_Lines",
         Debug_Split_Function_Lines'Access);
      Test_Support.Add
        (Suite, "control: Hook_Implicit_Return_Line",
         Hook_Implicit_Return_Line'Access);
      Test_Support.Add
        (Suite, "control: Debug_Tail_Frame",
         Debug_Tail_Frame'Access);
      Test_Support.Add
        (Suite, "control: Close_Logical_Caller",
         Close_Logical_Caller'Access);
      Test_Support.Add
        (Suite, "control: Debug_Iterator_Native_Frame",
         Debug_Iterator_Native_Frame'Access);
      Test_Support.Add
        (Suite, "control: Yieldability_After_Completion",
         Yieldability_After_Completion'Access);
      Test_Support.Add
        (Suite, "control: Closing_Quota_Abort", Closing_Quota_Abort'Access);
      Test_Support.Add
        (Suite, "control: Weak_Mode_Nul_Boundary",
          Weak_Mode_Nul_Boundary'Access);
      Test_Support.Add
        (Suite, "control: Collection_Stop_Result",
         Collection_Stop_Result'Access);
      Test_Support.Add
        (Suite, "control: Collection_Restart_Result",
         Collection_Restart_Result'Access);
      Test_Support.Add
        (Suite, "control: Disabled_Hook_Result",
         Disabled_Hook_Result'Access);
      Test_Support.Add
        (Suite, "control: Collection_Nil_Default",
          Collection_Nil_Default'Access);
      Test_Support.Add
        (Suite, "control: Hook_Empty_Configuration",
         Hook_Empty_Configuration'Access);
      Test_Support.Add
        (Suite, "control: Hook_Negative_Count_Reflection",
         Hook_Negative_Count_Reflection'Access);
      Test_Support.Add
        (Suite, "control: Hook_Mask_Nul_Boundary",
         Hook_Mask_Nul_Boundary'Access);
      Test_Support.Add
        (Suite, "control: Collection_Option_Nul_Boundary",
         Collection_Option_Nul_Boundary'Access);
      Test_Support.Add
        (Suite, "control: Debug_Info_Option_Nul_Boundary",
         Debug_Info_Option_Nul_Boundary'Access);
   end Register;
end Runtime_Control_Tests;
