package Lua.Sessions.CLI is
   function Write_Prompt
     (Self : in out Session; First_Line : Boolean) return Execution_Result;
   --  CLI-only operation: resolve _PROMPT/_PROMPT2 through the actual global
   --  environment, apply auxiliary tostring semantics and publish the prompt.
   --  Nil selects the native default. The converted Lua string stays rooted
   --  until its C-string prefix has been written and flushed. No value or
   --  string borrow escapes this call; errors/exits retain session policy.
   --  This child is built only by CLI/test projects, outside the runtime SAL.
end Lua.Sessions.CLI;
