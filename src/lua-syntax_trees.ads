with Lua.Frontend_Text;
with Lua.Inputs;
with Lua.Lexer_Core;
with Lua.Lexers;
with Lua.Runtime_Configuration;
with Lua.Storage.Vectors;
with Lua.Syntax;

private package Lua.Syntax_Trees is
   --  One compilation unit owns every syntax node and declaration. Indexed
   --  links survive vector growth; there are no pointers into movable storage.
   subtype Text_Ref is Lua.Frontend_Text.Text_Ref;
   Empty_Text : constant Text_Ref := Lua.Frontend_Text.Empty_Text;
   type Node_Id is new Natural;
   No_Node : constant Node_Id := 0;
   type Symbol_Id is new Natural;
   No_Symbol : constant Symbol_Id := 0;
   package Node_Lists is new Lua.Storage.Vectors (Node_Id);
   package Symbol_Lists is new Lua.Storage.Vectors (Symbol_Id);
   type Attribute is (Regular, Constant_Name, Closing_Name, Vararg_Name);
   type Binding_Kind is (Local_Name, Global_Name, Collective_Name);
   type Binding is record
      Name : Text_Ref;
      Kind : Binding_Kind := Local_Name;
      Mode : Attribute := Regular;
      Owner : Node_Id := No_Node;
      Site : Lua.Lexers.Source_Location;
   end record;
   package Bindings is new Lua.Storage.Vectors (Binding);
   type Node_Kind is
     (Literal, Name_Reference, Unary_Expression, Binary_Expression,
      Parenthesized, Index_Expression, Call_Expression, Method_Expression,
      Table_Expression, Table_Field, Function_Expression, Block_Statement,
      Assignment, Declaration, Call_Statement, If_Statement, While_Statement,
      Repeat_Statement, Numeric_For, Generic_For, Return_Statement,
      Break_Statement, Goto_Statement, Label_Statement, Empty_Statement);
   type Node (Kind : Node_Kind := Empty_Statement) is record
      Site : Lua.Lexers.Source_Location;
      End_Line : Natural := 0;
      Header_Line : Natural := 0;
      --  A for header's consumed do token. Entry preparation uses this line,
      --  while loop revisits use the for/iterator-expression source site.
      Children : Node_Lists.Vector;
      Symbols : Symbol_Lists.Vector;
      Captures : Symbol_Lists.Vector;
      Symbol : Symbol_Id := No_Symbol;
      Environment : Symbol_Id := No_Symbol;
      Text : Text_Ref;
      Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Flag : Boolean := False;
      Target : Node_Id := No_Node;
      case Kind is
         when Literal => Value : Lua.Lexer_Core.Token;
         when others => null;
      end case;
   end record;
   --  Children preserve source order. Declaration Symbols become visible
   --  only after its initializer nodes, except recursive local functions.
   --  Function Symbols are parameters; Flag means varargs are accepted.
   --  Name Symbol=0 means an _ENV lookup through Environment. Flag is const.
   package Nodes is new Lua.Storage.Vectors (Node);
   type Diagnostic is record
      Source, Message : Text_Ref;
      Line, Column : Positive := 1;
   end record;
   type Parse_Result is record
      Status : Lua.Syntax.Check_Status := Lua.Syntax.Success;
      Error : Diagnostic;
      Incomplete_Input : Boolean := False;
      --  Grammar expectations opt in only at the actual EOF token. Static
      --  name/label/attribute errors remain final even when their scan ended.
      Stack_Overflow : Boolean := False;
      --  Compatible parser depth fails like Lua's C-stack check: callers
      --  preserve its runtime-error status rather than a syntax-error status.
   end record;
   type Compilation_Unit is limited record
      Default_Memory : aliased Lua.Storage.Owner;
      --  Declared before borrowers: standalone units own their default arena;
      --  runtime units select the longer-lived universe allocator instead.
      Memory : Lua.Storage.Owner_Access;
      Texts : Lua.Frontend_Text.Arena;
      Tree : Nodes.Vector;
      Names : Bindings.Vector;
      Root : Node_Id := No_Node;
      Environment : Symbol_Id := No_Symbol;
      Unsupported : Node_Id := No_Node;
      Result : Parse_Result;
   end record;
   procedure Parse
     (Unit : in out Compilation_Unit; Source, Name : String;
      Limits : Lua.Syntax.Check_Limits;
      Memory : Lua.Storage.Owner_Access := null;
      Compatible_Global : Boolean :=
        Lua.Runtime_Configuration.Compatible_Global;
      Compatible_Limits : Boolean := False);
   procedure Parse
     (Unit : in out Compilation_Unit; Source : in out Lua.Inputs.Source;
      Name : String; Limits : Lua.Syntax.Check_Limits;
      Memory : Lua.Storage.Owner_Access := null;
      Compatible_Global : Boolean :=
        Lua.Runtime_Configuration.Compatible_Global;
      Compatible_Limits : Boolean := False);
   --  Build fully resolved owned syntax or a structured error. No World,
   --  VM register or prototype participates in parsing. An explicit allocator
   --  routes all retained syntax/text storage through its owning universe;
   --  omitting it uses the unit's independent standard-Ada storage owner.
   --  A previously bound unit can be reused only with the same owner.
   --  Compatible_Global follows the pinned default LUA_COMPAT_GLOBAL=1;
   --  false reserves the keyword for configuration-sensitive C consumers.
   --  Compatible_Limits selects catchable parser-stack overflow and explicit
   --  local-limit checks after initialization. False preserves standalone
   --  checking and bounded Ada session host-depth accounting.
   --  Both overloads use the same parser. A streaming source requests pieces
   --  through its guarded owner only when lexical lookahead needs more bytes.
   function Text (Unit : Compilation_Unit; Item : Text_Ref) return String;
   procedure Query_Text
     (Unit : in out Compilation_Unit; Item : Text_Ref;
      Process : not null access procedure (Text : String));
   --  Borrow actual arena bytes only during Process, without a String copy.
   function Text_Length (Item : Text_Ref) return Natural;
   function Text_Element
     (Unit : Compilation_Unit; Item : Text_Ref; Index : Positive)
      return Character;
end Lua.Syntax_Trees;
