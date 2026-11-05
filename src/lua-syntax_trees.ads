with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Lua.Lexers;
with Lua.Syntax;

private package Lua.Syntax_Trees is
   --  One compilation unit owns every syntax node and declaration. Indexed
   --  links survive vector growth; there are no pointers into movable storage.
   use Ada.Strings.Unbounded;
   type Node_Id is new Natural;
   No_Node : constant Node_Id := 0;
   type Symbol_Id is new Natural;
   No_Symbol : constant Symbol_Id := 0;
   package Node_Lists is new Ada.Containers.Vectors (Positive, Node_Id);
   package Symbol_Lists is new Ada.Containers.Vectors (Positive, Symbol_Id);
   type Attribute is (Regular, Constant_Name, Closing_Name, Vararg_Name);
   type Binding_Kind is (Local_Name, Global_Name, Collective_Name);
   type Binding is record
      Name : Unbounded_String;
      Kind : Binding_Kind := Local_Name;
      Mode : Attribute := Regular;
      Owner : Node_Id := No_Node;
      Site : Lua.Lexers.Source_Location;
   end record;
   package Bindings is new Ada.Containers.Vectors (Positive, Binding);
   type Node_Kind is
     (Literal, Name_Reference, Unary_Expression, Binary_Expression,
      Parenthesized, Index_Expression, Call_Expression, Method_Expression,
      Table_Expression, Table_Field, Function_Expression, Block_Statement,
      Assignment, Declaration, Call_Statement, If_Statement, While_Statement,
      Repeat_Statement, Numeric_For, Generic_For, Return_Statement,
      Break_Statement, Goto_Statement, Label_Statement, Empty_Statement);
   type Node (Kind : Node_Kind := Empty_Statement) is record
      Site : Lua.Lexers.Source_Location;
      Children : Node_Lists.Vector;
      Symbols : Symbol_Lists.Vector;
      Captures : Symbol_Lists.Vector;
      Symbol : Symbol_Id := No_Symbol;
      Environment : Symbol_Id := No_Symbol;
      Text : Unbounded_String;
      Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Flag : Boolean := False;
      Target : Node_Id := No_Node;
      case Kind is
         when Literal => Value : Lua.Lexers.Token;
         when others => null;
      end case;
   end record;
   --  Children preserve source order. Declaration Symbols become visible
   --  only after its initializer nodes, except recursive local functions.
   --  Function Symbols are parameters; Flag means varargs are accepted.
   --  Name Symbol=0 means an _ENV lookup through Environment. Flag is const.
   package Nodes is new Ada.Containers.Vectors (Positive, Node);
   type Compilation_Unit is limited record
      Tree : Nodes.Vector;
      Names : Bindings.Vector;
      Root : Node_Id := No_Node;
      Environment : Symbol_Id := No_Symbol;
      Unsupported : Node_Id := No_Node;
      Result : Lua.Syntax.Check_Result;
   end record;
   procedure Parse
     (Unit : in out Compilation_Unit; Source, Name : String;
      Limits : Lua.Syntax.Check_Limits);
   --  Build fully resolved owned syntax or a structured error. No World,
   --  VM register, prototype, or runtime allocation participates in parsing.
end Lua.Syntax_Trees;
