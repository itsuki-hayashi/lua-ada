with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Chunks;
with Lua.Numbers;
with Lua.Opcodes;
with Lua.Prototypes; use Lua.Prototypes;
with Lua.Storage;
with Lua.Storage.Buffers;
with Test_Support;

package body Lua.Chunk_Tests is
   use type Interfaces.Unsigned_64;
   use type Interfaces.Integer_8;
   use type Lua.Numbers.Integer_Value;
   use type Lua.Storage.Byte_Count;
   use type Lua.Chunks.Status;
   use type Lua.Chunks.Error_Kind;
   subtype Word is Interfaces.Unsigned_64;
   function Bits is new Ada.Unchecked_Conversion
     (Lua.Numbers.Real_Value, Word);
   function Number is new Ada.Unchecked_Conversion
     (Word, Lua.Numbers.Real_Value);

   procedure Tiny
     (Code : in out Program; Memory : in out Lua.Storage.Owner;
      Value : Lua.Numbers.Integer_Value := 42);
   procedure Tiny
     (Code : in out Program; Memory : in out Lua.Storage.Owner;
      Value : Lua.Numbers.Integer_Value := 42)
   is
      Node : Prototype_Access;
   begin
      Set_Owner (Code, Lua.Storage.Reference (Memory));
      Node := New_Prototype (Code);
      Set_Root (Code, Node);
      Node.Constants.Append (Constant_Value'(Integer_Constant, Value));
      Node.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_LOADK));
      Node.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN1));
   end Tiny;

   procedure Emit_Borrowed
     (Code : in out Program; Process : not null access procedure (Text :
       String));
   procedure Emit_Borrowed
     (Code : in out Program; Process : not null access procedure (Text :
       String))
   is
      Bytes : Lua.Storage.Buffers.Buffer := Lua.Chunks.Encode (Code);
   begin
      Bytes.Query (Process);
   end Emit_Borrowed;

   procedure Basic_Roundtrip;
   procedure Arbitrary_Source_Bounds;
   procedure Zigzag_Extremes;
   procedure Floating_Bits;
   procedure Nullable_Strings;
   procedure Binary_Strings;
   procedure Shared_Strings;
   procedure Strip_Metadata;
   procedure Debug_Alignment;
   procedure Debug_Line_Range;
   procedure Truncation_Cleanup;
   procedure Signature_Error;
   procedure Version_Error;
   procedure Numeric_Header_Error;
   procedure Opcode_Error;
   procedure Operand_Error;
   procedure Input_Quota;
   procedure Nesting_Quota;
   procedure String_Quota;
   procedure Allocator_Refusal;
   procedure Allocation_Transactions;
   procedure Missing_Arithmetic_Fallback;
   procedure Orphan_Extra_Argument;
   procedure Trailing_Bytes;
   procedure Cyclic_Graph_Cleanup;
   procedure Foreign_Root_Rejected;
   procedure Program_Ownership_Move;
   procedure Program_Self_Move;
   procedure Selected_Nested_Root;

   procedure Basic_Roundtrip is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded, "basic decode");
         Assert (Root (Result.Code).Constants (1).Integer_Data = 42,
                 "canonical constant data");
         Assert (Result.Consumed = Text'Length, "chunk consumption");
      end Check;
   begin
      --  A hand-built LOADK/RETURN1 program exercises the format independently
      --  of any parser, compiler or currently executable backend.
      Tiny (Code, Memory);
      Emit_Borrowed (Code, Check'Access);
   end Basic_Roundtrip;

   procedure Arbitrary_Source_Bounds is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Rebased : constant String (4_096 .. 4_095 + Text'Length) := Text;
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Rebased, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded and then
                 Result.Consumed = Rebased'Length, "arbitrary input bounds");
      end Check;
   begin
      --  Offset accounting is relative to signature byte zero, not to Ada's
      --  positive lower bound. A normal string slice must decode identically.
      Tiny (Code, Memory);
      Emit_Borrowed (Code, Check'Access);
   end Arbitrary_Source_Bounds;

   procedure Zigzag_Extremes is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded, "extreme integers");
         Assert (Root (Result.Code).Constants (1).Integer_Data =
                   Lua.Numbers.Integer_Value'First and then
                 Root (Result.Code).Constants (2).Integer_Data =
                   Lua.Numbers.Integer_Value'Last, "zigzag signed boundaries");
      end Check;
   begin
      --  Signed minimum maps to unsigned64'Last; no signed negation or
      --  intermediate multiplication may overflow while encoding it.
      Tiny (Code, Memory, Lua.Numbers.Integer_Value'First);
      Root (Code).Constants.Append (Constant_Value'
        (Integer_Constant, Lua.Numbers.Integer_Value'Last));
      Emit_Borrowed (Code, Check'Access);
   end Zigzag_Extremes;

   procedure Floating_Bits is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded, "floating constants");
         Assert (Bits (Root (Result.Code).Constants (2).Number_Data) = 2 ** 63,
                 "negative zero payload");
         Assert (Bits (Root (Result.Code).Constants (3).Number_Data) =
                   16#7FF8_0000_0000_1234#, "NaN payload bits");
      end Check;
   begin
      --  Native binary64 constants must preserve every bit, including values
      --  for which ordinary numeric equality cannot establish a round trip.
      Tiny (Code, Memory);
      Root (Code).Constants.Append
        (Constant_Value'(Number_Constant, Number (2 ** 63)));
      Root (Code).Constants.Append (Constant_Value'
        (Number_Constant, Number (16#7FF8_0000_0000_1234#)));
      Emit_Borrowed (Code, Check'Access);
   end Floating_Bits;

   procedure Nullable_Strings is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Empty : String_Id;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded, "empty source decode");
         Assert (Root (Result.Code).Source /= No_String and then
                 String_Length (Result.Code, Root (Result.Code).Source) = 0,
                 "empty string must not become nullable string");
      end Check;
   begin
      --  Both encodings occupy two bytes but differ: empty is size1+NUL;
      --  nullable is size0+index0. Preserve that semantic distinction.
      Tiny (Code, Memory);
      Empty := Intern (Code, "");
      Assert (Empty /= No_String, "interned empty identity");
      Root (Code).Source := Empty;
      Emit_Borrowed (Code, Check'Access);
   end Nullable_Strings;

   procedure Binary_Strings is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Text_Id : String_Id;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
         Id : String_Id;
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded,
           "binary string decode");
         Id := Root (Result.Code).Constants (2).String_Data;
         Assert (String_Length (Result.Code, Id) = 3 and then
                 String_Element (Result.Code, Id, 2) = ASCII.NUL and then
                 String_Element (Result.Code, Id, 3) = Character'Val (255),
                 "binary string payload");
      end Check;
   begin
      --  Length-delimited payloads contain arbitrary bytes; only the separate
      --  final NUL is the dump terminator.
      Tiny (Code, Memory);
      Text_Id := Intern (Code, "a" & ASCII.NUL & Character'Val (255));
      Root (Code).Constants.Append
        (Constant_Value'(String_Constant, Text_Id, False));
      Emit_Borrowed (Code, Check'Access);
   end Binary_Strings;

   procedure Shared_Strings is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Child : Prototype_Access;
      Id : String_Id;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
         Node : Prototype_Access;
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded,
           "shared string decode");
         Node := Root (Result.Code);
         Assert (String_Count (Result.Code) = 1 and then
                 Node.Source = Node.Children (1).Source and then
                 Node.Source = Node.Upvalues (1).Name,
                 "chunk-global string reuse");
      end Check;
   begin
      --  The first occurrence is inside a child; later parent/debug fields
      --  must reuse its saved index across prototype boundaries.
      Tiny (Code, Memory);
      Id := Intern (Code, "@same-source");
      Root (Code).Source := Id;
      Root (Code).Upvalues.Append
        (Upvalue'(In_Stack => True, Index => 0, Kind => 0, Name => Id));
      Child := New_Prototype (Code);
      Child.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN0));
      Child.Source := Id;
      Root (Code).Children.Append (Child);
      Emit_Borrowed (Code, Check'Access);
   end Shared_Strings;

   procedure Strip_Metadata is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Encoded : Lua.Storage.Buffers.Buffer;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded, "stripped decode");
         Assert (Root (Result.Code).Source = No_String and then
                 Root (Result.Code).Lines.Is_Empty and then
                 not Root (Result.Code).Upvalue_Names_Present,
                 "stripped metadata omitted");
      end Check;
   begin
      --  Stripping removes source, line tables, locals and upvalue-name
      --  markers while preserving executable canonical data.
      Tiny (Code, Memory);
      Root (Code).Source := Intern (Code, "@strip");
      Root (Code).Lines.Append (1, 2);
      Encoded := Lua.Chunks.Encode (Code, Strip => True);
      Encoded.Query (Check'Access);
   end Strip_Metadata;

   procedure Debug_Alignment is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Outcome = Lua.Chunks.Succeeded,
           "debug aligned decode");
         Assert (Root (Result.Code).Absolute_Lines (1).Line = 301 and then
                 Root (Result.Code).Locals (1).End_PC = 2,
                 "native int pairs and local PC bounds");
      end Check;
   begin
      --  A sentinel line delta requires a native aligned (pc,line) pair.
      --  Following local records protect the offset after that alignment.
      Tiny (Code, Memory);
      Root (Code).Lines.Append (-128);
      Root (Code).Lines.Append (0);
      Root (Code).Absolute_Lines.Append (Absolute_Line'(0, 301));
      Root (Code).Locals.Append (Local'(Intern (Code, "value"), 0, 2));
      Emit_Borrowed (Code, Check'Access);
   end Debug_Alignment;

   procedure Debug_Line_Range is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Output : Lua.Storage.Buffers.Buffer;
      Rejected : Boolean := False;
   begin
      --  The array shape is valid, but a negative delta from source line zero
      --  would produce an invalid runtime location. Reject before publishing
      --  the chunk rather than relying on a later checked Ada conversion.
      Tiny (Code, Memory);
      Root (Code).Lines.Append (-1);
      Root (Code).Lines.Append (0);
      begin
         Output := Lua.Chunks.Encode (Code);
      exception
         when Lua.Chunks.Invalid_Program => Rejected := True;
      end;
      Assert (Rejected and then Output.Is_Empty,
              "invalid reconstructed debug line accepted");
   end Debug_Line_Range;

   procedure Truncation_Cleanup is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Baseline : constant Lua.Storage.Byte_Count :=
           Lua.Storage.Statistics (Memory).Live_Blocks;
      begin
         for Length in 0 .. Text'Length - 1 loop
            declare
               Result : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
                 (Text (Text'First .. Text'First + Length - 1),
                  Lua.Storage.Reference (Memory));
            begin
               Assert (Result.Outcome = Lua.Chunks.Bad_Format,
                       "truncated prefix rejected");
            end;
            Assert (Lua.Storage.Statistics (Memory).Live_Blocks = Baseline,
                    "partial decode leaked managed storage");
         end loop;
      end Check;
   begin
      --  Cut at every byte boundary, including within a header/varint/string.
      --  Every rejected partial graph must release all nodes and work buffers.
      Tiny (Code, Memory);
      Root (Code).Source := Intern (Code, "@partial");
      Emit_Borrowed (Code, Check'Access);
   end Truncation_Cleanup;

   procedure Signature_Error is
      Memory : Lua.Storage.Owner;
      Result : constant Lua.Chunks.Decode_Result :=
        Lua.Chunks.Decode ("not Lua", Lua.Storage.Reference (Memory));
   begin
      --  Invalid signature is a format result, not a parser/VM exception.
      Assert (Result.Outcome = Lua.Chunks.Bad_Format and then
              Result.Error = Lua.Chunks.Signature_Mismatch,
                "signature failure");
   end Signature_Error;

   procedure Version_Error is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Data : Lua.Storage.Buffers.Buffer;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Error = Lua.Chunks.Version_Mismatch,
           "version failure");
      end Check;
   begin
      --  Version byte five belongs to the pinned 5.5 header, not the source
      --  name or Lua release patch number.
      Tiny (Code, Memory); Data := Lua.Chunks.Encode (Code);
      Data.Replace_Element (5, Character'Val (16#54#));
      Data.Query (Check'Access);
   end Version_Error;

   procedure Numeric_Header_Error is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Data : Lua.Storage.Buffers.Buffer;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Error = Lua.Chunks.Header_Mismatch,
                 "native numeric header mismatch");
      end Check;
   begin
      --  Reject an incompatible native int width before interpreting payloads.
      Tiny (Code, Memory); Data := Lua.Chunks.Encode (Code);
      Data.Replace_Element (13, Character'Val (1));
      Data.Query (Check'Access);
   end Numeric_Header_Error;

   procedure Opcode_Error is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Data : Lua.Storage.Buffers.Buffer;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
      begin
         Assert (Result.Error = Lua.Chunks.Invalid_Opcode,
                 "invalid opcode controlled rejection");
      end Check;
   begin
      --  The small fixture's first word starts at byte49 after aligned code.
      --  Replace its low opcode byte with the reserved ID127.
      Tiny (Code, Memory); Data := Lua.Chunks.Encode (Code);
      Data.Replace_Element (49, Character'Val (127));
      Data.Query (Check'Access);
   end Opcode_Error;

   procedure Operand_Error is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Rejected : Boolean := False;
      Output : Lua.Storage.Buffers.Buffer;
   begin
      --  Word encoding alone accepts register255. The prototype has only two
      --  registers, so structural encoding must reject the actual operand.
      Tiny (Code, Memory);
      Root (Code).Code.Replace_Element (1, Lua.Opcodes.Set
        (Root (Code).Code (1), Lua.Opcodes.A, 255).Value);
      begin Output := Lua.Chunks.Encode (Code);
      exception when Lua.Chunks.Invalid_Program => Rejected := True; end;
      Assert (Rejected and then Output.Is_Empty, "bad register bound");
   end Operand_Error;

   procedure Input_Quota is
      Memory : Lua.Storage.Owner;
      Result : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
        ("too long", Lua.Storage.Reference (Memory),
         (Input_Bytes => 1, others => <>));
   begin
      --  Host input quota precedes any signature read or graph allocation.
      Assert (Result.Outcome = Lua.Chunks.Resource_Limit and then
              Result.Error = Lua.Chunks.Input_Limit, "input quota result");
   end Input_Quota;

   procedure Nesting_Quota is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Child, Grandchild : Prototype_Access;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
           (Text, Lua.Storage.Reference (Memory), (Depth => 2, others => <>));
      begin
         Assert (Result.Outcome = Lua.Chunks.Resource_Limit and then
                 Result.Error = Lua.Chunks.Nesting_Limit, "nested quota");
      end Check;
   begin
      --  A valid three-node tree exceeds only the explicitly smaller nesting
      --  profile. It remains valid format, not a syntax corruption result.
      Tiny (Code, Memory);
      Child := New_Prototype (Code); Grandchild := New_Prototype (Code);
      Child.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN0));
      Grandchild.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN0));
      Root (Code).Children.Append (Child); Child.Children.Append (Grandchild);
      Emit_Borrowed (Code, Check'Access);
   end Nesting_Quota;

   procedure String_Quota is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
           (Text, Lua.Storage.Reference (Memory),
            (String_Bytes => 1, others => <>));
      begin
         Assert (Result.Outcome = Lua.Chunks.Resource_Limit and then
                 Result.Error = Lua.Chunks.String_Limit, "string quota");
      end Check;
   begin
      --  Source/debug bytes also belong to cumulative owned string storage.
      --  They cannot bypass a host limit just because no constant uses them.
      Tiny (Code, Memory); Root (Code).Source := Intern (Code, "ab");
      Emit_Borrowed (Code, Check'Access);
   end String_Quota;

   procedure Allocator_Refusal is
      Memory, Refusing : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Refusing));
      begin
         Assert (Result.Outcome = Lua.Chunks.Memory_Failure,
                 "managed allocation classification");
         Assert (Lua.Storage.Statistics (Refusing).Live_Blocks = 0,
                 "refused decoding leaked storage");
      end Check;
   begin
      --  Refuse the first graph/work allocation through a separate owner;
      --  this must return memory failure without damaging the source program.
      Tiny (Code, Memory); Lua.Storage.Set_Failure_Countdown (Refusing, 0);
      Emit_Borrowed (Code, Check'Access);
   end Allocator_Refusal;

   procedure Allocation_Transactions is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Child : Prototype_Access;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Completed : Boolean := False;
         Refusals : Natural := 0;
      begin
         --  Move the refusal across every growing allocation. This exercises
         --  node publication, interning, work lists and copied owned vectors,
         --  rather than checking only refusal before the first node exists.
         for Countdown in 0 .. 100 loop
            declare
               Attempt : Lua.Storage.Owner;
            begin
               Lua.Storage.Set_Failure_Countdown
                 (Attempt, Lua.Storage.Byte_Count (Countdown));
               declare
                  Result : constant Lua.Chunks.Decode_Result :=
                    Lua.Chunks.Decode (Text, Lua.Storage.Reference (Attempt));
               begin
                  Completed := Result.Outcome = Lua.Chunks.Succeeded;
                  Assert (Completed or else
                    Result.Outcome = Lua.Chunks.Memory_Failure,
                    "refusal changed the chunk's validity");
                  if not Completed then Refusals := Refusals + 1; end if;
               end;
               Assert (Lua.Storage.Statistics (Attempt).Live_Blocks = 0,
                       "partial graph allocation transaction leaked");
            end;
            exit when Completed;
         end loop;
         Assert (Completed and then Refusals > 10,
                 "allocation campaign did not reach a successful decode");
      end Check;
   begin
      --  Distinct parent/child strings and an upvalue keep several managed
      --  structures live when later growth fails. The source graph is separate
      --  from each disposable decoding owner and must survive all attempts.
      Tiny (Code, Memory);
      Root (Code).Source := Intern (Code, "@parent allocation transaction");
      Root (Code).Upvalues.Append (Upvalue'(Name => Intern
        (Code, "_ENV"), others => <>));
      Child := New_Prototype (Code);
      Child.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN0));
      Child.Source := Intern (Code, "@child allocation transaction");
      Root (Code).Children.Append (Child);
      Emit_Borrowed (Code, Check'Access);
   end Allocation_Transactions;

   procedure Missing_Arithmetic_Fallback is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Output : Lua.Storage.Buffers.Buffer;
      Rejected : Boolean := False;
   begin
      --  ADD's fast path skips the following MMBIN word, while its slow path
      --  uses that fallback. An ordinary RETURN1 cannot occupy the same slot.
      Tiny (Code, Memory);
      Root (Code).Code.Replace_Element
        (1, Lua.Opcodes.Create (Lua.Opcodes.Op_ADD));
      begin
         Output := Lua.Chunks.Encode (Code);
      exception
         when Lua.Chunks.Invalid_Program => Rejected := True;
      end;
      Assert (Rejected and then Output.Is_Empty,
              "arithmetic instruction lost its fallback pairing");
   end Missing_Arithmetic_Fallback;

   procedure Orphan_Extra_Argument is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Output : Lua.Storage.Buffers.Buffer;
      Rejected : Boolean := False;
   begin
      --  EXTRAARG is data for an adjacent owner instruction, not a standalone
      --  executable opcode. Reject it even though its numeric opcode is valid.
      Tiny (Code, Memory);
      Root (Code).Code.Replace_Element
        (1, Lua.Opcodes.Create (Lua.Opcodes.Op_EXTRAARG));
      begin
         Output := Lua.Chunks.Encode (Code);
      exception
         when Lua.Chunks.Invalid_Program => Rejected := True;
      end;
      Assert (Rejected and then Output.Is_Empty,
              "orphan extra argument accepted as executable code");
   end Orphan_Extra_Argument;

   procedure Trailing_Bytes is
      Memory : Lua.Storage.Owner;
      Code : Program;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Result : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
           (Text & "trailing", Lua.Storage.Reference (Memory));
      begin
         --  lua_load consumes one chunk rather than requiring stream EOF.
         --  Report its exact consumed length so a caller controls any framing.
         Assert (Result.Outcome = Lua.Chunks.Succeeded and then
                 Result.Consumed = Text'Length, "trailing stream framing");
      end Check;
   begin
      Tiny (Code, Memory);
      Emit_Borrowed (Code, Check'Access);
   end Trailing_Bytes;

   procedure Cyclic_Graph_Cleanup is
      Memory : Lua.Storage.Owner;
      Rejected : Boolean := False;
   begin
      --  A malformed graph is rejected, and flat ownership still frees its
      --  only node exactly once rather than recursively following the cycle.
      declare
         Code : Program;
         Output : Lua.Storage.Buffers.Buffer;
      begin
         Tiny (Code, Memory); Root (Code).Children.Append (Root (Code));
         begin Output := Lua.Chunks.Encode (Code);
         exception when Lua.Chunks.Invalid_Program => Rejected := True; end;
         Assert (Output.Is_Empty, "cyclic graph published bytes");
      end;
      Assert (Rejected and then Lua.Storage.Statistics (Memory).Live_Blocks
        = 0,
              "cyclic graph cleanup");
   end Cyclic_Graph_Cleanup;

   procedure Foreign_Root_Rejected is
      Memory : Lua.Storage.Owner;
      First, Other : Program;
      Rejected : Boolean := False;
   begin
      --  Sharing an allocator does not make two programs share ownership.
      --  A root must name its own flat registry, not a neighbor's node.
      Tiny (First, Memory); Tiny (Other, Memory);
      begin Set_Root (First, Root (Other));
      exception when Program_Error => Rejected := True; end;
      Assert (Rejected, "foreign program root accepted");
   end Foreign_Root_Rejected;

   procedure Program_Ownership_Move is
      Memory : Lua.Storage.Owner;
      Source, Target : Program;
      Original : Prototype_Access;
      Text : String_Id;
   begin
      --  Both graphs already own storage. Refuse every new allocation, then
      --  transfer the source: addresses/string IDs must survive, the replaced
      --  graph must die, and only the target may claim the transferred nodes.
      Tiny (Source, Memory, 42);
      Tiny (Target, Memory, 99);
      Original := Root (Source);
      Text := Intern (Source, "moved" & ASCII.NUL & "bytes");
      Original.Source := Text;
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      Move (Target, Source);
      Assert (Root (Source) = null and then Prototype_Count (Source) = 0,
              "move source still owns a graph");
      Assert (Root (Target) = Original and then Owns (Target, Original) and
              then not Owns (Source, Original), "moved registry identity");
      Assert (Prototype_At (Target, Original.Node_Index) = Original,
              "moved registry lookup");
      Assert (String_Length (Target, Text) = 11 and then
              String_Element (Target, Text, 6) = ASCII.NUL,
              "moved interned byte storage");
      Lua.Storage.Clear_Failures (Memory);
      Tiny (Source, Memory, 7);
      Assert (Root (Source).Constants (1).Integer_Data = 7 and then
              Root (Target).Constants (1).Integer_Data = 42,
              "moved source cannot be reused independently");
   end Program_Ownership_Move;

   procedure Program_Self_Move is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Original : Prototype_Access;
      Baseline : Lua.Storage.Byte_Count;
   begin
      --  A self move is useful in generic ownership plumbing. It must retain
      --  its graph/accounting rather than closing its own source.
      Tiny (Code, Memory);
      Original := Root (Code);
      Baseline := Lua.Storage.Statistics (Memory).Live_Blocks;
      Move (Code, Code);
      Assert (Root (Code) = Original and then Owns (Code, Original) and then
              Lua.Storage.Statistics (Memory).Live_Blocks = Baseline,
              "self move changed program ownership");
   end Program_Self_Move;

   procedure Selected_Nested_Root is
      Memory : Lua.Storage.Owner;
      Code : Program;
      Parent, Child : Prototype_Access;
      Bytes : Lua.Storage.Buffers.Buffer;
      procedure Check (Text : String);
      procedure Check (Text : String) is
         Decoded : constant Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Text, Lua.Storage.Reference (Memory));
         Node : constant Prototype_Access := Root (Decoded.Code);
      begin
         Assert (Decoded.Outcome = Lua.Chunks.Succeeded and then
                 Node.First_Line = 7 and then
                 Natural (Node.Upvalues.Length) = 1,
                 "selected function header/debug metadata");
         Assert (Node.Constants (1).Integer_Data = 99,
                 "dump selected the containing main function");
      end Check;
   begin
      --  string.dump may select a nested closure while the containing graph
      --  remains shared by live frames. Encode that actual subtree without
      --  temporarily replacing its immutable program root or capture metadata.
      Tiny (Code, Memory);
      Parent := Root (Code);
      Child := New_Prototype (Code);
      Child.First_Line := 7;
      Child.Last_Line := 7;
      Child.Constants.Append (Constant_Value'(Integer_Constant, 99));
      Child.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_LOADK));
      Child.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN1));
      Child.Upvalues.Append (Upvalue'
        (True, 0, 1, Intern (Code, "captured")));
      Parent.Children.Append (Child);
      Bytes := Lua.Chunks.Encode (Code, Root_Node => Child);
      Bytes.Query (Check'Access);
      Assert (Root (Code) = Parent and then
              Parent.Constants (1).Integer_Data = 42,
              "subtree dump mutated its shared containing graph");
   end Selected_Nested_Root;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "chunk: basic roundtrip",
        Basic_Roundtrip'Access);
      Test_Support.Add (Suite, "chunk: arbitrary bounds",
        Arbitrary_Source_Bounds'Access);
      Test_Support.Add (Suite, "chunk: signed varint limits",
        Zigzag_Extremes'Access);
      Test_Support.Add (Suite, "chunk: floating bit payloads",
        Floating_Bits'Access);
      Test_Support.Add (Suite, "chunk: nullable strings",
        Nullable_Strings'Access);
      Test_Support.Add (Suite, "chunk: binary string bytes",
        Binary_Strings'Access);
      Test_Support.Add (Suite, "chunk: shared saved strings",
        Shared_Strings'Access);
      Test_Support.Add (Suite, "chunk: stripped metadata",
        Strip_Metadata'Access);
      Test_Support.Add (Suite, "chunk: debug alignment",
        Debug_Alignment'Access);
      Test_Support.Add (Suite, "chunk: reconstructed line range",
        Debug_Line_Range'Access);
      Test_Support.Add (Suite, "chunk: truncated graph cleanup",
        Truncation_Cleanup'Access);
      Test_Support.Add (Suite, "chunk: invalid signature",
        Signature_Error'Access);
      Test_Support.Add (Suite, "chunk: wrong version", Version_Error'Access);
      Test_Support.Add (Suite, "chunk: native layout check",
        Numeric_Header_Error'Access);
      Test_Support.Add (Suite, "chunk: invalid opcode", Opcode_Error'Access);
      Test_Support.Add (Suite, "chunk: invalid operands",
        Operand_Error'Access);
      Test_Support.Add (Suite, "chunk: source quota", Input_Quota'Access);
      Test_Support.Add (Suite, "chunk: nesting quota", Nesting_Quota'Access);
      Test_Support.Add (Suite, "chunk: string quota", String_Quota'Access);
      Test_Support.Add (Suite, "chunk: allocator refusal",
        Allocator_Refusal'Access);
      Test_Support.Add (Suite, "chunk: allocation transactions",
        Allocation_Transactions'Access);
      Test_Support.Add (Suite, "chunk: arithmetic fallback pairing",
        Missing_Arithmetic_Fallback'Access);
      Test_Support.Add (Suite, "chunk: orphan extra argument",
        Orphan_Extra_Argument'Access);
      Test_Support.Add (Suite, "chunk: trailing byte framing",
        Trailing_Bytes'Access);
      Test_Support.Add (Suite, "chunk: cyclic model cleanup",
        Cyclic_Graph_Cleanup'Access);
      Test_Support.Add (Suite, "chunk: root ownership",
        Foreign_Root_Rejected'Access);
      Test_Support.Add (Suite, "chunk: ownership transfer",
        Program_Ownership_Move'Access);
      Test_Support.Add (Suite, "chunk: self ownership transfer",
        Program_Self_Move'Access);
      Test_Support.Add (Suite, "chunk: selected nested root",
        Selected_Nested_Root'Access);
   end Register;
end Lua.Chunk_Tests;
