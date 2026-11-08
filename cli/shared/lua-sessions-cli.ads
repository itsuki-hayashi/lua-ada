package Lua.Sessions.CLI is
   function Write_Prompt
     (Self : in out Session; First_Line : Boolean) return Execution_Result;
   --  CLI-only operation: resolve _PROMPT/_PROMPT2 through the actual global
   --  environment, apply auxiliary tostring semantics and publish the prompt.
   --  Nil selects the native default. The converted Lua string stays rooted
   --  until its C-string prefix has been written and flushed. No value or
   --  string borrow escapes this call; errors/exits retain session policy.
   --  This child is built only by CLI/test projects, outside the runtime SAL.

   function Execute_Selected_Script
     (Self : in out Session; Source, Name : String) return Execution_Result;
   --  Compile the already selected file/stdin bytes, then obtain its actual
   --  arguments from the current global arg table. Lookup and length handlers
   --  use real anonymous C callers; integer entries are copied raw, preserving
   --  Lua values, identities and nil holes. The selected filename and initial
   --  environment do not change if a handler replaces arg or registry globals.
   --  Compilation, callbacks and execution share one session budget/owner.
   --  No value or borrowed stack view escapes. Errors/exits retain session
   --  policy. This idle operation is only for explicit CLI script selection;
   --  snippets, initialization, implicit stdin and the REPL have other rules.
end Lua.Sessions.CLI;
