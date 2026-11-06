with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Lua.Chunks;
with Lua.Opcodes;
with Lua.Prototypes;
with Lua.Storage;
with Lua.Storage.Buffers;

procedure Lua.Chunk_Probe is
   use Ada.Command_Line;
   use type Ada.Streams.Stream_IO.Count;
   use type Lua.Chunks.Status;
   package Files renames Ada.Streams.Stream_IO;

   function Read_File (Path : String) return String;
   function Read_File (Path : String) return String is
      File : Files.File_Type;
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      Files.Open (File, Files.In_File, Path);
      if Files.Size (File) > 16_777_216 then
         Files.Close (File);
         raise Constraint_Error with "codec probe input exceeds fixture limit";
      end if;
      declare
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
      begin
         Files.Read (File, Data, Last);
         Files.Close (File);
         return Result : String (1 .. Natural (Last)) do
            for Index in Result'Range loop
               Result (Index) := Character'Val
                 (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
         end return;
      end;
   exception
      when others =>
         if Files.Is_Open (File) then Files.Close (File); end if;
         raise;
   end Read_File;

   procedure Write_File
     (Path : String; Data : in out Lua.Storage.Buffers.Buffer);
   procedure Write_File
     (Path : String; Data : in out Lua.Storage.Buffers.Buffer)
   is
      File : Files.File_Type;
      procedure Write_Bytes (Text : String);
      procedure Write_Bytes (Text : String) is
         Bytes : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Text'Length))
           with Import, Address => Text'Address;
      begin
         Files.Write (File, Bytes);
      end Write_Bytes;
   begin
      Files.Create (File, Files.Out_File, Path);
      --  The output stream borrows managed bytes synchronously. There is no
      --  second fixture-sized stream buffer or text newline conversion.
      Data.Query (Write_Bytes'Access);
      Files.Close (File);
   exception
      when others =>
         if Files.Is_Open (File) then Files.Close (File); end if;
         raise;
   end Write_File;

   Memory : Lua.Storage.Owner;
begin
   if Argument_Count = 2 and then Argument (1) = "emit" then
      declare
         Code : Lua.Prototypes.Program;
         Node : Lua.Prototypes.Prototype_Access;
         Data : Lua.Storage.Buffers.Buffer;
      begin
         Lua.Prototypes.Set_Owner (Code, Lua.Storage.Reference (Memory));
         Node := Lua.Prototypes.New_Prototype (Code);
         Lua.Prototypes.Set_Root (Code, Node);
         Node.Constants.Append (Lua.Prototypes.Constant_Value'
           (Lua.Prototypes.Integer_Constant, 42));
         Node.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_LOADK));
         Node.Code.Append (Lua.Opcodes.Create (Lua.Opcodes.Op_RETURN1));
         Node.Source := Lua.Prototypes.Intern (Code, "=Ada codec fixture");
         Data := Lua.Chunks.Encode (Code);
         Write_File (Argument (2), Data);
      end;
   elsif Argument_Count in 3 .. 4 and then Argument (1) = "roundtrip" then
      declare
         Source : constant String := Read_File (Argument (2));
         Result : Lua.Chunks.Decode_Result :=
           Lua.Chunks.Decode (Source, Lua.Storage.Reference (Memory));
         Data : Lua.Storage.Buffers.Buffer;
      begin
         if Result.Outcome /= Lua.Chunks.Succeeded then
            Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
              Lua.Chunks.Message (Result.Error) & " at byte" &
              Natural'Image (Result.Offset));
            Set_Exit_Status (Failure);
            return;
         end if;
         Data := Lua.Chunks.Encode
           (Result.Code, Strip => Argument_Count = 4 and then
              Argument (4) = "strip");
         Write_File (Argument (3), Data);
      end;
   else
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        "Usage: chunk_probe emit OUTPUT | roundtrip INPUT OUTPUT [strip]");
      Set_Exit_Status (Failure);
      return;
   end if;
   Ada.Text_IO.Put_Line ("CHUNK CODEC OK");
exception
   when Error : others =>
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        Ada.Exceptions.Exception_Name (Error) & ": " &
        Ada.Exceptions.Exception_Message (Error));
      Set_Exit_Status (Failure);
end Lua.Chunk_Probe;
