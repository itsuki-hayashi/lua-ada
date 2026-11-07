with Lua.Lexers; use Lua.Lexers;
with Ada.Characters.Handling;
with Lua.Storage.Buffers;

package body Lua.Syntax_Trees is
   use type Lua.Syntax.Check_Status;
   use type Lua.Storage.Owner_Access;

   --  Library-level instantiation is required by the shared subpool. Local
   --  access types could not allocate safely into a longer-lived owner.
   type Jump_Record is record
      Item : Node_Id;
      Block : Natural;
      Owner : Node_Id;
      Active : Symbol_Lists.Vector;
      Solved : Boolean := False;
   end record;
   package Jumps is new Lua.Storage.Vectors (Jump_Record);

   function Text (Unit : Compilation_Unit; Item : Text_Ref) return String is
     (Unit.Texts.Text (Item));

   procedure Query_Text
     (Unit : in out Compilation_Unit; Item : Text_Ref;
      Process : not null access procedure (Text : String)) is
   begin
      Unit.Texts.Query (Item, Process);
   end Query_Text;

   function Text_Length (Item : Text_Ref) return Natural is (Item.Length);

   function Text_Element
     (Unit : Compilation_Unit; Item : Text_Ref; Index : Positive)
      return Character is
     (Unit.Texts.Element (Item, Index));

   procedure Parse
     (Unit : in out Compilation_Unit; Source, Name : String;
      Limits : Lua.Syntax.Check_Limits;
      Memory : Lua.Storage.Owner_Access := null;
      Compatible_Global : Boolean :=
        Lua.Runtime_Configuration.Compatible_Global)
   is
      Input : Lua.Inputs.Source;
   begin
      Input.Borrow (Source'Address, Source'Length);
      Parse (Unit, Input, Name, Limits, Memory, Compatible_Global);
   end Parse;

   procedure Parse
     (Unit : in out Compilation_Unit; Source : in out Lua.Inputs.Source;
      Name : String; Limits : Lua.Syntax.Check_Limits;
      Memory : Lua.Storage.Owner_Access := null;
      Compatible_Global : Boolean :=
        Lua.Runtime_Configuration.Compatible_Global)
   is
      Selected : constant not null Lua.Storage.Owner_Access :=
        (if Memory /= null then Memory
         else Lua.Storage.Reference (Unit.Default_Memory));
      Reader : Lua.Lexer_Core.Scanner_State :=
        (Maximum => Limits.Tokens, Compatible_Global => Compatible_Global,
         others => <>);
      Current, Lookahead : Lua.Lexer_Core.Token;
      Have_Lookahead : Boolean := False;
      Active : Symbol_Lists.Vector;
      Function_Node : Node_Id := No_Node;
      Varargs : Boolean := True;
      Loop_Depth : Natural := 0;
      Depth : Natural := 0;
      Last_Line : Positive := 1;
      Scope : Natural := 0;
      Next_Scope : Natural := 0;
      Abandon : exception;
      Gotos, Labels : Jumps.Vector;

      function Here return Source_Location is (Current.Location);
      function Kind return Token_Kind is (Current.Kind);
      function Image (Item : Text_Ref) return String is (Text (Unit, Item));
      function Own (Bytes : String) return Text_Ref is
        (Lua.Frontend_Text.Store (Unit.Texts, Bytes));
      function Matches (Left, Right : Text_Ref) return Boolean is
        (Unit.Texts.Equal (Left, Right));
      function Matches (Left : Text_Ref; Right : String) return Boolean is
        (Unit.Texts.Equal (Left, Right));
      procedure Error
        (Message : String; Resource : Boolean := False;
         Incomplete : Boolean := False; Near_Token : Boolean := True);
      function Expected_Name (Item : Token_Kind) return String;
      function Line_Text (Line : Positive) return String;
      procedure Advance;
      function Peek return Token_Kind;
      function Take (Expected : Token_Kind) return Boolean;
      procedure Expect (Expected : Token_Kind);
      function Read_Name return Text_Ref;
      function Add (Item : Node) return Node_Id;
      function Fetch (Id : Node_Id) return Node is
        (Unit.Tree (Positive (Id)));
      procedure Save (Id : Node_Id; Item : Node);
      subtype Structural_Kind is Node_Kind
        range Name_Reference .. Empty_Statement;
      function Make (What : Structural_Kind) return Node_Id;
      procedure Child (Parent, Item : Node_Id);
      procedure Remember_End (Id : Node_Id);
      function New_Name
        (Name : Text_Ref; Mode : Attribute := Regular;
         Kind : Binding_Kind := Local_Name) return Symbol_Id;
      function Resolve
        (Name : Text_Ref; Environment : Boolean := False;
         Referenced : Text_Ref := Empty_Text)
         return Node_Id;
      procedure Writable (Id : Node_Id);
      function Expression (Minimum : Natural := 0) return Node_Id;
      function Prefix return Node_Id;
      function Constructor return Node_Id;
      function Function_Body
        (Definition : Source_Location; Method : Boolean := False)
         return Node_Id;
      function Expression_List return Node_Id;
      function Block (Own_Scope : Boolean := True) return Node_Id;
      function Statement return Node_Id;
      function Declaration
        (Global : Boolean := False; Recursive : Boolean := False;
         Definition : Source_Location := (others => 1)) return Node_Id;
      function Get_Attribute (Default : Attribute := Regular) return Attribute;
      procedure Finish_Scope
        (Block : Natural; Parent : Natural; Base : Symbol_Lists.Vector);
      procedure Enter;
      procedure Leave;

      function Line_Text (Line : Positive) return String is
         Image : constant String := Line'Image;
      begin
         return Image (2 .. Image'Last);
      end Line_Text;

      function Expected_Name (Item : Token_Kind) return String is
         Label : constant String := Token_Kind'Image (Item);
      begin
         --  Token names describe diagnostics, not another grammar. Keep the
         --  fixed spellings from llex.c distinct from source identifiers.
         if Item in And_Word .. While_Word then
            return "'" & Ada.Characters.Handling.To_Lower
              (Label (Label'First .. Label'Last - 5)) & "'";
         end if;
         return (case Item is
            when End_Of_Input => "<eof>", when Identifier => "<name>",
            when Integer_Literal => "<integer>",
            when Float_Literal => "<number>",
            when String_Literal => "<string>",
            when Plus => "'+'", when Minus => "'-'", when Star => "'*'",
            when Slash => "'/'", when Floor_Divide => "'//'",
            when Percent => "'%'", when Power => "'^'", when Length => "'#'",
            when Bit_And => "'&'", when Bit_Or => "'|'", when Bit_Xor => "'~'",
            when Shift_Left => "'<<'", when Shift_Right => "'>>'",
            when Equal => "'=='", when Not_Equal => "'~='",
            when Less => "'<'", when Less_Equal => "'<='",
            when Greater => "'>'", when Greater_Equal => "'>='",
            when Assign => "'='", when Left_Paren => "'('",
            when Right_Paren => "')'", when Left_Brace => "'{'",
            when Right_Brace => "'}'", when Left_Bracket => "'['",
            when Right_Bracket => "']'", when Semicolon => "';'",
            when Colon => "':'", when Double_Colon => "'::'",
            when Comma => "','", when Dot => "'.'",
            when Concatenate => "'..'", when Lua.Lexers.Varargs => "'...'",
            when others => "<symbol>");
      end Expected_Name;

      procedure Error
        (Message : String; Resource : Boolean := False;
         Incomplete : Boolean := False; Near_Token : Boolean := True)
      is
         Diagnostic : Lua.Storage.Buffers.Buffer;
         Truncated : Boolean := False;
         procedure Append_Text (Bytes : String);
         procedure Append_Text (Bytes : String) is
         begin
            --  txtToken uses a C string: embedded NUL ends the diagnostic,
            --  although the actual owned token retains every decoded byte.
            for Byte of Bytes loop
               if Byte = Character'Val (0) then
                  Truncated := True;
                  exit;
               end if;
               Diagnostic.Append (Byte);
            end loop;
         end Append_Text;
      begin
         --  Error text belongs to the same unit as the failing token. Only
         --  the public checking wrapper materializes a host diagnostic; an
         --  allocator refusal here must remain the runtime's memory failure.
         Unit.Result.Status :=
           (if Resource then Lua.Syntax.Resource_Error
            else Lua.Syntax.Syntax_Error);
         Unit.Result.Error.Line := Current.After.Line;
         Unit.Result.Error.Column := Here.Column;
         Unit.Result.Incomplete_Input := Incomplete and then not Resource;
         Diagnostic.Set_Owner (Selected);
         Diagnostic.Append (Message);
         if Near_Token and then not Resource then
            Diagnostic.Append (" near ");
            if Kind = End_Of_Input then
               Diagnostic.Append ("<eof>");
            elsif Kind = Byte_Symbol and then
              Character'Pos (Source.Element (Here.Offset)) not in 32 .. 126
            then
               declare
                  Code : constant String := Natural'Image
                    (Character'Pos (Source.Element (Here.Offset)));
               begin
                  Diagnostic.Append ("'<\" & Code (2 .. Code'Last) & ">'");
               end;
            else
               Diagnostic.Append (''');
               if Kind = String_Literal then
                  --  Quoted strings keep their delimiters in C's token
                  --  buffer. Long strings keep the complete bracket level;
                  --  borrow only those already-read delimiter bytes here.
                  declare
                     First : constant Character :=
                       Source.Element (Here.Offset);
                     Level : Natural := 1;
                  begin
                     if First = '[' then
                        while Source.Element (Here.Offset + Level) = '='
                        loop
                           Level := Level + 1;
                        end loop;
                        Level := Level + 1;
                     end if;
                     Source.Query (Here.Offset, Level, Append_Text'Access);
                     Unit.Texts.Query (Current.Text, Append_Text'Access);
                     if not Truncated then
                        Source.Query (Current.After.Offset - Level, Level,
                                      Append_Text'Access);
                     end if;
                  end;
               else
                  Unit.Texts.Query (Current.Text, Append_Text'Access);
               end if;
               Diagnostic.Append (''');
            end if;
         end if;
         Unit.Result.Error.Message :=
           Lua.Frontend_Text.Store (Unit.Texts, Diagnostic);
         raise Abandon;
      end Error;

      function Read_Token return Lua.Lexer_Core.Token;
      function Read_Token return Lua.Lexer_Core.Token is
         Step : constant Lua.Lexer_Core.Scan_Result :=
           Lua.Lexer_Core.Next (Source, Reader, Unit.Texts);
      begin
         --  The scanner retains no source copy or host token list. Its arena
         --  references survive the Reader, so lowering can consume the unit
         --  after parser-local scopes and one-token lookahead are discarded.
         if Step.Status /= Success then
            Current.Location := Step.Location;
            Current.After := Step.Location;
            --  A lexical diagnostic already belongs to the unit's arena.
            --  Retain that reference directly instead of copying it through
            --  a host String and appending a second diagnostic allocation.
            Unit.Result.Status :=
              (if Step.Status = Resource_Error then Lua.Syntax.Resource_Error
               else Lua.Syntax.Syntax_Error);
            Unit.Result.Error.Line := Step.Location.Line;
            Unit.Result.Error.Column := Step.Location.Column;
            Unit.Result.Error.Message := Step.Message;
            Unit.Result.Incomplete_Input := Step.Incomplete_Input;
            raise Abandon;
         end if;
         return Step.Item;
      end Read_Token;

      procedure Advance is
      begin
         Last_Line := Current.After.Line;
         if Have_Lookahead then
            Current := Lookahead;
            Have_Lookahead := False;
         else
            Current := Read_Token;
         end if;
      end Advance;

      function Peek return Token_Kind is
      begin
         --  Only table fields and contextual global declarations need one
         --  lookahead token. Preserve it so requesting it cannot skip input.
         if not Have_Lookahead then
            Lookahead := Read_Token;
            Have_Lookahead := True;
         end if;
         return Lookahead.Kind;
      end Peek;

      function Take (Expected : Token_Kind) return Boolean is
      begin
         if Kind /= Expected then
            return False;
         end if;
         Advance;
         return True;
      end Take;

      procedure Expect (Expected : Token_Kind) is
      begin
         if not Take (Expected) then
            Error (Expected_Name (Expected) & " expected",
                   Incomplete => Kind = End_Of_Input);
         end if;
      end Expect;

      function Read_Name return Text_Ref is
         Result : constant Text_Ref := Current.Text;
      begin
         Expect (Identifier);
         return Result;
      end Read_Name;

      function Add (Item : Node) return Node_Id is
         Owned : Node := Item;
      begin
         --  Enforce storage bounds before vector growth; no partially
         --  published node ID can escape a resource failure.
         if Natural (Unit.Tree.Length) >= Limits.Syntax_Nodes then
            Error ("syntax node limit exceeded", Resource => True);
         end if;
         --  Empty nested lists begin unbound. Bind them before publication;
         --  later child/capture appends then share the compilation allocator.
         Owned.Children.Set_Owner (Selected);
         Owned.Symbols.Set_Owner (Selected);
         Owned.Captures.Set_Owner (Selected);
         Unit.Tree.Append (Owned);
         return Node_Id (Unit.Tree.Last_Index);
      end Add;

      procedure Save (Id : Node_Id; Item : Node) is
      begin
         Unit.Tree.Replace_Element (Positive (Id), Item);
      end Save;

      function Make (What : Structural_Kind) return Node_Id is
      begin
         return Add ((Kind => What, Site => Here, others => <>));
      end Make;

      procedure Child (Parent, Item : Node_Id) is
         Value : constant Nodes.Reference_Type :=
           Unit.Tree.Reference (Positive (Parent));
      begin
         --  Append in place: copying the parent's growing child vector for
         --  every statement makes a flat block quadratic. This reference
         --  guards the outer arena only while its nested vector is mutated;
         --  no arena node is allocated until the reference leaves scope.
         Value.Children.Append (Item);
      end Child;

      procedure Remember_End (Id : Node_Id) is
         Item : constant Nodes.Reference_Type :=
           Unit.Tree.Reference (Positive (Id));
      begin
         --  Retain only consumed-token metadata. This brief borrow never
         --  copies a node's input-sized lists or survives a tree append.
         Item.End_Line := Last_Line;
      end Remember_End;

      procedure Enter is
      begin
         Depth := Depth + 1;
         if Depth > Limits.Nesting then
            Error ("syntax nesting limit exceeded", Resource => True);
         end if;
      end Enter;

      procedure Leave is
      begin
         Depth := Depth - 1;
      end Leave;

      function New_Name
        (Name : Text_Ref; Mode : Attribute := Regular;
         Kind : Binding_Kind := Local_Name) return Symbol_Id
      is
      begin
         if Natural (Unit.Names.Length) >= Limits.Syntax_Nodes then
            Error ("declaration limit exceeded", Resource => True);
         end if;
         Unit.Names.Append
           (Binding'(Name, Kind, Mode, Function_Node, Here));
         return Symbol_Id (Unit.Names.Last_Index);
      end New_Name;

      function Resolve
        (Name : Text_Ref; Environment : Boolean := False;
         Referenced : Text_Ref := Empty_Text)
         return Node_Id
      is
         Result : Node := (Kind => Name_Reference, Site => Here,
                           Text => Name, others => <>);
         Named_Global : Boolean := False;
         Collective : Boolean := False;
         Read_Only : Boolean := False;
         Explicit_Name : Boolean := False;
      begin
         --  Search source-point declarations, including outer functions.
         --  Globals restrict implicit names; a collective declaration restores
         --  them. Captures retain a unique Symbol_Id across later shadowing.
         for Id of reverse Active loop
            declare
               Item : constant Binding := Unit.Names (Positive (Id));
            begin
               if Item.Kind = Collective_Name then
                  if not Collective then
                     Collective := True;
                     Read_Only := Item.Mode = Constant_Name;
                  end if;
               elsif Matches (Item.Name, Name) then
                  Explicit_Name := True;
                  Result.Symbol :=
                    (if Item.Kind = Local_Name then Id else No_Symbol);
                  Result.Flag := Item.Mode /= Regular;
                  exit;
               elsif Item.Kind = Global_Name then
                  Named_Global := True;
               end if;
            end;
         end loop;
         if Result.Symbol = No_Symbol then
            if Named_Global and then not Collective then
               --  A matching explicit global bypasses implicit restrictions.
               declare
                  Found : Boolean := False;
               begin
                  for Id of reverse Active loop
                     if Matches (Unit.Names (Positive (Id)).Name, Name) then
                        Found := True;
                        exit;
                     end if;
                  end loop;
                  if not Found then
                     Error ("variable '" & Image (Name) &
                            "' not declared", Near_Token => False);
                  end if;
               end;
            end if;
            --  An explicit declaration supplies its own attribute, even
            --  when a nearer collective declaration supplied the fallback.
            if not Explicit_Name then
               Result.Flag := Read_Only;
            end if;
            if Environment then
               Error ("_ENV is global when accessing variable '" &
                      Image (Referenced) & "'", Near_Token => False);
            end if;
            declare
               Env : constant Node_Id := Resolve
                 (Own ("_ENV"), Environment => True,
                  Referenced => Name);
            begin
               Result.Environment := Fetch (Env).Symbol;
            end;
         elsif Function_Node /= No_Node then
            --  Record captures through every intervening function. Runtime
            --  lowering uses environment cells, but resolution must retain
            --  this ownership relationship independently of that backend.
            declare
               Owner : constant Node_Id :=
                 Unit.Names (Positive (Result.Symbol)).Owner;
               Function_Id : Node_Id := Function_Node;
               Closure : Node;
            begin
               while Function_Id /= Owner and then
                 Function_Id /= No_Node
               loop
                  Closure := Fetch (Function_Id);
                  if not Closure.Captures.Contains (Result.Symbol) then
                     Closure.Captures.Append (Result.Symbol);
                     Save (Function_Id, Closure);
                  end if;
                  Function_Id := Closure.Target;
               end loop;
            end;
         end if;
         return Add (Result);
      end Resolve;

      procedure Writable (Id : Node_Id) is
         Item : constant Node := Fetch (Id);
      begin
         if Item.Kind not in Name_Reference | Index_Expression then
            Error ("assignment target expected");
         elsif Item.Kind = Name_Reference and then Item.Flag then
            Error ("attempt to assign to const variable '" &
                   Image (Item.Text) & "'", Near_Token => False);
         end if;
      end Writable;

      function Get_Attribute (Default : Attribute := Regular) return Attribute
      is
         Name : Text_Ref;
      begin
         if not Take (Less) then
            return Default;
         end if;
         Name := Read_Name;
         Expect (Greater);
         if Matches (Name, "const") then
            return Constant_Name;
         elsif Matches (Name, "close") then
            return Closing_Name;
         else
            --  Retain the attribute spelling in the diagnostic. Attributes
            --  are contextual names, so an unknown one must not be reported
            --  as a general declaration failure (lparser.c:1807).
            Error ("unknown attribute '" & Image (Name) & "'",
                   Near_Token => False);
            return Regular;
         end if;
      end Get_Attribute;

      function Expression_List return Node_Id is
         Result : constant Node_Id := Make (Block_Statement);
      begin
         loop
            Child (Result, Expression);
            exit when not Take (Comma);
         end loop;
         Remember_End (Result);
         return Result;
      end Expression_List;

      function Constructor return Node_Id is
         Result : constant Node_Id := Make (Table_Expression);
         Field : Node_Id;
         Key : Lua.Lexer_Core.Token;
      begin
         --  Store fields in source order. A one-child field is sequential;
         --  a two-child field retains its explicit key/value evaluation order.
         Expect (Left_Brace);
         while Kind /= Right_Brace loop
            Field := Make (Table_Field);
            if Take (Left_Bracket) then
               Child (Field, Expression);
               Expect (Right_Bracket);
               Expect (Assign);
               Child (Field, Expression);
            elsif Kind = Identifier and then Peek = Assign then
               Key := Current;
               Key.Kind := String_Literal;
               Child (Field, Add ((Kind => Literal, Site => Here,
                                  Value => Key, others => <>)));
               Advance;
               Expect (Assign);
               Child (Field, Expression);
            else
               Child (Field, Expression);
            end if;
            Child (Result, Field);
            exit when not Take (Comma) and then not Take (Semicolon);
         end loop;
         Expect (Right_Brace);
         return Result;
      end Constructor;

      function Function_Body
        (Definition : Source_Location; Method : Boolean := False)
         return Node_Id is
         Result : constant Node_Id := Make (Function_Expression);
         Saved_Function : constant Node_Id := Function_Node;
         Saved_Varargs : constant Boolean := Varargs;
         Saved_Loops : constant Natural := Loop_Depth;
         Saved_Scope : constant Natural := Scope;
         Saved : constant Symbol_Lists.Vector := Active;
         Item : Node := Fetch (Result);
         Id : Symbol_Id;
      begin
         --  Parameters share source-point lookup with outer captures, while
         --  goto visibility, break targets, and vararg eligibility restart at
         --  each function boundary. Restore all parent context on success;
         --  failures discard the entire owned compilation unit.
         Enter;
         Function_Node := Result;
         Item.Site := Definition;
         Item.Target := Saved_Function;
         Save (Result, Item);
         Varargs := False;
         Loop_Depth := 0;
         Scope := 0;
         Expect (Left_Paren);
         if Method then
            Id := New_Name (Own ("self"));
            Active.Append (Id);
            Item.Symbols.Append (Id);
         end if;
         if Kind /= Right_Paren then
            loop
               if Take (Lua.Lexers.Varargs) then
                  Varargs := True;
                  if Kind = Identifier then
                     Id := New_Name (Read_Name, Vararg_Name);
                     Active.Append (Id);
                     Item.Symbol := Id;
                  end if;
                  exit;
               end if;
               Id := New_Name (Read_Name);
               Active.Append (Id);
               Item.Symbols.Append (Id);
               exit when not Take (Comma);
            end loop;
         end if;
         Expect (Right_Paren);
         Item.Flag := Varargs;
         Save (Result, Item);
         Child (Result, Block);
         Item := Fetch (Result);
         Item.End_Line := Here.Line;
         Save (Result, Item);
         Expect (End_Word);
         Active := Saved;
         Function_Node := Saved_Function;
         Varargs := Saved_Varargs;
         Loop_Depth := Saved_Loops;
         Scope := Saved_Scope;
         Leave;
         return Result;
      end Function_Body;

      function Prefix return Node_Id is
         Result, Next : Node_Id;
         Key : Lua.Lexer_Core.Token;
         Method : Boolean;
      begin
         --  Build suffix nodes rather than reading an indexed value here.
         --  The same resolved node can become an assignment address later.
         --  Parentheses deliberately remove assignability/multiple results.
         if Kind = Identifier then
            Result := Resolve (Current.Text);
            Advance;
         elsif Take (Left_Paren) then
            Result := Make (Parenthesized);
            Child (Result, Expression);
            Expect (Right_Paren);
         else
            Error ("unexpected symbol", Incomplete => Kind = End_Of_Input);
            return No_Node;
         end if;
         Remember_End (Result);
         loop
            Method := False;
            if Take (Left_Bracket) then
               Next := Make (Index_Expression);
               Child (Next, Result);
               Child (Next, Expression);
               Expect (Right_Bracket);
               Result := Next;
            elsif Kind in Dot | Colon then
               Method := Kind = Colon;
               Advance;
               Key := Current;
               Expect (Identifier);
               Key.Kind := String_Literal;
               Next := Make
                 ((if Method then Method_Expression else Index_Expression));
               Child (Next, Result);
               Child (Next, Add ((Kind => Literal, Site => Key.Location,
                                 Value => Key, others => <>)));
               Result := Next;
            elsif Kind not in Left_Paren | String_Literal | Left_Brace then
               exit;
            end if;
            if Method or else
              Kind in Left_Paren | String_Literal | Left_Brace
            then
               Next := Make (Call_Expression);
               Child (Next, Result);
               if Take (Left_Paren) then
                  if Kind /= Right_Paren then
                     Child (Next, Expression_List);
                  else
                     Child (Next, Make (Block_Statement));
                  end if;
                  Expect (Right_Paren);
               else
                  declare
                     Args : constant Node_Id := Make (Block_Statement);
                  begin
                     if Kind = Left_Brace then
                        Child (Args, Constructor);
                     elsif Kind = String_Literal then
                        Child (Args, Add ((Kind => Literal, Site => Here,
                                          Value => Current, others => <>)));
                        Advance;
                     else
                        Error ("function arguments expected",
                               Incomplete => Kind = End_Of_Input);
                     end if;
                     Child (Next, Args);
                  end;
               end if;
               Result := Next;
            end if;
            Remember_End (Result);
         end loop;
         return Result;
      end Prefix;

      function Priority (Op : Token_Kind) return Natural;
      function Priority (Op : Token_Kind) return Natural is
        (case Op is
            when Or_Word => 1, when And_Word => 2,
            when Equal | Not_Equal | Less | Less_Equal |
                 Greater | Greater_Equal => 3,
            when Bit_Or => 4, when Bit_Xor => 5, when Bit_And => 6,
            when Shift_Left | Shift_Right => 7, when Concatenate => 8,
            when Plus | Minus => 9,
            when Star | Slash | Floor_Divide | Percent => 10,
            when Power => 12, when others => 0);

      function Expression (Minimum : Natural := 0) return Node_Id is
         Result, Next : Node_Id;
         Op : Token_Kind;
         Site : Source_Location;
         Rank : Natural;
      begin
         --  Precedence climbing records evaluation order without executing
         --  or emitting code. Power and concatenation bind right-to-left;
         --  unary precedence is below power but above multiplicative forms.
         Enter;
         if Kind in Minus | Not_Word | Length | Bit_Xor then
            Op := Kind;
            Site := Here;
            Advance;
            Result := Add ((Kind => Unary_Expression, Site => Site,
                            Operator => Op, others => <>));
            Child (Result, Expression (11));
         elsif Kind in Number_Literal | String_Literal |
           Nil_Word | False_Word | True_Word
         then
            Result := Add ((Kind => Literal, Site => Here,
                            Value => Current, others => <>));
            Advance;
         elsif Kind = Lua.Lexers.Varargs then
            if not Varargs then
               Error ("cannot use '...' outside a vararg function");
            end if;
            Result := Add ((Kind => Literal, Site => Here,
                            Value => Current, others => <>));
            Advance;
         elsif Kind = Function_Word then
            Site := Here;
            Advance;
            Result := Function_Body (Site);
         elsif Kind = Left_Brace then
            Result := Constructor;
         else
            Result := Prefix;
         end if;
         while Priority (Kind) > Minimum loop
            Op := Kind;
            Rank := Priority (Op);
            Site := Here;
            Advance;
            Next := Add ((Kind => Binary_Expression, Site => Site,
                          Operator => Op, others => <>));
            Child (Next, Result);
            Child (Next, Expression
              ((if Op in Power | Concatenate then Rank - 1 else Rank)));
            Result := Next;
         end loop;
         --  Consumers can materialize a deferred expression later. Keep its
         --  final consumed token rather than guessing from lookahead/source.
         Remember_End (Result);
         Leave;
         return Result;
      end Expression;

      procedure Finish_Scope
        (Block : Natural; Parent : Natural; Base : Symbol_Lists.Vector)
      is
         Pending : Jump_Record;
         Destination : Node;
      begin
         --  Resolve against all labels in this block before exporting an
         --  unresolved jump outward. Inner blocks cannot see sibling labels.
         for Index in Gotos.First_Index .. Gotos.Last_Index loop
            Pending := Gotos (Index);
            if Pending.Block = Block and then not Pending.Solved then
               for Label of Labels loop
                  if Label.Block = Block and then
                    Label.Owner = Pending.Owner and then
                    Matches (Fetch (Label.Item).Text,
                             Fetch (Pending.Item).Text)
                  then
                     for Id of Label.Active loop
                        if not Pending.Active.Contains (Id) then
                           Error ("<goto " &
                                    Image (Fetch (Pending.Item).Text) &
                                    "> at line " & Line_Text
                                      (Fetch (Pending.Item).Site.Line) &
                                    " jumps into the scope of '" &
                                    Image (Unit.Names
                                      (Positive (Id)).Name) & "'",
                                  Near_Token => False);
                        end if;
                     end loop;
                     Destination := Fetch (Pending.Item);
                     Destination.Target := Label.Item;
                     Destination.Symbols := Label.Active;
                     Save (Pending.Item, Destination);
                     Pending.Solved := True;
                     exit;
                  end if;
               end loop;
               if not Pending.Solved then
                  if Parent = 0 then
                     Error ("no visible label '" &
                            Image (Fetch (Pending.Item).Text) &
                            "' for <goto> at line " & Line_Text
                              (Fetch (Pending.Item).Site.Line),
                            Near_Token => False);
                  end if;
                  Pending.Block := Parent;
                  Pending.Active := Base;
               end if;
               Gotos.Replace_Element (Index, Pending);
            end if;
         end loop;
         for Index in reverse Labels.First_Index .. Labels.Last_Index loop
            if Labels (Index).Block = Block then
               Labels.Delete (Index);
            end if;
         end loop;
      end Finish_Scope;

      function Block (Own_Scope : Boolean := True) return Node_Id is
         Result : constant Node_Id := Make (Block_Statement);
         Saved : constant Symbol_Lists.Vector := Active;
         Parent : constant Natural := Scope;
         Was_Return : Boolean;
         Item : Node_Id;
      begin
         Enter;
         if Own_Scope then
            Next_Scope := Next_Scope + 1;
            Scope := Next_Scope;
         end if;
         while Kind not in End_Of_Input | End_Word | Else_Word |
           Elseif_Word | Until_Word
         loop
            Was_Return := Kind = Return_Word;
            Item := Statement;
            Child (Result, Item);
            if Fetch (Item).Kind = Label_Statement and then
              Kind in End_Of_Input | End_Word | Else_Word | Elseif_Word
            then
               --  A terminal label is outside this block's locals. Only
               --  semicolons/labels can intervene; Statement consumes those.
               declare
                  Label_Data : Jump_Record := Labels.Last_Element;
               begin
                  Label_Data.Active := Saved;
                  Labels.Replace_Element (Labels.Last_Index, Label_Data);
               end;
            end if;
            exit when Was_Return;
         end loop;
         if Own_Scope then
            --  Every label in the trailing no-op sequence is outside locals,
            --  not just the final label. Until conditions retain body locals.
            if Kind /= Until_Word then
               for Id of reverse Fetch (Result).Children loop
                  exit when Fetch (Id).Kind not in
                    Label_Statement | Empty_Statement;
                  for Index in Labels.First_Index .. Labels.Last_Index loop
                     if Labels (Index).Item = Id then
                        declare
                           Data : Jump_Record := Labels (Index);
                        begin
                           Data.Active := Saved;
                           Labels.Replace_Element (Index, Data);
                        end;
                     end if;
                  end loop;
               end loop;
            end if;
            Finish_Scope (Scope, Parent, Saved);
            Scope := Parent;
            Active := Saved;
         end if;
         Leave;
         return Result;
      end Block;

      function Declaration
        (Global : Boolean := False; Recursive : Boolean := False;
         Definition : Source_Location := (others => 1)) return Node_Id
      is
         Result : constant Node_Id := Make (Syntax_Trees.Declaration);
         Item : Node := Fetch (Result);
         Default : Attribute := Regular;
         Mode : Attribute;
         Id : Symbol_Id;
         Closing : Boolean := False;
      begin
         --  Pending names are not visible to their own initializer list.
         --  Recursive local functions are the deliberate exception: publish
         --  their cell before resolving the function body.
         Item.Flag := Global;
         if Recursive then
            Id := New_Name (Read_Name);
            Item.Symbols.Append (Id);
            Active.Append (Id);
            Save (Result, Item);
            Child (Result, Function_Body (Definition));
            return Result;
         end if;
         Default := Get_Attribute;
         if Global and then Take (Star) then
            if Default = Closing_Name then
               Error ("global variables cannot be to-be-closed",
                      Near_Token => False);
            end if;
            Id := New_Name (Empty_Text, Default, Collective_Name);
            Active.Append (Id);
            Item.Symbols.Append (Id);
            Save (Result, Item);
            return Result;
         end if;
         loop
            declare
               Name : constant Text_Ref := Read_Name;
            begin
               Mode := Get_Attribute (Default);
               if Mode = Closing_Name then
                  if Global then
                     Error ("global variables cannot be to-be-closed",
                            Near_Token => False);
                  elsif Closing then
                     Error ("multiple to-be-closed variables in local list",
                            Near_Token => False);
                  end if;
                  Closing := True;
                  Unit.Unsupported := Result;
               end if;
               Id := New_Name
                 (Name, Mode, (if Global then Global_Name else Local_Name));
               Item.Symbols.Append (Id);
            end;
            exit when not Take (Comma);
         end loop;
         Save (Result, Item);
         if Take (Assign) then
            if Global then
               Item.Environment := Fetch (Resolve
                 (Own ("_ENV"), Environment => True)).Symbol;
               Save (Result, Item);
            end if;
            Child (Result, Expression_List);
         end if;
         for Symbol of Item.Symbols loop
            Active.Append (Symbol);
         end loop;
         return Result;
      end Declaration;

      function Statement return Node_Id is
         Result, Item, Target : Node_Id;
         Site : constant Source_Location := Here;
         Saved : Symbol_Lists.Vector;
         Id : Symbol_Id;
         Value : Node;
         Method : Boolean := False;
         Function_Site : Source_Location;
      begin
         if Take (Semicolon) then
            return Make (Empty_Statement);
         elsif Take (Do_Word) then
            Result := Block;
            Expect (End_Word);
         elsif Take (Local_Word) then
            declare
               Function_Site : constant Source_Location := Here;
            begin
               return Declaration
                 (Recursive => Take (Function_Word),
                  Definition => Function_Site);
            end;
         elsif Kind = Global_Word or else
           (Kind = Identifier and then Matches (Current.Text, "global")
            and then Peek in Identifier | Less | Star | Function_Word)
         then
            Advance;
            Function_Site := Here;
            if not Take (Function_Word) then
               return Declaration (Global => True);
            end if;
            Result := Make (Assignment);
            Value := Fetch (Result);
            Value.Flag := True;
            Save (Result, Value);
            Id := New_Name (Current.Text, Kind => Global_Name);
            Active.Append (Id);
            Target := Resolve (Read_Name);
            Item := Function_Body (Function_Site);
            Child (Result, Target);
            Child (Result, Item);
         elsif Take (Function_Word) then
            Result := Make (Assignment);
            Target := Resolve (Read_Name);
            while Kind in Dot | Colon loop
               Method := Kind = Colon;
               Advance;
               Value := (Kind => Literal, Site => Here,
                         Value => Current, others => <>);
               Value.Value.Kind := String_Literal;
               Expect (Identifier);
               Item := Make (Index_Expression);
               Child (Item, Target);
               Child (Item, Add (Value));
               Target := Item;
               exit when Method;
            end loop;
            Writable (Target);
            Child (Result, Target);
            Child (Result, Function_Body (Site, Method));
         elsif Kind in While_Word | Repeat_Word then
            declare
               Repeat : constant Boolean := Kind = Repeat_Word;
               Parent : constant Natural := Scope;
            begin
               Advance;
               Result := Make
                 ((if Repeat then Repeat_Statement else While_Statement));
               Loop_Depth := Loop_Depth + 1;
               if Repeat then
                  Saved := Active;
                  Next_Scope := Next_Scope + 1;
                  Scope := Next_Scope;
                  Child (Result, Block (Own_Scope => False));
                  Expect (Until_Word);
                  Child (Result, Expression);
                  Finish_Scope (Scope, Parent, Saved);
                  Scope := Parent;
                  Active := Saved;
               else
                  Child (Result, Expression);
                  Expect (Do_Word);
                  Child (Result, Block);
                  Expect (End_Word);
               end if;
               Loop_Depth := Loop_Depth - 1;
            end;
         elsif Take (If_Word) then
            Result := Make (If_Statement);
            loop
               Child (Result, Expression);
               Expect (Then_Word);
               Child (Result, Block);
               exit when not Take (Elseif_Word);
            end loop;
            if Take (Else_Word) then
               Child (Result, Block);
            end if;
            Expect (End_Word);
         elsif Take (For_Word) then
            --  Controls resolve in the surrounding scope. Only after parsing
            --  them do visible iteration variables enter the loop body.
            --  Lua 5.5 makes the first control variable read-only.
            Saved := Active;
            Id := New_Name (Read_Name, Constant_Name);
            Value := (Kind => Generic_For, Site => Site, others => <>);
            --  This temporary list is populated before Add can bind a stored
            --  node. Its loop-variable records already belong to this unit.
            Value.Symbols.Set_Owner (Selected);
            Value.Symbols.Append (Id);
            if Take (Assign) then
               Value := (Kind => Numeric_For, Site => Site,
                         Symbols => Value.Symbols, others => <>);
               Result := Add (Value);
               Child (Result, Expression);
               Expect (Comma);
               Child (Result, Expression);
               if Take (Comma) then
                  Child (Result, Expression);
               end if;
            else
               while Take (Comma) loop
                  Value.Symbols.Append (New_Name (Read_Name));
               end loop;
               Result := Add (Value);
               Expect (In_Word);
               Child (Result, Expression_List);
            end if;
            declare
               Header : constant Nodes.Reference_Type :=
                 Unit.Tree.Reference (Positive (Result));
            begin
               Header.Header_Line := Here.Line;
            end;
            Expect (Do_Word);
            for Symbol of Value.Symbols loop
               Active.Append (Symbol);
            end loop;
            Loop_Depth := Loop_Depth + 1;
            Child (Result, Block);
            Loop_Depth := Loop_Depth - 1;
            Active := Saved;
            declare
               Loop_Node : constant Nodes.Reference_Type :=
                 Unit.Tree.Reference (Positive (Result));
            begin
               Loop_Node.End_Line := Here.Line;
            end;
            Expect (End_Word);
         elsif Take (Return_Word) then
            --  Take has already scanned the following token. Preserve the
            --  keyword's original site, not the following end/EOF location.
            --  The emitted return uses the final expression token, retained
            --  separately below before an optional semicolon is consumed.
            Result := Add
              ((Kind => Return_Statement, Site => Site, others => <>));
            if Kind not in End_Of_Input | End_Word | Else_Word |
              Elseif_Word | Until_Word | Semicolon
            then
               Child (Result, Expression_List);
            end if;
            declare
               Return_Node : constant Nodes.Reference_Type :=
                 Unit.Tree.Reference (Positive (Result));
            begin
               Return_Node.End_Line := Last_Line;
            end;
            if Take (Semicolon) then
               null;
            end if;
         elsif Kind = Break_Word then
            if Loop_Depth = 0 then
               Error ("break outside loop");
            end if;
            Advance;
            Result := Add
              ((Kind => Break_Statement, Site => Site, others => <>));
         elsif Kind in Goto_Word | Double_Colon then
            declare
               Label : constant Boolean := Kind = Double_Colon;
            begin
               Advance;
               Result := Make
                 ((if Label then Label_Statement else Goto_Statement));
               Value := Fetch (Result);
               Value.Site := Site;
               Value.Text := Read_Name;
               Save (Result, Value);
               Unit.Unsupported := Result;
               if Label then
                  Expect (Double_Colon);
                  for Previous of Labels loop
                     if Previous.Owner = Function_Node and then
                       Matches (Fetch (Previous.Item).Text, Value.Text)
                     then
                        Error ("label '" & Image (Value.Text) &
                               "' already defined on line " & Line_Text
                                 (Fetch (Previous.Item).Site.Line),
                               Near_Token => False);
                     end if;
                  end loop;
                  Labels.Append
                    (Jump_Record'
                       (Result, Scope, Function_Node, Active, False));
                  while Take (Semicolon) loop
                     null;
                  end loop;
               else
                  Gotos.Append
                    (Jump_Record'
                       (Result, Scope, Function_Node, Active, False));
               end if;
            end;
         else
            Item := Prefix;
            if Fetch (Item).Kind = Call_Expression and then
              Kind not in Assign | Comma
            then
               Result := Make (Call_Statement);
               Child (Result, Item);
            else
               Result := Make (Assignment);
               Writable (Item);
               Child (Result, Item);
               while Take (Comma) loop
                  Item := Prefix;
                  Writable (Item);
                  Child (Result, Item);
               end loop;
               Expect (Assign);
               Child (Result, Expression_List);
            end if;
         end if;
         return Result;
      end Statement;

   begin
      if Unit.Memory /= null and then Unit.Memory /= Selected then
         raise Program_Error with "cannot rebind a compilation unit";
      end if;
      Unit.Memory := Selected;
      --  All growable compilation state has an explicit owner before its
      --  first append. No default vector can escape into the standard heap.
      Unit.Texts.Set_Owner (Selected);
      Unit.Tree.Set_Owner (Selected);
      Unit.Names.Set_Owner (Selected);
      Active.Set_Owner (Selected);
      Gotos.Set_Owner (Selected);
      Labels.Set_Owner (Selected);
      Unit.Texts.Clear;
      Unit.Result := (Status => Lua.Syntax.Success,
                      Error => (Source => Own (Name),
                                others => <>),
                      Incomplete_Input => False);
      if Source.Available > Limits.Source_Bytes then
         Error ("source byte limit exceeded", Resource => True);
      end if;
      Unit.Tree.Clear;
      Unit.Names.Clear;
      Unit.Root := No_Node;
      Unit.Unsupported := No_Node;
      Current := Read_Token;
      Unit.Environment := New_Name (Own ("_ENV"));
      Active.Append (Unit.Environment);
      Unit.Root := Block;
      declare
         Root : constant Nodes.Reference_Type :=
           Unit.Tree.Reference (Positive (Unit.Root));
      begin
         --  The main function's implicit return belongs to its final consumed
         --  token, not the final expression visited during lowering or the
         --  EOF after trailing trivia. Retain the scanner's existing position
         --  without copying the root's input-sized child list or rescanning.
         --  Empty input keeps the initial line one, matching luaK_code's
         --  ls.lastline when mainfunc closes without consuming TK_EOS.
         Root.End_Line := Last_Line;
      end;
      Expect (End_Of_Input);
   exception
      when Abandon =>
         Unit.Tree.Clear;
         Unit.Names.Clear;
         Unit.Root := No_Node;
      when Storage_Error =>
         --  A runtime allocator refusal is a distinct Allocation_Error and
         --  propagates unchanged. Physical Ada exhaustion belongs to the
         --  runtime boundary; standalone checking reports its resource result.
         if Memory /= null then
            raise;
         end if;
         Unit.Tree.Clear;
         Unit.Names.Clear;
         Unit.Root := No_Node;
         Unit.Result.Status := Lua.Syntax.Resource_Error;
         Unit.Result.Error.Message :=
           Own ("frontend storage exhausted");
   end Parse;
end Lua.Syntax_Trees;
