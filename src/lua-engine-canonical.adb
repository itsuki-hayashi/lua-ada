with Ada.Containers;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces;
with Lua.Integers;
with Lua.Opcodes;
with Lua.Engine.Tables;
with Lua.Engine.Machine;
with Lua.Engine.Stacks;

package body Lua.Engine.Canonical is
   use type Lua.Prototypes.Constant_Kind;
   use Lua.Opcodes;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Integer_8;
   use type Interfaces.Unsigned_64;
   use type Lua.Prototypes.Prototype_Access;
   use type Lua.Prototypes.String_Id;
   use type Lua.Storage.Owner_Access;
   use type Lua.Numbers.Number_Kind;
   use type Integer_Value;
   use type Real_Value;

   function Integer_Bits is new Ada.Unchecked_Conversion
     (Integer_Value, Interfaces.Unsigned_64);
   function Signed_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Integer_Value);
   procedure Release_Bundle is new Ada.Unchecked_Deallocation
     (Canonical_Program, Canonical_Program_Access);

   function Part (State : in out World; Code : Word; Field_Id : Field)
                  return Integer;
   function Constant_At
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Value;
   function Capture_Cell
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Object_Access;
   function Upvalue_Cell
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Object_Access;
   function Register_List
     (State : in out World; Activation : Frame_Access;
      First, Count : Natural) return Values.Vector;
   Unknown_Source : aliased constant String := "=?";

   function Source_Bytes (Code : Prototype_Access) return Byte_String is
      Result : Byte_String;
      procedure Borrow (Text : String);
      procedure Borrow (Text : String) is
      begin
         Result := (Text'Address, Text'Length);
      end Borrow;
   begin
      if Code.Canonical_Node.Source = Lua.Prototypes.No_String then
         return (Unknown_Source'Address, Unknown_Source'Length);
      end if;
      --  Query borrows the model's managed buffer, not a copied Ada String.
      --  Adopted graphs are immutable; the rooted wrapper owns its lifetime.
      Lua.Prototypes.Query_String
        (Code.Canonical_Owner.Model, Code.Canonical_Node.Source,
         Borrow'Access);
      return Result;
   end Source_Bytes;

   function Local_Name
     (State : in out World; Code : Prototype_Access; Index : Positive;
      PC : Natural) return Value
   is
      Remaining : Natural := Index;
      Result : Value;
      procedure Publish (Text : String);
      procedure Publish (Text : String) is
      begin
         Result := New_String (State, Text);
      end Publish;
   begin
      --  Canonical local records are declaration ordered. An active local's
      --  ordinal is its stack slot + 1; compile-time constants have no slot
      --  and no live-local record. End_PC is exclusive, following
      --  luaF_getlocalname.
      for Item of Code.Canonical_Node.Locals loop
         if Item.Start_PC <= PC and then PC < Item.End_PC then
            Remaining := Remaining - 1;
            if Remaining = 0 then
               if Item.Name = Lua.Prototypes.No_String then
                  return New_String (State, "(no name)");
               end if;
               Lua.Prototypes.Query_String
                 (Code.Canonical_Owner.Model, Item.Name, Publish'Access);
               return Result;
            end if;
         end if;
      end loop;
      return Nil_Value;
   end Local_Name;

   function Upvalue_Name
     (State : in out World; Code : Prototype_Access; Index : Positive)
      return Value
   is
      Result : Value;
      Id : Lua.Prototypes.String_Id;
      procedure Publish (Text : String);
      procedure Publish (Text : String) is
      begin
         Result := New_String (State, Text);
      end Publish;
   begin
      if Index > Code.Canonical_Node.Upvalues.Last_Index then
         Fail (State, "canonical upvalue name out of range");
      end if;
      Id := Code.Canonical_Node.Upvalues (Index).Name;
      if Id = Lua.Prototypes.No_String then
         return New_String (State, "(no name)");
      end if;
      Lua.Prototypes.Query_String
        (Code.Canonical_Owner.Model, Id, Publish'Access);
      return Result;
   end Upvalue_Name;

   procedure Store_Results
     (State : in out World; Activation : Frame_Access;
      Base : Natural; Wanted : Integer; Results : Values.Vector);
   function Number
     (State : in out World; Item : Value; Role : String)
      return Lua.Numbers.Number;
   procedure Prepare_For
     (State : in out World; Activation : Frame_Access;
      Base : Natural; Skip : out Boolean);

   function Part (State : in out World; Code : Word; Field_Id : Field)
                  return Integer
   is
      Result : constant Operand_Result := Get (Code, Field_Id);
   begin
      if Result.Status /= Success then
         Fail (State, "invalid canonical instruction operand");
      end if;
      return Result.Value;
   end Part;

   function Absolute_Register
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Positive;
   function Absolute_Register
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Positive is
   begin
      if not Activation.Has_Stack_Window or else
        Index >= Activation.Stack_Window_Length
      then
         Fail (State, "canonical register out of range");
      end if;
      return Activation.Stack_Base + Index + 1;
   end Absolute_Register;

   function Read_Register
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Value is
   begin
      return Stacks.Read
        (State, Activation.Context,
         Absolute_Register (State, Activation, Index));
   end Read_Register;

   procedure Write_Register
     (State : in out World; Activation : Frame_Access; Index : Natural;
      Item : Value) is
   begin
      Stacks.Write
        (State, Activation.Context,
         Absolute_Register (State, Activation, Index), Item);
   end Write_Register;

   function Constant_At
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Value
   is
   begin
      if Index >= Natural (Activation.Code.Canonical_Constants.Length) then
         Fail (State, "canonical constant out of range");
      end if;
      return Activation.Code.Canonical_Constants (Index + 1);
   end Constant_At;

   function Capture_Cell
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Object_Access is
   begin
      --  The arena can move; its index and independently owned cell cannot.
      --  Closing detaches that association before another lexical lifetime
      --  reuses the slot, so earlier closures keep their original binding.
      return Stacks.Capture
        (State, Activation.Context,
         Absolute_Register (State, Activation, Index));
   end Capture_Cell;

   function Upvalue_Cell
     (State : in out World; Activation : Frame_Access; Index : Natural)
      return Object_Access
   is
   begin
      if Index >= Natural (Activation.Callee.Reference.Upvalues.Length) then
         Fail (State, "canonical upvalue out of range");
      end if;
      return Activation.Callee.Reference.Upvalues (Index + 1);
   end Upvalue_Cell;

   procedure Close_Cells (Activation : Frame_Access; From : Natural) is
   begin
      if Activation.Has_Stack_Window and then
        From < Activation.Stack_Window_Length
      then
         --  Detach only this departing window. Ordinary calls overlap their
         --  caller's dead temporary tail; scope/return cleanup runs after
         --  child windows retire, never while a child owns these cells.
         Stacks.Detach
           (Activation.Context, Activation.Stack_Base + From + 1,
            Activation.Stack_Base + Activation.Stack_Window_Length);
      end if;
   end Close_Cells;

   procedure Prepare_Close
     (State : in out World; Activation : Frame_Access; From : Natural)
   is
   begin
      --  C closes open upvalues before invoking __close. Freeze the live
      --  stack slot now: a handler mutating an already closed upvalue must
      --  not replace the object passed to a later close handler.
      for Index in Activation.Closers.First_Index ..
        Activation.Closers.Last_Index
      loop
         declare
            Closing_Entry : Close_Entry := Activation.Closers (Index);
         begin
            if Closing_Entry.Depth > From and then
              not Closing_Entry.Frozen
            then
               Closing_Entry.Frozen_Value := Read_Register
                 (State, Activation, Closing_Entry.Symbol - 1);
               Closing_Entry.Frozen := True;
               Activation.Closers.Replace_Element (Index, Closing_Entry);
            end if;
         end;
      end loop;
      Close_Cells (Activation, From);
   end Prepare_Close;

   function Register_List
     (State : in out World; Activation : Frame_Access;
      First, Count : Natural) return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
   begin
      if First > Activation.Stack_Window_Length or else
        Count > Activation.Stack_Window_Length - First
      then
         Fail (State, "canonical register range out of bounds");
      end if;
      for Offset in 1 .. Count loop
         Result.Append (Read_Register (State, Activation, First + Offset - 1));
      end loop;
      return Result;
   end Register_List;

   procedure Store_Results
     (State : in out World; Activation : Frame_Access;
      Base : Natural; Wanted : Integer; Results : Values.Vector)
   is
      Count : constant Natural :=
        (if Wanted < 0 then Natural (Results.Length) else Wanted);
      New_Length : Natural;
   begin
      --  Fixed results restore the prototype reservation. Open results may
      --  extend it, but the real overlapping arena is charged by absolute
      --  stack top rather than by adding another per-frame register vector.
      if Count > Natural'Last - Base then
         Fail (State, "stack overflow");
      end if;
      New_Length := Natural'Max
        (Natural (Activation.Code.Canonical_Node.Max_Stack), Base + Count);
      Lua.Engine.Machine.Resize_Stack_Window
        (State, Activation, New_Length);
      for Offset in 1 .. Count loop
         Write_Register (State, Activation, Base + Offset - 1,
           (if Offset <= Natural (Results.Length) then Results (Offset)
            else Nil_Value));
      end loop;
      if Wanted < 0 then
         Activation.Canonical_Top := Base + Count;
         Activation.Canonical_GC_Top := Activation.Canonical_Top;
      else
         Activation.Canonical_GC_Top :=
           Natural (Activation.Code.Canonical_Node.Max_Stack);
      end if;
      if Activation.Context.Stack_Window = Activation then
         Activation.Context.Foreign_Top :=
           (if Wanted < 0 then
               Activation.Stack_Base + Activation.Canonical_Top else
               Activation.Context.Stack_Used);
      end if;
   end Store_Results;

   procedure Initialize_Frame
     (State : in out World; Activation : Frame_Access;
      Arguments : Values.Vector)
   is
      Code : constant Lua.Prototypes.Prototype_Access :=
        Activation.Code.Canonical_Node;
      Fixed : constant Natural := Natural (Code.Parameters);
      Actual : constant Natural := Natural'Max
        (Fixed, Natural (Arguments.Length));
      Is_Vararg : constant Boolean := (Code.Flags and 3) /= 0;
   begin
      --  Machine publishes the frame/base first. Incoming packets still root
      --  their values during this initial migration; reserve can collect or
      --  fail before any future window becomes visible to the collector.
      Lua.Engine.Machine.Resize_Stack_Window
        (State, Activation,
         Natural'Max (Natural (Code.Max_Stack), Actual));
      Stacks.Clear_Range
        (Activation.Context, Activation.Stack_Base + 1,
         Activation.Stack_Base + Activation.Stack_Window_Length);
      if Activation.Stack_Base /= 0 then
         Stacks.Write
           (State, Activation.Context, Activation.Stack_Base,
            Activation.Callee);
      end if;
      for Index in 1 .. (if Is_Vararg then Actual else Fixed) loop
         Write_Register (State, Activation, Index - 1,
           (if Index <= Natural (Arguments.Length) then Arguments (Index)
            else Nil_Value));
      end loop;
      Activation.Canonical_Top := Actual;
      Activation.Canonical_GC_Top :=
        (if Is_Vararg then Activation.Stack_Window_Length else
            Natural (Code.Max_Stack));
      Activation.Vararg_Count := (if Is_Vararg then Actual - Fixed else 0);
      Activation.Vararg_Base := Activation.Stack_Base + Fixed + 1;
      Activation.Hidden_Varargs := False;
      Activation.Context.Foreign_Top := Activation.Stack_Base + Actual;
      --  VARARGPREP performs the real hidden-layout shift or table creation
      --  at its instruction point. Call hooks must observe that final layout.
   end Initialize_Frame;

   function Vararg_Length (Activation : Frame_Access) return Natural is
     (if Activation.Hidden_Varargs then Activation.Vararg_Count else 0);

   function Read_Vararg
     (State : in out World; Activation : Frame_Access; Index : Positive)
      return Value is
   begin
      if not Activation.Hidden_Varargs or else
        Index > Activation.Vararg_Count
      then
         Fail (State, "canonical vararg index out of range");
      end if;
      return Stacks.Read
        (State, Activation.Context, Activation.Vararg_Base + Index - 1);
   end Read_Vararg;

   procedure Write_Vararg
     (State : in out World; Activation : Frame_Access; Index : Positive;
      Item : Value) is
   begin
      if not Activation.Hidden_Varargs or else
        Index > Activation.Vararg_Count
      then
         Fail (State, "canonical vararg index out of range");
      end if;
      Stacks.Write
        (State, Activation.Context, Activation.Vararg_Base + Index - 1, Item);
   end Write_Vararg;

   function Source_Line (Activation : Frame_Access; PC : Natural)
                         return Natural is
     (Source_Line (Activation.Code, PC));

   function Source_Line (Code : Prototype_Access; PC : Natural)
                         return Natural
   is
      Model : constant Lua.Prototypes.Prototype_Access :=
        Code.Canonical_Node;
      Low : Natural := 0;
      High : Natural := Natural (Model.Absolute_Lines.Length);
      Middle : Natural;
      First_PC : Natural := 0;
      Line : Integer := Integer (Model.First_Line);
   begin
      if PC >= Natural (Model.Lines.Length) then
         return 0;
      end if;
      --  Absolute checkpoints bound the delta walk. A binary search avoids
      --  walking every earlier line record for each loop iteration/hook.
      while Low < High loop
         Middle := Low + (High - Low + 1) / 2;
         if Model.Absolute_Lines (Middle).PC <= PC then
            Low := Middle;
         else
            High := Middle - 1;
         end if;
      end loop;
      if Low /= 0 then
         First_PC := Model.Absolute_Lines (Low).PC + 1;
         Line := Integer (Model.Absolute_Lines (Low).Line);
      end if;
      for Index in First_PC .. PC loop
         if Model.Lines (Index + 1) /= -128 then
            Line := Line + Integer (Model.Lines (Index + 1));
         end if;
      end loop;
      return Natural'Max (0, Line);
   end Source_Line;

   function Adopt_Program
     (State : in out World; Program : in out Lua.Prototypes.Program)
      return Prototype_Access
   is
      Owner : Canonical_Program_Access;

      Was_Compiling : constant Boolean := State.Compiling;

      Current : Prototype_Access;
      Pending_Text : Value;
      Literal_Strings : Scalar_Values.Vector;
      procedure String_Value (Text : String);
      procedure String_Value (Text : String) is
      begin
         Pending_Text := New_String (State, Text);
      end String_Value;
   begin
      if Lua.Prototypes.Owner_Of (Program) /=
        Lua.Storage.Reference (State.Memory)
      then
         raise Program_Error with "canonical program belongs to another owner";
      end if;
      State.Compiling := True;
      Owner := new (Lua.Storage.Handle (State.Memory)) Canonical_Program;
      Owner.Wrappers.Set_Owner (Lua.Storage.Reference (State.Memory));
      Lua.Prototypes.Move (Owner.Model, Program);
      Owner.Wrappers.Reserve_Capacity (Ada.Containers.Count_Type
        (Lua.Prototypes.Prototype_Count (Owner.Model)));
      --  The owned model already interns literals across all nested nodes.
      --  Materialize each such string once for this program, rather than
      --  losing its identity when another wrapper mentions the same ID.
      --  This temporary index uses the universe allocator and contains only
      --  values already retained by registered wrappers; it creates no new
      --  collector root or universe-wide long-string interning policy.
      Literal_Strings.Set_Owner (Lua.Storage.Reference (State.Memory));
      Literal_Strings.Reserve_Capacity (Ada.Containers.Count_Type
        (Lua.Prototypes.String_Count (Owner.Model)));
      for Index in 1 .. Lua.Prototypes.String_Count (Owner.Model) loop
         Literal_Strings.Append (Nil_Value);
      end loop;
      --  Each wrapper is registered before materializing its constants. The
      --  compiling bridge roots partial construction during allocation retry;
      --  no opaque fake private instructions stand in for canonical metadata.
      for Index in 1 .. Lua.Prototypes.Prototype_Count (Owner.Model) loop
         Current := New_Program (State);

         Owner.Wrappers.Append (Current);
         Owner.References := Owner.References + 1;
         Current.Canonical_Owner := Owner;
         Current.Canonical_Node :=
           Lua.Prototypes.Prototype_At (Owner.Model, Index);
         --  Once a new literal exists, publication into its wrapper must
         --  require no further allocation. Reserve all scalar slots before
         --  creating heap values, keeping construction and cache publication
         --  in one interval without a possible allocation safe point.
         Current.Canonical_Constants.Reserve_Capacity
           (Current.Canonical_Node.Constants.Length);
         Current.First_Line := Current.Canonical_Node.First_Line;
         Current.Last_Line := Current.Canonical_Node.Last_Line;
         Current.Register_Count := Natural (Current.Canonical_Node.Max_Stack);
         if Current.Register_Count > State.Bounds.Registers then
            Fail (State, "register limit exceeded", Resource => True);
         end if;
         Current.Vararg := (Current.Canonical_Node.Flags and 3) /= 0;
         Current.Is_Main := Current.Canonical_Node =
           Lua.Prototypes.Root (Owner.Model);
         for Item of Current.Canonical_Node.Constants loop
            case Item.Kind is
               when Lua.Prototypes.Nil_Constant =>
                  Pending_Text := Nil_Value;
               when Lua.Prototypes.Boolean_Constant =>
                  Pending_Text := (Boolean_Kind, Item.Boolean_Data);
               when Lua.Prototypes.Integer_Constant =>
                  Pending_Text := (Integer_Kind, Item.Integer_Data);
               when Lua.Prototypes.Number_Constant =>
                  Pending_Text := (Real_Kind, Item.Number_Data);
               when Lua.Prototypes.String_Constant =>
                  Pending_Text := Literal_Strings
                    (Positive (Item.String_Data));
                  if Pending_Text.Kind = Nil_Kind then
                     Lua.Prototypes.Query_String
                       (Owner.Model, Item.String_Data, String_Value'Access);
                  end if;
            end case;
            Current.Canonical_Constants.Append (Pending_Text);
            Code_Barrier (State, Current);
            if Item.Kind = Lua.Prototypes.String_Constant then
               --  Publish in the non-rooting index only after the wrapper
               --  owns the value. Capacity was reserved before construction,
               --  so this update cannot allocate or introduce a safe point.
               Literal_Strings.Replace_Element
                 (Positive (Item.String_Data), Pending_Text);
            end if;
         end loop;
      end loop;
      if Lua.Prototypes.Root (Owner.Model) = null then
         Fail (State, "canonical program has no root");
      end if;
      Current := Owner.Wrappers
        (Lua.Prototypes.Root (Owner.Model).Node_Index);
      State.Entry_Code := Current;
      State.Compiling := Was_Compiling;
      return Current;
   exception
      when others =>
         --  Release registered wrappers in reverse construction order. Their
         --  common program owner disappears only after the last wrapper; an
         --  allocation before the first registration is cleaned up directly.
         State.Entry_Code := null;
         if Current /= null and then Current.Canonical_Owner = null then
            Release_Registered_Program (State, Current);
         end if;
         if Owner /= null then
            if Owner.Wrappers.Is_Empty then
               Release_Bundle (Owner);
            else
               --  Stable registry holes invalidate dense-index rollback.
               --  The immutable owner records precisely this construction's
               --  wrappers; the last release destroys Owner, so no later
               --  iteration or cleanup may dereference that pointer.
               for Index in reverse Owner.Wrappers.First_Index ..
                 Owner.Wrappers.Last_Index
               loop
                  declare
                     Item : Prototype_Access := Owner.Wrappers (Index);
                  begin
                     Release_Registered_Program (State, Item);
                  end;
               end loop;
            end if;
         end if;
         State.Compiling := Was_Compiling;
         raise;
   end Adopt_Program;

   function Adopt
     (State : in out World; Program : in out Lua.Prototypes.Program;
      Environment : Value) return Value
   is
      Code : Prototype_Access;
      Main : Value;
   begin
      Pin (State, Environment);
      Code := Adopt_Program (State, Program);
      Main := New_Closure (State, Code, null);
      if not Main.Reference.Upvalues.Is_Empty then
         --  Explicit nil is an actual initial environment, distinct from an
         --  omitted environment. Other initial capture cells remain nil.
         Store_Cell
           (State, Main.Reference.Upvalues.First_Element, Environment);
      end if;
      return Main;
   end Adopt;

   function Number
     (State : in out World; Item : Value; Role : String)
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
      Fail (State, "'for' " & Role & " value must be a number");
      return (Kind => Lua.Numbers.Invalid);
   end Number;

   procedure Prepare_For
     (State : in out World; Activation : Frame_Access;
      Base : Natural; Skip : out Boolean)
   is
      Initial : constant Value := Read_Register (State, Activation, Base);
      Limit : constant Value := Read_Register (State, Activation, Base + 1);
      Step : constant Value := Read_Register (State, Activation, Base + 2);
      Bound : Lua.Numbers.Number;
      Start, Stride, Last : Integer_Value;
      Count : Interfaces.Unsigned_64;
      F_Start, F_Stride, F_Last : Real_Value;
   begin
      Skip := False;
      if Initial.Kind = Integer_Kind and then Step.Kind = Integer_Kind then
         Start := Initial.Integer_Data;
         Stride := Step.Integer_Data;
         if Stride = 0 then
            Fail (State, "'for' step is zero");
         end if;
         Bound := Number (State, Limit, "limit");
         if Bound.Kind = Lua.Numbers.Integer_Number then
            Last := Bound.Integer_Item;
         else
            F_Last := Bound.Real_Item;
            --  Out-of-range finite/infinite limits clip only on the side
            --  reached by this step. NaN follows pinned forlimit's negative
            --  out-of-range branch; no invalid Ada conversion is attempted.
            if F_Last /= F_Last or else F_Last < -(2.0 ** 63) then
               if Stride > 0 then Skip := True; return; end if;
               Last := Integer_Value'First;
            elsif F_Last >= 2.0 ** 63 then
               if Stride < 0 then Skip := True; return; end if;
               Last := Integer_Value'Last;
            else
               Last := Integer_Value
                 (if Stride > 0 then Real_Value'Floor (F_Last)
                  else Real_Value'Ceiling (F_Last));
            end if;
         end if;
         if (Stride > 0 and then Start > Last) or else
           (Stride < 0 and then Start < Last)
         then
            Skip := True;
            return;
         end if;
         --  The loop counter is unsigned distance, stored as an integer bit
         --  pattern. This handles the full mininteger..maxinteger span and
         --  a mininteger negative stride without signed overflow.
         if Stride > 0 then
            Count := (Integer_Bits (Last) - Integer_Bits (Start)) /
              Integer_Bits (Stride);
         else
            Count := (Integer_Bits (Start) - Integer_Bits (Last)) /
              (0 - Integer_Bits (Stride));
         end if;
         Write_Register (State, Activation, Base,
                         (Integer_Kind, Signed_Bits (Count)));
         Write_Register (State, Activation, Base + 1,
                         (Integer_Kind, Stride));
         Write_Register (State, Activation, Base + 2,
                         (Integer_Kind, Start));
      else
         --  Conversion order is observable when several operands are bad:
         --  Lua validates limit, step, then initial value in the float path.
         F_Last := Lua.Numbers.To_Real (Number (State, Limit, "limit"));
         F_Stride := Lua.Numbers.To_Real (Number (State, Step, "step"));
         F_Start := Lua.Numbers.To_Real
           (Number (State, Initial, "initial"));
         if F_Stride = 0.0 then
            Fail (State, "'for' step is zero");
         end if;
         Skip := (if F_Stride > 0.0 then F_Last < F_Start
                  else F_Start < F_Last);
         if not Skip then
            Write_Register (State, Activation, Base, (Real_Kind, F_Last));
            Write_Register
              (State, Activation, Base + 1, (Real_Kind, F_Stride));
            Write_Register
              (State, Activation, Base + 2, (Real_Kind, F_Start));
         end if;
      end if;
   end Prepare_For;

   procedure Charge_Companion (State : in out World);
   procedure Charge_Companion (State : in out World) is
   begin
      --  Companion words share a VM dispatch boundary, as in pinned lvm.c,
      --  but still consume the host's common work budget. Fusing an iterator
      --  transfer must not turn bounded execution into an uncharged loop.
      if State.Steps >= State.Bounds.Instructions then
         Fail (State, "instruction limit exceeded", Resource => True);
      end if;
      if State.Policy = Bounded then State.Steps := State.Steps + 1; end if;
   end Charge_Companion;

   procedure Finish_Iterator_Call
     (State : in out World; Activation : Frame_Access);
   procedure Finish_Iterator_Call
     (State : in out World; Activation : Frame_Access)
   is
      Prototype : constant Lua.Prototypes.Prototype_Access :=
        Activation.Code.Canonical_Node;
      Code : Word;
      Base : Natural;
      Target : Long_Long_Integer;
   begin
      --  TFORCALL consumes its following TFORLOOP after the iterator returns,
      --  including after suspension. Results have already replaced the real
      --  control register; no user callback or executor is entered here.
      if Activation.PC > Prototype.Code.Last_Index or else
        not Valid (Prototype.Code (Activation.PC)) or else
        Lua.Opcodes.Operation (Prototype.Code (Activation.PC)) /= Op_TFORLOOP
      then
         Fail (State, "missing canonical iterator loop instruction");
      end if;
      Code := Prototype.Code (Activation.PC);
      Base := Part (State, Code, A);
      if Base + 3 /= Activation.Canonical_Base then
         Fail (State, "canonical iterator loop register mismatch");
      end if;
      Charge_Companion (State);
      Activation.PC := Activation.PC + 1;
      if Read_Register (State, Activation, Base + 3).Kind /= Nil_Kind then
         Target := Long_Long_Integer (Activation.PC) -
           Long_Long_Integer (Part (State, Code, Bx));
         if Target < 1 or else Target >
           Long_Long_Integer (Prototype.Code.Last_Index) + 1
         then
            Fail (State, "canonical jump out of range");
         end if;
         Activation.PC := Positive (Target);
      end if;
   end Finish_Iterator_Call;

   procedure Deliver
     (State : in out World; Activation : Frame_Access;
      Results : Values.Vector)
   is
      Item : constant Value :=
        (if Results.Is_Empty then Nil_Value else Results.First_Element);
   begin
      --  This is called only after the scheduler has rooted the returned
      --  packet. Clear pending callback arguments after publishing the result
      --  or deciding the branch, so a collection sees one owner throughout.
      case Activation.Canonical_Pending is
         when Store_Canonical_Results | Store_Call_Results =>
            declare
               Is_Call : constant Boolean :=
                 Activation.Canonical_Pending = Store_Call_Results;
               Count : constant Natural :=
                 (if Activation.Canonical_Wanted < 0 then
                     Natural (Results.Length) else
                     Activation.Canonical_Wanted);
            begin
               Store_Results
                 (State, Activation, Activation.Canonical_Base,
                  Activation.Canonical_Wanted, Results);
               if Is_Call then
                  --  Real calls move results over the function slot and
                  --  publish their actual top. Operator helpers instead
                  --  restore their saved/protected reservation after copying
                  --  a scalar result into an ordinary destination register.
                  Activation.Canonical_Top :=
                    Activation.Canonical_Base + Count;
                  if Activation.Context.Stack_Window = Activation then
                     Activation.Context.Foreign_Top := Activation.Stack_Base +
                       Activation.Canonical_Top;
                  end if;
                  if Activation.PC > 1 and then
                    Valid (Activation.Code.Canonical_Node.Code
                      (Activation.PC - 1)) and then
                    Lua.Opcodes.Operation (Activation.Code.Canonical_Node.Code
                      (Activation.PC - 1)) = Op_TFORCALL
                  then
                     Finish_Iterator_Call (State, Activation);
                  end if;
               end if;
            end;
            Activation.Canonical_Pending := No_Canonical_Result;
         when Test_Canonical_Result =>
            if Truth (Item) /= Activation.Canonical_Test then
               Activation.PC := Activation.PC + 1;
            end if;
            Activation.Canonical_Pending := No_Canonical_Result;
         when Concat_Canonical_Result =>
            Write_Register
              (State, Activation, Activation.Canonical_Concat_Last - 1, Item);
            Activation.Canonical_Concat_Last :=
              Activation.Canonical_Concat_Last - 1;
            if Activation.Canonical_Concat_Last = Activation.Canonical_Base
            then
               Activation.Canonical_Pending := No_Canonical_Result;
            end if;
         when No_Canonical_Result => null;
      end case;
      Activation.Native_Arguments.Clear;
      Activation.Native_Results.Clear;
      Activation.Native_Captures.Clear;
   end Deliver;

   function Step
     (State : in out World; Activation : Frame_Access) return Action
   is
      Prototype : constant Lua.Prototypes.Prototype_Access :=
        Activation.Code.Canonical_Node;
      Code : Word;
      Op : Opcode;
      Reg_A, Reg_B, Reg_C : Natural;
      Result : Action;
      Left, Right, Item : Value;
      Count, Offset : Natural;
      Skip : Boolean;

      function Operand (Id : Field) return Integer is
        (Part (State, Code, Id));
      function Reg (Index : Natural) return Value is
        (Read_Register (State, Activation, Index));
      procedure Put (Index : Natural; Value_To_Write : Value);
      procedure Branch (Displacement : Integer);
      procedure Require_Next (Expected : Opcode);
      procedure Request
        (Name : String; Arguments : Values.Vector; Destination : Natural;
         Wanted : Integer := 1;
         Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input);
      procedure Binary_Request
        (Operator : Lua.Lexers.Token_Kind; A, B : Value; Destination : Natural;
         Test : Boolean := False);
      procedure Mark_Closing (Index : Natural);
      procedure Invoke_Iterator (Base, Wanted : Natural);
      procedure Freeze_Closing (From : Natural);
      function Integral (Value_To_Test : Value) return Boolean;
      function Arithmetic_Operator (Operation_Id : Opcode)
                                    return Lua.Lexers.Token_Kind;
      function Metamethod_Operator (Id : Natural)
                                    return Lua.Lexers.Token_Kind;

      procedure Put (Index : Natural; Value_To_Write : Value) is
      begin
         Write_Register (State, Activation, Index, Value_To_Write);
      end Put;

      procedure Branch (Displacement : Integer) is
         PC : constant Long_Long_Integer :=
           Long_Long_Integer (Activation.PC) +
             Long_Long_Integer (Displacement);
      begin
         if PC < 1 or else PC >
           Long_Long_Integer (Prototype.Code.Length) + 1
         then
            Fail (State, "canonical jump out of range");
         end if;
         Activation.PC := Positive (PC);
      end Branch;

      procedure Require_Next (Expected : Opcode) is
      begin
         if Activation.PC > Prototype.Code.Last_Index or else
           not Valid (Prototype.Code (Activation.PC)) or else
           Lua.Opcodes.Operation (Prototype.Code (Activation.PC)) /= Expected
         then
            Fail (State, "missing canonical companion instruction");
         end if;
      end Require_Next;

      procedure Invoke_Iterator (Base, Wanted : Natural) is
         Arguments : Values.Vector := Owned_Values (State);
      begin
         Require_Next (Op_TFORLOOP);
         if Part (State, Prototype.Code (Activation.PC), A) /= Base then
            Fail (State, "canonical iterator loop register mismatch");
         end if;
         --  Keep the existing explicit call continuation and its real rooted
         --  arguments. Entry preparation can invoke this same phase after
         --  consuming TFORCALL, without an extra scheduler dispatch boundary.
         Put (Base + 5, Reg (Base + 3));
         Put (Base + 4, Reg (Base + 1));
         Put (Base + 3, Reg (Base));
         Arguments.Append (Reg (Base + 4));
         Arguments.Append (Reg (Base + 5));
         Copy_Roots (State, Activation.Native_Arguments, Arguments);
         Activation.Native_Captures.Clear;
         Append_Root (State, Activation.Native_Captures, Reg (Base));
         Activation.Canonical_Pending := Store_Call_Results;
         Activation.Canonical_Base := Base + 3;
         Activation.Canonical_Wanted := Wanted;
         Result := (Kind => Invoke_Function,
                    Function_Value => Reg (Base), Arguments => Arguments,
                    Destination => Base + 4,
                    Call_Base => Activation.Stack_Base + Base + 4,
                    Has_Call_Window => True, others => <>);
      end Invoke_Iterator;

      procedure Request
        (Name : String; Arguments : Values.Vector; Destination : Natural;
         Wanted : Integer := 1;
         Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input)
      is
      begin
         Copy_Roots
           (State, Activation.Native_Arguments,
            Arguments);
         Activation.Canonical_Pending := Store_Canonical_Results;
         Activation.Canonical_Base := Destination;
         Activation.Canonical_Wanted := Wanted;
         Result := (Kind => Invoke_Helper,
                    Helper => To_Unbounded_String (Name),
                    Operator => Operator, Arguments => Arguments,
                    Destination => Destination + 1, others => <>);
      end Request;

      procedure Binary_Request
        (Operator : Lua.Lexers.Token_Kind; A, B : Value; Destination : Natural;
         Test : Boolean := False)
      is
         Arguments : Values.Vector := Owned_Values (State);
      begin
         Arguments.Append (A);
         Arguments.Append (B);
         Request ("@binary", Arguments, Destination, Operator => Operator);
         if Test then
            Activation.Canonical_Pending := Test_Canonical_Result;
            Activation.Canonical_Test := Operand (K) /= 0;
         end if;
      end Binary_Request;

      procedure Mark_Closing (Index : Natural) is
         Closing : constant Value := Reg (Index);
      begin
         if not Truth (Closing) then
            --  Nil/false never become TBC entries, even if debug later
            --  mutates an upvalue which once held that inactive value.
            return;
         end if;
         if Metafield (State, Closing, "__close").Kind = Nil_Kind
         then
            declare
               Name : constant Value := Local_Name
                 (State, Activation.Code, Index + 1, Activation.PC - 2);
            begin
               Fail (State, "variable '" &
                 (if Name.Kind = String_Kind
                  then Image (State.Current.Memory, Name) else "?") &
                 "' got a non-closable value");
            end;
         end if;
         --  Register numbers are used only for canonical lifetime ordering.
         --  Scope depth in a private frame remains its separate old meaning.
         Activation.Closers.Append
           (Close_Entry'(Cell => Capture_Cell (State, Activation, Index),
                         Symbol => Index + 1, Depth => Index + 1,
                         others => <>));
      end Mark_Closing;

      procedure Freeze_Closing (From : Natural) is
      begin
         Prepare_Close (State, Activation, From);
      end Freeze_Closing;

      function Integral (Value_To_Test : Value) return Boolean is
      begin
         return Value_To_Test.Kind = Integer_Kind or else
           (Value_To_Test.Kind = Real_Kind and then
            Value_To_Test.Real_Data >= -(2.0 ** 63) and then
            Value_To_Test.Real_Data < 2.0 ** 63 and then
            Real_Value'Floor (Value_To_Test.Real_Data) =
              Value_To_Test.Real_Data);
      end Integral;

      function Arithmetic_Operator (Operation_Id : Opcode)
                                    return Lua.Lexers.Token_Kind
      is
         use Lua.Lexers;
      begin
         case Operation_Id is
            when Op_ADDI | Op_ADDK | Op_ADD => return Plus;
            when Op_SUBK | Op_SUB => return Minus;
            when Op_MULK | Op_MUL => return Star;
            when Op_MODK | Op_MOD => return Percent;
            when Op_POWK | Op_POW => return Power;
            when Op_DIVK | Op_DIV => return Slash;
            when Op_IDIVK | Op_IDIV => return Floor_Divide;
            when Op_BANDK | Op_BAND => return Bit_And;
            when Op_BORK | Op_BOR => return Bit_Or;
            when Op_BXORK | Op_BXOR => return Bit_Xor;
            when Op_SHLI | Op_SHL => return Shift_Left;
            when Op_SHRI | Op_SHR => return Shift_Right;
            when others =>
               Fail (State, "invalid canonical arithmetic operation");
               return End_Of_Input;
         end case;
      end Arithmetic_Operator;

      function Metamethod_Operator (Id : Natural)
                                    return Lua.Lexers.Token_Kind
      is
      begin
         if Id not in 6 .. 17 then
            Fail (State, "invalid arithmetic metamethod event");
         end if;
         return Arithmetic_Operator
           (Opcode'Val (Opcode'Pos (Op_ADD) + Id - 6));
      end Metamethod_Operator;
   begin
      if Activation.Canonical_Pending = Concat_Canonical_Result then
         --  Right-associated concatenation resumes at a real register pair,
         --  retaining every later operand while the handler calls Lua.
         declare
            Arguments : Values.Vector := Owned_Values (State);
         begin
            Arguments.Append (Reg (Activation.Canonical_Concat_Last - 1));
            Arguments.Append (Reg (Activation.Canonical_Concat_Last));
            Copy_Roots
              (State, Activation.Native_Arguments,
               Arguments);
            return (Kind => Invoke_Helper,
                    Helper => To_Unbounded_String ("@binary"),
                    Operator => Lua.Lexers.Concatenate,
                    Arguments => Arguments, Destination =>
                      Activation.Canonical_Concat_Last, others => <>);
         end;
      elsif Activation.Canonical_Pending /= No_Canonical_Result then
         raise Program_Error with "canonical callback has not completed";
      end if;
      if Activation.PC > Prototype.Code.Last_Index then
         Fail (State, "canonical function ended without return");
      end if;
      Code := Prototype.Code (Activation.PC);
      if not Valid (Code) then
         Fail (State, "invalid canonical opcode");
      end if;
      Op := Lua.Opcodes.Operation (Code);
      Activation.Canonical_GC_Top :=
        (if Op = Op_VARARGPREP then Activation.Stack_Window_Length
         elsif Uses_Top (Code) then Activation.Canonical_Top
         else Natural (Prototype.Max_Stack));
      Activation.PC := Activation.PC + 1;
      State.Current.Failure_At :=
        (Line => Positive'Max (1, Source_Line (Activation, Activation.PC - 2)),
         Column => 1, Offset => 1);
      Reg_A := (if Describe (Op).Mode in IsJ then 0 else Operand (A));
      Reg_B := (if Describe (Op).Mode = IABC then Operand (B) else 0);
      Reg_C := (if Describe (Op).Mode = IABC then Operand (C) else 0);
      case Op is
         when Op_MOVE => Put (Reg_A, Reg (Reg_B));
         when Op_LOADI =>
            Put (Reg_A, (Integer_Kind, Integer_Value (Operand (SBx))));
         when Op_LOADF =>
            Put (Reg_A, (Real_Kind, Real_Value (Operand (SBx))));
         when Op_LOADK =>
            Put (Reg_A, Constant_At (State, Activation, Operand (Bx)));
         when Op_LOADKX =>
            Require_Next (Op_EXTRAARG);
            Put (Reg_A, Constant_At (State, Activation,
              Part (State, Prototype.Code (Activation.PC), Ax)));
            Activation.PC := Activation.PC + 1;
         when Op_LOADFALSE | Op_LFALSESKIP | Op_LOADTRUE =>
            Put (Reg_A, (Boolean_Kind, Op = Op_LOADTRUE));
            if Op = Op_LFALSESKIP then Branch (1); end if;
         when Op_LOADNIL =>
            for Index in Reg_A .. Reg_A + Reg_B loop
               Put (Index, Nil_Value);
            end loop;
         when Op_GETUPVAL =>
            Put (Reg_A, Upvalue_Cell (State, Activation, Reg_B).Cell_Value);
         when Op_SETUPVAL =>
            Store_Cell
              (State, Upvalue_Cell (State, Activation, Reg_B), Reg (Reg_A));
         when Op_GETTABUP | Op_GETTABLE | Op_GETI | Op_GETFIELD | Op_SELF =>
            Left := (if Op = Op_GETTABUP then
                       Upvalue_Cell (State, Activation, Reg_B).Cell_Value
                     else Reg (Reg_B));
            Right := (if Op = Op_GETTABLE then Reg (Reg_C)
                      elsif Op = Op_GETI then
                        (Integer_Kind, Integer_Value (Reg_C))
                      else Constant_At (State, Activation, Reg_C));
            if Op = Op_SELF then Put (Reg_A + 1, Left); end if;
            Item := (if Left.Kind = Table_Kind then Get (Left, Right)
                     else Nil_Value);
            if Left.Kind = Table_Kind and then
              (Item.Kind /= Nil_Kind or else
               Tables.Raw_Field
                 (Left.Reference.Metatable, "__index").Kind = Nil_Kind)
            then
               --  Plain lookup is allocation-free, as in the upstream VM.
               --  In particular a host must be able to retrieve its existing
               --  allocator-control callback while growth is refused. Only
               --  actual delegation needs an owned continuation packet.
               Put (Reg_A, Item);
            else
               declare
                  Arguments : Values.Vector := Owned_Values (State);
               begin
                  Arguments.Append (Left);
                  Arguments.Append (Right);
                  Request ("@get", Arguments, Reg_A);
               end;
            end if;
         when Op_SETTABUP | Op_SETTABLE | Op_SETI | Op_SETFIELD =>
            Left := (if Op = Op_SETTABUP then
                       Upvalue_Cell (State, Activation, Reg_A).Cell_Value
                     else Reg (Reg_A));
            Right := (if Op = Op_SETTABLE then Reg (Reg_B)
                      elsif Op = Op_SETI then
                        (Integer_Kind, Integer_Value (Reg_B))
                      else Constant_At (State, Activation, Reg_B));
            Item := (if Operand (K) /= 0 then
                       Constant_At (State, Activation, Reg_C)
                     else Reg (Reg_C));
            declare
               Arguments : Values.Vector := Owned_Values (State);
               Retried : Boolean := False;
            begin
               --  All three operands remain rooted in the current register
               --  window or its prototype constants. Reserve the temporary
               --  packet before publishing any entries, then retry one real
               --  refusal through emergency collection. Weak __newindex
               --  handlers may disappear during that collection: @set must
               --  resolve the handler only after these rooted operands are
               --  transferred to its activation.
               loop
                  begin
                     Arguments.Reserve_Capacity (3);
                     exit;
                  exception
                     when Lua.Storage.Allocation_Error =>
                        if not Retry_Allocation (State, Retried) then
                           raise;
                        end if;
                  end;
               end loop;
               Arguments.Append (Left);
               Arguments.Append (Right);
               Arguments.Append (Item);
               Request ("@set", Arguments, 0, Wanted => 0);
            end;
         when Op_NEWTABLE =>
            Require_Next (Op_EXTRAARG);
            Activation.PC := Activation.PC + 1;
            Put (Reg_A, New_Table (State));
            Activation.Canonical_GC_Top := Reg_A + 1;
         when Op_ADDI | Op_ADDK .. Op_SHR =>
            Left := Reg (Reg_B);
            Right := (if Op in Op_ADDI | Op_SHRI then
                        (Integer_Kind, Integer_Value (Operand (SC)))
                      elsif Op = Op_SHLI then
                        (Integer_Kind, Integer_Value (Operand (SC)))
                      elsif Op in Op_ADDK .. Op_BXORK then
                        Constant_At (State, Activation, Reg_C)
                      else Reg (Reg_C));
            if Op = Op_SHLI then
               Item := Left; Left := Right; Right := Item;
            end if;
            if (Op in Op_BANDK .. Op_SHRI | Op_BAND .. Op_SHR and then
                  Integral (Left) and then Integral (Right)) or else
              (Op not in Op_BANDK .. Op_SHRI | Op_BAND .. Op_SHR and then
                 Left.Kind in Integer_Kind | Real_Kind and then
                 Right.Kind in Integer_Kind | Real_Kind)
            then
               Item := Lua.Engine.Machine.Binary_Value
                 (State, Arithmetic_Operator (Op), Left, Right);
               Put (Reg_A, Item);
               --  Fast primitives consume their adjacent fallback word. On
               --  nonprimitive operands, leave PC at that real MMBIN/I/K so
               --  its original operands/event/flip drive the handler instead.
               if Activation.PC > Prototype.Code.Last_Index or else
                 not Valid (Prototype.Code (Activation.PC)) or else
                 Lua.Opcodes.Operation (Prototype.Code (Activation.PC)) not in
                   Op_MMBIN | Op_MMBINI | Op_MMBINK
               then
                  Fail (State, "missing arithmetic fallback instruction");
               end if;
               Activation.PC := Activation.PC + 1;
            end if;
         when Op_MMBIN | Op_MMBINI | Op_MMBINK =>
            if Activation.PC < 3 then
               Fail (State, "orphan arithmetic fallback instruction");
            end if;
            declare
               Previous : constant Word :=
                 Prototype.Code (Activation.PC - 2);
            begin
               if not Valid (Previous) or else
                 Lua.Opcodes.Operation (Previous) not in
                 Op_ADDI .. Op_SHR
               then
                  Fail (State, "invalid arithmetic fallback predecessor");
               end if;
               Left := Reg (Reg_A);
               Right := (if Op = Op_MMBIN then Reg (Reg_B)
                         elsif Op = Op_MMBINI then
                           (Integer_Kind, Integer_Value (Operand (SB)))
                         else Constant_At (State, Activation, Reg_B));
               if Op /= Op_MMBIN and then Operand (K) /= 0 then
                  Item := Left; Left := Right; Right := Item;
               end if;
               Binary_Request (Metamethod_Operator (Reg_C), Left, Right,
                               Part (State, Previous, A));
            end;
         when Op_UNM | Op_BNOT | Op_NOT | Op_LEN =>
            declare
               Arguments : Values.Vector := Owned_Values (State);
            begin
               Arguments.Append (Reg (Reg_B));
               Request ("@unary", Arguments, Reg_A, Operator =>
                 (case Op is
                     when Op_UNM => Lua.Lexers.Minus,
                     when Op_BNOT => Lua.Lexers.Bit_Xor,
                     when Op_NOT => Lua.Lexers.Not_Word,
                     when others => Lua.Lexers.Length));
            end;
         when Op_CONCAT =>
            if Reg_B = 0 then
               Fail (State, "empty canonical concat range");
            elsif Reg_B > 1 then
               Activation.Canonical_Base := Reg_A;
               Activation.Canonical_Concat_Last := Reg_A + Reg_B - 1;
               Activation.Canonical_Pending := Concat_Canonical_Result;
               --  Start the first pair without recursively executing Step.
               declare
                  Arguments : Values.Vector := Owned_Values (State);
               begin
                  Arguments.Append (Reg (Reg_A + Reg_B - 2));
                  Arguments.Append (Reg (Reg_A + Reg_B - 1));
                  Copy_Roots
                    (State, Activation.Native_Arguments,
                     Arguments);
                  Result := (Kind => Invoke_Helper,
                    Helper => To_Unbounded_String ("@binary"),
                    Operator => Lua.Lexers.Concatenate,
                    Arguments => Arguments,
                    Destination => Reg_A + Reg_B - 1, others => <>);
               end;
            end if;
         when Op_CLOSE =>
            Freeze_Closing (Reg_A);
            Result := (Kind => Close_From_Register, Close_From => Reg_A,
                       others => <>);
         when Op_TBC => Mark_Closing (Reg_A);
         when Op_JMP => Branch (Operand (SJ));
         when Op_EQ | Op_LT | Op_LE =>
            Binary_Request
              ((if Op = Op_EQ then Lua.Lexers.Equal
                elsif Op = Op_LT then Lua.Lexers.Less
                else Lua.Lexers.Less_Equal),
               Reg (Reg_A), Reg (Reg_B), 0, Test => True);
         when Op_EQK | Op_EQI =>
            Right := (if Op = Op_EQK then
                        Constant_At (State, Activation, Reg_B)
                      else (Integer_Kind, Integer_Value (Operand (SB))));
            if Equal (Reg (Reg_A), Right) /= (Operand (K) /= 0) then
               Branch (1);
            end if;
         when Op_LTI | Op_LEI | Op_GTI | Op_GEI =>
            Right := (if Reg_C = 0 then
                        (Integer_Kind, Integer_Value (Operand (SB)))
                      else (Real_Kind, Real_Value (Operand (SB))));
            Binary_Request
              ((if Op in Op_LTI | Op_GTI then Lua.Lexers.Less
                else Lua.Lexers.Less_Equal),
               (if Op in Op_GTI | Op_GEI then Right else Reg (Reg_A)),
               (if Op in Op_GTI | Op_GEI then Reg (Reg_A) else Right),
               0, Test => True);
         when Op_TEST | Op_TESTSET =>
            Item := Reg ((if Op = Op_TEST then Reg_A else Reg_B));
            if Truth (Item) /= (Operand (K) /= 0) then
               Branch (1);
            elsif Op = Op_TESTSET then
               Put (Reg_A, Item);
            end if;
         when Op_CALL | Op_TAILCALL =>
            if Reg_B = 0 then
               if Activation.Canonical_Top <= Reg_A then
                  Fail (State, "invalid open call top");
               end if;
               Count := Activation.Canonical_Top - Reg_A - 1;
            else
               Count := Reg_B - 1;
               Activation.Canonical_Top := Reg_A + Reg_B;
            end if;
            Activation.Canonical_GC_Top := Reg_A + Count + 1;
            Copy_Roots
              (State, Activation.Native_Arguments,
               Register_List (State, Activation, Reg_A + 1, Count));
            Activation.Native_Captures.Clear;
            Append_Root
              (State, Activation.Native_Captures,
               Reg (Reg_A));
            Activation.Canonical_Pending := Store_Call_Results;
            Activation.Canonical_Base := Reg_A;
            Activation.Canonical_Wanted := Integer (Reg_C) - 1;
            if Op = Op_TAILCALL then Freeze_Closing (0); end if;
            Result := (Kind => (if Op = Op_CALL then Invoke_Function
                                else Tail_Invoke),
                       Function_Value => Reg (Reg_A),
                       Arguments => Activation.Native_Arguments,
                       Destination => Reg_A + 1,
                       Call_Base => Activation.Stack_Base + Reg_A + 1,
                       Has_Call_Window => True, others => <>);
         when Op_RETURN | Op_RETURN0 | Op_RETURN1 =>
            if Op = Op_RETURN and then Reg_B = 0 and then
              Activation.Canonical_Top < Reg_A
            then
               Fail (State, "invalid open return top");
            end if;
            Count := (if Op = Op_RETURN0 then 0
                      elsif Op = Op_RETURN1 then 1
                      elsif Reg_B /= 0 then Reg_B - 1
                      else Activation.Canonical_Top - Reg_A);
            Copy_Roots
              (State, Activation.Unwind_Results,
               Register_List (State, Activation, Reg_A, Count));
            Freeze_Closing (0);
            Result := (Kind => Return_Results,
                       Arguments => Activation.Unwind_Results, others => <>);
         when Op_FORPREP =>
            Prepare_For (State, Activation, Reg_A, Skip);
            if Skip then Branch (Operand (Bx) + 1); end if;
         when Op_FORLOOP =>
            Left := Reg (Reg_A);
            Right := Reg (Reg_A + 1);
            Item := Reg (Reg_A + 2);
            if Right.Kind = Integer_Kind and then Left.Kind = Integer_Kind
              and then Item.Kind = Integer_Kind
            then
               declare
                  Remaining : constant Interfaces.Unsigned_64 :=
                    Integer_Bits (Left.Integer_Data);
               begin
                  if Remaining /= 0 then
                     Put (Reg_A, (Integer_Kind,
                                  Signed_Bits (Remaining - 1)));
                     Put (Reg_A + 2, (Integer_Kind, Lua.Integers.Add
                       (Item.Integer_Data, Right.Integer_Data)));
                     Branch (-Operand (Bx));
                  end if;
               end;
            elsif Right.Kind = Real_Kind and then Left.Kind = Real_Kind
              and then Item.Kind = Real_Kind
            then
               declare
                  Next : constant Real_Value :=
                    Item.Real_Data + Right.Real_Data;
               begin
                  if (if Right.Real_Data > 0.0 then Next <= Left.Real_Data
                      else Next >= Left.Real_Data)
                  then
                     Put (Reg_A + 2, (Real_Kind, Next));
                     Branch (-Operand (Bx));
                  end if;
               end;
            else
               Fail (State, "invalid canonical for state");
            end if;
         when Op_TFORPREP =>
            Item := Reg (Reg_A + 3);
            Put (Reg_A + 3, Reg (Reg_A + 2));
            Put (Reg_A + 2, Item);
            Mark_Closing (Reg_A + 2);
            Branch (Operand (Bx));
            Require_Next (Op_TFORCALL);
            if Part (State, Prototype.Code (Activation.PC), A) /= Reg_A then
               Fail (State, "canonical iterator call register mismatch");
            end if;
            Count := Part (State, Prototype.Code (Activation.PC), C);
            Charge_Companion (State);
            Activation.PC := Activation.PC + 1;
            Invoke_Iterator (Reg_A, Count);
         when Op_TFORCALL =>
            Invoke_Iterator (Reg_A, Reg_C);
         when Op_TFORLOOP =>
            if Reg (Reg_A + 3).Kind /= Nil_Kind then
               Branch (-Operand (Bx));
            end if;
         when Op_SETLIST =>
            Count := Operand (VB);
            Offset := Operand (VC);
            if Count = 0 then
               if Activation.Canonical_Top <= Reg_A then
                  Fail (State, "invalid open setlist top");
               end if;
               Count := Activation.Canonical_Top - Reg_A - 1;
            end if;
            if Operand (K) /= 0 then
               Require_Next (Op_EXTRAARG);
               if Part (State, Prototype.Code (Activation.PC), Ax) >
                 (Natural'Last - Offset) / 1_024
               then
                  Fail (State, "canonical sequence index overflow");
               end if;
               Offset := Offset + 1_024 *
                 Part (State, Prototype.Code (Activation.PC), Ax);
               Activation.PC := Activation.PC + 1;
            end if;
            Left := Reg (Reg_A);
            if Left.Kind /= Table_Kind then
               Fail (State, "canonical setlist requires a table");
            end if;
            for Index in 1 .. Count loop
               Set (State, Left,
                    (Integer_Kind, Integer_Value (Offset) +
                       Integer_Value (Index)), Reg (Reg_A + Index));
            end loop;
         when Op_CLOSURE =>
            declare
               Index : constant Natural := Operand (Bx);
               Child : Lua.Prototypes.Prototype_Access;
               Closure : Value;
            begin
               if Index >= Natural (Prototype.Children.Length) then
                  Fail (State, "canonical child prototype out of range");
               end if;
               Child := Prototype.Children (Index + 1);
               if not Lua.Prototypes.Owns
                 (Activation.Code.Canonical_Owner.Model, Child)
               then
                  Fail (State, "canonical child belongs to another program");
               end if;
               Closure := New_Closure (State,
                 Activation.Code.Canonical_Owner.Wrappers
                   (Child.Node_Index), null);
               Put (Reg_A, Closure);
               Activation.Canonical_GC_Top := Reg_A + 1;
               for Upvalue of Child.Upvalues loop
                  Append_Object_Edge
                    (State, Closure.Reference, Closure.Reference.Upvalues,
                     (if Upvalue.In_Stack then Capture_Cell
                        (State, Activation, Natural (Upvalue.Index))
                      else Upvalue_Cell
                        (State, Activation, Natural (Upvalue.Index))));
               end loop;
            end;
         when Op_VARARG =>
            declare
               Packet : Values.Vector := Owned_Values (State);
               Table : Value;
               Size : Value;
            begin
               if Operand (K) /= 0 then
                  Table := Reg (Reg_B);
                  if Table.Kind /= Table_Kind then
                     Fail (State, "vararg table has no proper 'n'");
                  end if;
                  Size := Tables.Raw_Field (Table.Reference, "n");
                  if Size.Kind /= Integer_Kind or else
                    Size.Integer_Data < 0 or else
                    Size.Integer_Data > Integer_Value (Integer'Last / 2)
                  then
                     Fail (State, "vararg table has no proper 'n'");
                  end if;
                  --  A fixed request only reads its requested prefix. The
                  --  semantic n can be much larger without allocating that
                  --  many slots; only open results expand the complete list.
                  Count := (if Reg_C = 0 then Natural (Size.Integer_Data)
                            else Natural'Min
                              (Natural (Size.Integer_Data), Reg_C - 1));
                  if Count > Natural'Last - Reg_A then
                     Fail (State, "stack overflow");
                  end if;
                  Lua.Engine.Machine.Resize_Stack_Window
                    (State, Activation, Natural'Max
                       (Natural (Prototype.Max_Stack), Reg_A + Count));
                  for Index in 1 .. Count loop
                     Packet.Append
                       (Get (Table, (Integer_Kind, Integer_Value (Index))));
                  end loop;
               else
                  Count := (if Reg_C = 0 then
                              Activation.Vararg_Count
                            else Natural'Min
                              (Activation.Vararg_Count,
                               Reg_C - 1));
                  for Index in 1 .. Count loop
                     Packet.Append (Read_Vararg (State, Activation, Index));
                  end loop;
               end if;
               Store_Results
                 (State, Activation, Reg_A, Integer (Reg_C) - 1, Packet);
            end;
         when Op_GETVARG =>
            Right := Reg (Reg_C);
            Item := Nil_Value;
            if Integral (Right) then
               declare
                  Index : constant Integer_Value :=
                    (if Right.Kind = Integer_Kind then Right.Integer_Data
                     else Integer_Value (Right.Real_Data));
               begin
                  if Index >= 1 and then Index <=
                    Integer_Value (Activation.Vararg_Count)
                  then
                     Item := Read_Vararg (State, Activation, Positive (Index));
                  end if;
               end;
            elsif Right.Kind = String_Kind and then
              Right.Reference.Bytes = "n"
            then
               Item := (Integer_Kind,
                        Integer_Value (Activation.Vararg_Count));
            end if;
            Put (Reg_A, Item);
         when Op_ERRNNIL =>
            if Reg (Reg_A).Kind /= Nil_Kind then
               if Operand (Bx) = 0 then
                  Fail (State, "global variable already defined");
               end if;
               Left := Constant_At (State, Activation, Operand (Bx) - 1);
               Fail (State, "global '" & Image (State.Current.Memory, Left) &
                     "' already defined");
            end if;
         when Op_VARARGPREP =>
            declare
               Fixed : constant Natural := Natural (Prototype.Parameters);
               Total : constant Natural := Activation.Canonical_Top;
               Extra : constant Natural := Activation.Vararg_Count;
               Old_Base : constant Natural := Activation.Stack_Base;
               New_Base : Natural;
               Argument : Value;
            begin
               if (Prototype.Flags and 2) /= 0 then
                  --  Do not overwrite the first extra argument with the new
                  --  table until every extra has been read from its real
                  --  source slot. Vararg_Table roots construction across the
                  --  allocations needed by the table and its n field.
                  Item := New_Table (State);
                  Activation.Vararg_Table := Item.Reference;
                  Root_Barrier (State, Activation.Vararg_Table);
                  Reserve_Table (State, Item, Extra, 1);
                  for Index in 1 .. Extra loop
                     Argument := Stacks.Read
                       (State, Activation.Context,
                        Activation.Vararg_Base + Index - 1);
                     Set (State, Item, (Integer_Kind, Integer_Value (Index)),
                          Argument);
                  end loop;
                  Set (State, Item, New_String (State, "n"),
                       (Integer_Kind, Integer_Value (Extra)));
                  Put (Fixed, Item);
                  Stacks.Clear_Range
                    (Activation.Context, Old_Base + Fixed + 2,
                     Old_Base + Total);
                  Activation.Vararg_Count := 0;
                  Activation.Vararg_Base := 0;
                  Activation.Hidden_Varargs := False;
                  Lua.Engine.Machine.Resize_Stack_Window
                    (State, Activation, Natural (Prototype.Max_Stack));
                  Activation.Canonical_Top := Fixed + 1;
               else
                  --  Match ltm.buildhiddenargs: retain extras below a copied
                  --  function/fixed-parameter prefix. This shift is actual
                  --  shared stack storage, not a hidden argument packet. A
                  --  successful reserve precedes every nonallocating move.
                  New_Base := Old_Base + Total + 1;
                  Lua.Engine.Machine.Resize_Stack_Window
                    (State, Activation,
                     Total + 1 + Natural (Prototype.Max_Stack));
                  Stacks.Write
                    (State, Activation.Context, New_Base, Activation.Callee);
                  for Index in 1 .. Fixed loop
                     Argument := Stacks.Read
                       (State, Activation.Context, Old_Base + Index);
                     Stacks.Write
                       (State, Activation.Context, New_Base + Index, Argument);
                     Stacks.Clear_Range
                       (Activation.Context, Old_Base + Index,
                        Old_Base + Index);
                  end loop;
                  Activation.Stack_Base := New_Base;
                  Activation.Stack_Window_Length :=
                    Natural (Prototype.Max_Stack);
                  Activation.Hidden_Varargs := True;
                  Put (Fixed, Nil_Value);
                  Activation.Canonical_Top := Fixed;
               end if;
               Activation.Canonical_GC_Top := Natural (Prototype.Max_Stack);
               Activation.Context.Foreign_Top := Activation.Stack_Base +
                 Activation.Canonical_Top;
            end;
         when Op_EXTRAARG =>
            Fail (State, "orphan canonical extra argument");
      end case;
      return Result;
   end Step;
end Lua.Engine.Canonical;
