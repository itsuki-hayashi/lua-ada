with Lua.Diagnostics;

package Lua.Syntax is
   type Check_Limits is record
      Source_Bytes : Positive := 1_000_000;
      Tokens : Positive := 100_000;
      Syntax_Nodes : Positive := 200_000;
      Nesting : Positive := 200;
   end record;
   --  Bounds apply to one source unit, independently of any Lua session.
   type Check_Status is (Success, Syntax_Error, Resource_Error);
   --  @enum Success Source is valid within the configured frontend limits.
   --  @enum Syntax_Error Lexical, grammar, or static-semantic rejection.
   --  @enum Resource_Error A configured budget or host storage was exhausted.
   type Check_Result is record
      Status : Check_Status := Success;
      Error : Lua.Diagnostics.Diagnostic;
      Incomplete_Input : Boolean := False;
      --  A grammar expectation or unfinished literal at actual EOF can be
      --  completed by more interactive input. False for success, resources,
      --  malformed numerals/escapes and static-semantic/resolver errors.
   end record;
   function Check
     (Source : String; Name : String := "(source)";
      Limits : Check_Limits := (others => <>)) return Check_Result;
   --  Validate text without executing code or allocating Lua runtime objects.
   --  @param Source Source bytes; arbitrary String lower bounds are accepted.
   --  @param Name Diagnostic label, retained in the returned owned value.
   --  @param Limits Bounds on frontend work and temporary storage.
   --  @return Success or a structured syntax/resource diagnostic.
end Lua.Syntax;
