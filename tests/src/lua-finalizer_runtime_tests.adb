with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Finalizers;
with Lua.Runtime_Configuration;
with Test_Support;

package body Lua.Finalizer_Runtime_Tests is
   package F renames Lua.Engine.Finalizers;
   procedure Check
     (Before, After : String; Remove_Handler : Boolean := False;
      Secondary : Boolean := False);
   procedure Check
     (Before, After : String; Remove_Handler : Boolean := False;
      Secondary : Boolean := False)
   is
      State : World;
      Item, Key, Thread : Value;
      function Selected (Node : Object_Access) return Boolean;
      function Selected (Node : Object_Access) return Boolean is
        (Node = Item.Reference);
   begin
      Initialize (State, (others => <>));
      begin
         --  Enqueue through the real private ownership component so these
         --  tests isolate scheduler behavior before the phased collector
         --  selects production enrollment. Actual Lua calls/roots/protection
         --  are used; no callback or successful result is simulated.
         Assert (Execute (State, Before, "finalizer-setup"),
                 To_String (State.Current.Failure_Text));
         Begin_Operation (State);
         Key := New_String (State, "candidate");
         Item := Get (Global_Environment (State), Key);
         F.Register (State, Item);
         F.Queue_Unreachable (State, Selected'Access);
         Set (State, Global_Environment (State), Key, Nil_Value);
         if Remove_Handler then Set_Metatable (State, Item, null); end if;
         if Secondary then
            Thread := New_Thread
              (State, Get (Global_Environment (State),
                           New_String (State, "entry")));
            --  This private fixture explicitly owns its selected context.
            --  Ordinary Lua coroutines remain reachable only via threads.
            State.Contexts
              (Thread.Reference.Context_Index).Host_Owned := True;
            Select_Context
              (State, Context_Id (Thread.Reference.Context_Index));
         end if;
         End_Operation (State);
         Assert (Execute (State, After, "finalizer-execution"),
                 To_String (State.Current.Failure_Text));
         Assert (not State.Finalizer_Active and then
                   State.Finalizing_Object = null and then
                   State.Current.Finalizer_Hook_Suppression = 0 and then
                   State.Current.Non_Yieldable = 0,
                 "finalizer completion retained an execution policy");
      exception
         when others => End_Operation (State); Finalize (State); raise;
      end;
      Finalize (State);
   end Check;

   procedure Actual_Argument;
   procedure Actual_Argument is
   begin
      --  Use a real Lua closure as a table finalizer.
      --  Queue the target, remove its last public owner, and execute a chunk.
      --  The ordinary VM passes exactly the original target as one argument.
      Check
        ("fin=0;candidate=setmetatable({id=42},{__gc=function(..." &
         ")local self=...;assert(select('#',...)==1 and self.id==" &
         "42);fin=1 end})",
         "assert(fin==1)");
   end Actual_Argument;

   procedure Discarded_Handler_Results;
   procedure Discarded_Handler_Results is
   begin
      --  Return false, nil, and an integer from a successful finalizer.
      --  Resume ordinary Lua execution after protected callback completion.
      --  A false return value is not mistaken for a callback failure.
      Check
        ("fin=0;candidate=setmetatable({},{__gc=function()fin=1;r" &
         "eturn false,nil,42 end})",
         "assert(fin==1)");
   end Discarded_Handler_Results;

   procedure Removed_Handler_Skipped;
   procedure Removed_Handler_Skipped is
   begin
      --  Queue an object, then remove its metatable before dispatch.
      --  Run the actual scheduler with the pending obligation still owned.
      --  A missing current handler is skipped without a warning or fallback.
      Check
        ("fin=0;candidate=setmetatable({},{__gc=function()fin=1 e" &
         "nd})",
         "assert(fin==0)", Remove_Handler => True);
   end Removed_Handler_Skipped;

   procedure Protected_Handler_Error;
   procedure Protected_Handler_Error is
   begin
      --  Disable default warnings and raise an ordinary Lua error in __gc.
      --  Execute a new chunk through the same real scheduler.
      --  The finalizer error is consumed and later script execution continues.
      Check
        ("warn('@off');fin=0;candidate=setmetatable({},{__gc=func" &
         "tion()fin=1;error('gc failed',0)end})",
         "assert(fin==1);assert(6*7==42)");
   end Protected_Handler_Error;

   procedure Callback_Graph_Roots;
   procedure Callback_Graph_Roots is
   begin
      --  The target owns a self cycle and a child table.
      --  Force real tracing from within the active callback.
      --  Current target, handler and child graph remain rooted throughout.
      Check
        ("fin=0;candidate={child={n=42}};candidate.self=candidate" &
         ";setmetatable(candidate,{__gc=function(self)collectgarb" &
         "age();assert(self.self==self and self.child.n==42);fin=" &
         "1 end})",
         "assert(fin==1)");
   end Callback_Graph_Roots;

   procedure Hidden_Control_Frames;
   procedure Hidden_Control_Frames is
   begin
      --  Inspect a running Lua finalizer through debug.getinfo.
      --  Read its logical caller while actual helper activations are active.
      --  Internal finalizer/protection phases do not appear as C frames.
      Check
        ("fin=0;candidate=setmetatable({},{__gc=function()assert(" &
         "debug.getinfo(1,'S').what=='Lua');assert(debug.getinfo(" &
         "2,'S').what=='main');fin=1 end})",
         "assert(fin==1)");
   end Hidden_Control_Frames;

   procedure Hook_Policy_Restored;
   procedure Hook_Policy_Restored is
   begin
      --  Enable call, return, line and instruction-count hooks.
      --  Call nested Lua code in the finalizer and then disable the hook.
      --  The callback sees no hook events; ordinary execution resumes hooks.
      Check
        ("hits=0;during=-1;debug.sethook(function()hits=hits+1 en" &
         "d,'crl',1);candidate=setmetatable({},{__gc=function()lo" &
         "cal before=hits;local function inner()return 42 end;ass" &
         "ert(inner()==42);during=hits-before end})",
         "debug.sethook();assert(during==0 and hits>0)");
   end Hook_Policy_Restored;

   procedure Coroutine_Handler_Barrier;
   procedure Coroutine_Handler_Barrier is
   begin
      --  Run the queued callback in a real secondary thread context.
      --  Inspect yieldability inside the handler and after its completion.
      --  The handler barrier is temporary and belongs to that context.
      Check
        ("fin=0;entry=function()end;candidate=setmetatable({},{__" &
         "gc=function()assert(not coroutine.isyieldable());fin=1 " &
         "end})",
         "assert(fin==1 and coroutine.isyieldable())", Secondary => True);
   end Coroutine_Handler_Barrier;

   procedure Quota_Abort_Recovery;
   procedure Quota_Abort_Recovery is
      State : World;
      Item, Key : Value;
      function Selected (Node : Object_Access) return Boolean;
      function Selected (Node : Object_Access) return Boolean is
        (Node = Item.Reference);
   begin
      Initialize (State, (others => <>));
      begin
         --  Run an endless handler inside pcall with a small explicit host
         --  budget. Quota exhaustion must abandon the complete chain rather
         --  than becoming a warning/catchable Lua result or restarting work.
         Assert (Execute (State,
           "fin=0;candidate=setmetatable({},{__gc=function()" &
           "fin=fin+1;pcall(function()while true do end end)end})",
           "finalizer-quota-setup"), "quota fixture setup");
         Begin_Operation (State);
         Key := New_String (State, "candidate");
         Item := Get (Global_Environment (State), Key);
         F.Register (State, Item);
         F.Queue_Unreachable (State, Selected'Access);
         Set (State, Global_Environment (State), Key, Nil_Value);
         End_Operation (State);
         State.Bounds.Instructions := 2_000;
         State.Saved_Bounds.Instructions := 2_000;
         Assert (not Execute (State, "error('unreached')", "quota-abort")
                   and then State.Current.Failure_Class = Host_Abort,
                 "handler quota was caught or converted into a Lua error");
         Assert (not State.Finalizer_Active and then
                   State.Finalizing_Object = null and then
                   State.Current.Finalizer_Hook_Suppression = 0 and then
                   State.Current.Non_Yieldable = 0 and then
                   State.Current.Stack.Is_Empty,
                 "quota abort retained finalizer execution state");
         Assert (Execute (State, "assert(fin==1 and 6*7==42)", "recovery"),
                 "aborted finalizer restarted or damaged later execution");
      exception
         when others => End_Operation (State); Finalize (State); raise;
      end;
      Finalize (State);
   end Quota_Abort_Recovery;

   procedure Unavailable_C_Stack_Defers;
   procedure Unavailable_C_Stack_Defers is
      State : World;
      Item, Key : Value;
      function Selected (Node : Object_Access) return Boolean;
      function Selected (Node : Object_Access) return Boolean is
        (Node = Item.Reference);
   begin
      Initialize (State, (others => <>));
      begin
         --  Model inherited native depth at the collector's documented
         --  minimum-call-space boundary. The interrupted caller must execute
         --  its next instruction, not repeatedly create a doomed GC helper.
         Assert (Execute (State,
           "fin=0;candidate=setmetatable({},{__gc=function()fin=1 end})",
           "deferred-setup"), "deferred finalizer fixture setup");
         Begin_Operation (State);
         Key := New_String (State, "candidate");
         Item := Get (Global_Environment (State), Key);
         F.Register (State, Item);
         F.Queue_Unreachable (State, Selected'Access);
         Set (State, Global_Environment (State), Key, Nil_Value);
         End_Operation (State);
         State.Bounds.Instructions := 5_000;
         State.Native_Depth :=
           Lua.Runtime_Configuration.Maximum_C_Calls - 2;
         Assert (Execute (State, "assert(fin==0)", "deferred-caller"),
                 "deferred finalizers starved the interrupted caller");
         Assert (F.Has_Pending (State) and then not State.Finalizer_Active,
                 "minimum-space refusal consumed a pending obligation");
         State.Native_Depth := 0;
         Assert (Execute (State, "assert(fin==1)", "later-cycle"),
                 "a later collection failed to retry the pending target");
      exception
         when others => End_Operation (State); Finalize (State); raise;
      end;
      Finalize (State);
   end Unavailable_C_Stack_Defers;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "finalizer execution: handler receives actual target",
         Actual_Argument'Access);
      Test_Support.Add
        (Suite, "finalizer execution: handler results are discarded",
         Discarded_Handler_Results'Access);
      Test_Support.Add
        (Suite, "finalizer execution: removed handler is skipped",
         Removed_Handler_Skipped'Access);
      Test_Support.Add
        (Suite, "finalizer execution: callback error is protected",
         Protected_Handler_Error'Access);
      Test_Support.Add
        (Suite, "finalizer execution: callback graph survives collection",
         Callback_Graph_Roots'Access);
      Test_Support.Add
        (Suite, "finalizer execution: control frames stay hidden",
         Hidden_Control_Frames'Access);
      Test_Support.Add
        (Suite, "finalizer execution: hooks suppressed only in callback",
         Hook_Policy_Restored'Access);
      Test_Support.Add
        (Suite, "finalizer execution: secondary handler barrier",
         Coroutine_Handler_Barrier'Access);
      Test_Support.Add
        (Suite, "finalizer execution: quota abort and recovery",
         Quota_Abort_Recovery'Access);
      Test_Support.Add
        (Suite, "finalizer execution: minimum space defers without starvation",
         Unavailable_C_Stack_Defers'Access);
   end Register;
end Lua.Finalizer_Runtime_Tests;
