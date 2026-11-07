with Ada.Containers;
with Lua.Engine.Strings;
with Interfaces.C;

package body Lua.Engine.Sorting is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;

   type Sort_Phase is
     (Initialize_Sort,
      Length_Ready,
      Choose_Root,
      Sift_Root,
      Read_Sibling,
      Choose_Child,
      Extract_Maximum,
      Compared_Root,
      Continue_Sift,
      Compared_Children,
      Extract_Last,
      Shrink_Heap,
      Validate_Adjacent,
      Validate_Right,
      Validate_Order,
      Validated_Order,
      After_Read,
      After_Write,
      After_Compare);
   for Sort_Phase use
     (Initialize_Sort => 0,
      Length_Ready => 1,
      Choose_Root => 3,
      Sift_Root => 4,
      Read_Sibling => 5,
      Choose_Child => 6,
      Extract_Maximum => 7,
      Compared_Root => 8,
      Continue_Sift => 9,
      Compared_Children => 10,
      Extract_Last => 11,
      Shrink_Heap => 12,
      Validate_Adjacent => 13,
      Validate_Right => 14,
      Validate_Order => 15,
      Validated_Order => 16,
      After_Read => 100,
      After_Write => 101,
      After_Compare => 102);

   function Decode (Code : Natural) return Sort_Phase;
   function Decode (Code : Natural) return Sort_Phase is
     (case Code is
         when 0 => Initialize_Sort,
         when 1 => Length_Ready,
         when 3 => Choose_Root,
         when 4 => Sift_Root,
         when 5 => Read_Sibling,
         when 6 => Choose_Child,
         when 7 => Extract_Maximum,
         when 8 => Compared_Root,
         when 9 => Continue_Sift,
         when 10 => Compared_Children,
         when 11 => Extract_Last,
         when 12 => Shrink_Heap,
         when 13 => Validate_Adjacent,
         when 14 => Validate_Right,
         when 15 => Validate_Order,
         when 16 => Validated_Order,
         when 100 => After_Read,
         when 101 => After_Write,
         when 102 => After_Compare,
         when others => raise Program_Error with
           "invalid sort continuation phase");

   function Create
     (State : in out World; Arguments : Values.Vector) return Values.Vector
   is
      Sequence_Size, Hash_Size : Integer_Value;
      Table : Value;
   begin
      if Arguments.Is_Empty then
         Fail (State, "bad argument to create (integer expected)");
      end if;
      Sequence_Size := Strings.Integer_Argument (State, Arguments (1));
      Hash_Size := (if Arguments.Length < 2 or else
                       Arguments (2).Kind = Nil_Kind then 0 else
                       Strings.Integer_Argument (State, Arguments (2)));
      if Sequence_Size < 0 or else
        Sequence_Size > Integer_Value (Interfaces.C.int'Last) or else
        Hash_Size < 0 or else
        Hash_Size > Integer_Value (Interfaces.C.int'Last)
      then
         Fail (State, "out of range");
      elsif Hash_Size > 2 ** (Interfaces.C.int'Size - 2) then
         --  The pinned format caps its hash exponent below the C sign bit.
         --  Validate this semantic overflow before applying allocation quotas.
         Fail (State, "table overflow");
      end if;
      Table := New_Table (State);
      Reserve_Table
        (State, Table, Natural (Sequence_Size), Natural (Hash_Size));
      return One_Value (State, Table);
   end Create;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Action : Native_Action := New_Action (State);
      --  The fixed capture layout is the entire resumable algorithm state:
      --  receiver, comparator, original length, shrinking heap end, root,
      --  candidate index, candidate value, sibling, sifted value, build
      --  index, build/extract mode, and comparison result. Captures are roots;
      --  no borrowed Ada activation or untraced scratch survives a callback.
      Receiver : constant Positive := 1;
      Comparator : constant Positive := 2;
      Size : constant Positive := 3;
      Heap_End : constant Positive := 4;
      Root : constant Positive := 5;
      Child : constant Positive := 6;
      Candidate : constant Positive := 7;
      Sibling : constant Positive := 8;
      Saved : constant Positive := 9;
      Build_Index : constant Positive := 10;
      Mode : constant Positive := 11;
      Compared : constant Positive := 12;

      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length) then
            Activation.Native_Arguments (Index) else Nil_Value);
      function Item (Index : Positive) return Value is
        (Activation.Native_Captures (Index));
      function Number (Index : Positive) return Integer_Value is
        (Item (Index).Integer_Data);
      function Returned return Value is
        (if Activation.Native_Results.Is_Empty then Nil_Value else
            Activation.Native_Results.First_Element);
      procedure Save (Index : Positive; Value_Item : Value);
      procedure Save_Number (Index : Positive; Value_Item : Integer_Value);
      procedure Charge;
      procedure Resume (Next : Sort_Phase);
      function Read_At
        (Index : Integer_Value; Slot : Positive; Next : Sort_Phase)
         return Boolean;
      function Write_At
        (Index : Integer_Value; Value_Item : Value; Next : Sort_Phase)
         return Boolean;
      function Compare
        (Left, Right : Value; Next : Sort_Phase) return Boolean;
      procedure Check_Receiver;
      Count : Integer_Value;

      procedure Save (Index : Positive; Value_Item : Value) is
      begin
         Replace_Root
           (State, Activation.Native_Captures,
            Index, Value_Item);
      end Save;

      procedure Save_Number (Index : Positive; Value_Item : Integer_Value) is
      begin
         Save (Index, (Integer_Kind, Value_Item));
      end Save_Number;

      procedure Resume (Next : Sort_Phase) is
      begin
         Activation.Native_Stage := Sort_Phase'Enum_Rep (Next);
      end Resume;

      procedure Charge is
      begin
         if State.Policy = Bounded then
            if State.Steps >= State.Bounds.Instructions then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            State.Steps := State.Steps + 1;
         end if;
      end Charge;

      function Read_At
        (Index : Integer_Value; Slot : Positive; Next : Sort_Phase)
         return Boolean
      is
         Value_Item : Value;
      begin
         if Item (Receiver).Kind = Table_Kind then
            Value_Item := Get (Item (Receiver), (Integer_Kind, Index));
            if Value_Item.Kind /= Nil_Kind or else
              Metafield (State, Item (Receiver), "__index").Kind = Nil_Kind
            then
               Save (Slot, Value_Item);
               Resume (Next);
               return False;
            end if;
         end if;
         --  Persist both the destination and next phase before requesting a
         --  real access. A collection/error inside __index cannot lose state.
         Activation.Native_Index := Slot;
         Activation.Native_Aux := Sort_Phase'Enum_Rep (Next);
         Resume (After_Read);
         Action.Kind := Invoke;
         Action.Function_Value := New_Native (State, "@get");
         Action.Arguments.Append (Item (Receiver));
         Action.Arguments.Append ((Integer_Kind, Index));
         return True;
      end Read_At;

      function Write_At
        (Index : Integer_Value; Value_Item : Value; Next : Sort_Phase)
         return Boolean
      is
      begin
         if Item (Receiver).Kind = Table_Kind and then
           (Get (Item (Receiver),
                 (Integer_Kind, Index)).Kind /= Nil_Kind or else
              Metafield (State, Item (Receiver), "__newindex").Kind = Nil_Kind)
         then
            Set (State, Item (Receiver), (Integer_Kind, Index), Value_Item);
            Resume (Next);
            return False;
         end if;
         Activation.Native_Aux := Sort_Phase'Enum_Rep (Next);
         Resume (After_Write);
         Action.Kind := Invoke;
         Action.Function_Value := New_Native (State, "@set");
         Action.Arguments.Append (Item (Receiver));
         Action.Arguments.Append ((Integer_Kind, Index));
         Action.Arguments.Append (Value_Item);
         return True;
      end Write_At;

      function Compare
        (Left, Right : Value; Next : Sort_Phase) return Boolean
      is
         function Numeric (Value_Item : Value) return Lua.Numbers.Number is
           (if Value_Item.Kind = Integer_Kind then
               (Lua.Numbers.Integer_Number, Value_Item.Integer_Data) else
               (Lua.Numbers.Real_Number, Value_Item.Real_Data));
      begin
         if Item (Comparator).Kind = Nil_Kind then
            if Left.Kind in Integer_Kind | Real_Kind and then
              Right.Kind in Integer_Kind | Real_Kind
            then
               Save (Compared, (Boolean_Kind,
                                Lua.Numbers.Less (Numeric (Left),
                                                  Numeric (Right))));
               Resume (Next);
               return False;
            elsif Left.Kind = String_Kind and then Right.Kind = String_Kind
            then
               Save (Compared, (Boolean_Kind,
                                Left.Reference.Bytes < Right.Reference.Bytes));
               Resume (Next);
               return False;
            end if;
            Action.Operator := Lua.Lexers.Less;
         else
            Action.Function_Value := Item (Comparator);
         end if;
         Activation.Native_Aux := Sort_Phase'Enum_Rep (Next);
         Resume (After_Compare);
         Action.Kind := Invoke;
         Action.Arguments.Append (Left);
         Action.Arguments.Append (Right);
         return True;
      end Compare;

      procedure Check_Receiver is
         Table_Item : constant Value := Arg (1);
      begin
         if Table_Item.Kind /= Table_Kind and then
           (Metafield (State, Table_Item, "__index").Kind = Nil_Kind or else
            Metafield (State, Table_Item, "__newindex").Kind = Nil_Kind or else
            (Table_Item.Kind /= String_Kind and then
               Metafield (State, Table_Item, "__len").Kind = Nil_Kind))
         then
            Fail (State, "bad argument to sort (table expected)");
         end if;
      end Check_Receiver;
   begin
      loop
         Charge;
         case Decode (Activation.Native_Stage) is
            when Initialize_Sort =>
               Check_Receiver;
               Activation.Native_Captures.Set_Length (12);
               Save (Receiver, Arg (1));
               Save (Comparator, Arg (2));
               if Arg (1).Kind = Table_Kind and then
                 Metafield (State, Arg (1), "__len").Kind = Nil_Kind
               then
                  Copy_Roots
                    (State, Activation.Native_Results,
                     One_Value (State, (Integer_Kind, Integer_Value
                       (Table_Length (Arg (1))))));
                  Resume (Length_Ready);
               else
                  Resume (Length_Ready);
                  Action.Kind := Invoke;
                  Action.Operator := Lua.Lexers.Length;
                  Action.Arguments.Append (Arg (1));
                  return Action;
               end if;
            when Length_Ready =>
               Count := Strings.Integer_Argument (State, Returned);
               if Count <= 1 then
                  return Action;
               elsif Count >= Integer_Value (Interfaces.C.int'Last) then
                  Fail (State, "array too big");
               elsif Item (Comparator).Kind not in Nil_Kind | Closure_Kind |
                 Native_Closure_Kind | Native_Kind_Value |
                 Foreign_Function_Kind
               then
                  Fail (State, "function expected");
               end if;
               --  Pinned sort normalizes the public C stack to receiver and
               --  comparator only for a nontrivial sequence. Retain this
               --  actual branch decision for its zero-result return hook;
               --  querying length again later could repeat a user callback.
               Activation.Native_Return_First := 3;
               Save_Number (Size, Count);
               Save_Number (Heap_End, Count);
               Save_Number (Build_Index, Count / 2);
               Save_Number (Mode, 0);
               Resume (Choose_Root);
            when Choose_Root =>
               --  Build bottom-up, then repeatedly move the maximum to the
               --  final unsorted position. Each sift needs constant state;
               --  no recursion or table-sized temporary allocation exists.
               if Number (Mode) = 0 then
                  if Number (Build_Index) = 0 then
                     Save_Number (Mode, 1);
                  else
                     Save_Number (Root, Number (Build_Index));
                     Save_Number (Build_Index, Number (Build_Index) - 1);
                     if Read_At (Number (Root), Saved, Sift_Root) then
                        return Action;
                     end if;
                  end if;
               elsif Number (Heap_End) <= 1 then
                  Save_Number (Root, 2);
                  Resume (Validate_Adjacent);
               elsif Read_At (1, Candidate, Extract_Maximum) then
                  return Action;
               end if;
            when Sift_Root =>
               Save_Number (Child, 2 * Number (Root));
               if Number (Child) > Number (Heap_End) then
                  if Write_At (Number (Root), Item (Saved), Choose_Root) then
                     return Action;
                  end if;
               elsif Read_At (Number (Child), Candidate, Read_Sibling) then
                  return Action;
               end if;
            when Read_Sibling =>
               if Number (Child) < Number (Heap_End) then
                  if Read_At (Number (Child) + 1, Sibling, Choose_Child) then
                     return Action;
                  end if;
               elsif Compare (Item (Saved), Item (Candidate), Compared_Root)
               then
                  return Action;
               end if;
            when Choose_Child =>
               if Compare (Item (Candidate), Item (Sibling), Compared_Children)
               then
                  return Action;
               end if;
            when Compared_Children =>
               if Truth (Item (Compared)) then
                  Save_Number (Child, Number (Child) + 1);
                  Save (Candidate, Item (Sibling));
               end if;
               if Compare (Item (Saved), Item (Candidate), Compared_Root) then
                  return Action;
               end if;
            when Compared_Root =>
               if Truth (Item (Compared)) then
                  if Write_At
                    (Number (Root), Item (Candidate), Continue_Sift)
                  then
                     return Action;
                  end if;
               elsif Write_At (Number (Root), Item (Saved), Choose_Root) then
                  return Action;
               end if;
            when Continue_Sift =>
               Save_Number (Root, Number (Child));
               Resume (Sift_Root);
            when Extract_Maximum =>
               if Read_At (Number (Heap_End), Saved, Extract_Last) then
                  return Action;
               end if;
            when Extract_Last =>
               if Write_At (Number (Heap_End), Item (Candidate), Shrink_Heap)
               then
                  return Action;
               end if;
            when Shrink_Heap =>
               Save_Number (Heap_End, Number (Heap_End) - 1);
               Save_Number (Root, 1);
               Resume (Sift_Root);
            when Validate_Adjacent =>
               --  A strict comparator cannot order a later sorted element
               --  before its predecessor. Detect contradictory always-true
               --  results without an unbounded partition loop.
               if Number (Root) > Number (Size) then
                  return Action;
               elsif Read_At (Number (Root) - 1, Candidate, Validate_Right)
               then
                  return Action;
               end if;
            when Validate_Right =>
               if Read_At (Number (Root), Sibling, Validate_Order) then
                  return Action;
               end if;
            when Validate_Order =>
               if Compare (Item (Sibling), Item (Candidate), Validated_Order)
               then
                  return Action;
               end if;
            when Validated_Order =>
               if Truth (Item (Compared)) then
                  Fail (State, "invalid order function for sorting");
               end if;
               Save_Number (Root, Number (Root) + 1);
               Resume (Validate_Adjacent);
            when After_Read =>
               Save (Activation.Native_Index, Returned);
               Resume (Decode (Activation.Native_Aux));
            when After_Write =>
               Resume (Decode (Activation.Native_Aux));
            when After_Compare =>
               Save (Compared, (Boolean_Kind, Truth (Returned)));
               Resume (Decode (Activation.Native_Aux));
         end case;
      end loop;
   end Advance;
end Lua.Engine.Sorting;
