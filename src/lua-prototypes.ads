with Ada.Finalization;
with Interfaces;
with Lua.Numbers;
with Lua.Opcodes;
with Lua.Storage.Buffers;
with Lua.Storage.Vectors;
with System;

private package Lua.Prototypes is
   --  Compiler-independent canonical data. No VM values or runtime heap
   --  handles enter this model. One program owns every node and byte string;
   --  nested references never own a node recursively.
   use type Interfaces.Unsigned_32;
   use type Interfaces.Integer_8;
   subtype Byte is Interfaces.Unsigned_8;
   type String_Id is new Natural;
   No_String : constant String_Id := 0;
   --  Zero means a nullable string, distinct from an interned empty string.

   type Constant_Kind is
     (Nil_Constant, Boolean_Constant, Integer_Constant, Number_Constant,
      String_Constant);
   type Constant_Value (Kind : Constant_Kind := Nil_Constant) is record
      case Kind is
         when Nil_Constant => null;
         when Boolean_Constant => Boolean_Data : Boolean;
         when Integer_Constant => Integer_Data : Lua.Numbers.Integer_Value;
         when Number_Constant => Number_Data : Lua.Numbers.Real_Value;
         when String_Constant =>
            String_Data : String_Id;
            Long_String : Boolean := False;
      end case;
   end record;
   type Upvalue is record
      In_Stack : Boolean := False;
      Index : Byte := 0;
      Kind : Byte := 0;
      Name : String_Id := No_String;
   end record;
   type Absolute_Line is record
      PC, Line : Natural := 0;
   end record;
   type Local is record
      Name : String_Id := No_String;
      Start_PC, End_PC : Natural := 0;
   end record;

   type Prototype;
   type Prototype_Access is access Prototype;
   for Prototype_Access'Storage_Pool use Lua.Storage.Pool;
   package Code_Lists is new Lua.Storage.Vectors (Lua.Opcodes.Word);
   package Constant_Lists is new Lua.Storage.Vectors (Constant_Value);
   package Upvalue_Lists is new Lua.Storage.Vectors (Upvalue);
   package Node_Lists is new Lua.Storage.Vectors (Prototype_Access);
   package Line_Lists is new Lua.Storage.Vectors (Interfaces.Integer_8);
   package Absolute_Lists is new Lua.Storage.Vectors (Absolute_Line);
   package Local_Lists is new Lua.Storage.Vectors (Local);

   type Prototype is record
      First_Line, Last_Line : Natural := 0;
      Parameters : Byte := 0;
      Flags : Byte := 0;
      Max_Stack : Byte := 2;
      Code : Code_Lists.Vector;
      Constants : Constant_Lists.Vector;
      Upvalues : Upvalue_Lists.Vector;
      Children : Node_Lists.Vector;
      Source : String_Id := No_String;
      Upvalue_Names_Present : Boolean := True;
      Lines : Line_Lists.Vector;
      Absolute_Lines : Absolute_Lists.Vector;
      Locals : Local_Lists.Vector;
      Owner_Token : System.Address := System.Null_Address;
      Node_Index : Natural := 0;
   end record;
   --  PCs in debug records are zero-based canonical instruction offsets.
   --  Flags use pinned PF_VAHID=1/PF_VATAB=2; imported PF_FIXED=4 is cleared.
   --  The ownership token/index are maintained only by New_Prototype.

   type Program is new Ada.Finalization.Limited_Controlled with private;
   procedure Set_Owner
     (Self : in out Program; Memory : not null Lua.Storage.Owner_Access);
   function Owner_Of (Self : Program) return Lua.Storage.Owner_Access;
   function New_Prototype (Self : in out Program) return Prototype_Access;
   --  Register a fully initialized node before returning it. Even unattached
   --  or cyclic partial graphs are freed once by the flat ownership list.
   function Owns (Self : Program; Item : Prototype_Access) return Boolean;
   procedure Set_Root (Self : in out Program; Item : Prototype_Access);
   function Root (Self : Program) return Prototype_Access;
   function Prototype_Count (Self : Program) return Natural;
   function Prototype_At
     (Self : Program; Index : Positive) return Prototype_Access;
   --  Borrow a checked stable registry slot, including an unattached node.
   --  @exception Constraint_Error Index is outside 1 .. Prototype_Count.

   function Intern (Self : in out Program; Text : String) return String_Id;
   --  Intern by byte content using indexed collision chains. Text may have
   --  arbitrary bounds/NULs; no unmanaged string copy is retained.
   function String_Count (Self : Program) return Natural;
   function String_Length (Self : Program; Id : String_Id) return Natural;
   function String_Element
     (Self : Program; Id : String_Id; Index : Positive) return Character;
   procedure Query_String
     (Self : in out Program; Id : String_Id;
      Process : not null access procedure (Text : String));
   --  Borrow actual managed bytes synchronously. Process must not retain the
   --  view, close Self or structurally mutate its string table.
   procedure Close (Self : in out Program);
   --  Release all nodes and byte strings without recursively walking children.
   --  Idempotent. Every program/borrower must die before its storage owner.
   procedure Move (Target, Source : in out Program);
   --  Destroy Target's old graph, then transfer Source without allocating or
   --  cloning. Node/string identities survive and now belong to Target.
   --  Source becomes empty and unbound; self-move is harmless. No string or
   --  registry borrow may be active. Its owner must outlive Target.

private
   type String_Entry is record
      Bytes : Lua.Storage.Buffers.Buffer;
      Hash : Interfaces.Unsigned_64 := 0;
      Next : String_Id := No_String;
   end record;
   package String_Lists is new Lua.Storage.Vectors (String_Entry);
   package Index_Lists is new Lua.Storage.Vectors (String_Id);
   type Program is new Ada.Finalization.Limited_Controlled with record
      Memory : Lua.Storage.Owner_Access;
      Nodes : Node_Lists.Vector;
      Texts : String_Lists.Vector;
      Buckets : Index_Lists.Vector;
      Main : Prototype_Access;
   end record;
   overriding procedure Finalize (Self : in out Program);
end Lua.Prototypes;
