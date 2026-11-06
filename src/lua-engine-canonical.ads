with Lua.Prototypes;

package Lua.Engine.Canonical is
   --  Canonical words operate on scalar registers. Lua/native transfers stay
   --  in Machine's single scheduler: this package never calls an executor or
   --  keeps an Ada activation across a user callback.
   type Action_Kind is
     (Advanced, Invoke_Helper, Invoke_Function, Tail_Invoke,
      Return_Results, Close_From_Register);
   type Action is record
      Kind : Action_Kind := Advanced;
      Helper : Unbounded_String;
      Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Function_Value : Value;
      Arguments : Values.Vector;
      Destination : Natural := 0;
      Close_From : Natural := 0;
      Call_Base : Natural := 0;
      Has_Call_Window : Boolean := False;
      --  Absolute original callee slot, distinct from relative result IDs.
   end record;
   --  Every callback packet is also retained in its owning frame before Step
   --  returns. Machine publishes it into the next explicit activation before
   --  ending the current operation. Destination is register index + 1.

   function Adopt_Program
     (State : in out World; Program : in out Lua.Prototypes.Program)
      return Prototype_Access;
   --  Transfer a checked graph and retain its initial compilation bridge.
   --  The caller publishes a closure/frame before clearing Entry_Code.

   function Adopt
     (State : in out World; Program : in out Lua.Prototypes.Program;
      Environment : Value) return Value;
   --  Move a checked canonical graph into this universe and create its main
   --  closure with an actual initial environment cell. No graph is copied.
   --  The program and every runtime constant use this universe's allocator.

   procedure Initialize_Frame
     (State : in out World; Activation : Frame_Access;
      Arguments : Values.Vector);
   --  Initialize scalar storage after Machine has published the activation.
   --  Initial parameters, varargs and named-vararg tables remain traced.

   function Step
     (State : in out World; Activation : Frame_Access) return Action;
   --  Execute one real canonical instruction, or request a scheduler action.
   --  Lua representation errors are controlled language errors; no invalid
   --  opcode/operand is passed to an unchecked enumeration conversion.

   function Vararg_Length (Activation : Frame_Access) return Natural;
   function Read_Vararg
     (State : in out World; Activation : Frame_Access; Index : Positive)
      return Value;
   procedure Write_Vararg
     (State : in out World; Activation : Frame_Access; Index : Positive;
      Item : Value);
   --  Debugger access to actual hidden argument slots. Named varargs reside
   --  in their real table and do not expose negative local stack indexes.

   function Source_Bytes (Code : Prototype_Access) return Byte_String;
   --  Borrow the immutable model's source bytes while Code remains rooted.
   function Local_Name
     (State : in out World; Code : Prototype_Access; Index : Positive;
      PC : Natural) return Value;
   --  Read the indexed live local name from actual zero-based PC lifetimes.
   function Upvalue_Name
     (State : in out World; Code : Prototype_Access; Index : Positive)
      return Value;
   --  Read the actual canonical descriptor name (or stripped-name marker).

   procedure Deliver
     (State : in out World; Activation : Frame_Access;
      Results : Values.Vector);
   --  Resume the pending operation, including fixed/open result adjustment,
   --  conditional skip decisions and right-associated concatenation.

   procedure Prepare_Close
     (State : in out World; Activation : Frame_Access; From : Natural);
   --  Freeze exiting stack values, then detach open upvalue cells before
   --  callbacks on all exit paths, including errors and coroutine closing.
   procedure Close_Cells (Activation : Frame_Access; From : Natural);
   --  Detach open register/cell associations at or above From. Closures keep
   --  their actual individually owned cells, and later bindings get new ones.
   function Read_Register
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Value;
   procedure Write_Register
     (State : in out World; Activation : Frame_Access; Index : Natural;
      Item : Value);
   --  Checked zero-based canonical register access. Writes update open cells.
   function Source_Line (Code : Prototype_Access; PC : Natural)
                         return Natural;
   function Source_Line (Activation : Frame_Access; PC : Natural)
                         return Natural;
   --  Decode real signed line deltas/absolute checkpoints; stripped is zero.
end Lua.Engine.Canonical;
