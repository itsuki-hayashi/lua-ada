with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Lua.Lexers is
   --  Byte-oriented Lua 5.5 lexical analysis. This development interface is
   --  not the session embedding API. Locations count source bytes from one.

   type Token_Kind is
     (End_Of_Input, Identifier, Number_Literal, String_Literal,
      And_Word, Break_Word, Do_Word, Else_Word, Elseif_Word, End_Word,
      False_Word, For_Word, Function_Word, Global_Word, Goto_Word,
      If_Word, In_Word, Local_Word, Nil_Word, Not_Word, Or_Word,
      Repeat_Word, Return_Word, Then_Word, True_Word, Until_Word,
      While_Word, Plus, Minus, Star, Slash, Floor_Divide, Percent,
      Power, Length, Bit_And, Bit_Or, Bit_Xor, Shift_Left, Shift_Right,
      Equal, Not_Equal, Less, Less_Equal, Greater, Greater_Equal,
      Assign, Left_Paren, Right_Paren, Left_Brace, Right_Brace,
      Left_Bracket, Right_Bracket, Semicolon, Colon, Double_Colon,
      Comma, Dot, Concatenate, Varargs);
   --  Keywords include deferred syntax so the parser can reject it clearly.

   type Source_Location is record
      Offset : Positive := 1;
      Line   : Positive := 1;
      Column : Positive := 1;
   end record;
   --  Offset and Column count bytes, not Unicode characters.

   type Token is record
      Kind     : Token_Kind := End_Of_Input;
      Location : Source_Location;
      Text     : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Text contains decoded bytes for strings and source spelling otherwise.

   package Token_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Token);

   type Scan_Status is (Success, Syntax_Error, Resource_Error);
   --  Language failures are returned; they do not escape as Ada exceptions.

   type Scan_Result is record
      Status   : Scan_Status := Success;
      Tokens   : Token_Lists.Vector;
      Location : Source_Location;
      Message  : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  A failed scan has no partial token list. Message describes the failure.

   function Scan
     (Source         : String;
      Maximum_Tokens : Positive := 100_000) return Scan_Result;
   --  Tokenize Source, including a final End_Of_Input token within the limit.
   --  @param Source Source bytes; any String lower bound is accepted.
   --  @param Maximum_Tokens Bound on token count, including End_Of_Input.
   --  @return Tokens or a located syntax/resource error.
end Lua.Lexers;
