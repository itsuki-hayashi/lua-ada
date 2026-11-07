package Lua.Engine.Call_Names is
   type Name_Kind is
     (Unknown, Local_Binding, Upvalue_Binding, Constant_Value,
      Global_Field, Table_Field, Method_Call, Iterator_Call, Metamethod_Call,
      Hook_Call);
   type Identity is record
      Item : Value;
      Kind : Name_Kind := Unknown;
   end record;
   type Borrowed_Identity is record
      Item : Byte_String;
      Kind : Name_Kind := Unknown;
   end record;
   function View_From_Caller
     (State : in out World; Caller : Frame_Access)
      return Borrowed_Identity;
   --  Infer through the same reaching-definition walk without allocating.
   --  Bytes are NUL-terminated immutable graph/constant storage, or static
   --  markers; the caller must retain its actual activation/prototype owner.
   function Name_Image (Item : Borrowed_Identity) return String;
   --  Render the C name prefix for Lua/debug/error text, ending at the first
   --  NUL. Raw C metadata can borrow the original address without this scan;
   --  the underlying field key retains all of its counted bytes.
   function Finalizer_Name return Byte_String;
   --  Borrow the static NUL-terminated __gc origin marker. Its lifetime is
   --  the package lifetime and no allocation or prototype owner is needed.
   function Hook_Name return Byte_String;
   --  Borrow the static '?' marker for an actual hook-origin call.
   function Kind_Image (Kind : Name_Kind) return String;
   function Kind_From_Image (Text : String) return Name_Kind;
   --  Decode the immutable activation's explicit public origin category.
   function From_Caller
     (State : in out World; Caller : Frame_Access) return Identity;
   --  Infer a logical callee's name only when debug inspection requests it.
   --  Read the actual saved canonical call word and its reaching definitions;
   --  no source-time name map or per-call bytecode scan is maintained.
   subtype Arithmetic_Operand is Positive range 1 .. 2;
   function View_From_Operand
     (State : in out World; Caller : Frame_Access; Index : Arithmetic_Operand)
      return Borrowed_Identity;
   --  Borrow a failed operand's real reaching-definition name, including the
   --  active right-fold pair of CONCAT. No query allocation is required.
   --  Index is the logical left/right operand (one/two), including flipped
   --  immediate fallbacks and index receivers. Unknown/stripped names stay
   --  unknown; Name_Image provides the C string view for diagnostic text.
end Lua.Engine.Call_Names;
