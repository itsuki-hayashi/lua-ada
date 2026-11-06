with Ada.Command_Line; use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Lua.Canonical_Compiler;
with Lua.Chunks;
with Lua.Storage;
with Lua.Storage.Buffers;
with Lua.Syntax;
with Lua.Syntax_Trees;

procedure Lua.Canonical_Compiler_Probe is
   use type Ada.Streams.Stream_IO.Count;
   use type Lua.Syntax.Check_Status;
   use type Lua.Canonical_Compiler.Status;
   package Files renames Ada.Streams.Stream_IO;
   function Read_File (Path : String) return String;
   function Read_File (Path : String) return String is
      File : Files.File_Type;
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      Files.Open (File, Files.In_File, Path);
      if Files.Size (File) > 16_777_216 then
         Files.Close (File);
         raise Constraint_Error with "compiler fixture input limit exceeded";
      end if;
      declare
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
      begin
         Files.Read (File, Data, Last);
         Files.Close (File);
         return Source : String (1 .. Natural (Last)) do
            for Index in Source'Range loop
               Source (Index) := Character'Val
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
     (Path : String; Bytes : in out Lua.Storage.Buffers.Buffer);
   procedure Write_File
     (Path : String; Bytes : in out Lua.Storage.Buffers.Buffer)
   is
      File : Files.File_Type;
      procedure Write (Text : String);
      procedure Write (Text : String) is
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Text'Length))
           with Import, Address => Text'Address;
      begin
         Files.Write (File, Data);
      end Write;
   begin
      Files.Create (File, Files.Out_File, Path);
      Bytes.Query (Write'Access);
      Files.Close (File);
   exception
      when others =>
         if Files.Is_Open (File) then Files.Close (File); end if;
         raise;
   end Write_File;
   Memory : Lua.Storage.Owner;
begin
   if Argument_Count /= 2 then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        "Usage: canonical_compiler_probe SOURCE OUTPUT");
      Set_Exit_Status (Failure);
      return;
   end if;
   declare
      Source : constant String := Read_File (Argument (1));
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      Lua.Syntax_Trees.Parse (Unit, Source, "@" & Argument (1),
        (Source_Bytes => Positive'Last, Tokens => Positive'Last,
         Syntax_Nodes => Positive'Last, Nesting => 200));
      if Unit.Result.Status /= Lua.Syntax.Success then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
           Lua.Syntax_Trees.Text (Unit, Unit.Result.Error.Message));
         Set_Exit_Status (Failure);
         return;
      end if;
      declare
         Result : Lua.Canonical_Compiler.Compilation_Result :=
           Lua.Canonical_Compiler.Compile
             (Unit, Lua.Storage.Reference (Memory), "@" & Argument (1));
         Bytes : Lua.Storage.Buffers.Buffer;
      begin
         if Result.Outcome /= Lua.Canonical_Compiler.Succeeded then
            Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
              Lua.Canonical_Compiler.Message (Result.Error) & " at line" &
              Positive'Image (Result.Location.Line));
            Set_Exit_Status (Failure);
            return;
         end if;
         Bytes := Lua.Chunks.Encode (Result.Code);
         Write_File (Argument (2), Bytes);
      end;
   end;
   Ada.Text_IO.Put_Line ("CANONICAL COMPILER OK");
exception
   when Error : others =>
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        Ada.Exceptions.Exception_Name (Error) & ": " &
        Ada.Exceptions.Exception_Message (Error));
      Set_Exit_Status (Failure);
end Lua.Canonical_Compiler_Probe;
