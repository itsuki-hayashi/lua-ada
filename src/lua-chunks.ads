with Lua.Prototypes;
with Lua.Storage.Buffers;

private package Lua.Chunks is
   type Status is (Succeeded, Bad_Format, Resource_Limit, Memory_Failure);
   type Error_Kind is
     (No_Error, Truncated, Signature_Mismatch, Version_Mismatch,
      Format_Mismatch, Header_Mismatch, Integer_Overflow,
      Invalid_String, Invalid_Constant, Invalid_Opcode, Invalid_Prototype,
      Invalid_Operand, Input_Limit, Nesting_Limit, Prototype_Limit,
      Instruction_Limit, Constant_Limit, String_Limit, Debug_Limit,
      Allocation_Refused);
   type Limits is record
      Input_Bytes : Positive := Positive'Last;
      Depth : Positive := 200;
      Prototypes : Positive := Positive'Last;
      Instructions : Positive := Positive'Last;
      Constants : Positive := Positive'Last;
      Strings : Positive := Positive'Last;
      String_Bytes : Positive := Positive'Last;
      Debug_Entries : Positive := Positive'Last;
   end record;
   --  Counters are cumulative over the entire chunk. Callers explicitly map
   --  bounded execution policy to these limits; no VM or host-global state
   --  influences standalone decoding. Mathematical C format limits remain.

   type Decode_Result is limited record
      Outcome : Status := Bad_Format;
      Error : Error_Kind := No_Error;
      Offset : Natural := 0;
      Consumed : Natural := 0;
      Code : Lua.Prototypes.Program;
   end record;
   --  Offset/Consumed count bytes from the first signature byte, independent
   --  of Source's Ada lower bound. Code owns its graph only on success.

   function Decode
     (Source : String; Memory : not null Lua.Storage.Owner_Access;
      Bounds : Limits := (others => <>)) return Decode_Result;
   --  Decode pinned native Lua 5.5 chunks into independently owned canonical
   --  data. Trailing bytes are left unread, as in lua_load. Header/operand
   --  failures and limits return typed results; partial graphs are destroyed.
   --  The borrowed owner must outlive the result and every prototype view.

   Invalid_Program : exception;
   function Encode
     (Code : in out Lua.Prototypes.Program; Strip : Boolean := False;
      Maximum_Depth : Positive := 200) return Lua.Storage.Buffers.Buffer;
   --  Encode the real canonical graph using pinned alignment, varints, tags
   --  and chunk-global string reuse. Strip omits source/debug fields.
   --  @exception Invalid_Program Invalid ownership, graph or operand metadata.
   --  @exception Lua.Storage.Allocation_Error Managed output/work refusal.
   --  The returned buffer borrows Code's owner and must die before that owner.

   function Message (Error : Error_Kind) return String;
   --  Constant diagnostic wording; caller adds source identity/location.
end Lua.Chunks;
