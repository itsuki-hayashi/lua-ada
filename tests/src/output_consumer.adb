with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Lua.Sessions; use Lua.Sessions;

procedure Output_Consumer is
   type Counting_Sink is new Output_Sink with record
      Calls : Natural := 0;
   end record;
   overriding procedure Write
     (Self : in out Counting_Sink; Bytes : String);

   overriding procedure Write
     (Self : in out Counting_Sink; Bytes : String) is
   begin
      if Bytes'Length > 0 then
         Self.Calls := Self.Calls + 1;
      end if;
   end Write;

   procedure Require (Condition : Boolean; Message : String);
   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   Universe : Session;
   Sink : aliased Counting_Sink;
   Result : Execution_Result;
   Mode : constant String :=
     (if Ada.Command_Line.Argument_Count = 1 then
         Ada.Command_Line.Argument (1) else "");
begin
   --  This real Ada consumer proves byte-level process output in a child
   --  process. The script reads raw stdout rather than decoding high bytes.
   --  Neither test-only FILE redirection nor VM callbacks are necessary.
   if Mode = "captured" then
      Result := Universe.Execute
        ("print('a'..string.char(0,255),7)", "captured-consumer");
      Require (Result.Status = Succeeded, "captured execution failed");
      Require
        (To_String (Result.Output) = "a" & Character'Val (0) &
         Character'Val (255) & Ada.Characters.Latin_1.HT & "7" &
         Ada.Characters.Latin_1.LF,
         "captured byte payload changed");
   else
      Universe.Set_Output_Policy (Process_Streams);
      if Mode = "bytes" then
         Result := Universe.Execute
           ("print('a'..string.char(0,255),7)", "process-consumer",
            Sink => Sink'Access);
      elsif Mode = "callback-order" then
         Result := Universe.Execute
           ("print(setmetatable({}, {__tostring=function() " &
            "print('inner'); return 'first' end}), 'second')",
            "process-callback-order", Sink => Sink'Access);
      elsif Mode = "recovery" then
         Result := Universe.Execute
           ("print('before'); error('expected')", "process-error",
            Sink => Sink'Access);
         Require (Result.Status = Runtime_Error, "expected runtime failure");
         Require (Length (Result.Output) = 0, "failure duplicated stdout");
         Result := Universe.Execute
           ("print('recovered')", "process-recovery", Sink => Sink'Access);
      elsif Mode = "switch" then
         Result := Universe.Execute ("print('process')", "before-switch");
         Require (Result.Status = Succeeded, "initial process write failed");
         Require (Length (Result.Output) = 0, "initial write was duplicated");
         Universe.Set_Output_Policy (Captured);
         Result := Universe.Execute ("print('captured')", "after-switch");
         Require (To_String (Result.Output) =
                   "captured" & Ada.Characters.Latin_1.LF,
                  "switch did not restore capture");
         --  The captured case intentionally retains bytes in Result.
         Require (Result.Status = Succeeded, "capture after switch failed");
         return;
      elsif Mode = "reset" then
         Result := Universe.Execute ("print('process')", "before-reset");
         Require (Result.Status = Succeeded, "initial process write failed");
         Universe.Reset;
         Result := Universe.Execute ("print('captured')", "after-reset");
         Require (Result.Status = Succeeded and then
                    To_String (Result.Output) =
                      "captured" & Ada.Characters.Latin_1.LF,
                  "reset did not restore captured default");
         return;
      elsif Mode = "quota" then
         Universe.Set_Limits ((Output_Bytes => 2, others => <>));
         Result := Universe.Execute
           ("print('ab')", "process-quota", Sink => Sink'Access);
         Require (Result.Status = Resource_Error, "output quota was ignored");
         Require (Length (Result.Output) = 0, "aborted output was duplicated");
         --  The next public execution has a fresh two-byte quota. Its flush
         --  also publishes the previously buffered completed argument.
         Result := Universe.Execute
           ("print('R')", "quota-recovery", Sink => Sink'Access);
      else
         raise Program_Error with "unknown output consumer case";
      end if;
      Require (Result.Status = Succeeded, "process execution failed");
      Require (Length (Result.Output) = 0, "process stdout was duplicated");
      Require (Sink.Calls = 0, "process delivery called captured output sink");
   end if;
exception
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Output_Consumer;
