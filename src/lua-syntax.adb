with Lua.Syntax_Trees;
with Lua.Storage;
with Ada.Strings.Unbounded;

package body Lua.Syntax is
   function Check
     (Source : String; Name : String := "(source)";
      Limits : Check_Limits := (others => <>)) return Check_Result
   is
      Unit : Syntax_Trees.Compilation_Unit;
   begin
      --  Reject oversized input before constructing the scanner's source
      --  copy. The public boundary also contains allocation failures during
      --  construction, before Parse's statement handler becomes active.
      if Source'Length > Limits.Source_Bytes then
         return (Status => Resource_Error,
                 Error => (Source =>
                   Ada.Strings.Unbounded.To_Unbounded_String (Name),
                   Message => Ada.Strings.Unbounded.To_Unbounded_String
                     ("source byte limit exceeded"), others => <>),
                 Incomplete_Input => False);
      end if;
      Syntax_Trees.Parse (Unit, Source, Name, Limits);
      --  Public diagnostics deliberately own ordinary Ada strings. The
      --  parser's internal result retains only references into Unit's arena;
      --  copy at this host boundary before that temporary owner is finalized.
      return
        (Status => Unit.Result.Status,
         Error =>
           (Source => Ada.Strings.Unbounded.To_Unbounded_String
              (Syntax_Trees.Text (Unit, Unit.Result.Error.Source)),
            Message => Ada.Strings.Unbounded.To_Unbounded_String
              (Syntax_Trees.Text (Unit, Unit.Result.Error.Message)),
            Line => Unit.Result.Error.Line,
            Column => Unit.Result.Error.Column),
         Incomplete_Input => Unit.Result.Incomplete_Input);
   exception
      when Storage_Error | Lua.Storage.Allocation_Error =>
         return (Status => Resource_Error,
                 Error => (Source =>
                   Ada.Strings.Unbounded.To_Unbounded_String (Name),
                   Message => Ada.Strings.Unbounded.To_Unbounded_String
                     ("frontend storage exhausted"), others => <>),
                 Incomplete_Input => False);
   end Check;
end Lua.Syntax;
