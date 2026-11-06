with Lua.Engine.Finalizers;
with Ada.Characters.Latin_1;
with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with System.Address_To_Access_Conversions;
with Interfaces;
with Interfaces.C;
with Lua.Integers;
with Lua.Lexers; use Lua.Lexers;
with Lua.Platform_Numerics;
with Lua.Prototypes;
with Lua.Runtime_Configuration;
with Lua.Engine.Strings;
with Lua.Engine.Packing;
with Lua.Engine.Unicode;
with Lua.Engine.Core_Libraries;
with Lua.Engine.Pattern_Drivers;
with Lua.Engine.Loaders;
with Lua.Engine.Format_Drivers;
with Lua.Engine.Table_Drivers;
with Lua.Engine.Sorting;
with Lua.Engine.Inspection;
with Lua.Engine.Canonical;
with Lua.Engine.Stacks;
with Lua.Engine.Foreign;
with Lua.Engine.Warnings;

package body Lua.Engine.Machine is
   GC_Warning_Start_Text : aliased constant String :=
     "error in " & ASCII.NUL;
   GC_Warning_Start : constant Byte_String :=
     (GC_Warning_Start_Text'Address,
      GC_Warning_Start_Text'Length - 1);
   GC_Warning_Where_Text : aliased constant String :=
     "__gc" & ASCII.NUL;
   GC_Warning_Where : constant Byte_String :=
     (GC_Warning_Where_Text'Address,
      GC_Warning_Where_Text'Length - 1);
   GC_Warning_Open_Text : aliased constant String :=
     " (" & ASCII.NUL;
   GC_Warning_Open : constant Byte_String :=
     (GC_Warning_Open_Text'Address,
      GC_Warning_Open_Text'Length - 1);
   GC_Warning_Close_Text : aliased constant String :=
     ")" & ASCII.NUL;
   GC_Warning_Close : constant Byte_String :=
     (GC_Warning_Close_Text'Address,
      GC_Warning_Close_Text'Length - 1);
   GC_Warning_Nonstring_Text : aliased constant String :=
     "error object is not a string" & ASCII.NUL;
   GC_Warning_Nonstring : constant Byte_String :=
     (GC_Warning_Nonstring_Text'Address,
      GC_Warning_Nonstring_Text'Length - 1);

   --  The VM is the only executor of compiled chunks. Registers hold result
   --  packets rather than plain values; every primitive explicitly chooses
   --  scalar or expanding consumption. Lua calls use the owned frame vector,
   --  leaving the Ada call stack independent of user recursion depth.
   use type Ada.Containers.Count_Type;
   use type Ada.Exceptions.Exception_Id;
   use type Integer_Value;
   use type Lua.Prototypes.Prototype_Access;
   use type System.Address;
   use type Interfaces.C.unsigned_long_long;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Numbers.Number_Kind;

   function First (Packet : Values.Vector) return Value is
     (if Packet.Is_Empty then Nil_Value else Packet.First_Element);

   function Scalar (Activation : Frame_Access;
     Register_Id : Natural)
                    return Value is
     (if Register_Id = 0 then Nil_Value
      else First (Activation.Slots (Register_Id)));

   function Code_Length (Activation : Frame_Access) return Natural is
     (if Activation.Code.Canonical_Node /= null then
         Natural (Activation.Code.Canonical_Node.Code.Length)
      else Natural (Activation.Code.Code.Length));
   function Line_At (Activation : Frame_Access; PC : Positive)
                     return Natural is
     (if Activation.Code.Canonical_Node /= null then
         Canonical.Source_Line (Activation, PC - 1)
      else Activation.Code.Code (PC).Location.Line);
   --  Both backends use one-based execution PCs. Canonical debug records use
   --  zero-based word offsets, and stripped chunks intentionally return zero.

   procedure Put_Packet
     (State : in out World; Activation : Frame_Access; Register_Id : Positive;
      Packet : Values.Vector);
   procedure Put_One
     (State : in out World; Activation : Frame_Access; Register_Id :
       Positive; Item : Value);
   function Flatten
     (Activation : Frame_Access; Inputs : Registers.Vector;
      Expand_Last : Boolean := True) return Values.Vector;
   function Numeric (State : in out World; Item : Value)
                     return Lua.Numbers.Number;
   function Diagnostic_Type (State : in out World; Item : Value)
                            return String;
   function Integral (State : in out World; Item : Value) return Integer_Value;
   procedure Put_Packet
     (State : in out World; Activation : Frame_Access; Register_Id : Positive;
      Packet : Values.Vector)
   is
      --  Coercion belongs at the primitive operation boundary, not in the
      --  stored value. A numeric string remains a string for type/identity.
   begin
      declare
         Old_Extra : constant Natural := Natural'Max
           (1, Natural (Activation.Slots (Register_Id).Length)) - 1;
         New_Extra : constant Natural :=
           Natural'Max (1, Natural (Packet.Length)) - 1;
         Delta_Slots : constant Integer := New_Extra - Old_Extra;
      begin
         --  One scalar slot is already charged by the prototype. Expanding
         --  packets charge their additional live slots, including duplicates
         --  retained by separate registers in this private backend.
         if Delta_Slots > 0 and then Delta_Slots >
           Lua.Runtime_Configuration.Maximum_Stack - Natural'Min
             (Lua.Runtime_Configuration.Maximum_Stack,
              State.Current.Stack_Slots)
         then
            Fail (State, "stack overflow");
         end if;
         Activation.Slots.Replace_Element (Register_Id, Packet);
         Activation.Slot_Cost := Activation.Slot_Cost + Delta_Slots;
         State.Current.Stack_Slots :=
           State.Current.Stack_Slots + Delta_Slots;
      end;
   end Put_Packet;

   procedure Put_One
     (State : in out World; Activation : Frame_Access; Register_Id :
       Positive; Item : Value)
   is
      Packet : Values.Vector := Owned_Values (State);
   begin
      Packet.Append (Item);
      Put_Packet (State, Activation, Register_Id, Packet);
   end Put_One;

   function Flatten
     (Activation : Frame_Access; Inputs : Registers.Vector;
      Expand_Last : Boolean := True) return Values.Vector
   is
      Result : Values.Vector := Owned_Values (Activation.Memory);
   begin
      --  Nonfinal expressions contribute one value, including nil for zero
      --  results. Only the final unparenthesized call/vararg packet expands.
      for Index in Inputs.First_Index .. Inputs.Last_Index loop
         if Expand_Last and then Index = Inputs.Last_Index then
            for Item of Activation.Slots (Inputs (Index)) loop
               Result.Append (Item);
            end loop;
         else
            Result.Append (Scalar (Activation, Inputs (Index)));
         end if;
      end loop;
      return Result;
   end Flatten;

   function Diagnostic_Type (State : in out World; Item : Value)
                            return String
   is
      Name : constant Value := Metafield (State, Item, "__name");
   begin
      --  type() remains the language's primitive category. Error wording
      --  alone honors a raw string __name supplied by the object's owner.
      return (if Name.Kind = String_Kind
              then Image (State.Current.Memory, Name)
              else Type_Name (Item));
   end Diagnostic_Type;

   function Numeric (State : in out World; Item : Value)
                     return Lua.Numbers.Number
   is
      Result : Lua.Numbers.Number;
   begin
      case Item.Kind is
         when Integer_Kind =>
            return (Lua.Numbers.Integer_Number, Item.Integer_Data);
         when Real_Kind => return (Lua.Numbers.Real_Number, Item.Real_Data);
         when String_Kind =>
            Result := Read_Number (State, Item.Reference.Bytes);
            if Result.Kind /= Lua.Numbers.Invalid then
               return Result;
            end if;
         when others => null;
      end case;
      Fail (State, "attempt to perform arithmetic on a " &
              Diagnostic_Type (State, Item) & " value");
      return (Kind => Lua.Numbers.Invalid);
   end Numeric;

   function Integral (State : in out World; Item : Value) return Integer_Value
   is
      Number : constant Lua.Numbers.Number := Numeric (State, Item);
      Real : Real_Value;
   begin
      if Number.Kind = Lua.Numbers.Integer_Number then
         return Number.Integer_Item;
      end if;
      Real := Number.Real_Item;
      if Real /= Real or else Real < -2.0 ** 63 or else Real >= 2.0 ** 63
        or else Real_Value'Truncation (Real) /= Real
      then
         Fail (State, "number has no integer representation");
      end if;
      return Integer_Value (Real);
   end Integral;

   function Binary_Value
     (State : in out World; Operator : Token_Kind; Left, Right : Value)
      return Value
   is
      L, R : Lua.Numbers.Number;
      FL, FR, Result : Real_Value;
      IL, IR : Integer_Value;
      function Bits (Item : Integer_Value) return Interfaces.Unsigned_64 is
        (if Item >= 0 then Interfaces.Unsigned_64 (Item) else
           Interfaces.Unsigned_64 (Item - Integer_Value'First) + 2 ** 63);
      function Signed (Item : Interfaces.Unsigned_64) return Integer_Value is
        (if Item < 2 ** 63 then Integer_Value (Item) else
           Integer_Value'First + Integer_Value (Item - 2 ** 63));
      function Ordered (A, B : Value) return Boolean;

      function Ordered (A, B : Value) return Boolean is
      begin
         if A.Kind = String_Kind and then B.Kind = String_Kind then
            return A.Reference.Bytes < B.Reference.Bytes;
         elsif A.Kind in Integer_Kind | Real_Kind and then
           B.Kind in Integer_Kind | Real_Kind
         then
            return Lua.Numbers.Less (Numeric (State, A), Numeric (State, B));
         end if;
         Fail (State, "attempt to compare " & Diagnostic_Type (State, A) &
                 " with " & Diagnostic_Type (State, B));
         return False;
      end Ordered;
   begin
      if Operator in Equal | Not_Equal then
         return (Boolean_Kind,
                 Engine.Equal (Left, Right) = (Operator = Equal));
      elsif Operator in Less | Less_Equal | Greater | Greater_Equal then
         case Operator is
            when Less => return (Boolean_Kind, Ordered (Left, Right));
            when Greater => return (Boolean_Kind, Ordered (Right, Left));
            when Less_Equal =>
               return (Boolean_Kind, Ordered (Left, Right) or else
                         Engine.Equal (Left, Right));
            when others =>
               return (Boolean_Kind, Ordered (Right, Left) or else
                         Engine.Equal (Left, Right));
         end case;
      elsif Operator = Concatenate then
         if Left.Kind not in String_Kind | Integer_Kind | Real_Kind or else
           Right.Kind not in String_Kind | Integer_Kind | Real_Kind
         then
            Fail (State, "attempt to concatenate a non-string value");
         end if;
         if Image (State.Current.Memory, Left)'Length >
           State.Bounds.String_Bytes - Natural'Min
             (Image (State.Current.Memory, Right)'Length,
              State.Bounds.String_Bytes)
         then
            Fail (State, "string byte limit exceeded", Resource => True);
         end if;
         return New_String
           (State, Image (State.Current.Memory, Left) &
            Image (State.Current.Memory, Right));
      elsif Operator in Bit_And | Bit_Or | Bit_Xor | Shift_Left | Shift_Right
      then
         --  Base argument conversion may accept numeric strings, but Lua's
         --  primitive bitwise operators do not. Keep that policy separate
         --  from Integral, which also serves tonumber/select/error arguments.
         if Left.Kind = String_Kind or else Right.Kind = String_Kind then
            Fail (State, "attempt to perform bitwise operation on a string");
         end if;
         IL := Integral (State, Left);
         IR := Integral (State, Right);
         case Operator is
            when Bit_And =>
               return (Integer_Kind, Signed (Bits (IL) and Bits (IR)));
            when Bit_Or =>
               return (Integer_Kind, Signed (Bits (IL) or Bits (IR)));
            when Bit_Xor =>
               return (Integer_Kind, Signed (Bits (IL) xor Bits (IR)));
            when Shift_Left =>
               return (Integer_Kind, Lua.Integers.Shift_Left (IL, IR));
            when others =>
               return (Integer_Kind, Lua.Integers.Shift_Right (IL, IR));
         end case;
      end if;
      L := Numeric (State, Left);
      R := Numeric (State, Right);
      if L.Kind = Lua.Numbers.Integer_Number and then
        R.Kind = Lua.Numbers.Integer_Number and then
        Operator in Plus | Minus | Star | Floor_Divide | Percent
      then
         IL := L.Integer_Item;
         IR := R.Integer_Item;
         case Operator is
            when Plus => return (Integer_Kind, Lua.Integers.Add (IL, IR));
            when Minus =>
               return (Integer_Kind, Lua.Integers.Subtract (IL, IR));
            when Star => return (Integer_Kind, Lua.Integers.Multiply (IL, IR));
            when Floor_Divide =>
               return (Integer_Kind, Lua.Integers.Floor_Divide (IL, IR));
            when others =>
               return (Integer_Kind, Lua.Integers.Modulo (IL, IR));
         end case;
      end if;
      FL := Lua.Numbers.To_Real (L);
      FR := Lua.Numbers.To_Real (R);
      case Operator is
         when Plus => Result := FL + FR;
         when Minus => Result := FL - FR;
         when Star => Result := FL * FR;
         when Slash | Floor_Divide | Percent =>
            if Operator = Percent then
               --  Host fmod supplies its native domain NaNs and preserves
               --  signed zero. Lua then adjusts a nonzero residue toward the
               --  divisor's sign. A quotient/product formula loses precision
               --  and can overflow even when the remainder is small.
               Result := Real_Value (Lua.Platform_Numerics.Remainder
                 (Interfaces.C.double (FL), Interfaces.C.double (FR)));
               if (Result > 0.0 and then FR < 0.0) or else
                 (Result < 0.0 and then FR > 0.0)
               then
                  Result := Result + FR;
               end if;
            else
               --  Ada's checked division cannot expose zero divisors as Lua
               --  values. The narrow host adapter retains target NaN signs
               --  and payloads; every ordinary Ada check stays enabled.
               Result := Real_Value (Lua.Platform_Numerics.Divide
                 (Interfaces.C.double (FL), Interfaces.C.double (FR)));
            end if;
            if Operator = Floor_Divide and then Result = Result
              and then abs Result <= Real_Value'Last
            then
               Result := Real_Value'Floor (Result);
            end if;
         when Power =>
            --  Preserve host libm rounding and all signed-zero/infinity
            --  cases. The differential matrix checks these systematically.
            Result := Real_Value (Lua.Platform_Numerics.Power
              (Interfaces.C.double (FL), Interfaces.C.double (FR)));
         when others => raise Program_Error with "invalid binary opcode";
      end case;
      return (Real_Kind, Result);
   exception
      when Lua.Integers.Arithmetic_Error =>
         Fail (State, "attempt to divide or perform modulo by zero");
         return Nil_Value;
   end Binary_Value;

   function Unary_Value
     (State : in out World; Operator : Token_Kind; Item : Value) return Value
   is
      Number : Lua.Numbers.Number;
   begin
      case Operator is
         when Not_Word => return (Boolean_Kind, not Truth (Item));
         when Length =>
            if Item.Kind = String_Kind then
               return (Integer_Kind,
                       Integer_Value (Lua.Engine.Length
                         (Item.Reference.Bytes)));
            elsif Item.Kind = Table_Kind then
               return (Integer_Kind, Integer_Value (Table_Length (Item)));
            end if;
            Fail (State, "attempt to get length of a " & Type_Name (Item));
         when Minus =>
            Number := Numeric (State, Item);
            if Number.Kind = Lua.Numbers.Integer_Number then
               return (Integer_Kind,
                       Lua.Integers.Negate (Number.Integer_Item));
            end if;
            return (Real_Kind, -Number.Real_Item);
         when Bit_Xor =>
            if Item.Kind = String_Kind then
               Fail
                 (State, "attempt to perform bitwise operation on a string");
            end if;
            return (Integer_Kind,
                    Lua.Integers.Subtract (-1, Integral (State, Item)));
         when others => raise Program_Error with "invalid unary opcode";
      end case;
      return Nil_Value;
   end Unary_Value;

   function Ensure_Stack
     (State : in out World; Context : not null Context_Access;
      Last : Natural; Raise_Error : Boolean := True) return Boolean
   is
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      Bound : Natural := Context.Stack_Allocated_Bound;

      procedure Handling_Overflow;
      procedure Handling_Overflow is
      begin
         --  luaD_errerr bypasses message handling. Reuse the actual stable
         --  bootstrap error object rather than allocate a replacement string
         --  while the error reserve itself has already been exhausted.
         Context.Failure := State.Handling_Error_Value;
         Context.Has_Failure_Value := True;
         Context.Failure_Class := Handling_Failure;
         Context.Failure_Handled := True;
         Context.Failure_Text :=
           To_Unbounded_String ("error in error handling");
         raise Language_Error;
      end Handling_Overflow;
   begin
      if Last < Bound then
         --  Actual vector capacity can be greater, but it never changes this
         --  semantic test. The five physical extras are not general Lua slots.
         Stacks.Reserve (State, Context, Bound + Extra_Stack);
         return True;
      elsif Context.Stack_Error_Phase = Error_Stack then
         if Raise_Error then Handling_Overflow; end if;
         return False;
      elsif Last < Maximum then
         --  Use the pinned 1.5 growth policy and mathematical needed extent.
         --  Maximum is configuration-derived, never adjusted for a fixture.
         Bound := Natural'Min
           (Maximum, Natural'Max (Bound + Bound / 2, Last + 1));
         Stacks.Reserve (State, Context, Bound + Extra_Stack);
         Context.Stack_Allocated_Bound := Bound;
         return True;
      else
         --  Install the error reserve before raising ordinary stack overflow,
         --  so a real handler/closer can run there. A refusal while reserving
         --  it remains a memory error, never permission to use another owner.
         Stacks.Reserve
           (State, Context, Maximum + Error_Stack_Reserve + Extra_Stack);
         Context.Stack_Allocated_Bound := Maximum + Error_Stack_Reserve;
         Context.Stack_Error_Phase := Error_Stack;
         if Raise_Error then Fail (State, "stack overflow"); end if;
         return False;
      end if;
   exception
      when Lua.Storage.Allocation_Error =>
         if Raise_Error then raise; end if;
         --  lua_checkstack is explicitly nonthrowing on allocator refusal.
         --  Keep the old semantic bound/values and consume only the genuine
         --  provider witness; physical Ada exhaustion remains a host abort.
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
      when Program_Error =>
         if Raise_Error or else
           not Lua.Storage.Refusal_Pending (State.Memory)
         then
            raise;
         end if;
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
   end Ensure_Stack;

   procedure Shrink_Error_Stack
     (State : in out World; Context : not null Context_Access)
   is
      pragma Unreferenced (State);
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      In_Use : Natural := Natural'Max
        (Context.Stack_Used, Context.Foreign_Top);
   begin
      if Context.Stack_Error_Phase = Normal_Stack then return; end if;
      --  Unlike ordinary return, shrinking is infrequent and must consider
      --  ancestors' current reservations too. A smaller child ci.top cannot
      --  hide an older live window when deciding whether overflow has ended.
      for Activation of Context.Stack loop
         if Activation.Has_Stack_Window then
            In_Use := Natural'Max
              (In_Use, Activation.Stack_Base +
                 Activation.Stack_Window_Length);
         end if;
      end loop;
      --  stackinuse counts through exclusive ci.top and one additional row;
      --  our stored bounds are inclusive offsets, hence this explicit +2.
      if In_Use > Maximum - 2 then return; end if;
      In_Use := In_Use + 2;
      Context.Stack_Allocated_Bound :=
        (if In_Use > Maximum / 2 then Maximum else In_Use * 2);
      Context.Stack_Error_Phase := Normal_Stack;
   end Shrink_Error_Stack;

   procedure Resize_Stack_Window
     (State : in out World; Activation : Frame_Access; Count : Natural)
   is
      Context : Context_Access;
      Last : Natural;
      Available : Boolean;
   begin
      if Activation = null or else Activation.Context = null or else
        Activation.Lifecycle /= Active
      then
         raise Program_Error with "invalid scalar stack window owner";
      end if;
      Context := Activation.Context;
      if Count > Natural'Last - Activation.Stack_Base
      then
         --  A mathematical request larger than our representation follows
         --  the same overflow path without overflowing Ada index arithmetic.
         Last := Natural'Last;
      else
         Last := Activation.Stack_Base + Count;
      end if;
      Available := Ensure_Stack (State, Context, Last);
      if not Available then
         raise Program_Error with "raising stack reservation returned false";
      end if;
      --  No new top/link is visible until both scalar and cell storage are
      --  initialized. A provider refusal therefore preserves the previous
      --  current window and lets ordinary protected recovery inspect it.
      if not Activation.Has_Stack_Window then
         Activation.Previous_Stack_Window := Context.Stack_Window;
         Activation.Saved_Stack_Used := Context.Stack_Used;
         Activation.Saved_Foreign_Top := Context.Foreign_Top;
         Activation.Has_Stack_Window := True;
         Context.Stack_Window := Activation;
      end if;
      Activation.Stack_Window_Length := Count;
      if Context.Stack_Window = Activation then
         Context.Stack_Used := Last;
      end if;
      --  In particular do not clear a shrinking parent's tail here: a live
      --  child can overlap it. Collector union tracing and actual retirement
      --  own clearing; raw capacity is never a second set of live roots.
   end Resize_Stack_Window;

   function Reserve_Native_Results
     (State : in out World; Activation : not null Frame_Access;
      Count : Natural) return Boolean
   is
      Needed : constant Natural :=
        (if Count > Natural'Last - Activation.Stack_Live_Top then
            Natural'Last else Activation.Stack_Live_Top + Count);
   begin
      if not Activation.Is_Native or else
        not Activation.Has_Stack_Window
      then
         raise Program_Error with "native results have no scalar window";
      end if;
      if not Ensure_Stack
        (State, Activation.Context, Needed, Raise_Error => False)
      then
         return False;
      end if;
      Resize_Stack_Window
        (State, Activation, Natural'Max
           (Activation.Stack_Window_Length, Needed - Activation.Stack_Base));
      return True;
   end Reserve_Native_Results;

   procedure Open_Stack_Window
     (State : in out World; Activation : not null Frame_Access;
      Function_Value : Value; Arguments : Values.Vector;
      Call_Base : Natural; Has_Call_Window : Boolean);
   procedure Retire_Stack_Window
     (Activation : not null Frame_Access);

   procedure Open_Stack_Window
     (State : in out World; Activation : not null Frame_Access;
      Function_Value : Value; Arguments : Values.Vector;
      Call_Base : Natural; Has_Call_Window : Boolean)
   is
      Context : constant Context_Access := Activation.Context;
      Caller : constant Frame_Access := Context.Stack_Window;
      Argument_Count : constant Natural := Natural (Arguments.Length);
      Width : Natural;
      Physical_Last : Natural;
      Available : Boolean;
   begin
      if Activation.Has_Stack_Window or else Context /= State.Current then
         raise Program_Error with "stack window was already published";
      end if;
      if Has_Call_Window and then Call_Base = 0 then
         raise Program_Error with "zero is not a physical call window";
      elsif Has_Call_Window then
         Activation.Stack_Base := Call_Base;
      elsif Caller = null then
         --  The base C context reserves its minimum free capacity but has no
         --  visible activation. A root function is placed after its actual
         --  host prefix, rather than after unused physical/reserved slots.
         Activation.Stack_Base := Context.Foreign_Top + 1;
      elsif Caller.Is_Native then
         --  A library's explicit callback request models pushing the callee
         --  after its live C arguments/temporaries. Hidden VM helpers instead
         --  run above the current real ci.top, matching Protect's top reset.
         Activation.Stack_Base := Caller.Stack_Live_Top + 1;
      else
         Activation.Stack_Base := Context.Stack_Used + 1;
      end if;
      Activation.Call_Base := Activation.Stack_Base;
      if Activation.Is_Native then
         Width :=
           (if Argument_Count > Natural'Last - Minimum_C_Stack then
               Natural'Last else Argument_Count + Minimum_C_Stack);
      else
         Width := Natural (Activation.Code.Canonical_Node.Max_Stack);
      end if;
      --  Excess Lua arguments can initially extend beyond maxstack before
      --  VARARGPREP/discard adjustment. Physical initialization must cover
      --  them too; their packet remains rooted until that setup completes.
      if Natural'Max (Width, Argument_Count) >
          Natural'Last - Activation.Stack_Base
      then
         Physical_Last := Natural'Last;
      else
         Physical_Last := Activation.Stack_Base +
           Natural'Max (Width, Argument_Count);
      end if;
      Available := Ensure_Stack (State, Context, Physical_Last);
      if not Available then
         raise Program_Error with "raising stack reservation returned false";
      end if;
      Resize_Stack_Window (State, Activation, Width);
      --  The callee and all arguments are already explicit operation/frame
      --  roots. Slot copies perform no allocation after publication, so an
      --  overlapping call window never needs borrowed vector references.
      Stacks.Write (State, Context, Activation.Stack_Base, Function_Value);
      for Index in 1 .. Argument_Count loop
         Stacks.Write (State, Context, Activation.Stack_Base + Index,
                       Arguments (Index));
      end loop;
      Activation.Stack_Live_Top := Activation.Stack_Base + Argument_Count;
      if Has_Call_Window and then Caller /= null then
         if Caller.Is_Native then
            Caller.Stack_Live_Top := Activation.Stack_Base - 1;
         else
            Caller.Canonical_GC_Top :=
              Activation.Stack_Base - Caller.Stack_Base;
         end if;
      end if;
   end Open_Stack_Window;

   procedure Retire_Stack_Window
     (Activation : not null Frame_Access)
   is
      Context : constant Context_Access := Activation.Context;
      Previous : Frame_Access;
      Last : Natural;
   begin
      if not Activation.Has_Stack_Window then
         --  Hidden protection/close/hook holders own their packets but have
         --  no scalar reservation. In particular they cannot restore stale
         --  saved tops after a real parent grows for open returned results.
         return;
      elsif Context.Stack_Window /= Activation then
         raise Program_Error with "retiring a noncurrent real stack window";
      end if;
      Previous := Activation.Previous_Stack_Window;
      Last := Natural'Max
        (Activation.Stack_Base + Activation.Stack_Window_Length,
         Activation.Stack_Live_Top);
      --  The actual call interval, including a hidden-vararg prefix, belongs
      --  to this departing frame. Outgoing values must already be rooted in
      --  a result/error holder before this allocation-free clear occurs.
      Stacks.Clear_Range (Context, Activation.Call_Base, Last);
      Context.Stack_Window := Previous;
      Context.Stack_Used :=
        (if Previous = null then Activation.Saved_Stack_Used else
           Previous.Stack_Base + Previous.Stack_Window_Length);
      Context.Foreign_Top :=
        (if Previous = null then Activation.Saved_Foreign_Top
         elsif Previous.Is_Native then Previous.Stack_Live_Top else
           Previous.Stack_Base + Previous.Canonical_Top);
      Activation.Previous_Stack_Window := null;
      Activation.Has_Stack_Window := False;
      --  Retain physical capacity. Clearing everything above an old parent
      --  reservation would be wrong during overlapping child execution; only
      --  this detached interval was owned here. Union GC clears other gaps.
   end Retire_Stack_Window;

   procedure Set_Native_Top
     (State : in out World; Activation : not null Frame_Access;
      Count : Natural)
   is
      Context : constant Context_Access := Activation.Context;
      Old_Top : constant Natural := Activation.Stack_Live_Top;
      New_Top : Natural;
   begin
      if not Activation.Is_Native or else Context /= State.Current or else
        Context.Stack_Window /= Activation
      then
         raise Program_Error with "native top requires its current window";
      end if;
      if Count > Natural'Last - Activation.Stack_Base then
         Fail (State, "stack overflow");
      end if;
      New_Top := Activation.Stack_Base + Count;
      Resize_Stack_Window
        (State, Activation,
         Natural'Max (Activation.Stack_Window_Length, Count));
      --  Preserve both views until all potentially allocating growth has
      --  succeeded. Shrinking the owned packet removes stale argument roots;
      --  clearing actual slots then detaches any cells above the new top.
      if Activation.Foreign_Handler = System.Null_Address then
         Activation.Native_Arguments.Set_Length
           (Ada.Containers.Count_Type (Count));
      end if;
      if New_Top < Old_Top then
         Stacks.Clear_Range (Context, New_Top + 1, Old_Top);
      else
         for Index in Old_Top + 1 .. New_Top loop
            Stacks.Write (State, Context, Index, Nil_Value);
         end loop;
      end if;
      Activation.Stack_Live_Top := New_Top;
      Context.Foreign_Top := New_Top;
   end Set_Native_Top;

   procedure Push_Native_Value
     (State : in out World; Activation : not null Frame_Access;
      Item : Value)
   is
      Count : constant Natural :=
        Activation.Stack_Live_Top - Activation.Stack_Base;
   begin
      --  Reservation can trigger emergency collection. Retain an existing
      --  value before it becomes part of the actual activation's root range.
      Pin (State, Item);
      Set_Native_Top (State, Activation, Count + 1);
      Activation.Native_Arguments.Replace_Element (Count + 1, Item);
      Stacks.Write
        (State, Activation.Context, Activation.Stack_Live_Top, Item);
   end Push_Native_Value;

   procedure Release_Frame (State : in out World; Item : in out Frame_Access);
   procedure Release_Frame (State : in out World; Item : in out Frame_Access)
   is
   begin
      Warnings.Discard (State, Item);
      if Item.Finalizer_Charge then
         --  Host aborts abandon callbacks without executing cleanup. Restore
         --  the precise owner policy before releasing its current roots.
         Item.Context.Finalizer_Hook_Suppression :=
           Item.Context.Finalizer_Hook_Suppression - 1;
         Item.Finalizer_Charge := False;
         Finalizers.Abandon_Current (State);
      end if;
      if Item.Foreign_Entered then
         --  A failed foreign callback can be retired by ordinary Lua error
         --  unwinding. Restore its C-stack window exactly as normal callback
         --  completion does; never leave a dangling active-frame identity.
         State.Current.Foreign_Top := Item.Saved_Foreign_Top;
         State.Current.Foreign_Base := Item.Foreign_Previous_Base;
         State.Current.Foreign_Activation := Item.Foreign_Previous_Frame;
         Item.Foreign_Entered := False;
      end if;
      if Item.Is_Native and then Item.Native_Name = "@hook" then
         State.Current.Hook_Active := False;
         State.Current.Hook_Frame := null;
      elsif Item.Unwind_Charge then
         State.Current.Cleanup_Depth := State.Current.Cleanup_Depth - 1;
      elsif Item.Message_Charge then
         State.Current.Message_Depth := State.Current.Message_Depth - 1;
      end if;
      State.Current.Stack_Slots := State.Current.Stack_Slots - Item.Slot_Cost;
      if Item.Blocks_Yield then
         State.Current.Non_Yieldable := State.Current.Non_Yieldable - 1;
      end if;
      if Item.Native_Charge then
         State.Current.Native_Depth := State.Current.Native_Depth - 1;
         State.Native_Depth := State.Native_Depth - 1;
      end if;
      Retire_Stack_Window (Item);
      Return_Frame (Item);
   end Release_Frame;

   procedure Reserve_Frame (State : in out World; Cost : Natural);
   procedure Reserve_Frame (State : in out World; Cost : Natural) is
      Maximum : constant Positive :=
        (Lua.Runtime_Configuration.Maximum_Stack +
           (if State.Current.Cleanup_Depth > 0 then 4_096 else 0));
   begin
      --  This cost belongs only to the retained private packet comparator.
      --  Canonical and native frames pass zero: their exact absolute scalar
      --  extent goes through Ensure_Stack and its typed error-stack phase.
      --  Metadata depth remains a distinct explicit embedding quota; an
      --  internal protection holder invents no extra Lua register window.
      if Cost > Maximum or else
        State.Current.Stack_Slots > Maximum - Cost
      then
         Fail (State, "stack overflow");
      end if;
      if Natural (State.Current.Stack.Length) >= State.Bounds.Call_Depth then
         Fail (State, "call depth limit exceeded", Resource => True);
      end if;
      --  Reserve geometrically before allocating the frame. This retains the
      --  exception-safe publication contract without quadratic stack copies.
      if State.Current.Stack.Length = State.Current.Stack.Capacity then
         State.Current.Stack.Reserve_Capacity
           (Ada.Containers.Count_Type'Max
              (8, State.Current.Stack.Capacity * 2));
      end if;
   end Reserve_Frame;

   procedure Clear_Frames (State : in out World) is
   begin
      while not State.Current.Stack.Is_Empty loop
         declare
            Item : Frame_Access := State.Current.Stack.Last_Element;
         begin
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Item);
         end;
      end loop;
   end Clear_Frames;

   package World_Addresses is new
     System.Address_To_Access_Conversions (World);

   procedure Prepare
     (Self : in out Driver; Universe : not null World_View);
   procedure Start_Borrowed
     (Self : in out Driver; Universe : not null World_View;
      Code : Prototype_Access; Function_Value : Value;
      Arguments : Values.Vector);
   procedure Abandon (Self : Driver);
   procedure Scheduler_Step (Self : in out Driver);

   procedure Dispatch
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination : Natural; Tail : Boolean := False;
      Protected_Call : Natural := 0;
      Call_Name : Unbounded_String := Null_Unbounded_String;
      Name_Kind : Unbounded_String := Null_Unbounded_String;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False);
   procedure Complete (Self : Driver; Result : Values.Vector);
   procedure Recover (Self : Driver);
   function Active_Handler (Self : Driver) return Value;
   procedure Invoke_Message_Handler (Self : Driver; Handler : Value);
   procedure Execute_Instruction (Self : Driver);
   procedure Execute_Private_Instruction (Self : Driver);
   procedure Start_Unwind
     (Self : Driver; Owner : Frame_Access; Reason : Unwind_Reason;
      Results : Values.Vector := Values.Empty_Vector;
      Depth : Natural := 0; PC : Natural := 0;
      Live : Registers.Vector := Registers.Empty_Vector);
   procedure Native_Step (Self : Driver);
   procedure Hook_Event
     (Self : Driver; Event : String; Line : Natural := 0);
   function Before_Step (Self : Driver) return Boolean;
   procedure Schedule
     (Self : Driver; Name : String; Arguments : Values.Vector;
      Destination : Natural;
      Operator : Token_Kind := End_Of_Input);
   function Native
     (Self : Driver; Function_Id : Native_Kind; Arguments : Values.Vector)
      return Values.Vector;
   function Wrap
     (State : in out World; Result : Values.Vector; Count : Natural;
      Success : Boolean := True) return Values.Vector;
   procedure Raise_Value
     (Self : Driver; Item : Value; Level : Natural := 1);
   procedure Push_Frame
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination, Protection : Natural;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False);
   procedure Deliver
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False);

   procedure Deliver
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False)
   is
      State : World renames Self.Universe.all;
   begin
      --  A callback resumes its owning native activation instead of
      --  writing a Lua register. This is the single return-channel bridge.
      if Activation.Native_Tail_State = Waiting_Native_Tail then
         Activation.Native_Results := Packet;
         Activation.Native_Tail_State := Ready_Native_Tail;
      elsif Activation.Is_Native then
         Activation.Native_Results := Packet;
         Activation.Result_Failure_Class := Failure;
         Activation.Result_Handler_Called := Handler_Called;
         if Activation.Native_Name = "@foreign.boundary" and then
           not Packet.Is_Empty and then Packet.First_Element.Kind =
             Boolean_Kind and then not Packet.First_Element.Boolean_Data
         then
            Activation.Native_Aux :=
              (if Failure = Memory_Failure then 4
               elsif Failure = Handling_Failure then 5 else 2);
         end if;
      elsif Activation.Code.Canonical_Node /= null then
         --  Scalar canonical registers have their own fixed/open-result and
         --  conditional continuations. Never insert private packet registers
         --  into this activation or bypass its pending result adjustment.
         Canonical.Deliver (State, Activation, Packet);
      elsif Destination /= 0 then
         Put_Packet (State, Activation, Destination, Packet);
      end if;
   end Deliver;

   procedure Schedule
     (Self : Driver; Name : String; Arguments : Values.Vector;
      Destination : Natural;
      Operator : Token_Kind := End_Of_Input)
   is
      State : World renames Self.Universe.all;
      Activation : Frame_Access;
   begin
      Reserve_Frame (State, 0);
      if Name (Name'First) /= '@' and then State.Native_Depth >=
        (if State.Current.Message_Depth > 0 then
            Lua.Runtime_Configuration.Maximum_C_Calls / 10 * 11
         else Lua.Runtime_Configuration.Maximum_C_Calls)
      then
         Fail (State, "C stack overflow");
      end if;
      Activation := New_Frame (State, State.Current);
      State.Current.Stack.Append (Activation);
      --  The reserved activation stack owns partial construction before any
      --  managed argument copy can fail. Rollback uses the same release path
      --  as ordinary unwinding, balancing every slot/depth charge exactly.
      begin
         --  A visible native call receives its actual scalar window in
         --  Dispatch. Internal holders consume no semantic Lua stack slots.
         Activation.Slot_Cost := 0;
         Activation.Native_Charge := Name (Name'First) /= '@';
         if Activation.Native_Charge then
            State.Native_Depth := State.Native_Depth + 1;
            State.Current.Native_Depth := State.Current.Native_Depth + 1;
         end if;
         --  Native continuations preserve ownership across callbacks; that
         --  alone does not make a C-compatible library boundary yieldable.
         Activation.Blocks_Yield := Name in "string.gsub" | "string.format" |
           "base.tostring" | "base.print" | "base.pairs" | "ipairs.iterator" |
           "table.concat" | "table.insert" | "table.remove" | "table.move" |
           "table.unpack" | "table.sort" | "base.load" | "base.loadfile" |
        "base.require" |
           "package.preload_searcher" | "package.lua_searcher";
         if Activation.Blocks_Yield then
            State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
         end if;
         Activation.Is_Native := True;
         Activation.Native_Name := To_Unbounded_String (Name);
         --  Empty default packets have no allocator owner. Copy their values
         --  into this frame's existing owned buffer rather than assigning the
         --  vector and discarding its owner/cached capacity. A later internal
         --  phase may reserve arguments even when this initial list is empty.
         Activation.Native_Arguments.Clear;
         Activation.Native_Arguments.Set_Owner (Activation.Memory);
         Activation.Native_Arguments.Append (Arguments);
         Activation.Transfer_Count := Natural (Arguments.Length);
         Activation.Native_Operator := Operator;
         Activation.Call_Site := State.Current.Failure_At;
         Activation.Return_To := Destination;
      exception
         when others =>
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Activation);
            raise;
      end;
   end Schedule;

   procedure Hook_Event
     (Self : Driver; Event : String; Line : Natural := 0) is
      State : World renames Self.Universe.all;
      Args : Values.Vector := Owned_Values (State);
   begin
      --  The continuation suppresses hooks until the entire callback
      --  returns. Its owned arguments and function remain collector roots.
      Args.Append (New_String (State, Event));
      Args.Append
        ((if Event = "line" then (Integer_Kind, Integer_Value (Line))
          else Nil_Value));
      State.Current.Hook_Frame := State.Current.Stack.Last_Element;
      State.Current.Hook_Transfer := Event in "call" | "tail call" |
        "return";
      State.Current.Hook_Active := True;
      Schedule (Self, "@hook", Values.Empty_Vector, 0);
      State.Current.Stack.Last_Element.Blocks_Yield := True;
      State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      Dispatch (Self, State.Current.Hook, Args, 0);
   end Hook_Event;

   function Before_Step (Self : Driver) return Boolean is
      State : World renames Self.Universe.all;
      Item : constant Frame_Access := State.Current.Stack.Last_Element;
      function Wants (Mask : Character) return Boolean is
        (State.Current.Hook.Kind /= Nil_Kind and then
         Ada.Strings.Fixed.Index
           (To_String (State.Current.Hook_Mask), "" & Mask) /= 0);
      Line : Natural;
   begin
      if State.Current.Hook_Active or else
        State.Current.Finalizer_Hook_Suppression /= 0
      then
         return False;
      end if;
      if not Item.Entry_Hook_Done and then not Item.Is_Native and then
        Item.Code.Canonical_Node /= null and then Item.Code.Vararg and then
        Item.PC = 1
      then
         return False;
      end if;
      if not Item.Entry_Hook_Done then
         Item.Entry_Hook_Done := True;
         if (not Item.Is_Native or else
              Element (Item.Native_Name, 1) /= '@') and then Wants ('c')
         then
            Hook_Event
              (Self, (if Item.Is_Tail_Call then "tail call" else "call"));
            return True;
         end if;
      end if;
      if not Item.Is_Native and then Item.PC <= Code_Length (Item)
      then
         if Item.Hook_PC /= Item.PC then
            Item.Hook_PC := Item.PC;
            if State.Current.Hook.Kind /= Nil_Kind and then
              State.Current.Hook_Count > 0
            then
               if State.Current.Hook_Remaining > 1 then
                  State.Current.Hook_Remaining :=
                    State.Current.Hook_Remaining - 1;
               else
                  State.Current.Hook_Remaining := State.Current.Hook_Count;
                  Hook_Event (Self, "count");
                  return True;
               end if;
            end if;
         end if;
         Line := Line_At (Item, Item.PC);
         if not Item.Line_Hook_Checked and then
           (Line /= Item.Hook_Line or else Item.PC <= Item.Last_Executed_PC)
         then
            Item.Line_Hook_Checked := True;
            Item.Hook_Line := Line;
            if Wants ('l') then
               Hook_Event (Self, "line", Line);
               return True;
            end if;
         end if;
      end if;
      return False;
   end Before_Step;

   procedure Start_Unwind
     (Self : Driver; Owner : Frame_Access; Reason : Unwind_Reason;
      Results : Values.Vector := Values.Empty_Vector;
      Depth : Natural := 0; PC : Natural := 0;
      Live : Registers.Vector := Registers.Empty_Vector)
   is
      State : World renames Self.Universe.all;
      Driver : Frame_Access;
   begin
      --  Publish all outgoing values before callbacks can collect. The
      --  owner remains on the stack until closing has completely finished.
      State.Current.Cleanup_Depth := State.Current.Cleanup_Depth + 1;
      begin
         Schedule (Self, "@unwind", Values.Empty_Vector, 0);
      exception
         when others =>
            State.Current.Cleanup_Depth := State.Current.Cleanup_Depth - 1;
            raise;
      end;
      Driver := State.Current.Stack.Last_Element;
      Driver.Unwind_Charge := True;
      Driver.Unwind := Reason;
      Driver.Unwind_Owner := Owner;
      Driver.Unwind_Depth := Depth;
      Driver.Unwind_PC := PC;
      Driver.Unwind_Live := Live;
      Driver.Unwind_Results := Results;
      if Owner.Code /= null and then
        Owner.Code.Canonical_Node /= null
      then
         --  Error and explicit coroutine-close paths also detach open cells
         --  before a handler can mutate them. Normal CLOSE/RETURN has already
         --  frozen the same departing slots; preparation is idempotent.
         Canonical.Prepare_Close
           (State, Owner,
            (if Reason in Return_Exit | Error_Exit | Coroutine_Exit then 0
             else Depth));
      else
         --  Freeze just the declarations leaving in this transfer, before any
         --  handler executes. Closed upvalues and departing stack slots are
         --  distinct Lua storage: debug.setupvalue may replace a closed cell
         --  while the original slot still waits for its own close callback.
         --  Outer declarations remain live and must retain later mutations.
         for Index in reverse Owner.Closers.First_Index ..
           Owner.Closers.Last_Index
         loop
            declare
               Closing : Close_Entry renames Owner.Closers (Index);
            begin
               exit when not
                 (Reason in Return_Exit | Error_Exit | Coroutine_Exit or else
                  Closing.Depth > Depth or else
                  (Reason = Jump_Exit and then Closing.Symbol /= 0 and then
                   not Live.Contains (Closing.Symbol)));
               if not Closing.Frozen then
                  Closing.Frozen_Value := Closing.Cell.Cell_Value;
                  Closing.Frozen := True;
               end if;
            end;
         end loop;
      end if;
      if Reason in Error_Exit | Coroutine_Exit then
         Driver.Unwind_Error := State.Current.Failure;
         Driver.Unwind_Has_Error := State.Current.Has_Failure_Value;
         Driver.Unwind_Failure_Class := State.Current.Failure_Class;
         Driver.Unwind_Handler_Called := State.Current.Failure_Handled;
         Driver.Blocks_Yield := True;
         State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      end if;
   end Start_Unwind;

   function Wrap
     (State : in out World; Result : Values.Vector; Count : Natural;
      Success : Boolean := True) return Values.Vector
   is
      Packet : Values.Vector := Owned_Values (State);
   begin
      --  Flatten chains such as pcall(pcall, f) without recursive Ada
      --  calls. Each successful outer protection contributes one true.
      for Index in 1 .. Count loop
         Packet.Append
           (Value'(Boolean_Kind, Success or else Index < Count));
      end loop;
      for Item of Result loop
         Packet.Append (Item);
      end loop;
      return Packet;
   end Wrap;

   procedure Raise_Value
     (Self : Driver; Item : Value; Level : Natural := 1) is
      State : World renames Self.Universe.all;
      Error_Value : Value := Item;
   begin
      --  Lua 5.5 normalizes nil errors before protected-call delivery.
      --  Preserve other arbitrary values, including false and tables.
      if Item.Kind = String_Kind and then Level in 1 ..
        Natural (State.Current.Stack.Length)
      then
         declare
            Activation : constant Frame_Access := State.Current.Stack
              (State.Current.Stack.Last_Index - Level + 1);
            Line : constant Positive :=
              (if Activation.Is_Native then Activation.Call_Site.Line
               else Positive'Max
                 (1, Line_At (Activation,
                     Positive'Max (1, Activation.PC - 1))));
         begin
            Error_Value := New_String
              (State, (if Activation.Is_Native then "(native)"
                       elsif Activation.Code.Canonical_Node /= null then
                          To_String (Canonical.Source_Bytes (Activation.Code))
                       else To_String (Activation.Code.Name)) & ":" &
               Ada.Strings.Fixed.Trim (Line'Image, Ada.Strings.Both) &
               ": " & Image (State.Current.Memory, Item));
         end;
      end if;
      State.Current.Failure := Error_Value;
      State.Current.Has_Failure_Value := True;
      State.Current.Failure_Text := To_Unbounded_String
        (Image (State.Current.Memory, Error_Value));
      State.Current.Failure_Class := Language_Failure;
      State.Current.Failure_Handled := False;
      raise Language_Error;
   end Raise_Value;

   function Native
     (Self : Driver; Function_Id : Native_Kind; Arguments : Values.Vector)
      return Values.Vector
   is
      State : World renames Self.Universe.all;
      Result : Values.Vector := Owned_Values (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      procedure Require (Count : Positive);
      procedure Require_Table;
      Item : Value;
      Number : Lua.Numbers.Number;
      Index : Integer_Value;

      procedure Require (Count : Positive) is
      begin
         if Natural (Arguments.Length) < Count then
            Fail (State, "missing argument to base function");
         end if;
      end Require;

      procedure Require_Table is
      begin
         Require (1);
         if Arg (1).Kind /= Table_Kind then
            Fail (State, "table expected");
         end if;
      end Require_Table;
   begin
      case Function_Id is
         when Print_Function =>
            --  Both delivery policies use the same quota and byte producer.
            --  This legacy primitive has no tostring continuation; ordinary
            --  Lua-visible print below performs its callbacks explicitly.
            for Position in Arguments.First_Index .. Arguments.Last_Index
            loop
               if Position > 1 then
                  Emit_Output (State, [Ada.Characters.Latin_1.HT]);
               end if;
               Emit_Output
                 (State, Image (State.Current.Memory, Arg (Position)));
            end loop;
            Emit_Output (State, [Ada.Characters.Latin_1.LF]);
            Flush_Output (State);
         when Assert_Function =>
            Require (1);
            if not Truth (Arg (1)) then
               if Arguments.Length >= 2 then
                  Raise_Value (Self, Arg (2));
               else
                  Raise_Value (Self, New_String (State, "assertion failed!"));
               end if;
            end if;
            return Arguments;
         when Error_Function =>
            Index := (if Arguments.Length >= 2 and then
                        Arg (2).Kind /= Nil_Kind then
                        Integral (State, Arg (2)) else 1);
            Raise_Value
              (Self, Arg (1), (if Index > 0 and then
                Index <= Integer_Value (State.Current.Stack.Length)
                then Natural (Index) else 0));
         when Type_Function =>
            Require (1);
            Result.Append (New_String (State, Type_Name (Arg (1))));
         when Tostring_Function =>
            Require (1);
            Result.Append
              (New_String (State, Image (State.Current.Memory, Arg (1))));
         when Tonumber_Function =>
            Require (1);
            if Arguments.Length >= 2 and then Arg (2).Kind /= Nil_Kind then
               Index := Integral (State, Arg (2));
               if Index not in 2 .. 36 or else
                 Arg (1).Kind /= String_Kind
               then
                  Fail (State, "base 2..36 and string expected");
               end if;
               Number := Read_Number
                 (State, Arg (1).Reference.Bytes,
                  Base => Natural (Index));
            elsif Arg (1).Kind in Integer_Kind | Real_Kind then
               Result.Append (Arg (1));
               return Result;
            elsif Arg (1).Kind = String_Kind then
               Number := Read_Number (State, Arg (1).Reference.Bytes);
            else
               Number := (Kind => Lua.Numbers.Invalid);
            end if;
            case Number.Kind is
               when Lua.Numbers.Invalid => Result.Append (Nil_Value);
               when Lua.Numbers.Integer_Number =>
                  Result.Append (Value'(Integer_Kind, Number.Integer_Item));
               when Lua.Numbers.Real_Number =>
                  Result.Append (Value'(Real_Kind, Number.Real_Item));
            end case;
         when Select_Function =>
            Require (1);
            if Arg (1).Kind = String_Kind and then
              Length (Arg (1).Reference.Bytes) > 0
              and then Element (Arg (1).Reference.Bytes, 1) = '#'
            then
               Result.Append
                 (Value'(Integer_Kind,
                         Integer_Value (Arguments.Length) - 1));
            else
               Index := Integral (State, Arg (1));
               if Index < 0 then
                  Index := Integer_Value (Arguments.Length) + Index;
               end if;
               if Index < 1 then
                  Fail (State, "index out of range");
               end if;
               if Index < Integer_Value (Arguments.Length) then
                  for Position in Positive (Index) + 1 ..
                    Arguments.Last_Index
                  loop
                     Result.Append (Arguments (Position));
                  end loop;
               end if;
            end if;
         when Next_Function =>
            Require_Table;
            return Next (State, Arg (1), Arg (2));
         when Pairs_Function | Ipairs_Function =>
            --  ipairs validates its state lazily when its iterator is
            --  called; pairs validates the table immediately.
            if Function_Id = Pairs_Function then
               Require_Table;
            else
               Require (1);
            end if;
            Result.Append
              (Value'(Native_Kind_Value,
                (if Function_Id = Pairs_Function then Next_Function
                 else Ipairs_Step)));
            Result.Append (Arg (1));
            Result.Append
              ((if Function_Id = Pairs_Function then Nil_Value
                else (Integer_Kind, 0)));
         when Ipairs_Step =>
            Require_Table;
            Index := Lua.Integers.Add (Integral (State, Arg (2)), 1);
            Item := Get (Arg (1), (Integer_Kind, Index));
            if Item.Kind /= Nil_Kind then
               Result.Append (Value'(Integer_Kind, Index));
            end if;
            Result.Append (Item);
         when Rawequal_Function =>
            Require (2);
            Result.Append
              (Value'(Boolean_Kind, Engine.Equal (Arg (1), Arg (2))));
         when Rawget_Function =>
            Require_Table;
            Require (2);
            Result.Append (Get (Arg (1), Arg (2)));
         when Rawset_Function =>
            Require_Table;
            Require (3);
            Set (State, Arg (1), Arg (2), Arg (3));
            Result.Append (Arg (1));
         when Rawlen_Function =>
            Require (1);
            if Arg (1).Kind = String_Kind then
               Index := Integer_Value (Lua.Engine.Length
                 (Arg (1).Reference.Bytes));
            elsif Arg (1).Kind = Table_Kind then
               Index := Integer_Value (Table_Length (Arg (1)));
            else
               Fail (State, "table or string expected");
            end if;
            Result.Append (Value'(Integer_Kind, Index));
         when Pcall_Function =>
            raise Program_Error with "pcall must use frame dispatch";
      end case;
      return Result;
   end Native;

   procedure Push_Frame
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination, Protection : Natural;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Item : Frame_Access;
      Prototype : constant Prototype_Access :=
        Function_Value.Reference.Code;
   begin
      --  A frame owns its fresh lexical scope and register packets.
      --  Publish it before parameter/vararg setup so the central cleanup
      --  path also owns partially initialized activations after failure.
      Reserve_Frame
        (State, (if Prototype.Canonical_Node /= null then 0 else
           Natural'Max (20, Prototype.Register_Count) +
             Natural (Arguments.Length)));
      Item := New_Frame (State, State.Current);
      Item.Slot_Cost :=
        (if Prototype.Canonical_Node /= null then 0 else
           Natural'Max (20, Prototype.Register_Count) +
             Natural (Arguments.Length));
      State.Current.Stack_Slots :=
        State.Current.Stack_Slots + Item.Slot_Cost;
      Item.Code := Prototype;
      Item.Callee := Function_Value;
      Item.Transfer_Count := Natural (Prototype.Parameters.Length);
      Item.Return_To := Destination;
      Item.Protection := Protection;
      State.Current.Stack.Append (Item);
      if Prototype.Canonical_Node /= null then
         --  Publishing the frame first gives partial scalar-register setup
         --  the same exception-safe owner as private parameter setup. Ordered
         --  upvalues already belong to the callee; no lexical environment or
         --  second set of packet registers is created for canonical code.
         Item.Transfer_Count := Natural
           (Prototype.Canonical_Node.Parameters);
         Open_Stack_Window
           (State, Item, Function_Value, Arguments,
            Call_Base, Has_Call_Window);
         Canonical.Initialize_Frame (State, Item, Arguments);
         return;
      end if;
      Item.Scope := New_Environment
        (State, Function_Value.Reference.Capture);
      Prepare_Private_Registers (Item, Prototype.Register_Count);
      if Prototype.Is_Main and then
        Function_Value.Reference.Capture = null
      then
         --  Host chunks start with a fresh global-environment binding.
         --  Loaded chunks already capture their persistent _ENV cell:
         --  shadowing it here would discard assignments between calls and
         --  split the binding observed by their nested Lua closures.
         Declare_Local (State, Item.Scope, Prototype.Environment_Symbol,
                        Global_Environment (State));
      end if;
      for Position in Prototype.Parameters.First_Index ..
        Prototype.Parameters.Last_Index
      loop
         Declare_Local
           (State, Item.Scope, Prototype.Parameters (Position),
            (if Position <= Natural (Arguments.Length) then
               Arguments (Position) else Nil_Value));
      end loop;
      if Prototype.Vararg then
         for Position in Natural (Prototype.Parameters.Length) + 1 ..
           Natural (Arguments.Length)
         loop
            Item.Varargs.Append (Arguments (Position));
         end loop;
      end if;
      if Prototype.Vararg_Name /= 0 then
         --  Named varargs have one authoritative mutable table. Keeping
         --  a second packet would make ... ignore later writes to t.n
         --  or t[i], and would retain values removed from that table.
         declare
            Table : constant Value := New_Table (State);
         begin
            for Position in Item.Varargs.First_Index ..
              Item.Varargs.Last_Index
            loop
               Set (State, Table, (Integer_Kind, Integer_Value (Position)),
                    Item.Varargs (Position));
            end loop;
            Set (State, Table, New_String (State, "n"),
                 (Integer_Kind, Integer_Value (Item.Varargs.Length)));
            Declare_Local (State, Item.Scope, Prototype.Vararg_Name, Table);
            Item.Vararg_Table := Table.Reference;
            Item.Varargs.Clear;
         end;
      end if;
   end Push_Frame;

   procedure Complete (Self : Driver; Result : Values.Vector) is
      State : World renames Self.Universe.all;
      Activation : Frame_Access := State.Current.Stack.Last_Element;
      Destination : constant Natural := Activation.Return_To;
      Policy : constant Completion_Policy := Activation.Completion;
      Packet : constant Values.Vector :=
        Wrap (State, Result, Activation.Protection);
   begin
      Pin (State, Result);
      Pin (State, Packet);
      if not State.Current.Hook_Active and then
        State.Current.Finalizer_Hook_Suppression = 0 and then
        not Activation.Return_Hook_Done and then
        State.Current.Hook.Kind /= Nil_Kind and then
        Ada.Strings.Fixed.Index
          (To_String (State.Current.Hook_Mask), "r") /= 0 and then
        (not Activation.Is_Native or else
           Element (Activation.Native_Name, 1) /= '@')
      then
         --  Keep the departing frame and outgoing values alive while its
         --  return hook executes. Only the continuation retires them.
         Activation.Return_Hook_Done := True;
         Activation.Transfer_Count := Natural (Result.Length);
         Schedule (Self, "@return.hook", Values.Empty_Vector, 0);
         State.Current.Stack.Last_Element.Unwind_Results := Result;
         Hook_Event (Self, "return");
         return;
      end if;
      --  Copy the outgoing packet before releasing its activation. No
      --  collection occurs until the caller's destination owns it again.
      --  The outermost chunk has no consumer and intentionally discards it.
      State.Current.Stack.Delete_Last;
      Release_Frame (State, Activation);
      if not State.Current.Stack.Is_Empty then
         if Policy = Deliver_Results then
            Deliver
              (Self, State.Current.Stack.Last_Element, Destination, Packet);
         end if;
      else
         State.Current.Transfer.Kind := Completed;
         State.Current.Transfer.Results := Packet;
      end if;
   end Complete;

   procedure Dispatch
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination : Natural; Tail : Boolean := False;
      Protected_Call : Natural := 0;
      Call_Name : Unbounded_String := Null_Unbounded_String;
      Name_Kind : Unbounded_String := Null_Unbounded_String;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Function_Item : Value := Function_Value;
      Args : Values.Vector := Owned_Values (State, Arguments);
      Protection : Natural := Protected_Call;
      Return_To : Natural := Destination;
      Effective_Base : Natural := Call_Base;
      Use_Window : Boolean := Has_Call_Window;
      Native_Tail : Boolean := False;
      Packet : Values.Vector := Owned_Values (State);
   begin
      Pin (State, Function_Value);
      Pin (State, Arguments);
      --  pcall is a frame boundary, not a recursive invocation of Run.
      --  Tail calls replace the current frame while retaining the outer
      --  protected-return contract and the caller's destination register.
      declare
         Hops : Natural := 0;
         Handler : Value;
      begin
         loop
            if Function_Item.Kind in Closure_Kind |
              Native_Closure_Kind | Native_Kind_Value | Foreign_Function_Kind
            then
               exit;
            else
               Handler := Metafield (State, Function_Item, "__call");
               if Handler.Kind = Nil_Kind then
                  Fail (State, "attempt to call a " &
                          Diagnostic_Type (State, Function_Item) &
                          " value");
               end if;
               Hops := Hops + 1;
               if Hops > 15 then
                  Fail (State, "call metamethod chain too long");
               end if;
               Args.Prepend (Function_Item);
               Function_Item := Handler;
            end if;
         end loop;
      end;
      if Function_Item.Kind in Closure_Kind | Native_Closure_Kind |
        Native_Kind_Value | Foreign_Function_Kind
      then
         Pin (State, Function_Item);
         Pin (State, Args);
         if Tail then
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               if Function_Item.Kind = Closure_Kind then
                  Return_To := Old.Return_To;
                  Protection := Protection + Old.Protection;
                  if Old.Has_Stack_Window then
                     Effective_Base := Old.Call_Base;
                     Use_Window := True;
                  end if;
                  State.Current.Stack.Delete_Last;
                  Release_Frame (State, Old);
               else
                  --  Native tail calls keep the Lua caller inspectable until
                  --  the native result/error returns. A later scheduler phase
                  --  performs its return; no Ada executor activation recurses.
                  Old.Native_Tail_State := Waiting_Native_Tail;
                  Native_Tail := True;
                  Return_To := 0;
               end if;
            end;
         end if;
         if Function_Item.Kind = Closure_Kind then
            Push_Frame
              (Self, Function_Item, Args, Return_To, Protection,
               Effective_Base, Use_Window);
            State.Current.Stack.Last_Element.Is_Tail_Call := Tail;
         elsif Function_Item.Kind = Foreign_Function_Kind then
            Schedule (Self, "foreign.callback", Args, Return_To);
            State.Current.Stack.Last_Element.Protection := Protection;
            State.Current.Stack.Last_Element.Callee := Function_Item;
            State.Current.Stack.Last_Element.Foreign_Handler :=
              Function_Item.Identity;
         elsif Function_Item.Kind = Native_Kind_Value then
            Schedule
              (Self, (if Function_Item.Native_Data = Pcall_Function then
                  "base.pcall" else "base.primitive"), Args, Return_To);
            State.Current.Stack.Last_Element.Protection := Protection;
            State.Current.Stack.Last_Element.Native_Id :=
              Function_Item.Native_Data;
            State.Current.Stack.Last_Element.Callee := Function_Item;
         else
            Schedule
              (Self, (if Function_Item.Reference.Foreign_Handler /=
                        System.Null_Address then "foreign.callback" else
                        To_String (Function_Item.Reference.Native_Name)),
               Args, Return_To);
            State.Current.Stack.Last_Element.Protection := Protection;
            if Function_Item.Reference.Foreign_Handler = System.Null_Address
            then
               for Cell of Function_Item.Reference.Captures loop
                  State.Current.Stack.Last_Element.Native_Captures.Append
                    (Cell.Cell_Value);
               end loop;
            end if;
            --  Foreign callbacks read real mutable upvalue cells. Copying
            --  their old values into another root packet would keep replaced
            --  weak values alive until the C callback returns.
            State.Current.Stack.Last_Element.Callee := Function_Item;
            State.Current.Stack.Last_Element.Native_Self :=
              Function_Item.Reference;
            State.Current.Stack.Last_Element.Foreign_Handler :=
              Function_Item.Reference.Foreign_Handler;
         end if;
         if Function_Item.Kind /= Closure_Kind then
            Open_Stack_Window
              (State, State.Current.Stack.Last_Element,
               Function_Item, Args, Effective_Base, Use_Window);
         end if;
         if not Tail or else Native_Tail then
            State.Current.Stack.Last_Element.Call_Name := Call_Name;
            State.Current.Stack.Last_Element.Name_Kind := Name_Kind;
         end if;
      end if;
   exception
      when Language_Error | Lua.Storage.Allocation_Error =>
         if Lua.Storage.Refusal_Pending (State.Memory) then
            Record_Memory_Error (State);
         end if;
         if Protection = 0 or else (State.Current.Failure_Class =
           Host_Abort)
         then
            raise;
         end if;
         if not State.Current.Has_Failure_Value then
            State.Current.Failure := New_String
              (State, To_String (State.Current.Failure_Text));
         end if;
         Packet.Clear;
         Packet.Append (State.Current.Failure);
         Packet := Wrap (State, Packet, Protection, Success => False);
         if Tail then
            Complete (Self, Packet);
         else
            Deliver
              (Self, State.Current.Stack.Last_Element, Destination, Packet);
         end if;
         State.Current.Failure := Nil_Value;
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
   end Dispatch;

   function Active_Handler (Self : Driver) return Value is
      State : World renames Self.Universe.all;
   begin
      --  A pcall without a handler shadows outer handlers. Internal close
      --  protection explicitly copies this nearest active dynamic boundary.
      for Activation of reverse State.Current.Stack loop
         if Activation.Protection > 0 then
            return Activation.Message_Handler;
         end if;
      end loop;
      return Nil_Value;
   end Active_Handler;

   procedure Invoke_Message_Handler (Self : Driver; Handler : Value) is
      State : World renames Self.Universe.all;
      Arguments : Values.Vector := Owned_Values (State);
      Limit : constant Natural :=
        Lua.Runtime_Configuration.Maximum_C_Calls;
   begin
      if State.Current.Message_Depth >= Limit / 10 * 11 then
         --  Overflow uses a bootstrap root, requiring no new allocation.
         --  Handler recursion is explicit state rather than abandoned stacks.
         State.Current.Failure := State.Handling_Error_Value;
         State.Current.Has_Failure_Value := True;
         State.Current.Failure_Class := Handling_Failure;
         State.Current.Failure_Handled := True;
         State.Current.Failure_Text :=
           To_Unbounded_String
             (Image (State.Current.Memory, State.Handling_Error_Value));
         return;
      elsif State.Current.Message_Depth + 1 = Limit then
         State.Current.Failure := New_String (State, "C stack overflow");
         State.Current.Has_Failure_Value := True;
         State.Current.Failure_Text :=
           To_Unbounded_String ("C stack overflow");
      end if;
      Arguments.Append (State.Current.Failure);
      Pin (State, Handler);
      Pin (State, Arguments);
      Arguments.Prepend (Handler);
      Schedule (Self, "@message.handler", Arguments, 0);
      State.Current.Message_Depth := State.Current.Message_Depth + 1;
      State.Current.Stack.Last_Element.Message_Charge := True;
      State.Current.Stack.Last_Element.Blocks_Yield := True;
      State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      --  Leave the same protected holder below this call. Recursive handler
      --  errors invoke it again; a successful transformation then unwinds the
      --  entire failed handler chain once, without nested pcall wrappers.
      --  Dispatch belongs to the next step. Its own native-depth/allocation
      --  failure must reenter ordinary scheduler recovery, rather than escape
      --  from this Recover activation as an unhandled root failure.
   end Invoke_Message_Handler;

   procedure Recover (Self : Driver) is
      State : World renames Self.Universe.all;
      Protected_Index : Natural := 0;
      Destination : Natural;
      Protection : Natural;
      Failure : Failure_Kind;
      Handler_Called : Boolean;
   begin
      --  Resource exhaustion is a host execution boundary: allowing Lua
      --  pcall to catch it could restart an exhausted instruction budget.
      --  Ordinary errors unwind only to the nearest protected VM frame.
      if (State.Current.Failure_Class = Host_Abort) then
         raise Language_Error;
      end if;
      if not State.Current.Has_Failure_Value then
         State.Current.Failure := New_String
           (State, To_String (State.Current.Failure_Text));
         State.Current.Has_Failure_Value := True;
      end if;
      if not State.Current.Failure_Handled and then
        State.Current.Failure_Class not in Memory_Failure | Handling_Failure
      then
         declare
            Handler : constant Value := Active_Handler (Self);
         begin
            if Handler.Kind /= Nil_Kind then
               Invoke_Message_Handler (Self, Handler);
               if State.Current.Failure_Class /= Handling_Failure then
                  return;
               end if;
            end if;
         end;
      end if;
      if State.Current.Failure.Kind = Nil_Kind then
         --  Lua 5.5 normalizes nil after the handler sees the original object,
         --  including the absent first result from a successful handler.
         State.Current.Failure := New_String (State, "<no error object>");
         State.Current.Failure_Text :=
           To_Unbounded_String ("<no error object>");
      end if;
      for Index in reverse State.Current.Stack.First_Index ..
        State.Current.Stack.Last_Index
      loop
         if State.Current.Stack (Index).Protection > 0 then
            Protected_Index := Index;
            exit;
         end if;
      end loop;
      if Protected_Index = 0 then
         if State.Current = Self.Root_Context then
            --  The host boundary is protected too, but must still report
            --  failure rather than wrapping it into a Lua return packet.
            for Index in reverse State.Current.Stack.First_Index ..
              State.Current.Stack.Last_Index
            loop
               if not State.Current.Stack (Index).Closers.Is_Empty then
                  while State.Current.Stack.Last_Index > Index loop
                     declare
                        Old : Frame_Access :=
                          State.Current.Stack.Last_Element;
                     begin
                        State.Current.Stack.Delete_Last;
                        Release_Frame (State, Old);
                     end;
                  end loop;
                  if not State.Current.Has_Failure_Value then
                     State.Current.Failure := New_String
                       (State, To_String (State.Current.Failure_Text));
                     State.Current.Has_Failure_Value := True;
                  end if;
                  Start_Unwind
                    (Self, State.Current.Stack.Last_Element, Error_Exit);
                  return;
               end if;
            end loop;
         end if;
         raise Language_Error;
      end if;
      --  Each frame's closers finish before that frame is retired. A close
      --  callback uses its own protected boundary, so a replacement error
      --  can be carried into the remaining outer close handlers.
      for Index in reverse Protected_Index ..
        State.Current.Stack.Last_Index
      loop
         if not State.Current.Stack (Index).Closers.Is_Empty then
            while State.Current.Stack.Last_Index > Index loop
               declare
                  Old : Frame_Access := State.Current.Stack.Last_Element;
               begin
                  State.Current.Stack.Delete_Last;
                  Release_Frame (State, Old);
               end;
            end loop;
            if not State.Current.Has_Failure_Value then
               State.Current.Failure := New_String
                 (State, To_String (State.Current.Failure_Text));
               State.Current.Has_Failure_Value := True;
            end if;
            Start_Unwind (Self, State.Current.Stack.Last_Element, Error_Exit);
            return;
         end if;
      end loop;
      Destination := State.Current.Stack (Protected_Index).Return_To;
      Protection := State.Current.Stack (Protected_Index).Protection;
      Failure := State.Current.Failure_Class;
      Handler_Called := State.Current.Failure_Handled;
      declare
         Holder : Frame_Access := State.Current.Stack (Protected_Index);
         Caller : Frame_Access;
      begin
         if Protection /= 1 or else Holder.Error_Packet.Capacity < 2 then
            raise Program_Error with "unreserved protected failure holder";
         end if;
         Holder.Error_Packet.Clear;
         Holder.Error_Packet.Append (Value'(Boolean_Kind, False));
         Holder.Error_Packet.Append (State.Current.Failure);
         while Natural (State.Current.Stack.Length) > Protected_Index loop
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
         end loop;
         if Holder.Retain_On_Failure then
            --  Move into the same live sentinel without allocating. Its C
            --  pump later consumes the packet while it is still a GC root.
            Holder.Protection := 0;
            Values.Move (Holder.Native_Results, Holder.Error_Packet);
            Holder.Result_Failure_Class := Failure;
            Holder.Result_Handler_Called := Handler_Called;
            Holder.Native_Aux :=
              (if Failure = Memory_Failure then 4
               elsif Failure = Handling_Failure then 5 else 2);
            Holder.Native_Stage := 1;
         else
            if Protected_Index > 1 then
               Caller := State.Current.Stack (Protected_Index - 1);
            else
               State.Current.Protected_Failure_Class := Failure;
               State.Current.Protected_Handler_Called := Handler_Called;
            end if;
            --  The source holder remains traced during publication. Native
            --  and root destinations take ownership; canonical scalar writes
            --  borrow it before retirement, including an allocation failure.
            --  Release its departing scalar interval first: the caller's
            --  destination overlaps this call's original function/arguments.
            --  The still-stacked holder keeps Error_Packet rooted, but its
            --  later metadata retirement must not erase newly returned data.
            Retire_Stack_Window (Holder);
            Deliver_Owned (Self, Caller, Destination, Holder.Error_Packet,
                           Failure, Handler_Called);
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Holder);
         end if;
      end;
      State.Current.Failure := Nil_Value;
      State.Current.Has_Failure_Value := False;
      State.Current.Failure_Class := No_Failure;
      State.Current.Failure_Handled := False;
      Shrink_Error_Stack (State, State.Current);
   end Recover;

   function Try_Push_Finalizers
     (Self : Driver; Silent : Boolean := False) return Boolean;
   function Try_Start_Finalizer
     (Self : Driver; Activation : Frame_Access) return Boolean;
   procedure Advance_Finalizers (Self : Driver);

   function Try_Push_Finalizers
     (Self : Driver; Silent : Boolean := False) return Boolean
   is
      State : World renames Self.Universe.all;
      Before : constant Natural := Natural (State.Current.Stack.Length);
   begin
      if State.Finalizer_Active then return False; end if;
      --  A failed minimum-stack/CI check ends this drain opportunity, just
      --  as pinned GCScallfin enters pause. Retrying before the caller's
      --  next instruction would starve the code needed to release space.
      State.Finalizers_Requested := False;
      if not Finalizers.Has_Pending (State) then return False; end if;
      --  This is an internal activation, not an allocated Lua closure. A
      --  failed optional CI allocation leaves every target queued. Explicit
      --  embedding quotas and physical host failures still abort execution.
      Schedule (Self, "@gc.finalize", Values.Empty_Vector, 0);
      State.Current.Stack.Last_Element.Completion :=
        (if Silent then Resume_Caller else Deliver_Results);
      return True;
   exception
      when Error : Lua.Storage.Allocation_Error | Program_Error =>
         if Ada.Exceptions.Exception_Identity (Error) =
           Program_Error'Identity and then
           not Lua.Storage.Refusal_Pending (State.Memory)
         then
            raise;
         end if;
         while Natural (State.Current.Stack.Length) > Before loop
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
         end loop;
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
   end Try_Push_Finalizers;

   function Try_Start_Finalizer
     (Self : Driver; Activation : Frame_Access) return Boolean
   is
      State : World renames Self.Universe.all;
      Before : constant Natural := Natural (State.Current.Stack.Length);
      Holder : Frame_Access;
   begin
      if State.Native_Depth >=
        Lua.Runtime_Configuration.Maximum_C_Calls - 2 or else
        State.Current.Foreign_Top > Natural'Last - Initial_Stack_Size
      then
         return False;
      end if;
      if not Ensure_Stack
        (State, State.Current,
         State.Current.Foreign_Top + Initial_Stack_Size,
         Raise_Error => False)
      then
         return False;
      end if;
      --  Reserve every helper-owned packet before consuming the pending
      --  obligation. This is the Ada CI equivalent of checkminstack: a
      --  persistent refusal defers callbacks rather than losing an object or
      --  trying to report a Lua allocation error from an unprotected phase.
      Schedule (Self, "@finalizer.invoke", Values.Empty_Vector, 0);
      Holder := State.Current.Stack.Last_Element;
      Holder.Native_Arguments.Reserve_Capacity (2);
      Holder.Error_Packet.Reserve_Capacity (2);
      Finalizers.Begin_Next (State);
      if Finalizers.Current_Handler (State).Kind = Nil_Kind then
         --  Enrollment survives removal, but a removed handler is skipped.
         Finalizers.Finish_Current (State);
         State.Current.Stack.Delete_Last;
         Release_Frame (State, Holder);
         return True;
      end if;
      Holder.Native_Arguments.Append (Finalizers.Current_Handler (State));
      Holder.Native_Arguments.Append (Finalizers.Current_Target (State));
      Holder.Protection := 1;
      Holder.Blocks_Yield := True;
      State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      --  Only the actual handler is non-yieldable/hook-suppressed. Pinned
      --  GCTM restores both policies before invoking a warning callback.
      Activation.Finalizer_Charge := True;
      Activation.Finalizer_Phase := Waiting_Finalizer_Handler;
      State.Current.Finalizer_Hook_Suppression :=
        State.Current.Finalizer_Hook_Suppression + 1;
      State.Finalizer_Active := True;
      return True;
   exception
      when Error : Lua.Storage.Allocation_Error | Program_Error =>
         if Ada.Exceptions.Exception_Identity (Error) =
           Program_Error'Identity and then
           not Lua.Storage.Refusal_Pending (State.Memory)
         then
            raise;
         end if;
         while Natural (State.Current.Stack.Length) > Before loop
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
         end loop;
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
   end Try_Start_Finalizer;

   procedure Advance_Finalizers (Self : Driver) is
      State : World renames Self.Universe.all;
      Activation : constant Frame_Access := State.Current.Stack.Last_Element;
      Error_Value : Value;
      procedure Fragment (Bytes : Byte_String; More : Boolean);
      procedure Fragment (Bytes : Byte_String; More : Boolean) is
      begin
         --  The caller passes package-level NUL-terminated constants. Their
         --  storage outlives any asynchronous warning acknowledgment; no
         --  transient concatenated Ada String is retained by a C callback.
         Emit_Warning
           (State, Bytes, To_Continue => More);
      end Fragment;
   begin
      case Activation.Finalizer_Phase is
         when Choosing_Finalizer =>
            if not Finalizers.Has_Pending (State) or else
              not Try_Start_Finalizer (Self, Activation)
            then
               State.Finalizers_Requested := False;
               Complete (Self, Values.Empty_Vector);
            end if;
         when Waiting_Finalizer_Handler =>
            State.Current.Finalizer_Hook_Suppression :=
              State.Current.Finalizer_Hook_Suppression - 1;
            Activation.Finalizer_Charge := False;
            Finalizers.Finish_Current (State);
            if Activation.Native_Results.Is_Empty or else
              Truth (Activation.Native_Results.First_Element)
            then
               Activation.Native_Results.Clear;
               Activation.Finalizer_Phase := Choosing_Finalizer;
            else
               --  Match luaE_warnerror's five observable fragments. The
               --  failed packet roots its original error through every C
               --  warning callback, including nested Lua/GC reentry.
               Fragment (GC_Warning_Start, True);
               Activation.Finalizer_Phase := Warning_Where;
            end if;
         when Warning_Where =>
            Fragment (GC_Warning_Where, True);
            Activation.Finalizer_Phase := Warning_Open;
         when Warning_Open =>
            Fragment (GC_Warning_Open, True);
            Activation.Finalizer_Phase := Warning_Error;
         when Warning_Error =>
            Error_Value :=
              (if Activation.Native_Results.Length >= 2 then
                  Activation.Native_Results (2) else Nil_Value);
            if Error_Value.Kind = String_Kind then
               Emit_Warning (State, Error_Value, To_Continue => True);
            else
               Fragment (GC_Warning_Nonstring, True);
            end if;
            Activation.Finalizer_Phase := Warning_Close;
         when Warning_Close =>
            Fragment (GC_Warning_Close, False);
            Activation.Native_Results.Clear;
            Activation.Finalizer_Phase := Choosing_Finalizer;
      end case;
   end Advance_Finalizers;

   procedure Native_Step (Self : Driver) is
      State : World renames Self.Universe.all;
      Activation : constant Frame_Access :=
        State.Current.Stack.Last_Element;
      Name : constant String := To_String (Activation.Native_Name);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length)
         then Activation.Native_Arguments (Index) else Nil_Value);
      Packet : Values.Vector := Owned_Values (State);
      Left : Value := Arg (1);
      Right : Value := Arg (2);
      Handler : Value;
      Event : Unbounded_String;
      Operator : Token_Kind := Activation.Native_Operator;
      Primitive : Boolean := False;
      Action : Native_Action := New_Action (State);
      Library_Step : Boolean := True;
      procedure Return_Native (Item : Value);
      procedure Invoke (Function_Value : Value; Args : Values.Vector);
      procedure Return_Native (Item : Value) is
         Result : Values.Vector := Owned_Values (State);
      begin
         Result.Append (Item);
         Complete (Self, Result);
      end Return_Native;
      procedure Invoke (Function_Value : Value; Args : Values.Vector) is
      begin
         --  Publish the resume phase before dispatch: immediate builtins
         --  may return immediately; Lua closures suspend this frame.
         Activation.Native_Stage := 1;
         Dispatch (Self, Function_Value, Args, 0);
      end Invoke;
   begin
      State.Current.Failure_At := Activation.Call_Site;
      --  Stateful libraries own their continuation phase. Dispatch their
      --  requested callback through this same activation stack, so neither
      --  Lua nesting nor a protected error creates a second VM or budget.
      if Activation.Warning_Failed then
         Activation.Warning_Failed := False;
         raise Language_Error;
      end if;
      if Name = "foreign.callback" then
         if Activation.Native_Stage = 0 then
            if Activation.Foreign_Handler = System.Null_Address then
               raise Program_Error with "foreign callback has no handler";
            end if;
            if State.Next_Foreign_Ticket =
              Interfaces.C.unsigned_long_long'Last
            then
               Fail (State, "foreign callback identity exhausted",
                     Resource => True);
            end if;
            State.Next_Foreign_Ticket := State.Next_Foreign_Ticket + 1;
            Activation.Foreign_Ticket := State.Next_Foreign_Ticket;
            Activation.Foreign_Base := Activation.Stack_Base;
            Activation.Foreign_Previous_Base := State.Current.Foreign_Base;
            Activation.Foreign_Previous_Frame :=
              State.Current.Foreign_Activation;
            Activation.Foreign_Entered := True;
            State.Current.Foreign_Base := Activation.Stack_Base;
            State.Current.Foreign_Top := Activation.Stack_Live_Top;
            State.Current.Foreign_Activation := Activation;
            --  Actual scalar slots now own every argument. Keeping a stale
            --  packet would retain C arguments removed/replaced by the host
            --  and invalidate weak observations during callback collection.
            Activation.Native_Arguments.Clear;
            Activation.Native_Stage := 1;
            --  Returning exposes an explicit C request. Invoking its function
            --  pointer here would let longjmp cross these live Ada frames.
         elsif Activation.Native_Stage = 2 then
            Complete (Self, Activation.Native_Results);
         elsif Activation.Native_Stage = 3 then
            raise Language_Error;
         else
            raise Program_Error with "foreign callback awaits its C pump";
         end if;
         return;
      elsif Name = "@foreign.boundary" then
         --  A protected child has delivered one wrapped packet. Leave it in
         --  this sentinel until the nested C pump publishes the results onto
         --  the caller's C stack, then explicitly removes the sentinel.
         Activation.Native_Results :=
           Wrap (State, Activation.Native_Results, 1);
         Activation.Native_Stage := 1;
         return;
      elsif Name = "@gc.finalize" then
         Advance_Finalizers (Self);
         return;
      elsif Name in "@foreign.entry" | "@close.invoke" |
        "@finalizer.invoke"
      then
         if Activation.Native_Stage = 0 then
            Handler := Arg (1);
            for Index in 2 ..
              Natural (Activation.Native_Arguments.Length)
            loop
               Packet.Append (Arg (Index));
            end loop;
            Activation.Native_Stage := 1;
            Dispatch (Self, Handler, Packet, 0,
                      Call_Base => Activation.Native_Index,
                      Has_Call_Window => Activation.Native_Aux /= 0);
            Activation.Native_Arguments.Clear;
         else
            Complete (Self, Activation.Native_Results);
         end if;
         return;
      elsif Name = "@message.handler" then
         if Activation.Native_Stage = 0 then
            Packet.Append (Arg (2));
            Activation.Native_Stage := 1;
            Dispatch (Self, Arg (1), Packet, 0);
            return;
         end if;
         --  Its raw target returned normally. Recursive handler errors never
         --  resume this phase: they return to the same protected holder and
         --  the eventual successful transformation retires the failed chain.
         Left := First (Activation.Native_Results);
         Pin (State, Left);
         State.Current.Stack.Delete_Last;
         declare
            Old : Frame_Access := Activation;
         begin
            State.Current.Failure_At := Old.Call_Site;
            Release_Frame (State, Old);
         end;
         State.Current.Failure := Left;
         State.Current.Has_Failure_Value := True;
         State.Current.Failure_Class := Language_Failure;
         State.Current.Failure_Handled := True;
         State.Current.Failure_Text :=
           To_Unbounded_String (Image (State.Current.Memory, Left));
         Recover (Self);
         return;
      elsif Name = "base.primitive" then
         Complete (Self, Native
           (Self, Activation.Native_Id, Activation.Native_Arguments));
         return;
      elsif Name = "base.pcall" then
         if Activation.Native_Stage = 0 then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            Packet := Activation.Native_Arguments;
            Handler := Packet (1);
            Packet.Delete_First;
            Activation.Error_Packet.Reserve_Capacity (2);
            Activation.Protection := Activation.Protection + 1;
            Activation.Native_Stage := 1;
            Stacks.Write
              (State, State.Current, Activation.Stack_Base + 1,
               (Boolean_Kind, True));
            Dispatch (Self, Handler, Packet, 0,
                      Call_Base => Activation.Stack_Base + 2,
                      Has_Call_Window => True);
            Activation.Native_Arguments.Clear;
         else
            Complete (Self, Activation.Native_Results);
         end if;
         return;
      elsif Name = "@hook" then
         State.Current.Hook_Active := False;
         Complete (Self, Values.Empty_Vector);
         return;
      elsif Name = "@return.hook" then
         Packet := Activation.Unwind_Results;
         State.Current.Stack.Delete_Last;
         declare
            Old : Frame_Access := Activation;
         begin
            Release_Frame (State, Old);
         end;
         Complete (Self, Packet);
         return;
      elsif Name = "base.collectgarbage" then
         declare
            Option : constant String :=
              (if Left.Kind = Nil_Kind then "collect"
               else C_Option (Image (State.Current.Memory, Left)));
         begin
            if Option = "collect" then
               Collect (State);
               Return_Native ((Integer_Kind, 0));
            elsif Option = "stop" then
               State.GC_Running := False;
               Return_Native ((Integer_Kind, 0));
            elsif Option = "restart" then
               State.GC_Running := True;
               Return_Native ((Integer_Kind, 0));
            elsif Option = "isrunning" then
               Return_Native ((Boolean_Kind, State.GC_Running));
            else
               Fail (State, "unsupported collectgarbage option '" &
                       Option & "'");
            end if;
         end;
         return;
      elsif Name = "@close.thread" then
         if State.Current.Stack.Length = 1 then
            State.Current.Stack.Delete_Last;
            declare
               Old : Frame_Access := Activation;
            begin
               Release_Frame (State, Old);
            end;
            State.Current.Transfer :=
              (Kind => (if State.Current.Has_Failure_Value then Lua_Raised
                        else Completed),
               Results => (if State.Current.Has_Failure_Value then
                 One_Value (State.Current.Memory, State.Current.Failure, 1)
                 else Values.Empty_Vector), Target => 0);
            State.Current.Failure := Nil_Value;
            State.Current.Has_Failure_Value := False;
         elsif Activation.Native_Stage = 1 then
            declare
               Owner : Frame_Access := State.Current.Stack
                 (State.Current.Stack.Last_Index - 1);
            begin
               State.Current.Stack.Delete
                 (State.Current.Stack.Last_Index - 1);
               Release_Frame (State, Owner);
               Activation.Native_Stage := 0;
            end;
         else
            declare
               Owner : constant Frame_Access := State.Current.Stack
                 (State.Current.Stack.Last_Index - 1);
            begin
               Activation.Native_Stage := 1;
               Start_Unwind (Self, Owner, Coroutine_Exit);
            end;
         end if;
         return;
      elsif Name = "@unwind" then
         declare
            Owner : constant Frame_Access := Activation.Unwind_Owner;
            Reason : Unwind_Reason := Activation.Unwind;
            Closing : Close_Entry;
            Need_Close : Boolean;
         begin
            if Activation.Native_Stage = 1 then
               if not Activation.Native_Results (1).Boolean_Data then
                  Activation.Unwind_Error :=
                    Activation.Native_Results (2);
                  Activation.Unwind_Has_Error := True;
                  Activation.Unwind_Failure_Class :=
                    Activation.Result_Failure_Class;
                  Activation.Unwind_Handler_Called :=
                    Activation.Result_Handler_Called;
                  if Reason /= Coroutine_Exit then
                     Reason := Error_Exit;
                     Activation.Unwind := Reason;
                  end if;
                  if not Activation.Blocks_Yield then
                     Activation.Blocks_Yield := True;
                     State.Current.Non_Yieldable :=
                       State.Current.Non_Yieldable + 1;
                  end if;
               end if;
               Activation.Native_Results.Clear;
               Activation.Native_Stage := 0;
            end if;
            while not Owner.Closers.Is_Empty loop
               Closing := Owner.Closers.Last_Element;
               Need_Close := Reason in Return_Exit | Error_Exit |
                 Coroutine_Exit or else
                 Closing.Depth > Activation.Unwind_Depth or else
                 (Reason = Jump_Exit and then Closing.Symbol /= 0 and then
                  not Activation.Unwind_Live.Contains (Closing.Symbol));
               exit when not Need_Close;
               Owner.Closers.Delete_Last;
               Left := (if Closing.Frozen then Closing.Frozen_Value else
                          Closing.Cell.Cell_Value);
               if Truth (Left) then
                  Handler := Metafield (State, Left, "__close");
                  if Handler.Kind = Nil_Kind then
                     Handler := New_Native (State, "@invalid.close");
                  end if;
                  Packet.Append (Left);
                  Packet.Append (Activation.Unwind_Error);
                  Activation.Native_Stage := 1;
                  --  Protection is a cleanup boundary, not a public pcall
                  --  activation. Logical debug frames expose the original
                  --  owner or its surrounding protected native caller.
                  declare
                     Message_Handler : constant Value :=
                       Active_Handler (Self);
                  begin
                     Packet.Prepend (Handler);
                     Pin (State, Packet);
                     Schedule (Self, "@close.invoke", Packet, 0);
                     State.Current.Stack.Last_Element.Error_Packet
                       .Reserve_Capacity (2);
                     State.Current.Stack.Last_Element.Protection := 1;
                     State.Current.Stack.Last_Element.Message_Handler :=
                       Message_Handler;
                  end;
                  return;
               end if;
            end loop;
            declare
               Results : constant Values.Vector :=
                 Activation.Unwind_Results;
               Error_Value : constant Value := Activation.Unwind_Error;
               Failed : constant Boolean := Activation.Unwind_Has_Error;
               Failure : constant Failure_Kind :=
                 Activation.Unwind_Failure_Class;
               Handler_Called : constant Boolean :=
                 Activation.Unwind_Handler_Called;
               Depth : constant Natural := Activation.Unwind_Depth;
               PC : constant Natural := Activation.Unwind_PC;
               Live : constant Registers.Vector := Activation.Unwind_Live;
               Old : Frame_Access := Activation;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
               if Reason in Error_Exit | Coroutine_Exit then
                  State.Current.Failure := Error_Value;
                  State.Current.Has_Failure_Value := Failed;
                  State.Current.Failure_Text :=
                    To_Unbounded_String
                      (Image (State.Current.Memory, Error_Value));
                  State.Current.Failure_Class := Failure;
                  State.Current.Failure_Handled := Handler_Called;
               end if;
               case Reason is
                  when Return_Exit => Complete (Self, Results);
                  when Scope_Exit =>
                     if Owner.Code.Canonical_Node = null then
                        Owner.Scope := Owner.Scope.Parent;
                        Owner.Scope_Depth := Owner.Scope_Depth - 1;
                     end if;
                     --  Canonical CLOSE uses register lifetime boundaries,
                     --  not the private backend's lexical environment chain.
                  when Jump_Exit =>
                     while Owner.Scope_Depth > Depth loop
                        Owner.Scope := Owner.Scope.Parent;
                        Owner.Scope_Depth := Owner.Scope_Depth - 1;
                     end loop;
                     for Index in reverse Owner.Scope.Locals.First_Index ..
                       Owner.Scope.Locals.Last_Index
                     loop
                        if not Live.Contains
                          (Owner.Scope.Locals (Index).Symbol)
                        then
                           Owner.Scope.Locals.Delete (Index);
                        end if;
                     end loop;
                     Owner.PC := PC;
                  when Error_Exit => Recover (Self);
                  when Coroutine_Exit => null;
                  when No_Unwind => raise Program_Error;
               end case;
            end;
         end;
         return;
      elsif Name = "@invalid.close" then
         Fail (State, "attempt to close a non-closable value");
      end if;
      if Name'Length >= 10 and then
        Name (Name'First .. Name'First + 9) = "coroutine."
      then
         if Name in "coroutine.create" | "coroutine.wrap" then
            if Left.Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Fail (State, "function expected");
            end if;
            Handler := New_Thread (State, Left);
            if Name = "coroutine.wrap" then
               Handler := New_Native
                 (State, "coroutine.wrapped", One_Value
                   (State, Handler, 1));
            end if;
            Return_Native (Handler);
         elsif Name = "coroutine.running" then
            Packet.Append (Value'(Thread_Kind, State.Current.Thread));
            Packet.Append (Value'(Boolean_Kind,
                                  State.Current = State.Main_Context));
            Complete (Self, Packet);
         elsif Name = "coroutine.yield" then
            if Activation.Native_Stage = 0 then
               if State.Current = State.Main_Context or else
                 State.Current.Resumer = null or else
                 State.Current.Non_Yieldable > 0 or else
                 State.Current.Phase = Closing
               then
                  Fail (State, "attempt to yield across a non-yieldable " &
                          "boundary");
               end if;
               Activation.Native_Stage := 1;
               State.Current.Transfer.Kind := Yielded;
               State.Current.Transfer.Results :=
                 Activation.Native_Arguments;
            else
               Complete (Self, Activation.Native_Results);
            end if;
         else
            declare
               Thread : Value := Left;
               Context : Context_Access;
               Args : Values.Vector :=
                 Owned_Values (State, Activation.Native_Arguments);
            begin
               if Name = "coroutine.wrapped" then
                  Thread := Activation.Native_Captures (1);
               elsif Name in "coroutine.isyieldable" |
                 "coroutine.close" and then
                 Activation.Native_Arguments.Is_Empty
               then
                  Thread := (Thread_Kind, State.Current.Thread);
               end if;
               if Thread.Kind /= Thread_Kind then
                  Fail (State, "thread expected");
               end if;
               Context := State.Contexts (Thread.Reference.Context_Index);
               if Name = "coroutine.status" then
                  Return_Native (New_String
                    (State,
                     (case Context.Status is
                         when New_Context | Suspended_Context =>
                           "suspended",
                         when Running_Context => "running",
                         when Normal_Context => "normal",
                         when Dead_Context => "dead")));
               elsif Name = "coroutine.isyieldable" then
                  --  This queries yield barriers, not resume validity.
                  --  A dead context retains error frames for inspection
                  --  and close, but their abandoned barriers do not count.
                  Return_Native ((Boolean_Kind,
                           Context /= State.Main_Context and then
                           Context.Phase /= Closing and then
                           (Context.Status = Dead_Context or else
                            Context.Non_Yieldable = 0)));
               elsif Name in "coroutine.resume" | "coroutine.wrapped" then
                  if Activation.Native_Stage = 2 then
                     --  wrap closes a failed body before raising. A close
                     --  error replaces the body's error, just as in Lua.
                     Packet := Activation.Native_Results;
                     Raise_Value
                       (Self, (if Packet (1).Boolean_Data then
                           Activation.Unwind_Error else Packet (2)));
                  elsif Activation.Native_Stage = 1 then
                     Packet := Activation.Native_Results;
                     if Name = "coroutine.wrapped" then
                        if not Packet (1).Boolean_Data then
                           Activation.Unwind_Error := Packet (2);
                           Activation.Native_Stage := 2;
                           State.Current.Transfer :=
                             (Kind => Close_Requested,
                              Results => Values.Empty_Vector,
                              Target => Thread.Reference.Context_Index);
                           return;
                        end if;
                        Packet.Delete_First;
                     end if;
                     Complete (Self, Packet);
                  elsif Context = State.Main_Context or else
                    Context.Status not in New_Context | Suspended_Context
                  then
                     Handler := New_String
                       (State, (if Context.Status = Dead_Context then
                          "cannot resume dead coroutine" else
                          "cannot resume non-suspended coroutine"));
                     if Name = "coroutine.wrapped" then
                        Raise_Value (Self, Handler);
                     end if;
                     Packet.Append (Value'(Boolean_Kind, False));
                     Packet.Append (Handler);
                     Complete (Self, Packet);
                  else
                     if Name = "coroutine.resume" then
                        Args.Delete_First;
                     end if;
                     Activation.Native_Stage := 1;
                     State.Current.Transfer :=
                       (Kind => Resume_Requested, Results => Args,
                        Target => Thread.Reference.Context_Index);
                  end if;
               elsif Name = "coroutine.close" then
                  if Activation.Native_Stage = 1 then
                     Complete (Self, Activation.Native_Results);
                     return;
                  end if;
                  if Context.Status = Normal_Context then
                     Fail (State, "cannot close a normal coroutine");
                  elsif Context = State.Main_Context then
                     Fail (State, "cannot close main thread");
                  elsif Context = State.Current then
                     --  Closing oneself never returns to the abandoned
                     --  Lua/native frames, even from inside __close.
                     Context.Phase := Closing;
                     Schedule (Self, "@close.thread", Values.Empty_Vector, 0);
                     return;
                  end if;
                  --  Close requests are consumed by the same scheduler;
                  --  the scope-exit driver supplies user cleanup below.
                  Activation.Native_Stage := 1;
                  State.Current.Transfer :=
                    (Kind => Close_Requested,
                     Results => Values.Empty_Vector,
                     Target => Thread.Reference.Context_Index);
               else
                  raise Program_Error with "unknown coroutine operation";
               end if;
            end;
         end if;
         return;
      end if;
      if Name'Length > 6 and then Name (1 .. 6) = "debug." then
         Complete (Self, Inspection.Inspect (State, Activation));
         return;
      end if;
      if Name = "base.warn" then
         Action := Warnings.Advance (State, Activation);
      elsif Name = "table.create" then
         Complete (Self, Sorting.Create (State, Activation.Native_Arguments));
         return;
      elsif Name = "table.sort" then
         Action := Sorting.Advance (State, Activation);
      elsif Name in "string.gmatch" | "gmatch.iterator" | "string.gsub" then
         Action := Pattern_Drivers.Advance (State, Activation);
      elsif Name = "string.format" then
         Action := Format_Drivers.Advance (State, Activation);
      elsif Name in "table.concat" | "table.insert" | "table.remove" |
        "table.move" | "table.unpack"
      then
         Action := Table_Drivers.Advance (State, Activation);
      elsif Name in "base.load" | "base.loadfile" | "base.dofile" |
        "base.require" | "package.searchpath" |
        "package.preload_searcher" | "package.lua_searcher"
      then
         Action := Loaders.Advance (State, Activation);
      else
         Library_Step := False;
         Action.Kind := Continue_Step;
      end if;
      if Action.Kind = Finished then
         Complete (Self, Action.Results);
         return;
      elsif Action.Kind = Drain_Finalizers then
         --  The requesting library already saved its result/resume phase.
         --  Optional inability to run a finalizer leaves that queue intact.
         if Try_Push_Finalizers (Self) then null; end if;
         return;
      elsif Action.Kind = Invoke then
         if Action.Operator /= End_Of_Input then
            --  Library continuations use the same primitive/metamethod
            --  operation as canonical instructions. Their captures already
            --  retain operands while this helper and any handler execute.
            Schedule
              (Self, (if Action.Operator = Length then "@unary" else
                        "@binary"), Action.Arguments, 0,
               Operator => Action.Operator);
         else
            Dispatch (Self, Action.Function_Value, Action.Arguments, 0);
         end if;
         return;
      elsif Library_Step then
         return;
      end if;
      if Activation.Native_Stage = 1 and then
        (Name in "@set" | "@invoke" | "@get" | "@binary" | "@unary" or else
         (Name'Length > 6 and then Name (1 .. 6) = "arith."))
      then
         if Name = "@set" then
            Complete (Self, Values.Empty_Vector);
         elsif Name = "@invoke" then
            Complete (Self, Activation.Native_Results);
         elsif Name = "@binary" and then
           Activation.Native_Operator in Equal | Not_Equal |
             Less | Less_Equal | Greater | Greater_Equal
         then
            Return_Native ((Boolean_Kind,
                     Truth (First (Activation.Native_Results)) xor
                     (Activation.Native_Operator = Not_Equal)));
         else
            Return_Native (First (Activation.Native_Results));
         end if;
         return;
      end if;
      if Name = "@invoke" then
         Handler := First (Activation.Native_Captures);
         Invoke (Handler, Activation.Native_Arguments);
      elsif Name in "@length" | "@equal" then
         if Activation.Native_Stage = 1 then
            Return_Native (First (Activation.Native_Results));
         else
            Activation.Native_Stage := 1;
            Schedule
              (Self, (if Name = "@length" then "@unary" else "@binary"),
               Activation.Native_Arguments, 0,
               (if Name = "@length" then Length else Equal));
         end if;
      elsif Name in "math.min" | "math.max" then
         if Activation.Native_Stage = 0 then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            Activation.Native_Captures := One_Value (State, Left, 1);
            Activation.Native_Index := 2;
         elsif Truth (First (Activation.Native_Results)) then
            Activation.Native_Captures.Replace_Element
              (1, Arg (Activation.Native_Index));
            Activation.Native_Index := Activation.Native_Index + 1;
         else
            Activation.Native_Index := Activation.Native_Index + 1;
         end if;
         if Activation.Native_Index >
           Natural (Activation.Native_Arguments.Length)
         then
            Return_Native (First (Activation.Native_Captures));
         else
            Left := First (Activation.Native_Captures);
            Right := Arg (Activation.Native_Index);
            Packet.Append ((if Name = "math.max" then Left else Right));
            Packet.Append ((if Name = "math.max" then Right else Left));
            Activation.Native_Stage := 1;
            Schedule (Self, "@binary", Packet, 0, Less);
         end if;
      elsif Name = "base.xpcall" then
         --  The native activation itself is the protected holder. A failing
         --  target keeps every original frame alive while Recover invokes
         --  its message handler, including recursively raised handler errors.
         if Activation.Native_Stage = 0 then
            if Natural (Activation.Native_Arguments.Length) < 2 then
               Fail (State, "xpcall needs a function and error handler");
            end if;
            if Arg (2).Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Fail (State, "error handler must be a function");
            end if;
            for Index in 3 ..
              Natural (Activation.Native_Arguments.Length)
            loop
               Packet.Append (Arg (Index));
            end loop;
            Activation.Error_Packet.Reserve_Capacity (2);
            Activation.Protection := Activation.Protection + 1;
            Activation.Message_Handler := Arg (2);
            Activation.Native_Stage := 1;
            Stacks.Write
              (State, State.Current, Activation.Stack_Base + 3,
               (Boolean_Kind, True));
            Dispatch (Self, Arg (1), Packet, 0,
                      Call_Base => Activation.Stack_Base + 4,
                      Has_Call_Window => True);
            Activation.Native_Arguments.Clear;
         else
            Complete (Self, Activation.Native_Results);
         end if;
      elsif Name = "base.tostring" then
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected");
         end if;
         if Activation.Native_Stage = 1 then
            Handler := First (Activation.Native_Results);
            if Handler.Kind not in String_Kind | Integer_Kind | Real_Kind
            then
               Fail (State, "__tostring must return a string");
            end if;
            Return_Native
              (New_String (State, Image (State.Current.Memory, Handler)));
         else
            Handler := Metafield (State, Left, "__tostring");
            if Handler.Kind /= Nil_Kind then
               Packet.Append (Left);
               Invoke (Handler, Packet);
            else
               Return_Native
                 (New_String (State, Image (State.Current.Memory, Left)));
            end if;
         end if;
      elsif Name = "base.print" then
         if Activation.Native_Stage = 1 then
            Handler := First (Activation.Native_Results);
            --  Publish each completed conversion before requesting another
            --  __tostring callback. A later callback can observe the output
            --  or fail, and neither event may erase the earlier argument.
            if Activation.Native_Index > 1 then
               Emit_Output (State, [Ada.Characters.Latin_1.HT]);
            end if;
            Emit_Output (State, Image (State.Current.Memory, Handler));
            Activation.Native_Index := Activation.Native_Index + 1;
            Activation.Native_Stage := 0;
         elsif Activation.Native_Index = 0 then
            Activation.Native_Index := 1;
         end if;
         if Activation.Native_Index >
           Natural (Activation.Native_Arguments.Length)
         then
            Emit_Output (State, [Ada.Characters.Latin_1.LF]);
            Flush_Output (State);
            Complete (Self, Values.Empty_Vector);
         else
            Packet.Append (Arg (Activation.Native_Index));
            Activation.Native_Stage := 1;
            Schedule (Self, "base.tostring", Packet, 0);
         end if;
      elsif Name = "base.pairs" then
         if Activation.Native_Stage = 1 then
            Packet := Activation.Native_Results;
         else
            Handler := Metafield (State, Left, "__pairs");
            if Handler.Kind /= Nil_Kind then
               Packet.Append (Left);
               Invoke (Handler, Packet);
               return;
            end if;
            Packet := Native
              (Self, Pairs_Function, Activation.Native_Arguments);
         end if;
         Packet.Set_Length (4);
         Complete (Self, Packet);
      elsif Name = "base.ipairs" then
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected");
         end if;
         Packet.Append (New_Native (State, "ipairs.iterator"));
         Packet.Append (Left);
         Packet.Append (Value'(Integer_Kind, 0));
         Complete (Self, Packet);
      elsif Name = "ipairs.iterator" then
         if Activation.Native_Stage = 0 then
            Right := (Integer_Kind,
              Lua.Integers.Add (Integral (State, Right), 1));
            Activation.Native_Captures := One_Value (State, Right, 1);
            Packet.Append (Left);
            Packet.Append (Right);
            Activation.Native_Stage := 1;
            Schedule (Self, "@get", Packet, 0);
         else
            Handler := First (Activation.Native_Results);
            if Handler.Kind /= Nil_Kind then
               Packet.Append (First (Activation.Native_Captures));
            end if;
            Packet.Append (Handler);
            Complete (Self, Packet);
         end if;
      elsif Name in "@get" | "@set" then
         loop
            if Name = "@get" then
               if Left.Kind = Table_Kind then
                  Handler := Get (Left, Right);
                  if Handler.Kind /= Nil_Kind then
                     Return_Native (Handler);
                     return;
                  end if;
               end if;
               Handler := Metafield (State, Left, "__index");
            else
               if Left.Kind = Table_Kind and then
                 Get (Left, Right).Kind /= Nil_Kind
               then
                  Set (State, Left, Right, Arg (3));
                  Complete (Self, Values.Empty_Vector);
                  return;
               end if;
               Handler := Metafield (State, Left, "__newindex");
            end if;
            if Handler.Kind = Nil_Kind then
               if Left.Kind /= Table_Kind then
                  Fail (State, "attempt to index a " & Type_Name (Left));
               elsif Name = "@get" then
                  Return_Native (Nil_Value);
               else
                  Set (State, Left, Right, Arg (3));
                  Complete (Self, Values.Empty_Vector);
               end if;
               return;
            elsif Handler.Kind in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Activation.Native_Arguments.Replace_Element (1, Left);
               Invoke (Handler, Activation.Native_Arguments);
               return;
            end if;
            Activation.Native_Aux := Activation.Native_Aux + 1;
            if State.Steps >= State.Bounds.Instructions then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            if State.Policy = Bounded then
               State.Steps := State.Steps + 1;
            end if;
            if Activation.Native_Aux >= 2000 then
               Fail (State, "metatable index chain too long");
            end if;
            Left := Handler;
         end loop;
      elsif Name in "@binary" | "@unary" then
         if Name = "@unary" then
            Primitive := Operator = Not_Word or else
              (Operator = Length and then Left.Kind = String_Kind) or else
              (Operator in Minus | Bit_Xor and then
                 Left.Kind in Integer_Kind | Real_Kind);
            Event := To_Unbounded_String
              ((case Operator is
                   when Minus => "__unm", when Bit_Xor => "__bnot",
                   when Length => "__len", when others => ""));
            Right := Left;  --  Unary handlers receive duplicate operands.
         else
            Primitive :=
              (Left.Kind in Integer_Kind | Real_Kind and then
                 Right.Kind in Integer_Kind | Real_Kind) or else
              (Operator in Concatenate | Less | Less_Equal |
                 Greater | Greater_Equal and then
                 Left.Kind = String_Kind and then Right.Kind = String_Kind);
            if Operator = Concatenate then
               Primitive := Left.Kind in String_Kind | Integer_Kind |
                 Real_Kind and then Right.Kind in String_Kind |
                 Integer_Kind | Real_Kind;
            end if;
            if Operator in Equal | Not_Equal then
               Primitive := Equal (Left, Right) or else
                 Left.Kind /= Right.Kind or else
                 Left.Kind not in Table_Kind | Userdata_Kind;
            end if;
            if Operator in Greater | Greater_Equal then
               Handler := Left;
               Left := Right;
               Right := Handler;
               Operator :=
                 (if Operator = Greater then Less else Less_Equal);
            end if;
            Event := To_Unbounded_String
              ((case Operator is
                   when Plus => "__add", when Minus => "__sub",
                   when Star => "__mul", when Slash => "__div",
                   when Floor_Divide => "__idiv", when Percent => "__mod",
                   when Power => "__pow", when Bit_And => "__band",
                   when Bit_Or => "__bor", when Bit_Xor => "__bxor",
                   when Shift_Left => "__shl", when Shift_Right => "__shr",
                   when Concatenate => "__concat",
                   when Equal | Not_Equal => "__eq",
                   when Less => "__lt", when Less_Equal => "__le",
                   when others => ""));
         end if;
         if not Primitive then
            Handler := Metafield (State, Left, To_String (Event));
            if Handler.Kind = Nil_Kind and then Name = "@binary" then
               Handler := Metafield (State, Right, To_String (Event));
            end if;
            if Handler.Kind /= Nil_Kind then
               Packet.Append (Left);
               Packet.Append (Right);
               Invoke (Handler, Packet);
               return;
            elsif Name = "@binary" and then
              Operator in Equal | Not_Equal
            then
               Return_Native ((Boolean_Kind, Operator = Not_Equal));
               return;
            elsif Left.Kind = String_Kind and then
              Operator not in Concatenate | Equal | Not_Equal |
                Less | Less_Equal | Greater | Greater_Equal
            then
               Fail (State, "no arithmetic metamethod for string");
            end if;
         end if;
         Return_Native ((if Name = "@unary"
                  then Unary_Value (State, Operator, Left)
                  else Binary_Value (State, Operator, Left, Right)));
      elsif Name = "base.getmetatable" then
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected");
         end if;
         Handler := Metafield (State, Left, "__metatable");
         if Handler.Kind /= Nil_Kind then
            Return_Native (Handler);
         else
            declare
               Meta : constant Object_Access := Raw_Metatable (State, Left);
            begin
               Return_Native ((if Meta = null then Nil_Value else
                                  (Table_Kind, Meta)));
            end;
         end if;
      elsif Name = "base.setmetatable" then
         if Left.Kind /= Table_Kind then
            Fail (State, "table expected");
         elsif Right.Kind not in Nil_Kind | Table_Kind then
            Fail (State, "nil or table expected");
         elsif Metafield (State, Left, "__metatable").Kind /= Nil_Kind then
            Fail (State, "cannot change a protected metatable");
         end if;
         Set_Metatable
           (State, Left, (if Right.Kind = Nil_Kind then null else
                            Right.Reference));
         Return_Native (Left);
      elsif Name'Length > 6 and then Name (1 .. 6) = "arith." then
         Event := To_Unbounded_String (Name (7 .. Name'Last));
         Operator :=
           (if Event = "__add" then Plus
            elsif Event = "__sub" or else Event = "__unm" then Minus
            elsif Event = "__mul" then Star
            elsif Event = "__mod" then Percent
            elsif Event = "__div" then Slash
            elsif Event = "__idiv" then Floor_Divide else Power);
         if Event = "__unm" then
            Right := Left;
         end if;
         declare
            function Convert (Item : Value) return Lua.Numbers.Number;
            function Convert (Item : Value) return Lua.Numbers.Number is
            begin
               if Item.Kind = String_Kind then
                  return Read_Number (State, Item.Reference.Bytes);
               elsif Item.Kind = Integer_Kind then
                  return (Lua.Numbers.Integer_Number, Item.Integer_Data);
               elsif Item.Kind = Real_Kind then
                  return (Lua.Numbers.Real_Number, Item.Real_Data);
               else
                  return (Kind => Lua.Numbers.Invalid);
               end if;
            end Convert;
            L : constant Lua.Numbers.Number := Convert (Left);
            R : constant Lua.Numbers.Number := Convert (Right);
         begin
            if L.Kind /= Lua.Numbers.Invalid and then
              R.Kind /= Lua.Numbers.Invalid
            then
               Return_Native ((if Event = "__unm"
                        then Unary_Value (State, Minus, Left)
                        else Binary_Value (State, Operator, Left, Right)));
            else
               Handler := (if Right.Kind /= String_Kind
                           then Metafield (State, Right, To_String (Event))
                           else Nil_Value);
               if Handler.Kind = Nil_Kind then
                  Fail (State, "attempt to perform arithmetic on a " &
                          Type_Name (Left));
               end if;
               Packet.Append (Left);
               Packet.Append (Right);
               Invoke (Handler, Packet);
            end if;
         end;
      elsif Name'Length > 5 and then
        (Name (1 .. 5) = "math." or else Name (1 .. 6) = "table.")
      then
         Complete (Self, Core_Libraries.Run
           (State, Name, Activation.Native_Arguments));
      elsif Name'Length > 7 and then Name (1 .. 7) = "string." then
         if Name in "string.pack" | "string.packsize" | "string.unpack"
         then
            Complete (Self, Packing.Run
              (State, Name (8 .. Name'Last), Activation.Native_Arguments));
         else
            Complete (Self, Strings.Run
              (State, Name (8 .. Name'Last), Activation.Native_Arguments));
         end if;
      elsif Name'Length > 5 and then Name (1 .. 5) = "utf8." then
         if Name = "utf8.codes" then
            Packet.Append (New_Native
              (State, "utf8.step", One_Value (State, Arg (2), 1)));
            for Item of Unicode.Run
              (State, "codes", Activation.Native_Arguments)
            loop
               Packet.Append (Item);
            end loop;
            Complete (Self, Packet);
         elsif Name = "utf8.step" then
            Packet := Activation.Native_Arguments;
            Packet.Append (First (Activation.Native_Captures));
            Complete (Self, Unicode.Run (State, "step", Packet));
         else
            Complete (Self, Unicode.Run
              (State, Name (6 .. Name'Last), Activation.Native_Arguments));
         end if;
      else
         Fail (State, "native continuation not implemented: " & Name);
      end if;
   end Native_Step;

   procedure Execute_Private_Instruction (Self : Driver) is
      State : World renames Self.Universe.all;
      --  Copy the instruction before dispatch: calls may replace the
      --  current activation, and a tail call may free it entirely.
      Activation : constant Frame_Access :=
        State.Current.Stack.Last_Element;
      Code : constant Instruction := Activation.Code.Code (Activation.PC);
      A : constant Natural := Code.A;
      B : constant Natural := Code.B;
      C : constant Natural := Code.C;
      Packet : Values.Vector := Owned_Values (State);
      Left, Right, Item : Value;
      L, R, S : Lua.Numbers.Number;
      Control, Bound, Stride : Integer_Value;
      Real_Control, Real_Bound, Real_Delta : Real_Value;
   begin
      Activation.PC := Activation.PC + 1;
      State.Current.Failure_At := Code.Location;
      case Code.Op is
         when No_Operation => null;
         when Clear_Registers =>
            for Register_Id in A .. B loop
               Put_Packet (State, Activation, Register_Id,
                 Values.Empty_Vector);
            end loop;
         when Load_Value => Put_One (State, Activation, A, Code.Literal);
         when Load_String =>
            Put_One (State, Activation, A,
                     New_String (State, To_String (Code.Text)));
         when Move_First => Put_One (State, Activation, A, Scalar
           (Activation, B));
         when Read_Local =>
            Put_One (State, Activation, A, Read_Local (Activation.Scope,
              B));
         when Write_Local =>
            Write_Local (Activation.Scope, B, Scalar (Activation, A));
         when Declare_Local =>
            Declare_Local (State, Activation.Scope, B, Scalar
              (Activation, A));
         when Enter_Scope =>
            Activation.Scope := New_Environment (State, Activation.Scope);
            Activation.Scope_Depth := Activation.Scope_Depth + 1;
         when Leave_Scope =>
            Start_Unwind
              (Self, Activation, Scope_Exit,
               Depth => Activation.Scope_Depth - 1);
         when Goto_Label =>
            Start_Unwind
              (Self, Activation, Jump_Exit, Depth => A, PC => Code.Target,
               Live => Code.Inputs);
         when Register_Close =>
            declare
               Cell : constant Object_Access :=
                 Find_Cell (Activation.Scope, B);
               Item : constant Value := Cell.Cell_Value;
            begin
               if Truth (Item) and then
                 Metafield (State, Item, "__close").Kind = Nil_Kind
               then
                  Fail (State, "variable '" & To_String (Code.Text) &
                          "' got a non-closable value");
               end if;
               if Truth (Item) then
                  --  False/nil declarations are never enrolled for closing.
                  --  A later debug upvalue mutation cannot turn an inactive
                  --  declaration into a new close obligation.
                  Activation.Closers.Append
                    (Close_Entry'(Cell => Cell, Symbol => B,
                                  Depth => Activation.Scope_Depth,
                                  others => <>));
               end if;
            end;
         when New_Table => Put_One (State, Activation, A, New_Table
           (State));
         when Get_Item =>
            Packet.Append (Scalar (Activation, B));
            Packet.Append (Scalar (Activation, C));
            Schedule (Self, "@get", Packet, A);
         when Set_Item =>
            Packet.Append (Scalar (Activation, A));
            Packet.Append (Scalar (Activation, B));
            Packet.Append (Scalar (Activation, C));
            Schedule (Self, "@set", Packet, 0);
         when Set_Sequence =>
            Packet := Flatten (Activation, Code.Inputs, C /= 0);
            for Index in Packet.First_Index .. Packet.Last_Index loop
               Set (State, Scalar (Activation, A),
                    (Integer_Kind, Integer_Value (B + Index - 1)),
                    Packet (Index));
            end loop;
         when Unary =>
            Packet.Append (Scalar (Activation, B));
            Schedule (Self, "@unary", Packet, A, Code.Operator);
         when Binary =>
            Packet.Append (Scalar (Activation, B));
            Packet.Append (Scalar (Activation, C));
            Schedule (Self, "@binary", Packet, A, Code.Operator);
         when Jump => Activation.PC := Code.Target;
         when Jump_False | Jump_True | Jump_Nil =>
            Item := Scalar (Activation, A);
            if (Code.Op = Jump_Nil and then Item.Kind = Nil_Kind) or else
              (Code.Op = Jump_False and then not Truth (Item)) or else
              (Code.Op = Jump_True and then Truth (Item))
            then
               Activation.PC := Code.Target;
            end if;
         when Make_Closure =>
            Put_One (State, Activation, A,
                     New_Closure (State, Code.Nested, Activation.Scope));
         when Read_Varargs =>
            if Activation.Vararg_Table = null then
               Put_Packet (State, Activation, A, Activation.Varargs);
            else
               --  A named Lua 5.5 vararg table is live storage: changes
               --  to indexed values or n affect subsequent ... results.
               Left := (Table_Kind, Activation.Vararg_Table);
               Right := Get (Left, New_String (State, "n"));
               if Right.Kind /= Integer_Kind or else
                 Right.Integer_Data < 0
               then
                  Fail (State, "vararg table has no proper 'n'");
               end if;
               if Right.Integer_Data >
                 Integer_Value (State.Bounds.Table_Entries)
               then
                  Fail (State, "vararg result limit exceeded", True);
               end if;
               for Index in 1 .. Natural (Right.Integer_Data) loop
                  Packet.Append
                    (Get (Left, (Integer_Kind, Integer_Value (Index))));
               end loop;
               Put_Packet (State, Activation, A, Packet);
            end if;
         when Pick_Value =>
            Packet := Flatten (Activation, Code.Inputs);
            Put_One (State, Activation, A,
                     (if B <= Natural (Packet.Length) then Packet (B)
                      else Nil_Value));
         when Return_Values =>
            if Activation.Closers.Is_Empty then
               Complete (Self, Flatten (Activation, Code.Inputs));
            else
               Start_Unwind
                 (Self, Activation, Return_Exit, Flatten (Activation,
                   Code.Inputs));
            end if;
         when Call_Function | Tail_Call =>
            Dispatch (Self, Scalar (Activation, B),
                      Flatten (Activation, Code.Inputs), A,
                      Tail => Code.Op = Tail_Call,
                      Call_Name => Code.Text, Name_Kind => Code.Name_Kind);
         when Check_Global =>
            if Get (Scalar (Activation, A), Scalar (Activation, B)).Kind /=
              Nil_Kind
            then
               Fail (State, "global '" &
                     Image (State.Current.Memory, Scalar (Activation, B)) &
                       "' already defined");
            end if;
         when Check_Iterator =>
            Left := Scalar (Activation, A);
            if Truth (Left) then
               if Metafield (State, Left, "__close").Kind = Nil_Kind then
                  Fail (State, "non-closable iterator value");
               end if;
               declare
                  Cell : constant Object_Access := New_Environment
                    (State, null);
               begin
                  --  A hidden environment cell roots the iterator's fourth
                  --  result for the entire loop, not just one iteration.
                  Declare_Local (State, Cell, 1, Left);
                  Activation.Closers.Append
                    (Close_Entry'(Cell => Find_Cell (Cell, 1), Symbol => 0,
                                  Depth => Activation.Scope_Depth,
                                  others => <>));
               end;
            end if;
         when For_Initialize =>
            Left := Scalar (Activation, Code.D);
            Right := Scalar (Activation, Code.Inputs (2));
            L := Numeric (State, Left);
            R := Numeric (State, Scalar (Activation, Code.Inputs (1)));
            S := Numeric (State, Right);
            if Left.Kind = Integer_Kind and then Right.Kind = Integer_Kind
            then
               Control := L.Integer_Item;
               Stride := S.Integer_Item;
               if Stride = 0 then
                  Fail (State, "for step is zero");
               end if;
               Put_One (State, Activation, A, (Integer_Kind, Control));
               Put_One (State, Activation, C, (Integer_Kind, Stride));
               if R.Kind = Lua.Numbers.Integer_Number then
                  Bound := R.Integer_Item;
               else
                  Real_Bound := R.Real_Item;
                  --  Integer loops round a float bound toward the valid
                  --  side of the interval, saturating finite overflow.
                  --  NaN or an entirely unreachable bound marks an empty
                  --  loop with nil, without an unsafe signed conversion.
                  if Real_Bound /= Real_Bound or else
                    (Stride > 0 and then Real_Bound < -2.0 ** 63) or else
                    (Stride < 0 and then Real_Bound >= 2.0 ** 63)
                  then
                     Put_One (State, Activation, A, Nil_Value);
                     Bound := 0;
                  elsif Real_Bound >= 2.0 ** 63 then
                     Bound := Integer_Value'Last;
                  elsif Real_Bound <= -2.0 ** 63 then
                     Bound := Integer_Value'First;
                  else
                     Bound := Integer_Value
                       (if Stride > 0 then Real_Value'Floor (Real_Bound)
                        else Real_Value'Ceiling (Real_Bound));
                  end if;
               end if;
               Put_One (State, Activation, B, (Integer_Kind, Bound));
            else
               Real_Delta := Lua.Numbers.To_Real (S);
               if Real_Delta = 0.0 then
                  Fail (State, "for step is zero");
               end if;
               Put_One (State, Activation, A,
                        (Real_Kind, Lua.Numbers.To_Real (L)));
               Put_One (State, Activation, B,
                        (Real_Kind, Lua.Numbers.To_Real (R)));
               Put_One (State, Activation, C, (Real_Kind, Real_Delta));
            end if;
         when For_Test =>
            Left := Scalar (Activation, A);
            if Left.Kind = Nil_Kind then
               Activation.PC := Code.Target;
            elsif Left.Kind = Integer_Kind then
               Control := Left.Integer_Data;
               Bound := Scalar (Activation, B).Integer_Data;
               Stride := Scalar (Activation, C).Integer_Data;
               if (Stride > 0 and then Control > Bound) or else
                 (Stride < 0 and then Control < Bound)
               then
                  Activation.PC := Code.Target;
               end if;
            else
               Real_Control := Left.Real_Data;
               Real_Bound := Scalar (Activation, B).Real_Data;
               Real_Delta := Scalar (Activation, C).Real_Data;
               if not (if Real_Delta > 0.0 then Real_Control <= Real_Bound
                       else Real_Control >= Real_Bound)
               then
                  Activation.PC := Code.Target;
               end if;
            end if;
         when For_Advance =>
            Left := Scalar (Activation, A);
            if Left.Kind = Integer_Kind then
               Control := Left.Integer_Data;
               Stride := Scalar (Activation, C).Integer_Data;
               --  The loop counter must stop before signed wraparound,
               --  Ordinary Lua integer arithmetic intentionally wraps;
               --  a numeric-for control variable must instead terminate.
               if (Stride > 0 and then
                 Control > Integer_Value'Last - Stride)
                 or else (Stride < 0 and then
                   Control < Integer_Value'First - Stride)
               then
                  Activation.PC := Code.D;
                  return;
               end if;
               Put_One (State, Activation, A, (Integer_Kind, Control +
                 Stride));
            else
               Put_One (State, Activation, A,
                 (Real_Kind,
                  Left.Real_Data + Scalar (Activation, C).Real_Data));
            end if;
            Activation.PC := Code.Target;
      end case;
   end Execute_Private_Instruction;

   procedure Execute_Instruction (Self : Driver) is
      State : World renames Self.Universe.all;
      Activation : constant Frame_Access :=
        State.Current.Stack.Last_Element;
   begin
      if Activation.Code.Canonical_Node = null then
         Execute_Private_Instruction (Self);
         return;
      end if;
      declare
         Next : constant Canonical.Action :=
           Canonical.Step (State, Activation);
      begin
         --  Canonical.Step returns before any Lua/native callable runs. Its
         --  frame owns every requested argument and outgoing result while
         --  this bridge publishes the next scheduler activation.
         case Next.Kind is
            when Canonical.Advanced => null;
            when Canonical.Invoke_Helper =>
               Schedule (Self, To_String (Next.Helper), Next.Arguments,
                         Next.Destination, Next.Operator);
            when Canonical.Invoke_Function =>
               Dispatch (Self, Next.Function_Value, Next.Arguments,
                         Next.Destination,
                         Call_Base => Next.Call_Base,
                         Has_Call_Window => Next.Has_Call_Window);
               Activation.Native_Arguments.Clear;
               Activation.Native_Captures.Clear;
            when Canonical.Tail_Invoke =>
               if not Activation.Closers.Is_Empty then
                  --  The compiler never emits TAILCALL while a TBC slot is
                  --  live. Reject an imported contradictory sequence rather
                  --  than retire that slot without invoking its handler.
                  Fail (State, "canonical tail call has pending close values");
               end if;
               Dispatch (Self, Next.Function_Value, Next.Arguments,
                         Next.Destination, Tail => True,
                         Call_Base => Next.Call_Base,
                         Has_Call_Window => Next.Has_Call_Window);
            when Canonical.Return_Results =>
               if Activation.Closers.Is_Empty then
                  Complete (Self, Next.Arguments);
               else
                  Start_Unwind
                    (Self, Activation, Return_Exit, Next.Arguments);
               end if;
            when Canonical.Close_From_Register =>
               Start_Unwind (Self, Activation, Scope_Exit,
                             Depth => Next.Close_From);
         end case;
      end;
   end Execute_Instruction;

   procedure Scheduler_Step (Self : in out Driver) is
      State : World renames Self.Universe.all;
   begin
      --  All cross-context movement occurs here. A suspended native
      --  activation owns its resume destination; no Ada frame survives a
      --  yield and no nested scheduler restarts an execution budget.
      if State.Current.Transfer.Kind in Resume_Requested |
        Close_Requested
      then
         declare
            Caller : constant Context_Access := State.Current;
            Request : constant Control_Transfer := Caller.Transfer;
            Target : constant Context_Access :=
              State.Contexts (Request.Target);
            Fresh : constant Boolean := Target.Status = New_Context;
         begin
            Pin (State, Request.Results);
            Caller.Transfer := (others => <>);
            if State.Native_Depth + Target.Native_Depth >=
              Lua.Runtime_Configuration.Maximum_C_Calls
            then
               Fail (State, "C stack overflow");
            end if;
            Caller.Status := Normal_Context;
            Target.Resumer := Caller;
            State.Current := Target;
            State.Native_Depth := State.Native_Depth +
              Target.Native_Depth;
            Target.Status := Running_Context;
            if Request.Kind = Close_Requested then
               Target.Phase := Closing;
               Target.Entry_Function := Nil_Value;
               Schedule (Self, "@close.thread", Values.Empty_Vector, 0);
            elsif Fresh then
               Dispatch (Self, Target.Entry_Function, Request.Results, 0);
               Target.Entry_Function := Nil_Value;
            else
               Target.Stack.Last_Element.Native_Results :=
                 Request.Results;
            end if;
         end;
      elsif State.Current.Transfer.Kind in Completed | Yielded |
        Lua_Raised
      then
         declare
            Child : constant Context_Access := State.Current;
            Transfer : constant Control_Transfer := Child.Transfer;
            Parent : constant Context_Access := Child.Resumer;
            Packet : Values.Vector := Owned_Values (State);
         begin
            Pin (State, Transfer.Results);
            if Parent /= null then
               Child.Transfer := (others => <>);
            end if;
            Child.Status :=
              (if Transfer.Kind = Yielded then Suspended_Context
               else Dead_Context);
            if Transfer.Kind /= Yielded then
               --  Closing is an execution phase, not a permanent dead
               --  thread attribute observed by later boundary queries.
               Child.Phase := Executing;
            end if;
            if Parent = null then
               Self.Done := True;
               return;
            end if;
            State.Native_Depth := State.Native_Depth -
              Child.Native_Depth;
            Child.Resumer := null;
            State.Current := Parent;
            Parent.Status := Running_Context;
            Packet.Append
              (Value'(Boolean_Kind, Transfer.Kind /= Lua_Raised));
            for Item of Transfer.Results loop
               Packet.Append (Item);
            end loop;
            Parent.Stack.Last_Element.Native_Results := Packet;
         end;
      else
         if State.GC_Running and then
           Natural (State.Heap.Length) >= State.Next_GC
         then
            Collect (State);
         end if;
         if State.Finalizers_Requested and then
           not State.Finalizer_Active and then
           State.Current.Stack.Last_Element.Native_Name /= "@gc.finalize"
           and then Try_Push_Finalizers (Self, Silent => True)
         then
            return;
         end if;
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
         begin
            if State.Current.Stack.Last_Element.Native_Tail_State =
              Ready_Native_Tail
            then
               Complete
                 (Self, State.Current.Stack.Last_Element.Native_Results);
            elsif Before_Step (Self) then
               null;
            elsif State.Current.Stack.Last_Element.Is_Native then
               Native_Step (Self);
            else
               State.Current.Stack.Last_Element.Hook_PC := 0;
               State.Current.Stack.Last_Element.Line_Hook_Checked :=
                 False;
               State.Current.Stack.Last_Element.Last_Executed_PC :=
                 State.Current.Stack.Last_Element.PC;
               Execute_Instruction (Self);
            end if;
         exception
            when Error : Language_Error |
              Lua.Storage.Allocation_Error | Program_Error =>
               if Lua.Storage.Refusal_Pending (State.Memory) or else
                 Ada.Exceptions.Exception_Identity (Error) =
                   Lua.Storage.Allocation_Error'Identity
               then
                  Record_Memory_Error (State);
               elsif Ada.Exceptions.Exception_Identity (Error) =
                 Program_Error'Identity
               then
                  raise;
               end if;
               begin
                  Recover (Self);
               exception
                  when Language_Error =>
                     if State.Current.Failure_Class = Host_Abort or else
                       State.Current = Self.Root_Context
                     then
                        raise;
                     end if;
                     if not State.Current.Has_Failure_Value then
                        State.Current.Failure := New_String
                          (State, To_String
                            (State.Current.Failure_Text));
                        State.Current.Has_Failure_Value := True;
                     end if;
                     State.Current.Transfer :=
                       (Kind => Lua_Raised,
                        Results => One_Value
                          (State.Current.Memory, State.Current.Failure, 1),
                        Target => 0);
               end;
         end;
      end if;
   exception
      when Error : Language_Error | Lua.Storage.Allocation_Error |
        Program_Error =>
         if Lua.Storage.Refusal_Pending (State.Memory) or else
           Ada.Exceptions.Exception_Identity (Error) =
             Lua.Storage.Allocation_Error'Identity
         then
            Record_Memory_Error (State);
         elsif Ada.Exceptions.Exception_Identity (Error) =
           Program_Error'Identity
         then
            raise;
         end if;
         begin
            Recover (Self);
         exception
            when Language_Error =>
               if State.Current.Failure_Class = Host_Abort or else
                 State.Current = Self.Root_Context
               then
                  raise;
               end if;
               if not State.Current.Has_Failure_Value then
                  State.Current.Failure := New_String
                    (State, To_String (State.Current.Failure_Text));
                  State.Current.Has_Failure_Value := True;
               end if;
               State.Current.Transfer :=
                 (Kind => Lua_Raised,
                  Results => One_Value
                    (State.Current.Memory, State.Current.Failure, 1),
                  Target => 0);
         end;
   end Scheduler_Step;

   procedure Abandon (Self : Driver) is
      State : World renames Self.Universe.all;
   begin
      --  A host abort invalidates this active resume chain as a unit.
      --  Abandoned continuations cannot be resumed to evade the quota.
      if State.Current /= Self.Root_Context then
         Self.Root_Context.Failure := State.Current.Failure;
         Self.Root_Context.Has_Failure_Value :=
           State.Current.Has_Failure_Value;
         Self.Root_Context.Failure_Text := State.Current.Failure_Text;
         Self.Root_Context.Failure_Class := State.Current.Failure_Class;
         Self.Root_Context.Failure_At := State.Current.Failure_At;
      end if;
      while State.Current /= Self.Root_Context loop
         declare
            Child : constant Context_Access := State.Current;
            Parent : constant Context_Access := Child.Resumer;
         begin
            Clear_Frames (State);
            Child.Status := Dead_Context;
            Child.Phase := Executing;
            Child.Resumer := null;
            State.Current := Parent;
         end;
      end loop;
   end Abandon;

   procedure Prepare
     (Self : in out Driver; Universe : not null World_View)
   is
   begin
      if Self.Universe /= null or else Universe.Current = null or else
        not Universe.Current.Stack.Is_Empty
      then
         raise Program_Error with "invalid VM driver start";
      end if;
      Self.Universe := Universe;
      Self.Root_Context := Universe.Current;
      Self.Done := False;
      Self.Failed := False;
   end Prepare;

   procedure Start_Borrowed
     (Self : in out Driver; Universe : not null World_View;
      Code : Prototype_Access; Function_Value : Value;
      Arguments : Values.Vector)
   is
      State : World renames Universe.all;
      Callee : Value := Function_Value;
      Prepared : Boolean := False;
   begin
      Prepare (Self, Universe);
      Prepared := True;
      Begin_Operation (State);
      State.Current.Transfer := (others => <>);
      if Code /= null then
         Pin (State, Code);
         Callee := New_Closure (State, Code, null);
      end if;
      --  Dispatch publishes the call into owned frames. The operation epoch
      --  protects construction and pins existing arguments before any frame
      --  replacement or allocator-triggered emergency collection can occur.
      Dispatch (Self, Callee, Arguments, 0);
      End_Operation (State);
   exception
      when others =>
         if Prepared then
            End_Operation (State);
            Self.Failed := True;
            Abandon (Self);
         end if;
         raise;
   end Start_Borrowed;

   procedure Start
     (Self : in out Driver; State : not null World_Access;
      Code : Prototype_Access)
   is
   begin
      Start_Borrowed
        (Self, World_View (State), Code, Nil_Value,
         State.Current.Arguments);
   end Start;

   procedure Start
     (Self : in out Driver; State : not null World_Access;
      Function_Value : Value; Arguments : Values.Vector)
   is
   begin
      Start_Borrowed
        (Self, World_View (State), null, Function_Value, Arguments);
   end Start;

   procedure Start_Foreign
     (Self : in out Driver; State : not null World_Access;
      Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False)
   is
      Packet : Values.Vector := Owned_Values (State.all);
      Prepared : Boolean := False;
   begin
      Prepare (Self, World_View (State));
      Prepared := True;
      Begin_Operation (State.all);
      State.Current.Transfer := (others => <>);
      Pin (State.all, Callee);
      Pin (State.all, Arguments);
      Pin (State.all, Message_Handler);
      Packet.Append (Callee);
      for Argument of Arguments loop
         Packet.Append (Argument);
      end loop;
      --  This holder exists before the target is dispatched, so even a call
      --  to a non-callable value has a real protected handler boundary. No
      --  synthetic heap closure or second executor is needed for C entry.
      Schedule (Self, "@foreign.entry", Packet, 0);
      State.Current.Stack.Last_Element.Native_Index := Call_Base;
      State.Current.Stack.Last_Element.Native_Aux :=
        Boolean'Pos (Has_Call_Window);
      State.Current.Stack.Last_Element.Error_Packet.Reserve_Capacity (2);
      State.Current.Stack.Last_Element.Protection := 1;
      State.Current.Stack.Last_Element.Message_Handler := Message_Handler;
      End_Operation (State.all);
   exception
      when others =>
         if Prepared then
            End_Operation (State.all);
            Self.Failed := True;
            Abandon (Self);
         end if;
         raise;
   end Start_Foreign;

   procedure Deliver_Owned
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : in out Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False)
   is
      State : World renames Self.Universe.all;
      procedure Move_Slot (Slot : in out Values.Vector);
      procedure Move_Slot (Slot : in out Values.Vector) is
      begin
         Values.Move (Slot, Packet);
      end Move_Slot;
   begin
      --  The source holder remains on the activation stack throughout this
      --  operation. No temporary pin vector or controlled packet copy is
      --  needed, including while a canonical result write can still fail.
      if Activation = null then
         Values.Move (State.Current.Transfer.Results, Packet);
         State.Current.Transfer.Kind := Completed;
         State.Current.Transfer.Target := 0;
      elsif Activation.Native_Tail_State = Waiting_Native_Tail then
         Values.Move (Activation.Native_Results, Packet);
         Activation.Native_Tail_State := Ready_Native_Tail;
      elsif Activation.Is_Native then
         declare
            Protected_Error : constant Boolean :=
              Activation.Native_Name = "@foreign.boundary" and then
              not Packet.Is_Empty and then Packet.First_Element.Kind =
                Boolean_Kind and then not Packet.First_Element.Boolean_Data;
         begin
            Values.Move (Activation.Native_Results, Packet);
            Activation.Result_Failure_Class := Failure;
            Activation.Result_Handler_Called := Handler_Called;
            if Protected_Error then
               Activation.Native_Aux :=
                 (if Failure = Memory_Failure then 4
                  elsif Failure = Handling_Failure then 5 else 2);
            end if;
         end;
      elsif Activation.Code.Canonical_Node /= null then
         --  Scalars/cells become authoritative before the source packet is
         --  cleared. A refused open-result growth leaves that source intact
         --  so the still-live protected holder can publish its reserved error.
         Canonical.Deliver (State, Activation, Packet);
         Packet.Clear;
      elsif Destination /= 0 then
         declare
            Old_Extra : constant Natural := Natural'Max
              (1, Natural (Activation.Slots (Destination).Length)) - 1;
            New_Extra : constant Natural :=
              Natural'Max (1, Natural (Packet.Length)) - 1;
            Delta_Slots : constant Integer := New_Extra - Old_Extra;
         begin
            --  Preserve the private backend's existing semantic accounting.
            --  Only the ownership transfer differs from Put_Packet; the
            --  outer register packet array was reserved when its frame began.
            if Delta_Slots > 0 and then Delta_Slots >
              Lua.Runtime_Configuration.Maximum_Stack - Natural'Min
                (Lua.Runtime_Configuration.Maximum_Stack,
                 State.Current.Stack_Slots)
            then
               Fail (State, "stack overflow");
            end if;
            Activation.Slots.Update_Element
              (Destination, Move_Slot'Access);
            Activation.Slot_Cost := Activation.Slot_Cost + Delta_Slots;
            State.Current.Stack_Slots :=
              State.Current.Stack_Slots + Delta_Slots;
         end;
      else
         Packet.Clear;
      end if;
   end Deliver_Owned;

   procedure Take_Results (Self : Driver; Packet : in out Values.Vector) is
   begin
      if Self.Universe = null or else not Self.Done then
         raise Program_Error with "unfinished VM driver results";
      end if;
      Values.Move (Packet, Self.Root_Context.Transfer.Results);
   end Take_Results;

   function New_Driver (State : in out World) return Driver_Access is
   begin
      return new (Lua.Storage.Handle (State.Memory)) Driver;
   end New_Driver;

   procedure Free_Driver (Self : in out Driver_Access) is
      procedure Destroy is new Ada.Unchecked_Deallocation
        (Driver, Driver_Access);
   begin
      if Self /= null and then Self.Universe /= null then
         raise Program_Error with "foreign driver still owns a drive";
      end if;
      Destroy (Self);
   end Free_Driver;

   function Needs_Foreign_Call (Self : Driver) return Boolean is
     (Self.Universe /= null and then not Self.Done and then not Self.Failed
      and then not Self.Universe.Current.Stack.Is_Empty and then
      Self.Universe.Current.Stack.Last_Element.Is_Native and then
      Self.Universe.Current.Stack.Last_Element.Native_Name =
        "foreign.callback" and then
      Self.Universe.Current.Stack.Last_Element.Native_Stage = 1);

   function Foreign_Handler (Self : Driver) return System.Address is
   begin
      if not Needs_Foreign_Call (Self) then
         raise Program_Error with "no pending foreign callback";
      end if;
      return Self.Universe.Current.Stack.Last_Element.Foreign_Handler;
   end Foreign_Handler;

   function Foreign_Token (Self : Driver) return Callback_Identity is
      Activation : Frame_Access;
   begin
      if not Needs_Foreign_Call (Self) then
         raise Program_Error with "no pending foreign callback identity";
      end if;
      Activation := Self.Universe.Current.Stack.Last_Element;
      return (Activation => Activation.all'Address,
              Serial => Activation.Foreign_Ticket);
   end Foreign_Token;

   function Foreign_Context (Self : Driver) return Context_Access is
   begin
      if not Needs_Foreign_Call (Self) then
         raise Program_Error with "no pending foreign context";
      end if;
      return Self.Universe.Current;
   end Foreign_Context;

   procedure Complete_Foreign_Call
     (Self : Driver; Result_Count : Natural; Error_Status : Natural := 0;
      Handler_Called : Boolean := False;
      Token : Callback_Identity)
   is
      State : World renames Self.Universe.all;
      Context : constant Context_Access := State.Current;
      Activation : Frame_Access;
      Count : Natural;
   begin
      if not Needs_Foreign_Call (Self) or else
        Error_Status not in 0 | 2 | 4 | 5
      then
         raise Program_Error with "invalid foreign callback completion";
      end if;
      Activation := Context.Stack.Last_Element;
      --  A nested C pump can return through several live guards. Each one
      --  acknowledges its own activation, never whichever frame happens to
      --  be deepest after a child transfer. Serial also rejects cache reuse.
      if Token.Activation /= Activation.all'Address or else
        Token.Serial /= Activation.Foreign_Ticket
      then
         raise Program_Error with "stale foreign callback identity";
      end if;
      Count := Context.Foreign_Top - Context.Foreign_Base;
      if (Error_Status = 0 and then Result_Count > Count) or else
        (Error_Status /= 0 and then Count = 0)
      then
         Fail (State, "invalid number of C callback results");
      end if;
      Count := (if Error_Status = 0 then Result_Count else 1);
      if Error_Status /= 0 then
         --  Callback failure has one existing C-stack object. Do not allocate
         --  a temporary packet while a permanent provider refusal is active.
         --  The preserved window and explicit context error are both roots.
         Context.Failure := Stacks.Read (Context, Context.Foreign_Top);
         Context.Has_Failure_Value := True;
         Context.Failure_Text := To_Unbounded_String
           (Image (Context.Memory, Context.Failure));
         Context.Failure_Class :=
           (if Error_Status = 4 then Memory_Failure
            elsif Error_Status = 5 then Handling_Failure
            else Language_Failure);
         Context.Failure_Handled := Handler_Called;
         Activation.Native_Stage := 3;
         return;
      end if;
      Activation.Native_Results.Clear;
      Activation.Native_Results.Reserve_Capacity
        (Ada.Containers.Count_Type (Count));
      for Index in Context.Foreign_Top - Count + 1 .. Context.Foreign_Top
      loop
         Activation.Native_Results.Append (Stacks.Read (Context, Index));
      end loop;
      --  The live activation owns every result before the C window is
      --  truncated. No extra temporary pin or controlled copy is required.
      Context.Foreign_Top := Activation.Saved_Foreign_Top;
      Context.Foreign_Base := Activation.Foreign_Previous_Base;
      Context.Foreign_Activation := Activation.Foreign_Previous_Frame;
      Activation.Foreign_Entered := False;
      Context.Failure := Nil_Value;
      Context.Has_Failure_Value := False;
      Context.Failure_Class := No_Failure;
      Context.Failure_Handled := False;
      Activation.Native_Stage := 2;
   end Complete_Foreign_Call;

   procedure Start_Foreign_Boundary
     (Self : Driver; Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Original_Depth : constant Natural :=
        Natural (State.Current.Stack.Length);
   begin
      if not Needs_Foreign_Call (Self) and then
        (State.Warning_Head = null or else
         State.Warning_Head.Warning_Phase /= Warning_Callback_Active)
      then
         raise Program_Error with "foreign boundary has no C caller";
      end if;
      Pin (State, Callee);
      Pin (State, Arguments);
      Pin (State, Message_Handler);
      Schedule (Self, "@foreign.boundary", Values.Empty_Vector, 0);
      State.Current.Stack.Last_Element.Error_Packet.Reserve_Capacity (2);
      --  lua_call without a continuation cannot suspend its C activation.
      --  A future continuation-aware boundary must make that choice explicit,
      --  rather than treating every scheduler continuation as yieldable.
      State.Current.Stack.Last_Element.Blocks_Yield := True;
      State.Current.Stack.Last_Element.Protection := 1;
      State.Current.Stack.Last_Element.Message_Handler := Message_Handler;
      State.Current.Stack.Last_Element.Retain_On_Failure := True;
      State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      begin
         Dispatch (Self, Callee, Arguments, 0,
                   Call_Base => Call_Base,
                   Has_Call_Window => Has_Call_Window);
      exception
         when Language_Error => Recover (Self);
         when Lua.Storage.Allocation_Error =>
            Record_Memory_Error (State);
            Recover (Self);
      end;
   exception
      when others =>
         --  A setup failure precedes execution of the protected child. Remove
         --  only this boundary's partial activations; the outer C callback
         --  and its live C guard still own the interrupted driver.
         while Natural (State.Current.Stack.Length) > Original_Depth loop
            declare
               Item : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Item);
            end;
         end loop;
         raise;
   end Start_Foreign_Boundary;

   function Has_Foreign_Result (Self : Driver) return Boolean is
     (Self.Universe /= null and then not Self.Done and then not Self.Failed
      and then not Self.Universe.Current.Stack.Is_Empty and then
      Self.Universe.Current.Stack.Last_Element.Is_Native and then
      Self.Universe.Current.Stack.Last_Element.Native_Name =
        "@foreign.boundary" and then
      Self.Universe.Current.Stack.Last_Element.Native_Stage = 1);

   procedure Take_Foreign_Result
     (Self : Driver; Packet : in out Values.Vector; Error_Status : out Natural;
      Handler_Called : out Boolean)
   is
      State : World renames Self.Universe.all;
      Activation : Frame_Access;
   begin
      if not Has_Foreign_Result (Self) then
         raise Program_Error with "no completed foreign boundary";
      end if;
      Activation := State.Current.Stack.Last_Element;
      if Activation.Native_Results.Is_Empty or else
        Activation.Native_Results.First_Element.Kind /= Boolean_Kind
      then
         raise Program_Error with "foreign boundary lost protection packet";
      end if;
      Error_Status :=
        (if Activation.Native_Results.First_Element.Boolean_Data then 0
         else Natural'Max (2, Activation.Native_Aux));
      Handler_Called := Activation.Result_Handler_Called;
      Values.Move (Packet, Activation.Native_Results);
      Packet.Delete_First;
      State.Current.Stack.Delete_Last;
      Release_Frame (State, Activation);
   end Take_Foreign_Result;

   function Current_Message_Handler (Self : Driver) return Value is
     (Active_Handler (Self));

   procedure Step (Self : in out Driver) is
      Validated : Boolean := False;
   begin
      if Self.Universe = null or else Self.Done or else Self.Failed then
         raise Program_Error with "inactive VM driver step";
      end if;
      if Needs_Foreign_Call (Self) or else Has_Foreign_Result (Self) then
         raise Program_Error with "foreign drive requires its C-owned pump";
      end if;
      Validated := True;
      Begin_Operation (Self.Universe.all);
      --  Exactly one transfer or instruction/native/hook phase runs here.
      --  All continuations are frame data; returning drops every helper's
      --  Ada activation while retaining the same world, roots and budget.
      Scheduler_Step (Self);
      End_Operation (Self.Universe.all);
   exception
      when others =>
         if Validated then
            End_Operation (Self.Universe.all);
            Self.Failed := True;
            Abandon (Self);
         end if;
         raise;
   end Step;

   function Is_Complete (Self : Driver) return Boolean is (Self.Done);

   function Outcome (Self : Driver) return Transfer_Kind is
   begin
      if Self.Universe = null or else not Self.Done then
         raise Program_Error with "unfinished VM driver outcome";
      end if;
      return Self.Root_Context.Transfer.Kind;
   end Outcome;

   function Results (Self : Driver) return Values.Vector is
   begin
      if Self.Universe = null or else not Self.Done then
         raise Program_Error with "unfinished VM driver results";
      end if;
      return Self.Root_Context.Transfer.Results;
   end Results;

   procedure Finish (Self : in out Driver) is
   begin
      if Self.Universe /= null and then not Self.Done and then
        not Self.Failed
      then
         raise Program_Error with "unfinished VM driver borrow";
      end if;
      if Self.Done and then Self.Root_Context /= null then
         Self.Root_Context.Transfer := (others => <>);
      end if;
      Self.Universe := null;
      Self.Root_Context := null;
      Self.Done := False;
      Self.Failed := False;
   end Finish;

   procedure Run (State : in out World; Code : Prototype_Access) is
      Self : Driver;
   begin
      --  The legacy synchronous entry borrows an in-out formal, whose stable
      --  address belongs to its caller. This isolated standard Ada address
      --  view cannot escape: Finish clears the local driver's access before
      --  Run returns or propagates failure. Foreign callers instead pass an
      --  actual owned World_Access through Start, without this adaptation.
      Start_Borrowed
        (Self, World_View (World_Addresses.To_Pointer (State'Address)),
         Code, Nil_Value, State.Current.Arguments);
      while not Is_Complete (Self) loop
         if Needs_Foreign_Call (Self) or else Warnings.Pending (State) then
            --  The helper installs its C guard above this waiting host
            --  activation. No internal Ada step spans the foreign callback;
            --  nested C API work continues on this same explicit driver.
            Lua.Engine.Foreign.Invoke_Borrowed (State, Self);
         else
            Step (Self);
         end if;
      end loop;
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Run;
end Lua.Engine.Machine;
