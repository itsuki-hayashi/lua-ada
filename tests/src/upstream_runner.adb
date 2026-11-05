with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Lua.Sessions; use Lua.Sessions;
with Lua.Sources;

procedure Upstream_Runner is
   --  A deliberately small host for unchanged upstream source files. It
   --  exercises the public Session API rather than a test-only interpreter.
   --  Bind this main with -Wb: output strings are bytes, not UTF-8 characters.
   use Ada.Command_Line;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;
   Bounds : Execution_Limits;
   Universe : Session;
   Source_Index : Positive := 1;

   function Read_Source (Path : String) return String;
   procedure Report (Result : Execution_Result);

   function Read_Source (Path : String) return String is
      package Files renames Ada.Streams.Stream_IO;
      File : Files.File_Type;
   begin
      --  Binary reading preserves literal NULs and every original newline.
      --  The common file policy is applied after reading. The selected
      --  fixtures have no BOM/interpreter line, so their bytes stay unchanged.
      Files.Open (File, Files.In_File, Path);
      if Files.Size (File) > Files.Count (Bounds.Source_Bytes) then
         Files.Close (File);
         raise Constraint_Error with "source byte limit exceeded";
      end if;
      declare
         Bytes : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
         Last : Ada.Streams.Stream_Element_Offset;
         Text : String (1 .. Bytes'Length);
      begin
         Files.Read (File, Bytes, Last);
         Files.Close (File);
         if Last /= Bytes'Last then
            raise Ada.Text_IO.End_Error with "short source read";
         end if;
         for Index in Text'Range loop
            Text (Index) := Character'Val
              (Bytes (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;
         return Lua.Sources.File_Preamble (Text);
      end;
   exception
      when others =>
         if Files.Is_Open (File) then
            Files.Close (File);
         end if;
         raise;
   end Read_Source;

   procedure Report (Result : Execution_Result) is
   begin
      --  Text_IO.New_Line matches native C stdout translation on Windows.
      --  Character Put, together with -Wb, retains every non-newline byte.
      for Byte of To_String (Result.Output) loop
         if Byte = Character'Val (10) then
            Ada.Text_IO.New_Line;
         else
            Ada.Text_IO.Put (Byte);
         end if;
      end loop;
      if Result.Status /= Succeeded then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Execution_Status'Image (Result.Status) & ": " &
            To_String (Result.Error.Source) & ":" &
            Ada.Strings.Fixed.Trim
              (Result.Error.Line'Image, Ada.Strings.Both) & ": " &
            To_String (Result.Error.Message));
         Set_Exit_Status (Failure);
      end if;
   end Report;
begin
   if Argument_Count = 3 and then Argument (1) = "--instructions" then
      --  The larger profile is explicit, bounded, and recorded by the driver.
      --  It is never selected automatically after a failed conformance run.
      Bounds.Instructions := Positive'Value (Argument (2));
      if Bounds.Instructions not in 1_000_000 | 20_000_000 then
         raise Constraint_Error with "unsupported upstream budget profile";
      end if;
      Source_Index := 3;
   elsif Argument_Count /= 1 then
      raise Constraint_Error with
        "Usage: upstream_runner [--instructions N] SCRIPT";
   end if;
   Universe.Set_Limits (Bounds);
   declare
      Setup : constant Execution_Result := Universe.Execute
        ("assert(rawget(_G, 'T') == nil); " &
         "package.path = './?.lua;./?/init.lua'", "(upstream setup)");
   begin
      Report (Setup);
      if Setup.Status /= Succeeded then
         return;
      end if;
   end;
   Report (Universe.Execute
     (Read_Source (Argument (Source_Index)), Argument (Source_Index)));
exception
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "upstream_runner: " & Ada.Exceptions.Exception_Message (Error));
      Set_Exit_Status (Failure);
end Upstream_Runner;
