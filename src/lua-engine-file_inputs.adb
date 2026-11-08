with Lua.Platform_Streams;
with Lua.Platform_OS;
with Lua.Sources;

package body Lua.Engine.File_Inputs is
   package C renames Interfaces.C;
   package Streams renames Lua.Platform_Streams;
   use type C.int;
   use type C.size_t;
   use type Streams.Handle;
   use type System.Address;
   function Message (Observed : Result; Filename : String) return String is
      Operation : constant String :=
        (case Observed.Status is
           when Open_Failure => "open", when Reopen_Failure => "reopen",
           when Ready | Read_Failure => "read");
   begin
      if Observed.Error = 0 then
         return "cannot " & Operation & " " & Filename;
      end if;
      declare
         Address : constant System.Address :=
           Lua.Platform_OS.Error_Text (Observed.Error);
         Size : constant Natural := Natural
           (Lua.Platform_OS.Text_Length (Address));
         Text : constant String (1 .. Size) with Import, Address => Address;
      begin
         return "cannot " & Operation & " " & Filename & ": " & Text;
      end;
   end Message;

   procedure Read_All
     (State : in out World; Filename : System.Address;
      Output : in out Lua.Storage.Buffers.Buffer; Observed : out Result)
   is
      File : Streams.Handle := Streams.No_Stream;
      Owned : constant Boolean := Filename /= System.Null_Address;
      Error : aliased C.int := 0;
      Mode : aliased constant String := "r" & Character'Val (0);
      Binary_Mode : aliased constant String := "rb" & Character'Val (0);
      Data : aliased String (1 .. 4_096);
      Failed : Boolean := False;
      Info : Lua.Sources.File_Preamble_Info;
      Binary : Boolean := False;
      procedure Close;
      procedure Read_Bytes;
      procedure Inspect (Text : String);

      procedure Close is
         Ignored : C.int;
         pragma Unreferenced (Ignored);
      begin
         if Owned and then File /= Streams.No_Stream then
            Ignored := Streams.Close (File, Error'Access);
            File := Streams.No_Stream;
         end if;
      end Close;

      procedure Read_Bytes is
         Count : C.size_t;
         Size : Natural;
      begin
         Output.Clear;
         loop
            --  The fixed transfer block is host I/O scratch. Every byte
            --  retained after this iteration belongs to the managed buffer.
            Count := Streams.Read
              (File, Data'Address, Data'Length, Error'Access);
            Size := Natural (Count);
            if Size > State.Bounds.Source_Bytes - Output.Length then
               Fail (State, "source byte limit exceeded", Resource => True);
            end if;
            if State.Policy = Bounded then
               if Size > State.Bounds.Instructions - State.Steps then
                  Fail (State, "instruction limit exceeded",
                        Resource => True);
               end if;
               State.Steps := State.Steps + Size;
            end if;
            Output.Append (Data (1 .. Size));
            exit when Count = 0 or else Streams.Has_Error (File) /= 0;
         end loop;
         Failed := Streams.Has_Error (File) /= 0;
      end Read_Bytes;

      procedure Inspect (Text : String) is
      begin
         Info := Lua.Sources.Inspect_File_Preamble (Text);
         Binary := Info.Skipped_Bytes < Text'Length and then
           Text (Text'First + Info.Skipped_Bytes) = Character'Val (27);
      end Inspect;
   begin
      Observed := (others => <>);
      Output.Set_Owner (Lua.Storage.Reference (State.Memory));
      if Owned then
         File := Streams.Open (Filename, Mode'Address, Error'Access);
      else
         File := Streams.Standard (Streams.Standard_Input);
      end if;
      if File = Streams.No_Stream then
         Observed := (Open_Failure, Error);
         return;
      end if;
      Read_Bytes;
      Output.Query (Inspect'Access);
      if Binary and then Owned then
         --  Windows text streams may already have translated or stopped at
         --  a binary payload byte. Reopen the same filename before consuming
         --  canonical bytes. The previous handle is retired before any next
         --  open; no failure path can lose ownership of either native handle.
         Close;
         File := Streams.Open (Filename, Binary_Mode'Address, Error'Access);
         if File = Streams.No_Stream then
            Observed := (Reopen_Failure, Error);
            return;
         end if;
         Read_Bytes;
      end if;
      --  Pinned loadfile clears errno before fclose, then uses that final
      --  errno for a read failure. The stream read's errno is deliberately
      --  not substituted into its observable error text.
      Error := 0;
      Close;
      if Failed then
         Observed := (Read_Failure, Error);
      end if;
   exception
      when others => Close; raise;
   end Read_All;

   procedure Prepare (Source : in out Lua.Storage.Buffers.Buffer) is
      Info : Lua.Sources.File_Preamble_Info;
      procedure Inspect (Text : String);
      procedure Inspect (Text : String) is
      begin
         Info := Lua.Sources.Inspect_File_Preamble (Text);
      end Inspect;
   begin
      Source.Query (Inspect'Access);
      if Info.Skipped_Bytes /= 0 then
         Source.Delete (1, Info.Skipped_Bytes);
      end if;
      for Index in 1 .. Info.Blanked_Bytes loop
         Source.Replace_Element (Index, ' ');
      end loop;
   end Prepare;
end Lua.Engine.File_Inputs;
