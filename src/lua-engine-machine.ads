with Lua.Lexers;
with Lua.Storage;
with System;

package Lua.Engine.Machine is
   function Binary_Value
     (State : in out World; Operator : Lua.Lexers.Token_Kind;
      Left, Right : Value) return Value;
   function Unary_Value
     (State : in out World; Operator : Lua.Lexers.Token_Kind;
      Item : Value) return Value;
   --  Shared primitive arithmetic used by both execution backends. These
   --  helpers never dispatch metamethods; callers must select primitive
   --  applicability before bypassing a canonical metamethod instruction.

   type For_Failure_Kind is
     (Initial_Not_Number, Limit_Not_Number, Step_Not_Number, Zero_Step);
   procedure For_Error
     (State : in out World; Kind : For_Failure_Kind;
      Item : Value := Nil_Value);
   --  Raise the pinned numeric-for diagnostic at its actual Lua source.
   --  Conversion failures use Item's table/userdata diagnostic type; zero
   --  step has no offending type and ignores the default nil Item.

   procedure Concatenate_Primitives
     (State : in out World; First : Positive; Last : in out Natural);
   --  Fold the convertible suffix of an actual C operand interval. Publish
   --  each run in its first slot and consume its other slots. Stop at the
   --  first handler-requiring pair; First=Last means a complete result.
   --  The current addressed C/borrowed window owns all input/result roots.

   function Ensure_Stack
     (State : in out World; Context : not null Context_Access;
      Last : Natural; Raise_Error : Boolean := True) return Boolean;
   --  Last is inclusive; native top pointers name Last+1. Physical storage
   --  includes five hidden extra rows. First overflow installs the pinned
   --  200-row error stack; another growth request there becomes ERRERR.

   procedure Prepare_C_Call_Storage
     (State : in out World; Context : not null Context_Access;
      Window_Last : Natural);
   --  Before publishing a Lua window, prepare backing for its actual end
   --  plus the public minimum C-call space, using the normal capped growth
   --  rule. This changes no semantic bound, top or window. Allocation refusal
   --  preserves those fields; physical buffer capacity may remain larger.

   procedure Shrink_Error_Stack
     (State : in out World; Context : not null Context_Access);
   --  Reevaluate the overflow latch after protected recovery. Retained
   --  backing-vector capacity is separate from the semantic stack bound.

   procedure Resize_Stack_Window
     (State : in out World; Activation : Frame_Access; Count : Natural);
   --  Validate the actual absolute semantic extent, reserve paired scalar
   --  storage, then publish this real frame's current window. Hidden holders
   --  never call this helper and consume no invented Lua slots. A noncurrent
   --  parent may grow its reservation without overwriting a child's ci.top.

   procedure Begin_Hook_View
     (State : in out World; Context : not null Context_Access;
      Token : Callback_Identity);
   procedure End_Hook_View
     (State : in out World; Context : not null Context_Access;
      Token : Callback_Identity);
   --  Called only by the actual C hook transport's guarded entry. The
   --  private argument window retires before borrowing interrupted cells;
   --  the real callback guard/serial retains continuation/error ownership.
   --  End is also performed by typed completion/abandonment if C cannot
   --  return normally. Neither procedure executes callbacks or another VM.

   function Reserve_Native_Results
     (State : in out World; Activation : not null Frame_Access;
      Count : Natural) return Boolean;
   --  Nonthrowing semantic reservation above a real native argument/result
   --  prefix, matching lua_checkstack before a library builds many results.
   --  A false result lets that library issue its own pinned argument error.

   procedure Set_Native_Top
     (State : in out World; Activation : not null Frame_Access;
      Count : Natural);
   --  Apply lua_settop to a running native activation's actual shared
   --  window and owned argument view. Removed values stop being roots.

   procedure Push_Native_Value
     (State : in out World; Activation : not null Frame_Access;
      Item : Value);
   --  Append one rooted scalar through the same reservation/publication
   --  path. The native activation must be the current real stack window.

   procedure Prepare_Argument_Diagnostic
     (State : in out World; Owner : not null Frame_Access);
   --  A directly called builtin can fail while a hidden phase still owns
   --  its working scalar prefix. Transfer that actual prefix to the original
   --  public C owner and retire the failed phase's window/request. The failed
   --  operation must never resume; no callback or executor is invoked here.

   type Driver is limited private;
   type Driver_Access is access Driver;
   for Driver_Access'Storage_Pool use Lua.Storage.Pool;
   --  A driver borrows one stable universe and its root context. It contains
   --  no access-to-nested-subprogram closure or saved Ada activation. The
   --  universe must outlive Start through Finish; serialize its operations.

   procedure Start
     (Self : in out Driver; State : not null World_Access;
      Code : Prototype_Access);
   procedure Start
     (Self : in out Driver; State : not null World_Access;
      Function_Value : Value; Arguments : Values.Vector);
   --  Schedule a new call on an empty context without resetting the budget.
   --  Arguments/callee become explicit frame and operation roots.
   --  @param Self An idle driver, or one released by Finish.
   --  @param State Owning universe, retained by its host during this borrow.

   procedure Start_Host_Main
     (Self : in out Driver; State : not null World_Access;
      Arguments : Values.Vector);
   --  Enter one actual native CLI-main activation behind root protection.
   --  Pump until Host_Work_Requested before performing idle host policy.
   --  Its implemented builtin identity is callable but rejects reentry and
   --  calls outside this explicit live owner; no borrowed host pointer exists.

   function Host_Work_Requested (Self : Driver) return Boolean;
   --  A typed suspension of the native host continuation, not a Lua yield or
   --  completed drive. The same driver/context/frame remain owned until the
   --  next host call or explicit Complete_Host_Main/Cancel.

   procedure Begin_Host_Call
     (Self : in out Driver; Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value; Wanted_Results : Integer := -1);
   --  Schedule a protected child above the retained actual host activation.
   --  Call only at a host-work request; arguments become owned frame roots
   --  before returning. No callback or executor runs synchronously here.
   --  Publish the real handler/function/argument window above the existing
   --  host prefix. Minus one keeps all results; a nonnegative count adjusts
   --  them before returning host work, as the public protected call does.

   procedure Take_Host_Results
     (Self : Driver; Packet : in out Values.Vector;
      Failure : out Failure_Kind; Handler_Called : out Boolean);
   --  Move the completed child's protected status/results into a traced
   --  destination at the next host-work request. Preserve failure class and
   --  actual handler invocation; no fresh status packet is manufactured.

   procedure Complete_Host_Main (Self : in out Driver; Success : Boolean);
   --  Resume the real native main continuation to return one true result or
   --  no result, matching pmain's successful/failed normal return. Pump to
   --  Is_Complete, then Finish. Cancellation abandons it without return hooks.

   procedure Step (Self : in out Driver);
   --  Perform one scheduler transfer or one Lua/native/hook execution step.
   --  Return to the caller before any future foreign callback is invoked.
   --  Internal language/host failures remain structured in the universe and
   --  raise Language_Error; Finish releases the failed driver's borrow.

   function Is_Complete (Self : Driver) return Boolean;
   --  True when the root drive reaches a terminal completion/yield packet.
   --  It never means failed execution succeeded; inspect Outcome separately.

   function Outcome (Self : Driver) return Transfer_Kind;
   function Results (Self : Driver) return Values.Vector;
   --  Inspect the completed drive's real packet. It remains traced through
   --  the root context until Finish; publish copies into owned roots first.

   procedure Finish (Self : in out Driver);
   --  Release a completed/failed borrow. Idempotent for an idle driver; an
   --  active unfinished driver is a misuse, rather than silent abandonment.

   procedure Cancel (Self : in out Driver);
   --  Release an interrupted foreign pump's borrow after an exceptional
   --  boundary exit. No callback executes here; retained root frames remain
   --  available to the ordinary context close/recovery protocol.

   procedure Deliver_Owned
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : in out Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False);
   --  Transfer a packet already rooted by its source holder. A null target
   --  publishes the current context's completed result; native targets take
   --  ownership without copying. Canonical targets consume a borrowed view
   --  before the caller retires the holder. Packet is consumed on success.
   --  Scalar destination growth, when needed, remains an ordinary allocation;
   --  protected holders reserve their bounded failure destination in advance.

   procedure Take_Results (Self : Driver; Packet : in out Values.Vector);
   --  Move the completed root result without allocation. Packet must belong
   --  to a traced owner before any subsequent VM/allocator safe point. Foreign
   --  publication uses Context.Boundary_Results until the C stack owns values.

   function New_Driver (State : in out World) return Driver_Access;
   procedure Free_Driver (Self : in out Driver_Access);
   --  Foreign control blocks retain an initialized driver allocated through
   --  their universe's provider. Free only an idle/released drive.

   procedure Start_Foreign
     (Self : in out Driver; State : not null World_Access;
      Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False;
      Retained_Depth : Natural := 0; Direct_Builtin : Boolean := False);
   procedure Start_Foreign
     (Self : in out Driver; State : in out World;
      Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False;
      Retained_Depth : Natural := 0; Direct_Builtin : Boolean := False);
   --  Both forms borrow one real world until Finish/Cancel. The in-out form
   --  also supports C calls on another context of an Ada-owned session; it
   --  never transfers universe ownership or resets the existing work budget.
   --  Start a C-entry call behind an owned protected holder. Its handler runs
   --  above intact failed frames; the terminal packet has a success boolean.

   procedure Start_Resume
     (Self : in out Driver; State : in out World;
      Callee : Value; Arguments : Values.Vector;
      Fresh : Boolean; Call_Base : Natural := 0);
   --  Borrow an addressed context for the C lua_resume protocol. A suspended
   --  activation receives its actual resume arguments; no executor recurses.
   --  The limited world is passed by reference and must outlive this drive.
   --  Its terminal packet is the actual return/yield/error sequence without
   --  an invented protected-call boolean.

   function Has_Thread_Closers (Context : not null Context_Access)
                                return Boolean;
   --  Inspect actual pending Lua/C closing owners without allocating.

   procedure Reset_Without_Closers
     (State : in out World; Native_Base : Natural)
     with Pre => not Has_Thread_Closers (State.Current);
   --  Reset an addressed idle/suspended thread without a callback or drive.
   --  Existing failure ownership stays rooted for C status publication.

   procedure Start_Close_Thread
     (Self : in out Driver; State : in out World; Native_Base : Natural;
      Self_Close : Boolean := False);
   --  Start a real reset/closing walk after every target C body has been
   --  abandoned. A self-close reuses the current driver/resumer relationship;
   --  other closes borrow an idle driver and restore their caller in C.

   procedure Acknowledge_Self_Close
     (Self : Driver; Token : Callback_Identity);
   --  Validate one exact actual callback and relinquish its live C window.
   --  This never executes or physically releases any pending close owner.

   function Needs_Foreign_Call (Self : Driver) return Boolean;
   function Foreign_Handler (Self : Driver) return System.Address;
   function Foreign_Token (Self : Driver) return Callback_Identity;
   function Foreign_Context (Self : Driver) return Context_Access;
   function Foreign_Continuation (Self : Driver) return System.Address;
   function Foreign_KContext (Self : Driver) return Interfaces.C.ptrdiff_t;
   function Foreign_KStatus (Self : Driver) return Interfaces.C.int;
   --  Inspect a suspended C callback request after Step has returned. The
   --  C-owned pump invokes its handler; no Ada activation may span that call.
   --  Arguments are rooted on the addressed context's base-relative C stack.

   procedure Complete_Foreign_Call
     (Self : Driver; Result_Count : Natural; Error_Status : Natural := 0;
      Handler_Called : Boolean := False;
      Token : Callback_Identity);
   --  Publish the C callback's real result/error packet and restore its caller
   --  stack base before the next Step. Status zero completes normally; two
   --  and four propagate language/memory failure through ordinary protection.
   --  Token is the exact identity returned with this callback request; a
   --  stale/null/other activation identity is rejected before state mutation.

   procedure Adopt_Deferred_Error_Scopes
     (State : in out World; Token : Callback_Identity;
      Owner : out Frame_Access; Prefix_Floor : out Natural;
      Retained_Traceback : out Boolean);
   --  After the exact regular C guard has returned, remove its held error
   --  view and restore the context-owned scope chain without allocation or
   --  executing an old PC. The token is the real completed callback identity;
   --  all inner borrowed guards must have acknowledged first. Reject a stale
   --  owner or a noncurrent error view before mutation. The caller chooses
   --  protected recovery or genuine thread reset and retires execution there.

   procedure Start_Foreign_Boundary
     (Self : Driver; Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False;
      Yieldable : Boolean := False; Wanted : Integer := 0;
      Protected_Call : Boolean := False; Direct_Builtin : Boolean := False;
      Error_Token : Callback_Identity := (others => <>));
   function Has_Foreign_Result (Self : Driver) return Boolean;
   function Pending_Foreign_Error_Transfer (Self : Driver) return Boolean;
   --  A regular unprotected C guard still owns this error. Its actual
   --  temporary C view is already published; the pump must not overwrite
   --  preserved closing slots before the matching callback acknowledges it.
   procedure Take_Foreign_Result
     (Self : Driver; Packet : in out Values.Vector; Error_Status : out Natural;
      Handler_Called : out Boolean);
   function Current_Message_Handler (Self : Driver) return Value;
   --  Reentrant C lua_call/pcall uses a protected sentinel on this same drive.
   --  The nested C pump stops at that explicit boundary, without completing
   --  or recursively entering the outer interpreter drive.

   procedure Run (State : in out World; Code : Prototype_Access);
   --  Synchronous Ada convenience wrapper over Start, Step and Finish.

   procedure Run_Retaining (State : in out World; Code : Prototype_Access);
   --  Run Code exactly like Run, but on normal completion move the chunk's
   --  result packet into State.Current.Arguments. That vector is a traced
   --  root, so the values survive every later allocation and collection
   --  until the caller consumes or clears it. A typed process exit, which
   --  produces no displayable packet, leaves the vector empty. Failure
   --  propagates as in Run and retains nothing.

   procedure Run_Display (State : in out World);
   --  Start a sequential drive to resolve the current global print through
   --  ordinary lookup and call it with State.Current.Arguments. Hidden host
   --  phases add no Lua helper frame. Never call from an active drive.

   procedure Run_Warning_Control (State : in out World; Enabled : Boolean);
   --  Deliver a host warning control through the actual warning handler,
   --  independently of replaceable Lua globals. Custom C callbacks use the
   --  ordinary borrowed portal and complete before this host call returns.

   procedure Run_Package_Environment
     (State : in out World; Ignore_Environment : Boolean);
   --  Configure native package paths and the real LUA_NOENV registry marker
   --  through an idle borrowed driver, including deferred release callbacks.

   procedure Close_Lua_State (State : in out World);
   --  Drive an idle main thread's TBC/finalizer close protocol, leaving
   --  physical ownership with the caller. Never call from an active drive.
   procedure Drain_External_Releases (State : in out World);
   --  Borrow an idle driver to release queued external payloads before
   --  physical teardown. No executor step spans a C allocator callback.

   procedure Retire_Frame_Execution
     (State : in out World; Item : not null Frame_Access)
     with Pre => Item.Context = State.Current and then
       (not Item.Has_Stack_Window or else
        Item.Context.Stack_Window = Item);
   --  Retire genuinely abandoned execution ownership exactly once, visiting
   --  physical windows from top to bottom. The caller establishes the active
   --  native-depth accounting and preserves any scalar prefix needed during
   --  closing before this call. Closed cells/frozen closers/code stay rooted
   --  until physical release; pending result/argument temporaries do not.
   --  Never call across a live foreign body: acknowledge its typed C transfer
   --  first. An already retired activation is harmless; reuse resets it.

   function Pending_Closing_Level
     (Item : not null Frame_Access) return Natural;
   --  Highest actual C/Lua closing slot retained by this frame. The private
   --  packet backend has no scalar level and continues owning its cells.
   --  This reads pending metadata in linear time without allocation.

   procedure Set_Closing_Stack_Prefix
     (State : in out World; Level : Natural)
     with Pre => State.Current /= null and then
       Level <= Natural (State.Current.Foreign_Stack.Length);
   --  Publish an actual scalar prefix and recompute its physical/public
   --  high-water marks without allocation. Callers save/restore the previous
   --  floor and never lower below another active cleanup owner's prefix.
   --  No blind range clear occurs: union tracing preserves real surviving
   --  closer windows while discarding abandoned gaps at the next collection.

   procedure Clear_Frames
     (State : in out World; Retained_Depth : Natural := 0);
   --  Release all frame-owned packets after success or failed execution.

private
   type World_View is access all World;
   type Host_Phase is
     (No_Host, Starting_Host, Waiting_Host, Calling_Host_Child,
      Returning_Host_Success, Returning_Host_Failure);
   type Driver is limited record
      Universe : World_View;
      Root_Context : Context_Access;
      Entry_Depth : Natural := 0;
      Done : Boolean := False;
      Failed : Boolean := False;
      Host_Main : Frame_Access;
      Host_State : Host_Phase := No_Host;
      Host_Waiting : Boolean := False;
      Host_Prefix : Natural := 0;
      Host_Wanted : Integer := -1;
      --  A borrowed pointer to the actual stack-owned native activation.
      --  Only Waiting_Host permits host access; membership is checked before
      --  dereference. Finish/Cancel remove the borrow before its owner ends.
   end record;
end Lua.Engine.Machine;
