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
      Message_Handler : Value := Nil_Value);
   --  Start a C-entry call behind an owned protected holder. Its handler runs
   --  above intact failed frames; the terminal packet has a success boolean.

   function Needs_Foreign_Call (Self : Driver) return Boolean;
   function Foreign_Handler (Self : Driver) return System.Address;
   function Foreign_Context (Self : Driver) return Context_Access;
   --  Inspect a suspended C callback request after Step has returned. The
   --  C-owned pump invokes its handler; no Ada activation may span that call.
   --  Arguments are rooted on the addressed context's base-relative C stack.

   procedure Complete_Foreign_Call
     (Self : Driver; Result_Count : Natural; Error_Status : Natural := 0;
      Handler_Called : Boolean := False);
   --  Publish the C callback's real result/error packet and restore its caller
   --  stack base before the next Step. Status zero completes normally; two
   --  and four propagate language/memory failure through ordinary protection.

   procedure Start_Foreign_Boundary
     (Self : Driver; Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value);
   function Has_Foreign_Result (Self : Driver) return Boolean;
   procedure Take_Foreign_Result
     (Self : Driver; Packet : in out Values.Vector; Error_Status : out Natural;
      Handler_Called : out Boolean);
   function Current_Message_Handler (Self : Driver) return Value;
   --  Reentrant C lua_call/pcall uses a protected sentinel on this same drive.
   --  The nested C pump stops at that explicit boundary, without completing
   --  or recursively entering the outer interpreter drive.

   procedure Run (State : in out World; Code : Prototype_Access);
   --  Synchronous Ada convenience wrapper over Start, Step and Finish.

   procedure Clear_Frames (State : in out World);
   --  Release all frame-owned packets after success or failed execution.

private
   type World_View is access all World;
   type Driver is limited record
      Universe : World_View;
      Root_Context : Context_Access;
      Done : Boolean := False;
      Failed : Boolean := False;
   end record;
end Lua.Engine.Machine;
