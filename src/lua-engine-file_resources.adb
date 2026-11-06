with Lua.Engine.Tables;
with System.Address_To_Access_Conversions;

package body Lua.Engine.File_Resources is
   use type Interfaces.C.int;
   use type Foreign.C_Function;
   use type Streams.Handle;
   use type Lua.Storage.Byte_Count;

   type File_Control is record
      Kind : File_Kind := Regular_File;
      Original : Streams.Handle := Streams.No_Stream;
   end record;
   package Controls is new
     System.Address_To_Access_Conversions (File_Control);
   package Headers is new
     System.Address_To_Access_Conversions (Stream_Header);

   procedure Release_Resource
     (Memory : not null Lua.Storage.Owner_Access;
      Payload, Data : System.Address; Reason : Resource_Release_Reason);

   procedure Release_Resource
     (Memory : not null Lua.Storage.Owner_Access;
      Payload, Data : System.Address; Reason : Resource_Release_Reason)
   is
      Control : constant Controls.Object_Pointer :=
        Controls.To_Pointer (Data);
      View : constant Headers.Object_Pointer := Headers.To_Pointer (Payload);
      Error : aliased Interfaces.C.int := 0;
      Ignored : Interfaces.C.int;
      pragma Unreferenced (Ignored);
      Owned : System.Address := Data;
   begin
      --  Ordinary collection and explicit Lua state close follow the actual
      --  __gc field. Removing/replacing that handler deliberately changes Lua
      --  behavior; host cleanup must not secretly substitute fclose for it.
      --  Forced host disposal is different: no Lua callbacks are permitted,
      --  so release only the still-open stream this metadata actually owns.
      if Reason = Host_Disposal and then
        Control.Kind /= Borrowed_File and then
        Control.Original /= Streams.No_Stream and then
        View.File = Control.Original and then View.Closer /= null
      then
         --  closef, not f, denotes open state: C Lua intentionally retains a
         --  stale nonnull FILE pointer after an ordinary explicit close.
         --  Clearing first makes the fallback idempotent even on OS failure.
         View.Closer := null;
         if Control.Kind = Pipe_File then
            Ignored := Streams.Close_Pipe (View.File, Error'Access);
         else
            Ignored := Streams.Close (View.File, Error'Access);
         end if;
      end if;
      Lua.Storage.Release (Memory.all, Owned);
   end Release_Resource;

   function Header (Item : Value) return Header_Access is
   begin
      if Item.Kind /= Userdata_Kind or else
        Item.Reference.Userdata_Size <
          Stream_Header'Object_Size / System.Storage_Unit
      then
         raise Program_Error with "invalid internal file payload borrow";
      end if;
      return Header_Access (Headers.To_Pointer (Userdata_Address (Item)));
   end Header;

   function Is_File (State : World; Item : Value) return Boolean is
      Metatable : constant Value :=
        Tables.Raw_Field (State.Foreign_Registry, "FILE*");
   begin
      return Item.Kind = Userdata_Kind and then
        Item.Reference.Userdata_Size >=
          Stream_Header'Object_Size / System.Storage_Unit and then
        Metatable.Kind = Table_Kind and then
        Item.Reference.Userdata_Metatable = Metatable.Reference;
   end Is_File;

   function New_Closed
     (State : in out World; Kind : File_Kind) return Value
   is
      Item : constant Value := New_Userdata
        (State, Stream_Header'Object_Size / System.Storage_Unit);
      Metatable : constant Value :=
        Tables.Raw_Field (State.Foreign_Registry, "FILE*");
      Owned : System.Address := System.Null_Address;
   begin
      --  Initialize every public byte before a potentially collecting
      --  allocation or metatable publication can expose this prefile.
      Header (Item).all := (others => <>);
      Pin (State, Item);
      if Metatable.Kind /= Table_Kind then
         raise Program_Error with "file metatable is not installed";
      end if;
      Owned := Lua.Storage.Allocate
        (State.Memory, File_Control'Object_Size / System.Storage_Unit,
         File_Control'Alignment);
      Controls.To_Pointer (Owned).all :=
        (Kind => Kind, Original => Streams.No_Stream);
      Attach_Resource (Item, Owned, Release_Resource'Access);
      --  Attachment now owns metadata; every failure before it leaves the
      --  constructor with no FILE and an explicitly releasable raw block.
      Owned := System.Null_Address;
      --  Use the one real association transition so the collector can enroll
      --  __gc ownership at the same point as debug/C metatable changes.
      Set_Metatable (State, Item, Metatable.Reference);
      return Item;
   exception
      when others =>
         Lua.Storage.Release (State.Memory, Owned);
         raise;
   end New_Closed;

   procedure Prepare
     (Item : Value; Closer : not null Foreign.C_Function)
   is
      View : constant Header_Access := Header (Item);
   begin
      if View.File /= Streams.No_Stream or else
        Item.Reference.Cleanup_Resource /= Release_Resource'Access or else
        Controls.To_Pointer (Item.Reference.Resource_Data).Original /=
          Streams.No_Stream
      then
         raise Program_Error with "invalid prefile preparation";
      end if;
      View.Closer := Closer;
   end Prepare;

   procedure Publish
     (Item : Value; File : Streams.Handle;
      Closer : not null Foreign.C_Function)
   is
      View : constant Header_Access := Header (Item);
   begin
      if File = Streams.No_Stream or else
        View.File /= Streams.No_Stream or else
        (View.Closer /= null and then View.Closer /= Closer) or else
        Item.Reference.Cleanup_Resource /= Release_Resource'Access or else
        Controls.To_Pointer (Item.Reference.Resource_Data).Original /=
          Streams.No_Stream
      then
         raise Program_Error with "invalid file resource publication";
      end if;
      Controls.To_Pointer (Item.Reference.Resource_Data).Original := File;
      View.File := File;
      View.Closer := Closer;
   end Publish;

   function Take_Closer (Item : Value) return Foreign.C_Function is
      View : constant Header_Access := Header (Item);
      Result : constant Foreign.C_Function := View.Closer;
   begin
      View.Closer := null;
      return Result;
   end Take_Closer;

   procedure Close_Native
     (Item : Value; Kind : File_Kind;
      Primitive : not null Foreign.C_Function;
      Status, Error : out Interfaces.C.int)
   is
      View : constant Header_Access := Header (Item);
      Native_Error : aliased Interfaces.C.int := 0;
   begin
      --  aux_close normally clears closef before calling this primitive.
      --  Direct C invocations of the actual closef trampoline share this
      --  operation and cannot leave a recognized FILE falsely marked open.
      View.Closer := null;
      case Kind is
         when Regular_File =>
            Status := Streams.Close (View.File, Native_Error'Access);
         when Pipe_File =>
            Status := Streams.Close_Pipe (View.File, Native_Error'Access);
         when Borrowed_File =>
            View.Closer := Primitive;
            Status := -1;
      end case;
      Error := Native_Error;
   end Close_Native;
end Lua.Engine.File_Resources;
