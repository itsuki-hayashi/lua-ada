with Lua.Frontend_Text;
with Lua.Lexers;
with Lua.Numbers;
with Lua.Runtime_Configuration;

private package Lua.Lexer_Core is
   --  The single lexical state machine serves both the public host scanner
   --  and owned parsing. Source is borrowed for each synchronous Next call;
   --  all retained token bytes belong to the caller's compilation arena.
   type Token is record
      Kind : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Location : Lua.Lexers.Source_Location;
      Text : Lua.Frontend_Text.Text_Ref;
      Numeric : Lua.Numbers.Number;
      After : Lua.Lexers.Source_Location;
   end record;
   type Scan_Result is record
      Status : Lua.Lexers.Scan_Status := Lua.Lexers.Success;
      Item : Token;
      Location : Lua.Lexers.Source_Location;
      Message : Lua.Frontend_Text.Text_Ref;
   end record;
   type Scanner_State is record
      Cursor : Lua.Lexers.Source_Location;
      Maximum : Positive := 100_000;
      Compatible_Global : Boolean :=
        Lua.Runtime_Configuration.Compatible_Global;
      --  Pinned default keeps 'global' contextual. Instrumented/configured
      --  consumers can select its reserved form without another scanner.
      Count : Natural := 0;
      Finished : Boolean := False;
      Terminal : Scan_Result;
   end record;
   function Next
     (Source : String; Self : in out Scanner_State;
      Texts : in out Lua.Frontend_Text.Arena) return Scan_Result;
   --  Retain one-token lookahead in the parser, never by scanning all input.
   --  Allocation refusal propagates for the owning runtime's memory policy;
   --  only language/explicit frontend limits become returned scan failures.
end Lua.Lexer_Core;
