with Ada.Command_Line; use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Lua.Canonical_Compiler;
with Lua.Chunks;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Canonical;
with Lua.Engine.Machine;
with Lua.Prototypes;
with Lua.Sources;
with Lua.Storage;
with Lua.Syntax;
with Lua.Syntax_Trees;

procedure Lua.Canonical_Runtime_Probe is
   use type Ada.Streams.Stream_IO.Count;
   use type Lua.Syntax.Check_Status;
   use type Lua.Canonical_Compiler.Status;
   use type Lua.Chunks.Status;
   package Files renames Ada.Streams.Stream_IO;
   package VM renames Lua.Engine.Machine;
   procedure Free is new Ada.Unchecked_Deallocation (World, World_Access);
   State : World_Access := new World;
   Driver : VM.Driver;
   Callee : Value;
   Initialized : Boolean := False;

   function Read_File (Path : String) return String;
   function Read_File (Path : String) return String is
      File : Files.File_Type;
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      Files.Open (File, Files.In_File, Path);
      if Files.Size (File) > 16_777_216 then
         Files.Close (File);
         raise Constraint_Error with "runtime fixture input limit exceeded";
      end if;
      declare
         Bytes : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
      begin
         Files.Read (File, Bytes, Last);
         Files.Close (File);
         return Text : String (1 .. Natural (Last)) do
            for Index in Text'Range loop
               Text (Index) := Character'Val
                 (Bytes (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
         end return;
      end;
   exception
      when others =>
         if Files.Is_Open (File) then Files.Close (File); end if;
         raise;
   end Read_File;

   procedure Adopt (Model : in out Lua.Prototypes.Program);
   procedure Adopt (Model : in out Lua.Prototypes.Program) is
   begin
      Begin_Operation (State.all);
      begin
         Callee := Canonical.Adopt
           (State.all, Model, Global_Environment (State.all));
      exception
         when others => End_Operation (State.all); raise;
      end;
      End_Operation (State.all);
   end Adopt;

   procedure Write_Output;
   procedure Write_Output is
   begin
      --  Match native stdout newline translation while retaining every other
      --  byte, including NUL/high bytes. Bind with -Wb like the CLI.
      for Byte of Ada.Strings.Unbounded.To_String (State.Output) loop
         if Byte = ASCII.LF then Ada.Text_IO.New_Line;
         else Ada.Text_IO.Put (Byte); end if;
      end loop;
      State.Output := Ada.Strings.Unbounded.Null_Unbounded_String;
   end Write_Output;

   procedure Close;
   procedure Close is
   begin
      VM.Finish (Driver);
      if Initialized then
         Finalize (State.all);
         Initialized := False;
      end if;
      Free (State);
   end Close;
begin
   if Argument_Count /= 1 then
      raise Constraint_Error with
        "Usage: canonical_runtime_probe SOURCE|CHUNK";
   end if;
   --  This host has an explicit process-test allocator ceiling. Source,
   --  syntax, code and heap allocations all use this same owner; input reading
   --  itself is host fixture setup with a separate documented 16-MiB cap.
   Lua.Storage.Set_Ceiling (State.Memory, 2_147_483_648);
   Initialize (State.all, (others => <>));
   Initialized := True;
   Set_Policy (State.all, Lua_Compatible);
   declare
      Input : constant String := Read_File (Argument (1));
   begin
      if Input'Length > 0 and then Input (Input'First) = ASCII.ESC then
         declare
            Decoded : Lua.Chunks.Decode_Result := Lua.Chunks.Decode
              (Input, Lua.Storage.Reference (State.Memory));
         begin
            if Decoded.Outcome /= Lua.Chunks.Succeeded then
               raise Constraint_Error with Lua.Chunks.Message (Decoded.Error);
            end if;
            Adopt (Decoded.Code);
         end;
      else
         declare
            Unit : Lua.Syntax_Trees.Compilation_Unit;
         begin
            Lua.Syntax_Trees.Parse
              (Unit, Lua.Sources.File_Preamble (Input), "@" & Argument (1),
               (Source_Bytes => Positive'Last, Tokens => Positive'Last,
                Syntax_Nodes => Positive'Last, Nesting => 200),
               Memory => Lua.Storage.Reference (State.Memory));
            if Unit.Result.Status /= Lua.Syntax.Success then
               raise Constraint_Error with Lua.Syntax_Trees.Text
                 (Unit, Unit.Result.Error.Message);
            end if;
            declare
               Lowered : Lua.Canonical_Compiler.Compilation_Result :=
                 Lua.Canonical_Compiler.Compile
                   (Unit, Lua.Storage.Reference (State.Memory),
                    "@" & Argument (1));
            begin
               if Lowered.Outcome /= Lua.Canonical_Compiler.Succeeded then
                  raise Constraint_Error with
                    Lua.Canonical_Compiler.Message (Lowered.Error);
               end if;
               Adopt (Lowered.Code);
            end;
         end;
      end if;
   end;
   VM.Start (Driver, State, Callee, Values.Empty_Vector);
   while not VM.Is_Complete (Driver) loop VM.Step (Driver); end loop;
   VM.Finish (Driver);
   Write_Output;
   Close;
exception
   when Language_Error =>
      Write_Output;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        "Lua error at line" & Positive'Image (State.Current.Failure_At.Line) &
        ": " & Failure_Image (State.Current));
      Close;
      Set_Exit_Status (Failure);
   when Error : others =>
      if Initialized then Write_Output; end if;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        Ada.Exceptions.Exception_Name (Error) & ": " &
        Ada.Exceptions.Exception_Message (Error));
      Close;
      Set_Exit_Status (Failure);
end Lua.Canonical_Runtime_Probe;
