with Ada.Exceptions;
with Ada.Unchecked_Deallocation;

package body Lua.Sessions is
   use Ada.Strings.Unbounded;
   use type Lua.Engine.World_Access;
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
         Result.Error.Message := Self.State.Current.Failure_Text;
      end if;
      return Result;
   end Failure;

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
   begin
      if Self.State /= null then
         Lua.Engine.Finalize (Self.State.all);
         Free (Self.State);
      end if;
   end Close;

   overriding procedure Finalize (Self : in out Session) is
   begin
      Self.Close;
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
         Self.State.Current.Arguments.Append
           (Lua.Engine.New_String (Self.State.all, To_String (Argument)));
      end loop;
      if Lua.Engine.Execute (Self.State.all, Source, Name) then
         Result.Output := Self.State.Output;
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
      return (Natural (Self.State.Heap.Length), Self.State.Entry_Count,
              Natural (Self.State.Programs.Length), Self.State.Collections);
   end Statistics;
end Lua.Sessions;
