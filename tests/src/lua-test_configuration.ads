package Lua.Test_Configuration is
   function Compatible_Global return Boolean;
   --  Expected lexical contract of the selected build, independent of the
   --  lexer/parser being tested. Instrumented Lua reserves the global word.
end Lua.Test_Configuration;
