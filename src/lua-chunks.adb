with Ada.Containers;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with Lua.Numbers;
with Lua.Opcodes;
with Lua.Storage.Vectors;

package body Lua.Chunks is
   --  This codec is deliberately independent of execution. The input cursor
   --  only borrows Source; all retained strings, nodes, vectors and work lists
   --  use the caller's owner. A failed decode closes its partially published
   --  graph before returning a typed result. It never creates Lua heap values.
   use Lua.Prototypes;
   use type Ada.Containers.Count_Type;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Lua.Storage.Owner_Access;
   use type Lua.Numbers.Integer_Value;
   use type Lua.Numbers.Real_Value;
   use type Interfaces.Integer_8;
   subtype Word is Interfaces.Unsigned_64;
   type Native_Bytes is array (0 .. 3) of Byte;
   for Native_Bytes'Component_Size use 8;
   function Native_View is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_32, Native_Bytes);
   function Integer_Bits is new Ada.Unchecked_Conversion
     (Lua.Numbers.Integer_Value, Word);
   function Integer_From is new Ada.Unchecked_Conversion
     (Word, Lua.Numbers.Integer_Value);
   function Number_Bits is new Ada.Unchecked_Conversion
     (Lua.Numbers.Real_Value, Word);
   function Number_From is new Ada.Unchecked_Conversion
     (Word, Lua.Numbers.Real_Value);
   function Signed_Byte is new Ada.Unchecked_Conversion
     (Byte, Interfaces.Integer_8);
   function Unsigned_Byte is new Ada.Unchecked_Conversion
     (Interfaces.Integer_8, Byte);
   Little : constant Boolean := Native_View (16#0102_0304#) (0) = 4;
   C_Int_Bytes : constant Positive := Interfaces.C.int'Size / 8;
   Signature : constant String := ASCII.ESC & "Lua";
   Header_Data : constant String :=
     Character'Val (16#19#) & Character'Val (16#93#) &
     ASCII.CR & ASCII.LF & Character'Val (16#1A#) & ASCII.LF;

   package Id_Lists is new Lua.Storage.Vectors (String_Id);
   package Flags is new Lua.Storage.Vectors (Boolean);

   procedure Validate
     (Code : Program; Item, Parent : Prototype_Access;
      Depth, Maximum_Depth : Positive; Seen : in out Flags.Vector);

   function Message (Error : Error_Kind) return String is
   begin
      return (case Error is
         when No_Error => "",
         when Truncated => "truncated chunk",
         when Truncated_Fixed_Buffer => "truncated fixed buffer",
         when Signature_Mismatch => "not a binary chunk",
         when Version_Mismatch => "version mismatch",
         when Format_Mismatch => "format mismatch",
         when Header_Mismatch => "numeric format or size mismatch",
         when Integer_Overflow => "integer overflow",
         when Invalid_String => "invalid string index or payload",
         when Invalid_Constant => "invalid constant",
         when Invalid_Opcode => "invalid opcode",
         when Invalid_Prototype => "invalid prototype metadata",
         when Invalid_Operand => "invalid instruction operand",
         when Input_Limit => "binary input byte limit exceeded",
         when Nesting_Limit => "binary nesting limit exceeded",
         when Prototype_Limit => "binary prototype limit exceeded",
         when Instruction_Limit => "binary instruction limit exceeded",
         when Constant_Limit => "binary constant limit exceeded",
         when String_Limit => "binary string limit exceeded",
         when Debug_Limit => "binary debug limit exceeded",
         when Allocation_Refused => "not enough memory");
   end Message;

   procedure Validate
     (Code : Program; Item, Parent : Prototype_Access;
      Depth, Maximum_Depth : Positive; Seen : in out Flags.Vector)
   is
      use Lua.Opcodes;
      Stack : Natural;
      Count : Natural;
      procedure Require (Condition : Boolean);
      procedure Require (Condition : Boolean) is
      begin
         if not Condition then
            raise Invalid_Program;
         end if;
      end Require;
      procedure Register (Index : Natural);
      procedure Register (Index : Natural) is
      begin
         Require (Index < Stack);
      end Register;
      procedure Constant_Index (Index : Natural; Text : Boolean := False);
      procedure Constant_Index (Index : Natural; Text : Boolean := False) is
      begin
         Require (Index < Natural (Item.Constants.Length));
         if Text then
            Require (Item.Constants (Index + 1).Kind = String_Constant);
         end if;
      end Constant_Index;
      procedure Upvalue_Index (Index : Natural);
      procedure Upvalue_Index (Index : Natural) is
      begin
         Require (Index < Natural (Item.Upvalues.Length));
      end Upvalue_Index;
      procedure String_Index (Id : String_Id; Nullable : Boolean := True);
      procedure String_Index (Id : String_Id; Nullable : Boolean := True) is
      begin
         Require ((Nullable or else Id /= No_String) and then
                  Id <= String_Id (String_Count (Code)));
      end String_Index;
   begin
      --  Ownership is checked before dereferencing child metadata. The flat
      --  registry supplies stable indices, so one mark rejects both cycles and
      --  multiply owned subtrees without following either during destruction.
      Require (Depth <= Maximum_Depth and then Owns (Code, Item));
      Require (not Seen (Item.Node_Index));
      Seen.Replace_Element (Item.Node_Index, True);
      Stack := Natural (Item.Max_Stack);
      Count := Natural (Item.Code.Length);
      Require (Stack >= 2 and then Natural (Item.Parameters) <= Stack and then
               Count > 0 and then Item.Upvalues.Length <= 255);
      Require ((Item.Flags and not Byte'(3)) = 0);
      Require (Item.First_Line <= Item.Last_Line);
      String_Index (Item.Source);
      for Data of Item.Constants loop
         if Data.Kind = String_Constant then
            String_Index (Data.String_Data, Nullable => False);
         end if;
      end loop;
      for Capture of Item.Upvalues loop
         String_Index (Capture.Name);
         Require (Capture.Kind <= 4);
         if Parent /= null then
            Require
              (if Capture.In_Stack then Capture.Index < Parent.Max_Stack
               else Natural (Capture.Index) < Natural
                 (Parent.Upvalues.Length));
         end if;
      end loop;
      Require (Item.Lines.Is_Empty or else
               Item.Lines.Length = Item.Code.Length);
      for Data of Item.Locals loop
         String_Index (Data.Name);
         Require (Data.Start_PC <= Data.End_PC and then Data.End_PC <= Count);
      end loop;
      declare
         Previous : Integer := -1;
         Markers : Natural := 0;
      begin
         for Data of Item.Absolute_Lines loop
            Require (Data.PC < Count and then Integer (Data.PC) > Previous);
            Require (not Item.Lines.Is_Empty and then
                     Item.Lines (Data.PC + 1) = -128);
            Previous := Integer (Data.PC);
         end loop;
         for Line_Delta of Item.Lines loop
            if Line_Delta = -128 then Markers := Markers + 1; end if;
         end loop;
         Require (Markers = Natural (Item.Absolute_Lines.Length));
      end;
      declare
         Line : Long_Long_Integer := Long_Long_Integer (Item.First_Line);
         Absolute_Index : Natural := 0;
      begin
         --  PC/marker agreement alone does not make debug data safe. Bound
         --  each reconstructed line before runtime lookup uses an Integer;
         --  malicious deltas must not overflow or produce negative locations.
         for Line_Delta of Item.Lines loop
            if Line_Delta = -128 then
               Absolute_Index := Absolute_Index + 1;
               Line := Long_Long_Integer
                 (Item.Absolute_Lines (Absolute_Index).Line);
            else
               Line := Line + Long_Long_Integer (Line_Delta);
            end if;
            Require (Line in 0 .. Long_Long_Integer (Interfaces.C.int'Last));
         end loop;
      end;
      for PC in 1 .. Count loop
         declare
            Instruction : constant Lua.Opcodes.Word := Item.Code (PC);
            Op : Opcode;
            A, B, C, K : Natural := 0;
            function Field_Value (Part : Field) return Integer;
            function Field_Value (Part : Field) return Integer is
               Decoded : constant Operand_Result := Get (Instruction, Part);
            begin
               Require (Decoded.Status = Success);
               return Decoded.Value;
            end Field_Value;
            procedure Jump (Target : Long_Long_Integer);
            procedure Jump (Target : Long_Long_Integer) is
            begin
               Require (Target >= 0 and then
                        Target < Long_Long_Integer (Count));
            end Jump;
            function Next_Is (Expected : Opcode) return Boolean;
            function Next_Is (Expected : Opcode) return Boolean is
              (PC < Count and then Valid (Item.Code (PC + 1)) and then
               Operation (Item.Code (PC + 1)) = Expected);
         begin
            Require (Valid (Instruction));
            Op := Operation (Instruction);
            if Describe (Op).Mode not in IAx | IsJ then
               A := Natural (Field_Value (Lua.Opcodes.A));
            end if;
            if Describe (Op).Mode = IABC then
               B := Natural (Field_Value (Lua.Opcodes.B));
               C := Natural (Field_Value (Lua.Opcodes.C));
               K := Natural (Field_Value (Lua.Opcodes.K));
            end if;
            if Op not in Op_JMP | Op_EXTRAARG | Op_RETURN0 |
              Op_VARARGPREP | Op_SETTABUP | Op_CLOSE | Op_RETURN
            then
               Register (A);
            end if;
            case Op is
               when Op_MOVE | Op_GETI | Op_GETFIELD | Op_SELF |
                 Op_ADDI | Op_SHLI | Op_SHRI | Op_UNM | Op_BNOT |
                 Op_NOT | Op_LEN | Op_TESTSET => Register (B);
               when Op_ADD .. Op_SHR | Op_GETTABLE =>
                  Register (B);
                  Register (C);
               when Op_GETVARG => Register (C);
               when Op_ADDK .. Op_BXORK =>
                  Register (B);
                  Constant_Index (C);
                  Require (Item.Constants (C + 1).Kind in
                    Integer_Constant | Number_Constant);
                  if Op in Op_BANDK .. Op_BXORK then
                     Require (Item.Constants (C + 1).Kind = Integer_Constant);
                  end if;
               when Op_EQ | Op_LT | Op_LE | Op_MMBIN => Register (B);
               when Op_EQK | Op_MMBINK => Constant_Index (B);
               when Op_GETUPVAL | Op_SETUPVAL => Upvalue_Index (B);
               when Op_GETTABUP =>
                  Upvalue_Index (B);
                  Constant_Index (C, Text => True);
               when Op_SETTABUP =>
                  Upvalue_Index (A);
                  Constant_Index (B, Text => True);
               when Op_SETTABLE => Register (B);
               when Op_SETFIELD => Constant_Index (B, Text => True);
               when Op_LOADK =>
                  Constant_Index (Natural (Field_Value (Bx)));
               when Op_CLOSURE =>
                  Require (Natural (Field_Value (Bx)) <
                           Natural (Item.Children.Length));
               when Op_LOADNIL => Require (A + B < Stack);
               when Op_CONCAT => Require (B >= 2 and then A + B <= Stack);
               when Op_FORPREP | Op_FORLOOP | Op_TFORPREP | Op_TFORLOOP =>
                  --  Lua 5.5's numeric controls occupy three slots. Generic
                  --  loops additionally retain their closing/control slots.
                  Require (A + (if Op in Op_FORPREP | Op_FORLOOP then 2
                                else 3) < Stack);
                  if Op = Op_FORPREP then
                     Jump (Long_Long_Integer (PC) +
                           Long_Long_Integer (Field_Value (Bx)) + 1);
                  elsif Op = Op_TFORPREP then
                     Jump (Long_Long_Integer (PC) +
                           Long_Long_Integer (Field_Value (Bx)));
                  else
                     Jump (Long_Long_Integer (PC) -
                           Long_Long_Integer (Field_Value (Bx)));
                  end if;
               when Op_CALL | Op_TAILCALL =>
                  Require (B = 0 or else A + B <= Stack);
                  if Op = Op_CALL then
                     Require (C = 0 or else C = 1 or else A + C - 1 <= Stack);
                  end if;
               when Op_RETURN =>
                  Require (A <= Stack and then
                    (B = 0 or else B = 1 or else A + B - 1 <= Stack));
               when Op_TFORCALL =>
                  Require (A + Natural'Max (6, C + 3) <= Stack);
                  Require (Next_Is (Op_TFORLOOP));
                  Require (Get (Item.Code (PC + 1), Lua.Opcodes.A).Value = A);
               when Op_VARARG =>
                  Require (Item.Flags /= 0);
                  Require (C = 0 or else C = 1 or else A + C - 1 <= Stack);
                  if K /= 0 then Register (B); end if;
               when Op_CLOSE => Require (A <= Stack);
               when Op_ERRNNIL =>
                  if Field_Value (Bx) /= 0 then
                     Constant_Index (Natural (Field_Value (Bx)) - 1,
                                     Text => True);
                  end if;
               when Op_JMP =>
                  Jump (Long_Long_Integer (PC) +
                        Long_Long_Integer (Field_Value (SJ)));
               when Op_VARARGPREP => null;
               when others => null;
            end case;
            if Op in Op_GETFIELD | Op_SELF then
               Constant_Index (C, Text => True);
            end if;
            if Op = Op_SELF then Require (A + 1 < Stack); end if;
            --  Arithmetic always has a following fallback instruction. The
            --  fast path skips it; the slow path reads the previous word to
            --  recover its result register. Neither half is free-standing.
            if Op in Op_ADD .. Op_SHR then
               Require (Next_Is (Op_MMBIN));
            elsif Op in Op_ADDK .. Op_BXORK then
               Require (Next_Is (Op_MMBINK));
            elsif Op in Op_ADDI | Op_SHLI | Op_SHRI then
               Require (Next_Is (Op_MMBINI));
            elsif Op in Op_MMBIN | Op_MMBINI | Op_MMBINK then
               Require (PC > 1);
               declare
                  Previous : constant Opcode :=
                    Operation (Item.Code (PC - 1));
               begin
                  Require (C in 6 .. 17);
                  Require
                    ((Op = Op_MMBIN and then Previous in Op_ADD .. Op_SHR) or
                     (Op = Op_MMBINK and then Previous in
                       Op_ADDK .. Op_BXORK) or
                     (Op = Op_MMBINI and then Previous in
                       Op_ADDI | Op_SHLI | Op_SHRI));
               end;
            end if;
            if Op in Op_SETTABUP | Op_SETTABLE | Op_SETI | Op_SETFIELD then
               if K = 0 then Register (C); else Constant_Index (C); end if;
            end if;
            if Op in Op_LOADKX | Op_NEWTABLE or else
              (Op = Op_SETLIST and then Field_Value (Lua.Opcodes.K) /= 0)
            then
               Require (Next_Is (Op_EXTRAARG));
               if Op = Op_LOADKX then
                  Constant_Index (Natural (Get (Item.Code (PC + 1),
                    Ax).Value));
               end if;
            end if;
            if Op = Op_SETLIST then
               B := Natural (Field_Value (VB));
               Require (B = 0 or else A + B < Stack);
            end if;
            if Op = Op_EXTRAARG then
               Require (PC > 1);
               declare
                  Previous : constant Opcode :=
                    Operation (Item.Code (PC - 1));
               begin
                  Require (Previous in Op_LOADKX | Op_NEWTABLE or else
                    (Previous = Op_SETLIST and then
                     Get (Item.Code (PC - 1), Lua.Opcodes.K).Value /= 0));
               end;
            end if;
            if Op = Op_TFORPREP then
               declare
                  Target : constant Positive :=
                    PC + Natural (Field_Value (Bx)) + 1;
               begin
                  Require (Valid (Item.Code (Target)) and then
                    Operation (Item.Code (Target)) = Op_TFORCALL and then
                    Get (Item.Code (Target), Lua.Opcodes.A).Value = A);
               end;
            end if;
            if Describe (Op).Tests then Require (Next_Is (Op_JMP)); end if;
            if Op = Op_LFALSESKIP then Require (PC + 1 < Count); end if;
         end;
      end loop;
      for Child of Item.Children loop
         Validate (Code, Child, Item, Depth + 1, Maximum_Depth, Seen);
      end loop;
   end Validate;

   function Decode
     (Source : String; Memory : not null Lua.Storage.Owner_Access;
      Bounds : Limits := (others => <>)) return Decode_Result
   is
      Input : Lua.Inputs.Source;
   begin
      Input.Borrow (Source'Address, Source'Length);
      return Decode (Input, Memory, Bounds);
   end Decode;

   function Decode
     (Source : in out Lua.Inputs.Source;
      Memory : not null Lua.Storage.Owner_Access;
      Bounds : Limits := (others => <>); Fixed_Buffer : Boolean := False)
      return Decode_Result
   is
   begin
      return Result : Decode_Result do
         Set_Owner (Result.Code, Memory);
         declare
            Position : Natural := 0;
            Node_Total, Instruction_Total, Constant_Total : Natural := 0;
            String_Total, String_Bytes, Debug_Total : Natural := 0;
            Saved : Id_Lists.Vector;
            Seen : Flags.Vector;
            Failure : exception;
            procedure Reject (Error : Error_Kind);
            procedure Reject (Error : Error_Kind) is
            begin
               Result.Error := Error;
               Result.Offset := Position;
               raise Failure;
            end Reject;
            procedure Charge
              (Total : in out Natural; Added : Natural;
               Maximum : Positive; Error : Error_Kind);
            procedure Charge
              (Total : in out Natural; Added : Natural;
               Maximum : Positive; Error : Error_Kind)
            is
            begin
               if Added > Maximum - Total then Reject (Error); end if;
               Total := Total + Added;
            end Charge;
            procedure Require_Bytes
              (Count : Natural; Fixed_Block : Boolean := False);
            procedure Require_Bytes
              (Count : Natural; Fixed_Block : Boolean := False) is
            begin
               if Count > Natural'Last - Position then
                  Reject (Integer_Overflow);
               elsif Fixed_Block and then Fixed_Buffer then
                  if not Source.Ensure_Block (Position + 1, Count) then
                     Reject (Truncated_Fixed_Buffer);
                  end if;
               elsif not Source.Ensure (Position + Count) then
                  Reject (Truncated);
               end if;
            end Require_Bytes;
            procedure Require_Array (Count : Natural; Width : Positive);
            procedure Require_Array (Count : Natural; Width : Positive) is
            begin
               if not Source.Streaming and then not Fixed_Buffer and then
                 Count > (Source.Available - Position) / Width
               then
                  Reject (Truncated);
               elsif Count > Natural'Last / Width then
                  Reject (Integer_Overflow);
               end if;
               Require_Bytes (Count * Width, Fixed_Block => True);
            end Require_Array;
            function Read_Byte return Byte;
            function Read_Byte return Byte is
               Item : Byte;
            begin
               Require_Bytes (1);
               Item := Character'Pos (Source.Element (Position + 1));
               Position := Position + 1;
               return Item;
            end Read_Byte;
            function Read_Fixed (Size : Positive) return Word;
            function Read_Fixed (Size : Positive) return Word is
               Value : Word := 0;
               Item : Byte;
            begin
               for Index in 0 .. Size - 1 loop
                  Item := Read_Byte;
                  Value := Value or Interfaces.Shift_Left
                    (Word (Item), (if Little then Index else Size - Index - 1)
                     * 8);
               end loop;
               return Value;
            end Read_Fixed;
            function Variable (Maximum : Word) return Word;
            function Variable (Maximum : Word) return Word is
               Value : Word := 0;
               Item : Byte;
            begin
               loop
                  Item := Read_Byte;
                  --  Check before the shift, then after adding the next seven
                  --  bits. A malformed overlong varint cannot wrap a count or
                  --  turn its remaining bytes into an unrelated chunk field.
                  if Value > Interfaces.Shift_Right (Maximum, 7) then
                     Reject (Integer_Overflow);
                  end if;
                  Value := Interfaces.Shift_Left (Value, 7) or
                    Word (Item and 16#7F#);
                  if Value > Maximum then Reject (Integer_Overflow); end if;
                  exit when (Item and 16#80#) = 0;
               end loop;
               return Value;
            end Variable;
            function Count return Natural;
            function Count return Natural is
              (Natural (Variable (Word (Interfaces.C.int'Last))));
            procedure Align (Size : Positive);
            procedure Align (Size : Positive) is
               Ignored : Byte;
               pragma Unreferenced (Ignored);
            begin
               while Position mod Size /= 0 loop
                  Ignored := Read_Byte;
               end loop;
            end Align;
            procedure Literal (Text : String; Error : Error_Kind);
            procedure Literal (Text : String; Error : Error_Kind) is
            begin
               for Item of Text loop
                  if Read_Byte /= Character'Pos (Item) then
                     Reject (Error);
                  end if;
               end loop;
            end Literal;
            function Text return String_Id;
            function Text return String_Id is
               Size : constant Word := Variable (2 ** 63 - 1);
               Index : Word;
               Id : String_Id;
               Length : Natural;
            begin
               --  Saved indices are chunk-global and refer to encounter order,
               --  including strings in earlier child prototypes. Interned IDs
               --  are content identities instead: keeping a separate Saved
               --  list preserves indices even if an input repeats a payload.
               if Size = 0 then
                  Index := Variable (Word'Last);
                  if Index = 0 then return No_String; end if;
                  if Index > Word (Saved.Length) then
                     Reject (Invalid_String);
                  end if;
                  return Saved (Positive (Index));
               end if;
               if Size > Word (Natural'Last - Position) then
                  Reject (Truncated);
               end if;
               Length := Natural (Size - 1);
               --  Pinned lundump copies short strings (up to 40 bytes), even
               --  in B mode. Only long strings require a single fixed block;
               --  the managed Ada model copies either form after acquisition.
               Require_Bytes (Natural (Size), Fixed_Block => Length > 40);
               Charge (String_Total, 1, Bounds.Strings, String_Limit);
               Charge (String_Bytes, Length, Bounds.String_Bytes,
                 String_Limit);
               if Length = 0 then
                  Id := Intern (Result.Code, "");
               else
                  declare
                     procedure Save (Bytes : String);
                     procedure Save (Bytes : String) is
                     begin
                        Id := Intern (Result.Code, Bytes);
                     end Save;
                  begin
                     Source.Query (Position + 1, Length, Save'Access);
                  end;
               end if;
               Position := Position + Length;
               if Read_Byte /= 0 then Reject (Invalid_String); end if;
               Saved.Append (Id);
               return Id;
            end Text;
            function Load (Depth : Positive) return Prototype_Access;
            function Load (Depth : Positive) return Prototype_Access is
               Node : Prototype_Access;
               N : Natural;
               Tag, B : Byte;
               Encoded : Word;
               Id : String_Id;
            begin
               if Depth > Bounds.Depth then Reject (Nesting_Limit); end if;
               Charge (Node_Total, 1, Bounds.Prototypes, Prototype_Limit);
               Node := New_Prototype (Result.Code);
               --  Publish the node in Program's flat owner list before filling
               --  it. Later truncation, limits or callback refusal therefore
               --  has exactly one cleanup path, including unfinished children.
               Node.First_Line := Count;
               Node.Last_Line := Count;
               Node.Parameters := Read_Byte;
               Node.Flags := Read_Byte and not Byte'(4);
               Node.Max_Stack := Read_Byte;
               N := Count;
               Charge (Instruction_Total, N, Bounds.Instructions,
                 Instruction_Limit);
               --  Alignment is relative to the first signature byte, not this
               --  prototype. Each array word is decoded arithmetically; native
               --  Ada record layout never determines the serialized format.
               Align (4);
               Require_Array (N, 4);
               Node.Code.Reserve_Capacity (Ada.Containers.Count_Type (N));
               for Index in 1 .. N loop
                  declare
                     Instruction : constant Lua.Opcodes.Word :=
                       Lua.Opcodes.Word (Read_Fixed (4));
                  begin
                     if not Lua.Opcodes.Valid (Instruction) then
                        Reject (Invalid_Opcode);
                     end if;
                     Node.Code.Append (Instruction);
                  end;
               end loop;
               N := Count;
               Charge (Constant_Total, N, Bounds.Constants, Constant_Limit);
               --  Constants preserve integer classification and raw binary64
               --  bits. Reinterpreting through Real arithmetic would destroy
               --  signed zero or NaN payloads before the encoder sees them.
               if not Source.Streaming and then
                 N > Source.Available - Position
               then
                  Reject (Truncated);
               end if;
               for Index in 1 .. N loop
                  Tag := Read_Byte;
                  case Tag is
                     when 0 => Node.Constants.Append (Constant_Value'(Kind
                       => Nil_Constant));
                     when 1 | 17 => Node.Constants.Append
                       (Constant_Value'(Boolean_Constant, Tag = 17));
                     when 3 =>
                        Encoded := Variable (Word'Last);
                        Node.Constants.Append
                          (Constant_Value'(Integer_Constant,
                          Integer_From (if (Encoded and 1) = 0 then
                            Interfaces.Shift_Right (Encoded, 1)
                            else not Interfaces.Shift_Right (Encoded, 1))));
                     when 19 => Node.Constants.Append
                       (Constant_Value'(Number_Constant, Number_From
                         (Read_Fixed (8))));
                     when 4 | 20 =>
                        Id := Text;
                        if Id = No_String then
                           Reject (Invalid_Constant);
                        end if;
                        Node.Constants.Append
                          (Constant_Value'(String_Constant, Id, Tag = 20));
                     when others => Reject (Invalid_Constant);
                  end case;
               end loop;
               N := Count;
               if N > 255 then Reject (Invalid_Prototype); end if;
               for Index in 1 .. N loop
                  B := Read_Byte;
                  if B > 1 then Reject (Invalid_Prototype); end if;
                  declare
                     Capture : Upvalue;
                  begin
                     Capture.In_Stack := B = 1;
                     Capture.Index := Read_Byte;
                     Capture.Kind := Read_Byte;
                     Node.Upvalues.Append (Capture);
                  end;
               end loop;
               N := Count;
               if N > Bounds.Prototypes - Node_Total then
                  Reject (Prototype_Limit);
               end if;
               if not Source.Streaming and then
                 N > Source.Available - Position
               then
                  Reject (Truncated);
               end if;
               for Index in 1 .. N loop
                  Node.Children.Append (Load (Depth + 1));
               end loop;
               Node.Source := Text;
               --  Debug information follows children and source in 5.5. These
               --  PC offsets describe canonical words, never private packets.
               N := Count;
               Charge (Debug_Total, N, Bounds.Debug_Entries, Debug_Limit);
               if Source.Streaming or else Fixed_Buffer then
                  Require_Array (N, 1);
               end if;
               for Index in 1 .. N loop
                  Node.Lines.Append (Signed_Byte (Read_Byte));
               end loop;
               N := Count;
               Charge (Debug_Total, N, Bounds.Debug_Entries, Debug_Limit);
               if N > 0 then
                  Align (C_Int_Bytes);
                  if Source.Streaming or else Fixed_Buffer then
                     Require_Array (N, C_Int_Bytes * 2);
                  end if;
                  for Index in 1 .. N loop
                     declare
                        PC : constant Word := Read_Fixed (C_Int_Bytes);
                        Line : constant Word := Read_Fixed (C_Int_Bytes);
                     begin
                        if PC > Word (Natural'Last) or else
                          Line > Word (Natural'Last)
                        then
                           Reject (Invalid_Prototype);
                        end if;
                        Node.Absolute_Lines.Append (Absolute_Line'(Natural
                          (PC), Natural (Line)));
                     end;
                  end loop;
               end if;
               N := Count;
               Charge (Debug_Total, N, Bounds.Debug_Entries, Debug_Limit);
               for Index in 1 .. N loop
                  declare
                     Item : Local;
                  begin
                     Item.Name := Text;
                     Item.Start_PC := Count;
                     Item.End_PC := Count;
                     Node.Locals.Append (Item);
                  end;
               end loop;
               N := Count;
               --  Pinned loading treats any nonzero name-count marker as
               --  "all upvalues have names", rather than trusting that count.
               Node.Upvalue_Names_Present := N /= 0;
               if N /= 0 then
                  N := Natural (Node.Upvalues.Length);
                  Charge (Debug_Total, N, Bounds.Debug_Entries, Debug_Limit);
                  for Index in 1 .. N loop
                     Id := Text;
                     declare
                        procedure Name (Capture : in out Upvalue);
                        procedure Name (Capture : in out Upvalue) is
                        begin
                           Capture.Name := Id;
                        end Name;
                     begin
                        Node.Upvalues.Update_Element (Index, Name'Access);
                     end;
                  end loop;
               end if;
               return Node;
            end Load;
            Main_Node : Prototype_Access;
            Captures : Byte;
            Expected : Word;
         begin
            Saved.Set_Owner (Memory);
            Seen.Set_Owner (Memory);
            if Source.Available > Bounds.Input_Bytes then
               Reject (Input_Limit);
            end if;
            Literal (Signature, Signature_Mismatch);
            if Read_Byte /= 16#55# then Reject (Version_Mismatch); end if;
            if Read_Byte /= 0 then Reject (Format_Mismatch); end if;
            Literal (Header_Data, Header_Mismatch);
            --  Lua chunks are native-format files. Exact width, byte order and
            --  numeric sentinels must agree before any prototype is decoded;
            --  accepting only the version byte would misread hostile counts.
            if Read_Byte /= Byte (C_Int_Bytes) then
               Reject (Header_Mismatch);
            end if;
            Expected := (0 - Word'(16#5678#)) and
              Interfaces.Shift_Right (Word'Last, (8 - C_Int_Bytes) * 8);
            if Read_Fixed (C_Int_Bytes) /= Expected then
               Reject (Header_Mismatch);
            end if;
            if Read_Byte /= 4 or else Read_Fixed (4) /= 16#1234_5678# then
               Reject (Header_Mismatch);
            end if;
            if Read_Byte /= 8 or else
              Read_Fixed (8) /= 0 - Word'(16#5678#)
            then
               Reject (Header_Mismatch);
            end if;
            if Read_Byte /= 8 or else
              Read_Fixed (8) /= Number_Bits (-370.5)
            then
               Reject (Header_Mismatch);
            end if;
            Captures := Read_Byte;
            Main_Node := Load (1);
            if Natural (Captures) /= Natural (Main_Node.Upvalues.Length) then
               Reject (Invalid_Prototype);
            end if;
            Set_Root (Result.Code, Main_Node);
            Seen.Append (False, Ada.Containers.Count_Type (Prototype_Count
              (Result.Code)));
            begin
               --  A syntactically decodable word stream is not sufficient:
               --  check all register/constant/capture and paired-word bounds
               --  before publishing success to a future execution backend.
               Validate (Result.Code, Main_Node, null, 1, Bounds.Depth, Seen);
            exception
               when Invalid_Program => Reject (Invalid_Operand);
            end;
            Result.Outcome := Succeeded;
            Result.Consumed := Position;
         exception
            when Failure =>
               Result.Outcome := (if Result.Error in Input_Limit .. Debug_Limit
                                  then Resource_Limit else Bad_Format);
               Close (Result.Code);
            when Lua.Inputs.Input_Limit =>
               Result.Outcome := Resource_Limit;
               Result.Error := Input_Limit;
               Result.Offset := Position;
               Close (Result.Code);
            when Lua.Storage.Allocation_Error =>
               Result.Outcome := Memory_Failure;
               Result.Error := Allocation_Refused;
               Result.Offset := Position;
               Close (Result.Code);
            when Program_Error =>
               if Lua.Storage.Refusal_Pending (Memory.all) then
                  Result.Outcome := Memory_Failure;
                  Result.Error := Allocation_Refused;
                  Result.Offset := Position;
                  Close (Result.Code);
               else
                  Close (Result.Code);
                  raise;
               end if;
            when others =>
               --  Guarded reader failure is returned through Ada, so every
               --  partial graph can be released before the outer C boundary
               --  receives its real callback status and error stack object.
               Close (Result.Code);
               raise;
         end;
      end return;
   end Decode;

   function Encode
     (Code : in out Program; Strip : Boolean := False;
      Maximum_Depth : Positive := 200;
      Root_Node : Prototype_Access := null)
      return Lua.Storage.Buffers.Buffer
   is
      Memory : constant Lua.Storage.Owner_Access := Owner_Of (Code);
      Seen : Flags.Vector;
      Saved : Id_Lists.Vector;
      Serial : String_Id := 0;
      Selected : constant Prototype_Access :=
        (if Root_Node = null then Root (Code) else Root_Node);
   begin
      if Memory = null or else Selected = null then
         raise Invalid_Program;
      end if;
      Seen.Set_Owner (Memory);
      Saved.Set_Owner (Memory);
      Seen.Append (False, Ada.Containers.Count_Type (Prototype_Count (Code)));
      --  Validate before allocating output. Invalid input never exposes a
      --  partially emitted chunk; allocator refusal likewise destroys Output
      --  through its normal controlled-buffer finalization.
      Validate (Code, Selected, null, 1, Maximum_Depth, Seen);
      Saved.Append (No_String, Ada.Containers.Count_Type (String_Count
        (Code)));
      return Output : Lua.Storage.Buffers.Buffer do
         Output.Set_Owner (Memory);
         declare
            procedure Write_Byte (Item : Byte);
            procedure Write_Byte (Item : Byte) is
            begin
               Output.Append (Character'Val (Item));
            end Write_Byte;
            procedure Fixed (Item : Word; Size : Positive);
            procedure Fixed (Item : Word; Size : Positive) is
            begin
               for Index in 0 .. Size - 1 loop
                  Write_Byte (Byte (Interfaces.Shift_Right
                    (Item, (if Little then Index else Size - Index - 1) * 8)
                     and 16#FF#));
               end loop;
            end Fixed;
            procedure Variable (Item : Word);
            procedure Variable (Item : Word) is
               type Bytes is array (Positive range 1 .. 10) of Byte;
               Varint_Bytes : Bytes;
               First : Positive := Varint_Bytes'Last;
               Value : Word := Item;
            begin
               --  This fixed ten-byte workspace covers every unsigned64
               --  value without allocating a temporary proportional to it.
               Varint_Bytes (First) := Byte (Value and 16#7F#);
               Value := Interfaces.Shift_Right (Value, 7);
               while Value /= 0 loop
                  First := First - 1;
                  Varint_Bytes (First) := Byte (Value and 16#7F#) or 16#80#;
                  Value := Interfaces.Shift_Right (Value, 7);
               end loop;
               for Index in First .. Varint_Bytes'Last loop
                  Write_Byte (Varint_Bytes (Index));
               end loop;
            end Variable;
            procedure Align (Size : Positive);
            procedure Align (Size : Positive) is
            begin
               while Output.Length mod Size /= 0 loop
                  Write_Byte (0);
               end loop;
            end Align;
            procedure Text (Id : String_Id);
            procedure Text (Id : String_Id) is
               procedure Content (Bytes : String);
               procedure Content (Bytes : String) is
               begin
                  Output.Append (Bytes);
               end Content;
            begin
               --  One serial map spans the entire dump. Sources, local names
               --  and constants reuse earlier byte payloads as C Lua does.
               if Id = No_String then
                  Variable (0); Variable (0);
               elsif Saved (Positive (Id)) /= No_String then
                  Variable (0); Variable (Word (Saved (Positive (Id))));
               else
                  Variable (Word (String_Length (Code, Id)) + 1);
                  Query_String (Code, Id, Content'Access);
                  Write_Byte (0);
                  Serial := Serial + 1;
                  Saved.Replace_Element (Positive (Id), Serial);
               end if;
            end Text;
            procedure Dump (Node : Prototype_Access);
            procedure Dump (Node : Prototype_Access) is
            begin
               --  Preserve the pinned field order, including source/debug
               --  after nested prototypes. Stripping changes only nullable
               --  source and debug arrays; lexical capture descriptors remain.
               Variable (Word (Node.First_Line)); Variable (Word
                 (Node.Last_Line));
               Write_Byte (Node.Parameters); Write_Byte (Node.Flags and
                 not Byte'(4));
               Write_Byte (Node.Max_Stack);
               Variable (Word (Node.Code.Length)); Align (4);
               for Instruction of Node.Code loop
                  Fixed (Word (Instruction), 4);
               end loop;
               Variable (Word (Node.Constants.Length));
               for Item of Node.Constants loop
                  case Item.Kind is
                     when Nil_Constant => Write_Byte (0);
                     when Boolean_Constant => Write_Byte (if
                       Item.Boolean_Data then 17 else 1);
                     when Integer_Constant =>
                        Write_Byte (3);
                        Variable (if Item.Integer_Data >= 0 then 2 *
                          Integer_Bits (Item.Integer_Data)
                                  else 2 * (not Integer_Bits
                                    (Item.Integer_Data)) + 1);
                     when Number_Constant => Write_Byte (19); Fixed
                       (Number_Bits (Item.Number_Data), 8);
                     when String_Constant =>
                        Write_Byte (if Item.Long_String then 20 else 4);
                        Text (Item.String_Data);
                  end case;
               end loop;
               Variable (Word (Node.Upvalues.Length));
               for Item of Node.Upvalues loop
                  Write_Byte (Boolean'Pos (Item.In_Stack));
                  Write_Byte (Item.Index); Write_Byte (Item.Kind);
               end loop;
               Variable (Word (Node.Children.Length));
               for Child of Node.Children loop Dump (Child); end loop;
               Text (if Strip then No_String else Node.Source);
               Variable (if Strip then 0 else Word (Node.Lines.Length));
               if not Strip then
                  for Item of Node.Lines loop
                     Write_Byte (Unsigned_Byte (Item));
                  end loop;
               end if;
               Variable (if Strip then 0 else Word
                 (Node.Absolute_Lines.Length));
               if not Strip and then not Node.Absolute_Lines.Is_Empty then
                  Align (C_Int_Bytes);
                  for Item of Node.Absolute_Lines loop
                     Fixed (Word (Item.PC), C_Int_Bytes); Fixed (Word
                       (Item.Line), C_Int_Bytes);
                  end loop;
               end if;
               Variable (if Strip then 0 else Word (Node.Locals.Length));
               if not Strip then
                  for Item of Node.Locals loop
                     Text (Item.Name);
                     Variable (Word (Item.Start_PC));
                     Variable (Word (Item.End_PC));
                  end loop;
               end if;
               Variable (if Strip or else not Node.Upvalue_Names_Present
                         then 0 else Word (Node.Upvalues.Length));
               if not Strip and then Node.Upvalue_Names_Present then
                  for Item of Node.Upvalues loop Text (Item.Name); end loop;
               end if;
            end Dump;
         begin
            Output.Append (Signature); Write_Byte (16#55#); Write_Byte (0);
            Output.Append (Header_Data);
            Write_Byte (Byte (C_Int_Bytes)); Fixed (0 - Word'(16#5678#),
              C_Int_Bytes);
            Write_Byte (4); Fixed (16#1234_5678#, 4);
            Write_Byte (8); Fixed (0 - Word'(16#5678#), 8);
            Write_Byte (8); Fixed (Number_Bits (-370.5), 8);
            Write_Byte (Byte (Selected.Upvalues.Length));
            Dump (Selected);
         end;
      end return;
   end Encode;
end Lua.Chunks;
