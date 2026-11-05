with Lua.Syntax_Trees;
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
                     ("source byte limit exceeded"), others => <>));
      end if;
      Syntax_Trees.Parse (Unit, Source, Name, Limits);
      return Unit.Result;
   exception
      when Storage_Error =>
         return (Status => Resource_Error,
                 Error => (Source =>
                   Ada.Strings.Unbounded.To_Unbounded_String (Name),
                   Message => Ada.Strings.Unbounded.To_Unbounded_String
                     ("frontend storage exhausted"), others => <>));
   end Check;
end Lua.Syntax;
