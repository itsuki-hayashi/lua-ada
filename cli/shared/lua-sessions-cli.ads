package Lua.Sessions.CLI is
   function Write_Prompt
     (Self : in out Session; First_Line : Boolean) return Execution_Result;
   --  CLI-only operation: resolve _PROMPT/_PROMPT2 through the actual global
   --  environment, apply auxiliary tostring semantics and publish the prompt.
   --  Nil selects the native default. The converted Lua string stays rooted
   --  until its C-string prefix has been written and flushed. No value or
   --  string borrow escapes this call; errors/exits retain session policy.
   --  This child is built only by CLI/test projects, outside the runtime SAL.

   function Initialize_Readline
     (Self : in out Session; Ignore_Environment : Boolean)
      return Execution_Result;
   --  Select the pinned platform's native REPL transport. Linux can load an
   --  optional host library; -E ignores its environment override. Warnings
   --  pass through the actual Lua warning API and guarded callback portal.

   function Read_REPL_Line
     (Self : in out Session; First_Line : Boolean;
      Line : out Ada.Strings.Unbounded.Unbounded_String;
      Available : out Boolean) return Execution_Result;
   --  Resolve and retain the actual prompt through native readline/fgets.
   --  Copy the returned C-string prefix and release the transport buffer
   --  exactly once, including exceptional copying. EOF sets Available false.
   --  Native fallback reads at most 511 bytes, including a possible LF.

   function Save_REPL_Line
     (Self : in out Session; Line : String) return Execution_Result;
   --  Save a complete nonempty command with the selected backend. A temporary
   --  selected-owner NUL-terminated buffer outlives the synchronous C call.
   --  Refusal is returned as a normal memory/resource failure; no buffer or
   --  borrowed view survives the call and the session remains owned.

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
