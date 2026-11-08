with Lua.Diagnostic_Text;
with Ada.Exceptions;
with Ada.Unchecked_Deallocation;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Lua.Storage;

package body Lua.Sessions is
   use Ada.Strings.Unbounded;
   use type Lua.Engine.World_Access;
   use type Lua.Engine.Process_Exit_Phase;
   procedure Free is new Ada.Unchecked_Deallocation
     (Lua.Engine.World, Lua.Engine.World_Access);

   function Failure
     (Self : Session; Name : String) return Execution_Result;

   function Failure
     (Self : Session; Name : String) return Execution_Result
   is
      Result : Execution_Result;
   begin
      Result.Error.Source := To_Unbounded_String (Name);
      if Self.State = null then
         Result.Status := Runtime_Error;
         Result.Error.Message := To_Unbounded_String ("session is closed");
      else
         Result.Status :=
           (case Self.State.Current.Failure_Class is
               when Lua.Engine.Host_Abort => Resource_Error,
               when Lua.Engine.Syntax_Failure => Syntax_Error,
               when Lua.Engine.Unsupported_Failure => Unsupported_Feature,
               when others => Runtime_Error);
         Result.Output := Self.State.Output;
         Result.Error.Line := Self.State.Current.Failure_At.Line;
         Result.Error.Column := Self.State.Current.Failure_At.Column;
         Result.Error.Message := To_Unbounded_String
           (Lua.Engine.Failure_Image (Self.State.Current));
      end if;
      return Result;
   end Failure;

   procedure Apply_Exit
     (Self : in out Session; Result : in out Execution_Result);

   procedure Apply_Exit
     (Self : in out Session; Result : in out Execution_Result) is
   begin
      --  Shared by Execute and Execute_Display: publish a completed typed
      --  os.exit request. Unchanged from the original inline sequence.
      Result.Status := Exit_Requested;
      Result.Exit_Request :=
        (Self.State.Exit_Code, Self.State.Exit_Close_State);
      if Self.State.Exit_Close_State then
         --  The scheduler has already drained main-thread TBC values
         --  and finalizers. Snapshot the public result before physical
         --  release; a C-owned pump follows the same ordering.
         Lua.Engine.Finalize (Self.State.all, Lua.Engine.Lua_State_Close);
         Free (Self.State);
      else
         Self.State.Exit_Phase := Lua.Engine.No_Process_Exit;
         Self.State.Current := Self.State.Main_Context;
         Self.State.Current.Status := Lua.Engine.Suspended_Context;
      end if;
   end Apply_Exit;

   overriding procedure Initialize (Self : in out Session) is
   begin
      Self.State := new Lua.Engine.World;
      Lua.Engine.Initialize (Self.State.all, (others => <>));
   exception
      when others =>
         --  Construction owns partially initialized state too. Do not leak a
         --  partially bootstrapped universe if host allocation fails here.
         if Self.State /= null then
            Lua.Engine.Finalize (Self.State.all);
            Free (Self.State);
         end if;
         raise;
   end Initialize;

   procedure Close (Self : in out Session) is
      Reason : Lua.Engine.Resource_Release_Reason :=
        Lua.Engine.Lua_State_Close;
   begin
      if Self.State /= null then
         begin
            Lua.Engine.Machine.Close_Lua_State (Self.State.all);
         exception
            when Lua.Engine.Language_Error | Storage_Error =>
               --  An explicit host abort cannot run more Lua cleanup. The
               --  remaining resources retain their host-disposal policy.
               Reason := Lua.Engine.Host_Disposal;
         end;
         Lua.Engine.Finalize (Self.State.all, Reason);
         Free (Self.State);
      end if;
   end Close;

   overriding procedure Finalize (Self : in out Session) is
   begin
      --  Ada scope exit is physical host disposal, not a new Lua execution.
      --  In particular it cannot restart callbacks after an exhausted quota.
      if Self.State /= null then
         Lua.Engine.Finalize (Self.State.all);
         Free (Self.State);
      end if;
   end Finalize;

   procedure Reset (Self : in out Session) is
   begin
      Self.Close;
      Initialize (Self);
   end Reset;

   procedure Set_Execution_Policy
     (Self : in out Session; Policy : Execution_Policy) is
   begin
      if Self.State /= null then
         Lua.Engine.Set_Policy
           (Self.State.all,
            (if Policy = Bounded then Lua.Engine.Bounded
             else Lua.Engine.Lua_Compatible));
      end if;
   end Set_Execution_Policy;

   procedure Set_Output_Policy
     (Self : in out Session; Policy : Output_Policy) is
   begin
      if Self.State /= null then
         Self.State.Output_Mode :=
           (if Policy = Captured then Lua.Engine.Captured
            else Lua.Engine.Process_Streams);
      end if;
   end Set_Output_Policy;

   procedure Set_Limits (Self : in out Session; Bounds : Execution_Limits) is
   begin
      if Self.State /= null then
         Self.State.Bounds :=
           (Bounds.Source_Bytes, Bounds.Tokens, Bounds.Instructions,
            Bounds.Call_Depth, Bounds.Heap_Objects, Bounds.Table_Entries,
            Bounds.String_Bytes, Bounds.Output_Bytes, Bounds.Registers,
            Bounds.Syntax_Nodes, Bounds.Syntax_Depth);
         Self.State.Saved_Bounds := Self.State.Bounds;
         Self.State.Policy := Lua.Engine.Bounded;
         Self.State.Next_GC := Positive'Min
           (Self.State.Next_GC, Bounds.Heap_Objects);
      end if;
   end Set_Limits;

   function Execute
     (Self : in out Session; Source : String;
      Name : String := "(source)";
      Arguments : Argument_Array := No_Arguments;
      Sink : access Output_Sink'Class := null) return Execution_Result
   is
      Result : Execution_Result;
   begin
      if Self.State = null then
         return Failure (Self, Name);
      end if;
      --  Arguments are rooted before the compiler's first collection. The
      --  engine releases this root after returning; captured values remain
      --  alive through their ordinary lexical/table owners.
      Self.State.Current.Arguments.Clear;
      Self.State.Output := Null_Unbounded_String;
      Self.State.Output_Used := 0;
      Self.State.Current.Failure_At := (others => 1);
      for Argument of Arguments loop
         Lua.Engine.Append_Root
           (Self.State.all, Self.State.Current.Arguments,
            Lua.Engine.New_String (Self.State.all, To_String (Argument)));
      end loop;
      if Lua.Engine.Execute (Self.State.all, Source, Name) then
         Result.Output := Self.State.Output;
         if Self.State.Exit_Phase = Lua.Engine.Exit_Complete then
            Apply_Exit (Self, Result);
         end if;
      else
         Result := Failure (Self, Name);
      end if;
      if Sink /= null and then Length (Result.Output) > 0 then
         begin
            Sink.Write (To_String (Result.Output));
         exception
            when Error : others =>
               Result.Status := Host_Error;
               Result.Error.Source := To_Unbounded_String (Name);
               Result.Error.Message := To_Unbounded_String
                 ("output sink failed: " &
                  Ada.Exceptions.Exception_Message (Error));
         end;
      end if;
      return Result;
   exception
      when Lua.Engine.Language_Error => return Failure (Self, Name);
      when Storage_Error =>
         Result.Status := Resource_Error;
         Result.Error.Source := To_Unbounded_String (Name);
         Result.Error.Message :=
           To_Unbounded_String ("host storage exhausted");
         return Result;
   end Execute;

   function Execute_Display
     (Self : in out Session; Source : String;
      Name : String := "=stdin"; Display_Failed : out Boolean)
      return Execution_Result
   is
      Result : Execution_Result;
      Phase_One_Done : Boolean := False;

      procedure Unwind (Collect_After : Boolean := True);
      procedure Unwind (Collect_After : Boolean := True) is
         --  Mirrors the failure epilogue of Lua.Engine.Execute so a failed
         --  display session is as reusable as a failed ordinary chunk.
         State : Lua.Engine.World renames Self.State.all;
      begin
         State.Entry_Code := null;
         State.Current.Status := Lua.Engine.Suspended_Context;
         State.Current.Arguments.Clear;
         Lua.Engine.Machine.Clear_Frames (State);
         if Collect_After and then State.GC_Running then
            Lua.Engine.Collect (State);
         end if;
      end Unwind;
   begin
      Display_Failed := False;
      if Self.State = null then
         return Failure (Self, Name);
      end if;
      declare
         State : Lua.Engine.World renames Self.State.all;
         Code : Lua.Engine.Prototype_Access;
      begin
         --  Phase one: the prelude is the same state reset Engine.Execute
         --  performs. Results of the REPL chunk are never visible before
         --  the chunk has completed, as in lua.c's docall/l_print split.
         State.Current.Arguments.Clear;
         State.Current.Status := Lua.Engine.Running_Context;
         State.Current.Failure := Lua.Engine.Nil_Value;
         State.Current.Has_Failure_Value := False;
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         State.Current.Failure_Class := Lua.Engine.No_Failure;
         State.Current.Failure_Handled := False;
         State.Current.Protected_Failure_Class := Lua.Engine.No_Failure;
         State.Current.Protected_Handler_Called := False;
         State.Output := Null_Unbounded_String;
         State.Output_Used := 0;
         State.Steps := 0;
         State.Current.Failure_At := (others => 1);
         if State.GC_Running then
            Lua.Engine.Collect (State);
         end if;
         if Source'Length > State.Bounds.Source_Bytes then
            Lua.Engine.Fail
              (State, "source byte limit exceeded", Resource => True);
         end if;
         Lua.Engine.Begin_Operation (State);
         Code := Lua.Engine.Compiler.Compile (State, Source, Name);
         State.Entry_Code := Code;
         Lua.Engine.Machine.Run_Retaining (State, Code);
         State.Entry_Code := null;
         Lua.Engine.End_Operation (State);
         Phase_One_Done := True;
         if State.Exit_Phase = Lua.Engine.Exit_Complete then
            Result.Output := State.Output;
            Apply_Exit (Self, Result);
            return Result;
         end if;
         if not State.Current.Arguments.Is_Empty then
            --  Phase two: look up the *current* global print only now, as
            --  lua.c does after the chunk returns. The packet in Arguments
            --  is a traced root through the key allocation and the call.
            Display_Failed := True;
            Lua.Engine.Machine.Run_Display (State);
            Display_Failed := False;
         end if;
         State.Current.Arguments.Clear;
         if State.GC_Running then
            Lua.Engine.Collect (State);
         end if;
         State.Current.Status := Lua.Engine.Suspended_Context;
         Result.Output := State.Output;
         if State.Exit_Phase = Lua.Engine.Exit_Complete then
            --  print (a replaced global) may itself request process exit.
            Apply_Exit (Self, Result);
         end if;
         return Result;
      end;
   exception
      when Lua.Engine.Language_Error =>
         if not Phase_One_Done then
            Lua.Engine.End_Operation (Self.State.all);
            Display_Failed := False;
         end if;
         Unwind;
         return Failure (Self, Name);
      when Lua.Storage.Allocation_Error =>
         Lua.Engine.End_Operation (Self.State.all);
         Lua.Engine.Record_Memory_Error (Self.State.all);
         Unwind (Collect_After => False);
         return Failure (Self, Name);
      when Storage_Error =>
         if Self.State /= null then
            Lua.Engine.End_Operation (Self.State.all);
            Unwind (Collect_After => False);
            Self.State.Current.Failure_Class := Lua.Engine.Host_Abort;
         end if;
         Result.Status := Resource_Error;
         Result.Error.Source := To_Unbounded_String (Name);
         Result.Error.Message :=
           To_Unbounded_String ("host storage exhausted");
         return Result;
      when Error : Constraint_Error | Program_Error =>
         Lua.Engine.End_Operation (Self.State.all);
         if Lua.Storage.Refusal_Pending (Self.State.Memory) then
            Lua.Engine.Record_Memory_Error (Self.State.all);
         else
            Lua.Engine.Set_Failure_Text
              (Self.State.all, Self.State.Current,
               "internal Ada check: " &
               Ada.Exceptions.Exception_Message (Error));
         end if;
         Unwind (Collect_After => False);
         return Failure (Self, Name);
   end Execute_Display;

   function Set_Warnings_Enabled
     (Self : in out Session; Enabled : Boolean) return Execution_Result
   is
      Result : Execution_Result;
      procedure Recover;
      procedure Recover is
         State : Lua.Engine.World renames Self.State.all;
      begin
         Lua.Engine.End_Operation (State);
         Lua.Engine.Machine.Clear_Frames (State);
         State.Current.Arguments.Clear;
         State.Current.Status := Lua.Engine.Suspended_Context;
      end Recover;
   begin
      if Self.State = null then
         return Failure (Self, "(warning)");
      end if;
      declare
         State : Lua.Engine.World renames Self.State.all;
      begin
         --  This is an idle host entry, not a recursive executor call from a
         --  Lua callback. The warning's native phase retains every deferred
         --  callback event; changing the public warn binding has no effect.
         State.Current.Failure := Lua.Engine.Nil_Value;
         State.Current.Has_Failure_Value := False;
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         State.Current.Failure_Class := Lua.Engine.No_Failure;
         State.Current.Failure_Handled := False;
         State.Current.Protected_Failure_Class := Lua.Engine.No_Failure;
         State.Current.Protected_Handler_Called := False;
         State.Current.Failure_At := (others => 1);
         State.Current.Arguments.Clear;
         State.Output := Null_Unbounded_String;
         State.Output_Used := 0;
         State.Steps := 0;
         Lua.Engine.Begin_Operation (State);
         Lua.Engine.Machine.Run_Warning_Control (State, Enabled);
         Lua.Engine.End_Operation (State);
         State.Current.Status := Lua.Engine.Suspended_Context;
         Result.Output := State.Output;
         if State.Exit_Phase = Lua.Engine.Exit_Complete then
            Apply_Exit (Self, Result);
         end if;
      end;
      return Result;
   exception
      when Lua.Engine.Language_Error =>
         Recover;
         return Failure (Self, "(warning)");
      when Lua.Storage.Allocation_Error =>
         Lua.Engine.Record_Memory_Error (Self.State.all);
         Recover;
         return Failure (Self, "(warning)");
      when Storage_Error =>
         Recover;
         Result.Status := Resource_Error;
         Result.Error.Source := To_Unbounded_String ("(warning)");
         Result.Error.Message :=
           To_Unbounded_String ("host storage exhausted");
         return Result;
   end Set_Warnings_Enabled;

   function Configure_Package_Environment
     (Self : in out Session; Ignore_Environment : Boolean := False)
      return Execution_Result
   is
      Result : Execution_Result;
      procedure Recover;
      procedure Recover is
         State : Lua.Engine.World renames Self.State.all;
      begin
         Lua.Engine.End_Operation (State);
         Lua.Engine.Machine.Clear_Frames (State);
         State.Current.Arguments.Clear;
         State.Current.Status := Lua.Engine.Suspended_Context;
      end Recover;
   begin
      if Self.State = null then return Failure (Self, "(package)"); end if;
      declare
         State : Lua.Engine.World renames Self.State.all;
      begin
         --  Like warning control, this is a serialized idle-host operation.
         --  Run it through the ordinary driver so a collection-triggered
         --  external-string release uses its real guarded C callback portal.
         State.Current.Failure := Lua.Engine.Nil_Value;
         State.Current.Has_Failure_Value := False;
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         State.Current.Failure_Class := Lua.Engine.No_Failure;
         State.Current.Failure_Handled := False;
         State.Current.Protected_Failure_Class := Lua.Engine.No_Failure;
         State.Current.Protected_Handler_Called := False;
         State.Current.Failure_At := (others => 1);
         State.Current.Arguments.Clear;
         State.Output := Null_Unbounded_String;
         State.Output_Used := 0;
         State.Steps := 0;
         Lua.Engine.Begin_Operation (State);
         Lua.Engine.Machine.Run_Package_Environment
           (State, Ignore_Environment);
         Lua.Engine.End_Operation (State);
         State.Current.Status := Lua.Engine.Suspended_Context;
         Result.Output := State.Output;
         if State.Exit_Phase = Lua.Engine.Exit_Complete then
            Apply_Exit (Self, Result);
         end if;
      end;
      return Result;
   exception
      when Lua.Engine.Language_Error =>
         Recover;
         return Failure (Self, "(package)");
      when Lua.Storage.Allocation_Error =>
         Lua.Engine.Record_Memory_Error (Self.State.all);
         Recover;
         return Failure (Self, "(package)");
      when Storage_Error =>
         Recover;
         Result.Status := Resource_Error;
         Result.Error.Source := To_Unbounded_String ("(package)");
         Result.Error.Message :=
           To_Unbounded_String ("host storage exhausted");
         return Result;
   end Configure_Package_Environment;

   function Set_Arguments
     (Self : in out Session; Arguments : Argument_Array)
      return Execution_Result
   is
      Table, Key, Item : Lua.Engine.Value;
   begin
      if Self.State = null then
         return Failure (Self, "(arguments)");
      end if;
      Self.State.Current.Failure_Class := Lua.Engine.No_Failure;
      Self.State.Output := Null_Unbounded_String;
      Self.State.Output_Used := 0;
      Lua.Engine.Collect (Self.State.all);
      Table := Lua.Engine.New_Table (Self.State.all);
      for Index in Arguments'Range loop
         Item := Lua.Engine.New_String
           (Self.State.all, To_String (Arguments (Index)));
         Lua.Engine.Set
           (Self.State.all, Table,
            (Lua.Engine.Integer_Kind, Lua.Engine.Integer_Value (Index)), Item);
      end loop;
      Key := Lua.Engine.New_String (Self.State.all, "arg");
      Lua.Engine.Set (Self.State.all,
                      Lua.Engine.Global_Environment (Self.State.all),
                      Key, Table);
      return (others => <>);
   exception
      when Lua.Engine.Language_Error => return Failure (Self, "(arguments)");
      when Storage_Error =>
         return (Status => Resource_Error,
                 Error => (Message => To_Unbounded_String
                   ("host storage exhausted"), others => <>), others => <>);
   end Set_Arguments;

   procedure Collect (Self : in out Session) is
   begin
      if Self.State /= null then
         Lua.Engine.Collect (Self.State.all);
      end if;
   end Collect;

   function Statistics (Self : Session) return Heap_Statistics is
   begin
      if Self.State = null then
         return (others => 0);
      end if;
      return (Self.State.Live_Objects, Self.State.Entry_Count,
              Self.State.Live_Programs, Self.State.Collections);
   end Statistics;
end Lua.Sessions;
