with Ada.Containers;
with Interfaces;
with Lua.Integers;
with Lua.Numbers;
with Lua.Opcodes; use Lua.Opcodes;
with Lua.Runtime_Configuration;
with Lua.Storage.Vectors;
with Lua.Syntax;

package body Lua.Canonical_Compiler is
   use Lua.Lexers;
   use Lua.Prototypes;
   use Lua.Syntax_Trees;
   use type Ada.Containers.Count_Type;
   use type Interfaces.Integer_8;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;
   use type Lua.Syntax.Check_Status;
   use type Lua.Numbers.Real_Value;
   use type Lua.Numbers.Integer_Value;

   --  These library-level managed instantiations contain compilation work,
   --  never runtime roots. Their owner is explicit even on exceptional exits.
   type Place_Kind is (Stack_Place, Upvalue_Place, Constant_Place);
   type Place is record
      Kind : Place_Kind := Stack_Place;
      Index : Natural := 0;
      Data : Constant_Value;
   end record;
   type Binding_Place is record
      Symbol : Symbol_Id := No_Symbol;
      Value : Place;
      Debug_Index : Natural := 0;
      Captured : Boolean := False;
      --  A child prototype actually closes over this active stack binding.
      --  Iteration control needs CLOSE only when such a cell must detach.
   end record;
   package Places is new Lua.Storage.Vectors (Binding_Place);
   package Indices is new Lua.Storage.Vectors (Natural);
   type String_Constant_Entry is record
      Text : String_Id := No_String;
      Long_String : Boolean := False;
      Constant_Index, Next : Natural := 0;
   end record;
   package String_Constants is new
     Lua.Storage.Vectors (String_Constant_Entry);
   type Label_Point is record
      Id : Node_Id := No_Node;
      PC : Natural := 0;
   end record;
   package Labels is new Lua.Storage.Vectors (Label_Point);
   type Pending_Jump is record
      Target : Node_Id := No_Node;
      PC : Positive;
   end record;
   package Jumps is new Lua.Storage.Vectors (Pending_Jump);
   type Loop_State is record
      Base : Natural := 0;
      Breaks : Indices.Vector;
   end record;
   package Loops is new Lua.Storage.Vectors (Loop_State);
   type Function_State is tagged limited record
      Code : Prototype_Access;
      Active, Captures : Places.Vector;
      String_Keys : String_Constants.Vector;
      String_Buckets : Indices.Vector;
      --  Per-function constant indexes keyed by immutable model string IDs.
      --  Dense entry/bucket storage grows with retained keys, never with the
      --  largest global string ID or the number of repeated source uses.
      Targets : Labels.Vector;
      Pending : Jumps.Vector;
      Loop_Stack : Loops.Vector;
      Base, Next : Natural := 0;
      Depth : Positive := 1;
      Last_Line : Natural := 0;
      Has_Closing : Boolean := False;
   end record;
   type Index_Kind is (Register_Key, Constant_Key, Integer_Key);
   type Lvalue is record
      Where : Place;
      Table : Place;
      Key : Natural := 0;
      Key_Kind : Index_Kind := Register_Key;
      Is_Table : Boolean := False;
      --  Indexed targets retain a live local/upvalue operand until the store,
      --  unless a computed expression or later LHS conflict needs a snapshot.
      --  These are compiler descriptors, never borrowed runtime values.
   end record;
   package Lvalues is new Lua.Storage.Vectors (Lvalue);

   function Message (Error : Error_Kind) return String is
   begin
      return (case Error is
         when No_Error => "",
         when Register_Limit => "too many registers",
         when Return_Limit => "too many returns",
         when Local_Limit => "too many local variables",
         when Upvalue_Limit => "too many upvalues",
         when Jump_Limit => "control structure too long",
         when Constant_Encoding_Limit => "too many constants",
         when Instruction_Budget => "instruction lowering limit exceeded",
         when Constant_Budget => "constant lowering limit exceeded",
         when Prototype_Budget => "prototype lowering limit exceeded",
         when Nesting_Budget => "lowering nesting limit exceeded",
         when Allocation_Refused => "not enough memory");
   end Message;

   function Compile
     (Unit : in out Compilation_Unit;
      Memory : not null Lua.Storage.Owner_Access;
      Source_Name : String; Bounds : Lowering_Limits := (others => <>))
      return Compilation_Result
   is
      Site : Source_Location;
      Instruction_Count, Constant_Count, Node_Count : Natural := 0;
      Abandon : exception;
   begin
      if Unit.Result.Status /= Lua.Syntax.Success then
         raise Program_Error with "canonical lowering requires valid syntax";
      end if;
      return Result : Compilation_Result do
         Set_Owner (Result.Code, Memory);
         declare
            function Intern_Text (Item : Text_Ref) return String_Id;
            function Intern_Text (Item : Text_Ref) return String_Id is
               Id : String_Id;
               procedure Save (Text : String);
               procedure Save (Text : String) is
               begin
                  Id := Intern (Result.Code, Text);
               end Save;
            begin
               --  Borrow managed frontend bytes directly into the canonical
               --  interner. Source-sized host String snapshots would otherwise
               --  bypass the allocator on every decoded string and identifier.
               Query_Text (Unit, Item, Save'Access);
               return Id;
            end Intern_Text;
            function Fetch (Id : Node_Id) return
              Nodes.Constant_Reference_Type is
              (Unit.Tree.Constant_Reference (Positive (Id)));
            function Binding_Kind (Id : Symbol_Id) return Byte;
            function Binding_Kind (Id : Symbol_Id) return Byte is
              (case Unit.Names (Positive (Id)).Mode is
                 when Regular => 0, when Constant_Name => 1,
                 when Vararg_Name => 2, when Closing_Name => 3);
            procedure Fail (Error : Error_Kind; Host : Boolean := False);
            procedure Fail (Error : Error_Kind; Host : Boolean := False) is
            begin
               Result.Error := Error;
               Result.Location := Site;
               Result.Outcome :=
                 (if Host then Resource_Limit else Compiler_Limit);
               raise Abandon;
            end Fail;
            procedure Reserve (Fn : in out Function_State; Last : Natural);
            procedure Reserve (Fn : in out Function_State; Last : Natural) is
            begin
               if Last > 255 then Fail (Register_Limit); end if;
               Fn.Next := Natural'Max (Fn.Next, Last);
               Fn.Code.Max_Stack := Byte'Max
                 (Fn.Code.Max_Stack, Byte (Last));
            end Reserve;
            function Temporary (Fn : in out Function_State) return Natural;
            function Temporary (Fn : in out Function_State) return Natural is
               Index : constant Natural := Fn.Next;
            begin
               Reserve (Fn, Index + 1);
               return Index;
            end Temporary;
            function Field_Set
              (Instruction : Lua.Opcodes.Word; Part : Field; Value : Integer)
               return Lua.Opcodes.Word;
            function Field_Set
              (Instruction : Lua.Opcodes.Word; Part : Field; Value : Integer)
               return Lua.Opcodes.Word
            is
               Changed : constant Instruction_Result :=
                 Set (Instruction, Part, Value);
            begin
               if Changed.Status /= Success then Fail (Jump_Limit); end if;
               return Changed.Value;
            end Field_Set;
            function ABC
              (Op : Opcode; X : Natural := 0; Y : Natural := 0;
               Z : Natural := 0; Flag : Boolean := False)
               return Lua.Opcodes.Word;
            function ABC
              (Op : Opcode; X : Natural := 0; Y : Natural := 0;
               Z : Natural := 0; Flag : Boolean := False)
               return Lua.Opcodes.Word
            is
               Instruction : Lua.Opcodes.Word := Create (Op);
            begin
               Instruction := Field_Set (Instruction, A, X);
               Instruction := Field_Set (Instruction, B, Y);
               Instruction := Field_Set (Instruction, C, Z);
               return Field_Set (Instruction, K, Boolean'Pos (Flag));
            end ABC;
            function ABx
              (Op : Opcode; X, Y : Natural) return Lua.Opcodes.Word;
            function ABx
              (Op : Opcode; X, Y : Natural) return Lua.Opcodes.Word is
              (Field_Set (Field_Set (Create (Op), A, X), Bx, Y));
            function PC (Fn : Function_State) return Positive is
              (Natural (Fn.Code.Code.Length) + 1);
            procedure Put
              (Fn : in out Function_State; Instruction : Lua.Opcodes.Word);
            procedure Put
              (Fn : in out Function_State; Instruction : Lua.Opcodes.Word)
            is
               Difference : constant Long_Long_Integer :=
                 Long_Long_Integer (Site.Line) -
                 Long_Long_Integer (Fn.Last_Line);
            begin
               if Instruction_Count = Bounds.Instructions then
                  Fail (Instruction_Budget, Host => True);
               end if;
               Instruction_Count := Instruction_Count + 1;
               --  Every word receives its real source line. Native getbaseline
               --  estimates an absolute-record index from pc / MAXIWTHABS;
               --  the writer's maximum gap must not exceed that reader's
               --  selected interval (128 ordinarily, 3 under ltests.h).
               --  lcode:savelineinfo resets its post-increment counter to one
               --  after a marker. Its subsequent periodic gaps equal that
               --  interval; large line deltas can only add closer markers.
               --  Our fixed checkpoints, including PC zero, satisfy the same
               --  lower-bound requirement without copying its private layout.
               if Difference not in -127 .. 127 or else
                 (PC (Fn) - 1) mod
                   Lua.Runtime_Configuration.Absolute_Line_Interval = 0
               then
                  Fn.Code.Lines.Append (-128);
                  Fn.Code.Absolute_Lines.Append
                    (Absolute_Line'(PC (Fn) - 1, Site.Line));
               else
                  Fn.Code.Lines.Append (Interfaces.Integer_8 (Difference));
               end if;
               Fn.Last_Line := Site.Line;
               Fn.Code.Code.Append (Instruction);
            end Put;
            procedure Retire_Condition
              (Fn : in out Function_State; Register_Id : Natural);
            procedure Retire_Condition
              (Fn : in out Function_State; Register_Id : Natural) is
            begin
               --  Statement conditions consume a private temporary. Their
               --  truthy edge must retire its value before evaluating the
               --  body or running close handlers: a later RHS can allocate
               --  in higher registers before overwriting this lower slot.
               --  Keeping a weakly reachable condition there can mark it
               --  again on every collection, preventing loop termination.
               --  Local/captured cells remain below Base. TEST itself keeps
               --  its ordinary value semantics for and/or expressions.
               if Register_Id < Fn.Base then
                  raise Program_Error with "condition is not a temporary";
               end if;
               Put (Fn, ABC (Op_LOADNIL, Register_Id));
            end Retire_Condition;
            function Jump (Fn : in out Function_State) return Positive;
            function Jump (Fn : in out Function_State) return Positive is
               Index : constant Positive := PC (Fn);
            begin
               Put (Fn, Field_Set (Create (Op_JMP), SJ, 0));
               return Index;
            end Jump;
            procedure Patch
              (Fn : in out Function_State; Index, Target : Positive);
            procedure Patch
              (Fn : in out Function_State; Index, Target : Positive) is
            begin
               Fn.Code.Code.Replace_Element (Index, Field_Set
                 (Fn.Code.Code (Index), SJ, Target - Index - 1));
            end Patch;
            procedure Move
              (Fn : in out Function_State; Destination, Source : Natural);
            procedure Move
              (Fn : in out Function_State; Destination, Source : Natural) is
            begin
               if Destination /= Source then
                  Put (Fn, ABC (Op_MOVE, Destination, Source));
               end if;
            end Move;
            function String_Bucket
              (Text : String_Id; Long_String : Boolean; Count : Positive)
               return Positive;
            function String_Bucket
              (Text : String_Id; Long_String : Boolean; Count : Positive)
               return Positive is
              (Natural (((Interfaces.Unsigned_64 (Text) *
                16#9E37_79B9_7F4A_7C15#) xor
                Interfaces.Unsigned_64 (Boolean'Pos (Long_String))) mod
                Interfaces.Unsigned_64 (Count)) + 1);
            procedure Grow_String_Keys (Fn : in out Function_State);
            procedure Grow_String_Keys (Fn : in out Function_State) is
               Size : constant Natural :=
                 Natural (Fn.String_Buckets.Length);
               Bucket : Positive;
               Key_Record : String_Constant_Entry;
            begin
               if Size /= 0 and then
                 Natural (Fn.String_Keys.Length) < Size / 2
               then
                  return;
               elsif Size > Natural'Last / 2 then
                  raise Lua.Storage.Allocation_Error;
               end if;
               --  Allocate through the compilation owner before relinking.
               --  Entries contain only scalar IDs/links, so rehash performs
               --  no hidden text copies or allocations after bucket growth.
               Fn.String_Buckets.Set_Length
                 (Ada.Containers.Count_Type (Natural'Max (8, Size * 2)));
               for Index in Fn.String_Buckets.First_Index ..
                 Fn.String_Buckets.Last_Index
               loop
                  Fn.String_Buckets.Replace_Element (Index, 0);
               end loop;
               for Index in Fn.String_Keys.First_Index ..
                 Fn.String_Keys.Last_Index
               loop
                  Key_Record := Fn.String_Keys (Index);
                  Bucket := String_Bucket
                    (Key_Record.Text, Key_Record.Long_String,
                     Natural (Fn.String_Buckets.Length));
                  Key_Record.Next := Fn.String_Buckets (Bucket);
                  Fn.String_Keys.Replace_Element (Index, Key_Record);
                  Fn.String_Buckets.Replace_Element (Bucket, Index);
               end loop;
            end Grow_String_Keys;
            function Constant_Index
              (Fn : in out Function_State; Data : Constant_Value)
               return Natural;
            function Constant_Index
              (Fn : in out Function_State; Data : Constant_Value)
               return Natural
            is
               Index : constant Natural := Natural (Fn.Code.Constants.Length);
               Bucket, Cursor : Natural := 0;
               Key_Record : String_Constant_Entry;
            begin
               --  The model already interns exact string bytes. Reuse only
               --  the same typed string constant within this function; integer
               --  and floating constants keep their existing representation.
               --  Look up before growth so a hit needs no new allocation.
               if Data.Kind = String_Constant and then
                 not Fn.String_Buckets.Is_Empty
               then
                  Bucket := String_Bucket
                    (Data.String_Data, Data.Long_String,
                     Natural (Fn.String_Buckets.Length));
                  Cursor := Fn.String_Buckets (Bucket);
                  while Cursor /= 0 loop
                     Key_Record := Fn.String_Keys (Cursor);
                     if Key_Record.Text = Data.String_Data and then
                       Key_Record.Long_String = Data.Long_String
                     then
                        return Key_Record.Constant_Index;
                     end if;
                     Cursor := Key_Record.Next;
                  end loop;
               end if;
               if Constant_Count = Bounds.Constants then
                  Fail (Constant_Budget, Host => True);
               elsif Index >= 2 ** 25 then
                  Fail (Constant_Encoding_Limit);
               end if;
               if Data.Kind = String_Constant then
                  Grow_String_Keys (Fn);
                  Bucket := String_Bucket
                    (Data.String_Data, Data.Long_String,
                     Natural (Fn.String_Buckets.Length));
                  --  Reserve both publications before changing either live
                  --  sequence. Refusal abandons the owned compilation; no
                  --  half-published constant or borrowed frontend byte span
                  --  escapes. First occurrence still fixes the pool order.
                  Fn.Code.Constants.Reserve_Capacity
                    (Fn.Code.Constants.Length + 1);
                  Fn.String_Keys.Reserve_Capacity
                    (Fn.String_Keys.Length + 1);
                  Fn.String_Keys.Append
                    (String_Constant_Entry'(Data.String_Data,
                     Data.Long_String, Index, Fn.String_Buckets (Bucket)));
                  Fn.String_Buckets.Replace_Element
                    (Bucket, Natural (Fn.String_Keys.Length));
               end if;
               Constant_Count := Constant_Count + 1;
               Fn.Code.Constants.Append (Data);
               return Index;
            end Constant_Index;
            procedure Load
              (Fn : in out Function_State; Register_Id : Natural;
               Data : Constant_Value);
            procedure Load
              (Fn : in out Function_State; Register_Id : Natural;
               Data : Constant_Value)
            is
               Index : Natural;
            begin
               case Data.Kind is
                  when Nil_Constant =>
                     Put (Fn, ABC (Op_LOADNIL, Register_Id));
                  when Boolean_Constant =>
                     Put (Fn, ABC ((if Data.Boolean_Data then Op_LOADTRUE
                                   else Op_LOADFALSE), Register_Id));
                  when others =>
                     Index := Constant_Index (Fn, Data);
                     if Index < 2 ** 17 then
                        Put (Fn, ABx (Op_LOADK, Register_Id, Index));
                     else
                        Put (Fn, ABx (Op_LOADKX, Register_Id, 0));
                        Put (Fn, Field_Set (Create (Op_EXTRAARG), Ax, Index));
                     end if;
               end case;
            end Load;
            function Locate
              (Fn : Function_State; Id : Symbol_Id) return Place;
            function Locate
              (Fn : Function_State; Id : Symbol_Id) return Place is
            begin
               for Index in reverse
                 Fn.Active.First_Index .. Fn.Active.Last_Index
               loop
                  if Fn.Active (Index).Symbol = Id then
                     return Fn.Active (Index).Value;
                  end if;
               end loop;
               for Item of Fn.Captures loop
                  if Item.Symbol = Id then return Item.Value; end if;
               end loop;
               raise Program_Error with "resolved lexical binding missing";
            end Locate;
            procedure Read
              (Fn : in out Function_State; Where : Place;
               Destination : Natural);
            procedure Read
              (Fn : in out Function_State; Where : Place;
               Destination : Natural) is
            begin
               case Where.Kind is
                  when Stack_Place => Move (Fn, Destination, Where.Index);
                  when Upvalue_Place =>
                     Put (Fn, ABC (Op_GETUPVAL, Destination, Where.Index));
                  when Constant_Place => Load (Fn, Destination, Where.Data);
               end case;
            end Read;
            procedure Bind
              (Fn : in out Function_State; Id : Symbol_Id;
               Register_Id : Natural);
            procedure Bind
              (Fn : in out Function_State; Id : Symbol_Id;
               Register_Id : Natural) is
            begin
               if Register_Id >= 200 then Fail (Local_Limit); end if;
               Fn.Code.Locals.Append (Local'
                 (Intern_Text (Unit.Names (Positive (Id)).Name),
                  PC (Fn) - 1, 0));
               Fn.Active.Append (Binding_Place'
                 (Id, (Stack_Place, Register_Id, (Kind => Nil_Constant)),
                  Natural (Fn.Code.Locals.Length), False));
               Fn.Base := Natural'Max (Fn.Base, Register_Id + 1);
               Reserve (Fn, Fn.Base);
            end Bind;
            procedure Leave
              (Fn : in out Function_State; Base, Active : Natural;
               Emit_Close : Boolean := True);
            procedure Leave
              (Fn : in out Function_State; Base, Active : Natural;
               Emit_Close : Boolean := True)
            is
               Ending : constant Natural := PC (Fn) - 1;
            begin
               --  CLOSE detaches captured cells before a reused stack slot
               --  receives a new declaration instance. This is also the sole
               --  ordinary scope-exit operation for to-be-closed variables.
               if Emit_Close and then Fn.Base > Base then
                  Put (Fn, ABC (Op_CLOSE, Base));
               end if;
               while Natural (Fn.Active.Length) > Active loop
                  if Fn.Active.Last_Element.Debug_Index /= 0 then
                     declare
                        Index : constant Positive :=
                          Fn.Active.Last_Element.Debug_Index;
                        Data : Local := Fn.Code.Locals (Index);
                     begin
                        Data.End_PC := Ending;
                        Fn.Code.Locals.Replace_Element (Index, Data);
                     end;
                  end if;
                  Fn.Active.Delete_Last;
               end loop;
               Fn.Base := Base;
               Fn.Next := Base;
            end Leave;
            function Multiple (Id : Node_Id) return Boolean is
              (Fetch (Id).Kind = Call_Expression or else
               (Fetch (Id).Kind = Literal and then
                Fetch (Id).Value.Kind = Varargs));
            procedure Expression
              (Fn : in out Function_State; Id : Node_Id;
               Destination : Natural; Wanted : Integer := 1;
               Tail : Boolean := False; At_Line : Natural := 0);
            procedure Statement
              (Fn : in out Function_State; Id : Node_Id);
            procedure Block
              (Fn : in out Function_State; Id : Node_Id;
               Own_Scope : Boolean := True);
            procedure Build_Function
              (Fn : in out Function_State; Id : Node_Id;
               Parent : access Function_State := null);
            procedure Values
              (Fn : in out Function_State; Id : Node_Id;
               Destination : Natural; Wanted : Integer;
               Open_Last : out Boolean; Count : out Natural);
            procedure Values
              (Fn : in out Function_State; Id : Node_Id;
               Destination : Natural; Wanted : Integer;
               Open_Last : out Boolean; Count : out Natural)
            is
               Length : constant Natural :=
                 (if Id = No_Node then 0 else
                  Natural (Fetch (Id).Children.Length));
               Needed : Integer;
            begin
               Open_Last := False;
               Count := Length;
               for Index in 1 .. Length loop
                  Needed := 1;
                  if Index = Length and then
                    Multiple (Fetch (Id).Children (Index))
                  then
                     Needed := (if Wanted < 0 then -1 else
                       Integer'Max (0, Wanted - Length + 1));
                     Open_Last := Needed < 0;
                  end if;
                  Expression (Fn, Fetch (Id).Children (Index),
                              Destination + Index - 1, Needed);
               end loop;
               if Wanted >= 0 then
                  if Length = 0 or else
                    (Length < Wanted and then
                     not Multiple (Fetch (Id).Children (Length)))
                  then
                     Reserve (Fn, Destination + Wanted);
                     if Wanted > Length then
                        Put (Fn, ABC (Op_LOADNIL, Destination + Length,
                                      Wanted - Length - 1));
                     end if;
                  end if;
                  Count := Natural (Wanted);
               end if;
            end Values;
            function Fold
              (Fn : Function_State; Id : Node_Id; Data : out Constant_Value)
               return Boolean;
            function End_Line (Id : Node_Id) return Natural;
            function End_Line (Id : Node_Id) return Natural is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
            begin
               return (if Item.End_Line /= 0 then Item.End_Line else
                         Item.Site.Line);
            end End_Line;
            function Direct_Local
              (Fn : Function_State; Id : Node_Id) return Place;
            function Direct_Local
              (Fn : Function_State; Id : Node_Id) return Place
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Value : Place;
            begin
               if Item.Kind = Name_Reference and then
                 Item.Symbol /= No_Symbol
               then
                  Value := Locate (Fn, Item.Symbol);
                  if Value.Kind = Stack_Place then return Value; end if;
               elsif Item.Kind = Parenthesized then
                  return Direct_Local (Fn, Item.Children (1));
               end if;
               return (Constant_Place, 0, (Kind => Nil_Constant));
            end Direct_Local;
            function Register_Operand
              (Fn : in out Function_State; Id : Node_Id; Line : Natural)
               return Natural;
            function Register_Operand
              (Fn : in out Function_State; Id : Node_Id; Line : Natural)
               return Natural
            is
               Value : constant Place := Direct_Local (Fn, Id);
               Index : Natural;
            begin
               --  A live local register is already an operand, not a value
               --  copied before later callbacks can mutate its shared cell.
               if Value.Kind = Stack_Place then return Value.Index; end if;
               Index := Temporary (Fn);
               Expression (Fn, Id, Index, At_Line => Line);
               return Index;
            end Register_Operand;
            procedure Key_Data
              (Fn : in out Function_State; Target : in out Lvalue;
               Data : Constant_Value);
            procedure Key_Data
              (Fn : in out Function_State; Target : in out Lvalue;
               Data : Constant_Value)
            is
               Index : Natural;
            begin
               if Data.Kind = Integer_Constant and then
                 Data.Integer_Data in 0 .. 255
               then
                  Target.Key_Kind := Integer_Key;
                  Target.Key := Natural (Data.Integer_Data);
               elsif Data.Kind = String_Constant then
                  Index := Constant_Index (Fn, Data);
                  if Index < 256 and then String_Length
                    (Result.Code, Data.String_Data) <= 40
                  then
                     Target.Key_Kind := Constant_Key;
                     Target.Key := Index;
                  else
                     Target.Key := Temporary (Fn);
                     if Index < 2 ** 17 then
                        Put (Fn, ABx (Op_LOADK, Target.Key, Index));
                     else
                        Put (Fn, ABx (Op_LOADKX, Target.Key, 0));
                        Put (Fn, Field_Set (Create (Op_EXTRAARG), Ax, Index));
                     end if;
                  end if;
               else
                  Target.Key := Temporary (Fn);
                  Load (Fn, Target.Key, Data);
               end if;
            end Key_Data;
            procedure Capture_Table
              (Fn : in out Function_State; Target : in out Lvalue);
            procedure Capture_Table
              (Fn : in out Function_State; Target : in out Lvalue)
            is
               Index : Natural;
            begin
               if Target.Table.Kind = Constant_Place or else
                 (Target.Table.Kind = Upvalue_Place and then
                  Target.Key_Kind /= Constant_Key)
               then
                  Index := Temporary (Fn);
                  Read (Fn, Target.Table, Index);
                  Target.Table := (Stack_Place, Index,
                                   (Kind => Nil_Constant));
               end if;
            end Capture_Table;
            function Global_Address
              (Fn : in out Function_State; Environment : Symbol_Id;
               Name : Text_Ref) return Lvalue;
            function Global_Address
              (Fn : in out Function_State; Environment : Symbol_Id;
               Name : Text_Ref) return Lvalue
            is
               Target : Lvalue;
            begin
               Target.Is_Table := True;
               Target.Table := Locate (Fn, Environment);
               Key_Data (Fn, Target, Constant_Value'
                 (String_Constant, Intern_Text (Name),
                  Text_Length (Name) > 40));
               Capture_Table (Fn, Target);
               return Target;
            end Global_Address;
            function Address
              (Fn : in out Function_State; Id : Node_Id) return Lvalue;
            function Address
              (Fn : in out Function_State; Id : Node_Id) return Lvalue
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Target : Lvalue;
               Base_Node : Node_Id;
               Base : Place;
               Data : Constant_Value;
            begin
               Site := Item.Site;
               if Item.Kind = Name_Reference then
                  if Item.Symbol /= No_Symbol then
                     Target.Where := Locate (Fn, Item.Symbol);
                  else
                     Target := Global_Address
                       (Fn, Item.Environment, Item.Text);
                  end if;
               else
                  Target.Is_Table := True;
                  Base_Node := Item.Children (1);
                  Base := Direct_Local (Fn, Base_Node);
                  if Base.Kind = Stack_Place then
                     Target.Table := Base;
                  elsif Fetch (Base_Node).Kind = Name_Reference and then
                    Fetch (Base_Node).Symbol /= No_Symbol and then
                    Locate (Fn, Fetch (Base_Node).Symbol).Kind = Upvalue_Place
                  then
                     Target.Table := Locate
                       (Fn, Fetch (Base_Node).Symbol);
                  else
                     Target.Table := (Stack_Place, Temporary (Fn),
                                      (Kind => Nil_Constant));
                     Expression (Fn, Base_Node, Target.Table.Index);
                  end if;
                  if Fold (Fn, Item.Children (2), Data) then
                     Site := Fetch (Item.Children (2)).Site;
                     Site.Line := End_Line (Item.Children (2));
                     Key_Data (Fn, Target, Data);
                  else
                     Target.Key := Register_Operand
                       (Fn, Item.Children (2), End_Line (Item.Children (2)));
                  end if;
                  --  An upvalue with a short constant key is read at the
                  --  eventual table operation. Other keys force its table
                  --  only after key evaluation (luaK_indexed), so a key
                  --  callback can replace the referenced upvalue first.
                  Capture_Table (Fn, Target);
               end if;
               return Target;
            end Address;
            procedure Read_Target
              (Fn : in out Function_State; Target : Lvalue;
               Destination : Natural);
            procedure Read_Target
              (Fn : in out Function_State; Target : Lvalue;
               Destination : Natural) is
            begin
               if not Target.Is_Table then
                  Read (Fn, Target.Where, Destination);
               elsif Target.Table.Kind = Upvalue_Place then
                  Put (Fn, ABC (Op_GETTABUP, Destination,
                                Target.Table.Index, Target.Key));
               else
                  Put (Fn, ABC
                    ((case Target.Key_Kind is
                        when Register_Key => Op_GETTABLE,
                        when Constant_Key => Op_GETFIELD,
                        when Integer_Key => Op_GETI),
                     Destination, Target.Table.Index, Target.Key));
               end if;
            end Read_Target;
            procedure Store
              (Fn : in out Function_State; Target : Lvalue; Source : Natural);
            procedure Store
              (Fn : in out Function_State; Target : Lvalue; Source :
                Natural) is
            begin
               if Target.Is_Table then
                  if Target.Table.Kind = Upvalue_Place then
                     Put (Fn, ABC (Op_SETTABUP, Target.Table.Index,
                                   Target.Key, Source));
                  else
                     Put (Fn, ABC
                       ((case Target.Key_Kind is
                           when Register_Key => Op_SETTABLE,
                           when Constant_Key => Op_SETFIELD,
                           when Integer_Key => Op_SETI),
                        Target.Table.Index, Target.Key, Source));
                  end if;
               elsif Target.Where.Kind = Stack_Place then
                  Move (Fn, Target.Where.Index, Source);
               elsif Target.Where.Kind = Upvalue_Place then
                  Put (Fn, ABC (Op_SETUPVAL, Source, Target.Where.Index));
               else
                  raise Program_Error with "assignment to folded constant";
               end if;
            end Store;
            procedure Add_Target
              (Fn : in out Function_State; Targets : in out Lvalues.Vector;
               Item : Lvalue);
            procedure Add_Target
              (Fn : in out Function_State; Targets : in out Lvalues.Vector;
               Item : Lvalue)
            is
               Saved : Natural := 0;
               Has_Saved : Boolean := False;
               function Snapshot return Natural;
               procedure Preserve (Earlier : in out Lvalue);

               function Snapshot return Natural is
               begin
                  if not Has_Saved then
                     Saved := Temporary (Fn);
                     Read (Fn, Item.Where, Saved);
                     Has_Saved := True;
                  end if;
                  return Saved;
               end Snapshot;

               procedure Preserve (Earlier : in out Lvalue) is
               begin
                  if Earlier.Is_Table then
                     if Earlier.Table.Kind = Item.Where.Kind and then
                       Earlier.Table.Index = Item.Where.Index
                     then
                        Earlier.Table :=
                          (Stack_Place, Snapshot, (Kind => Nil_Constant));
                     end if;
                     if Item.Where.Kind = Stack_Place and then
                       Earlier.Key_Kind = Register_Key and then
                       Earlier.Key = Item.Where.Index
                     then
                        Earlier.Key := Snapshot;
                     end if;
                  end if;
               end Preserve;
            begin
               --  Parallel assignments store in reverse order. A later LHS
               --  rebinding a local/upvalue must preserve any earlier table
               --  or key operand that uses that same binding. Ordinary RHS
               --  callbacks alone do not cause a snapshot (check_conflict).
               if not Item.Is_Table and then
                 Item.Where.Kind in Stack_Place | Upvalue_Place
               then
                  for Index in Targets.First_Index .. Targets.Last_Index loop
                     Targets.Update_Element (Index, Preserve'Access);
                  end loop;
               end if;
               Targets.Append (Item);
            end Add_Target;
            function Is_Comparison (Id : Node_Id) return Boolean is
              (Fetch (Id).Kind = Binary_Expression and then
               Fetch (Id).Operator in Equal | Not_Equal | Less |
                 Less_Equal | Greater | Greater_Equal);
            function Comparison_Jump
              (Fn : in out Function_State; Id : Node_Id;
               When_True : Boolean) return Positive;
            function Comparison_Jump
              (Fn : in out Function_State; Id : Node_Id;
               When_True : Boolean) return Positive
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Left : constant Natural := Register_Operand
                 (Fn, Item.Children (1), Item.Site.Line);
               Right : constant Natural := Register_Operand
                 (Fn, Item.Children (2), End_Line (Item.Children (2)));
               Op : constant Opcode :=
                 (case Item.Operator is when Equal | Not_Equal => Op_EQ,
                    when Less | Greater => Op_LT, when others => Op_LE);
            begin
               Site := Item.Site;
               Put (Fn, ABC (Op,
                 (if Item.Operator in Greater | Greater_Equal then Right
                  else Left),
                 (if Item.Operator in Greater | Greater_Equal then Left
                  else Right),
                 Flag => When_True xor (Item.Operator = Not_Equal)));
               return Jump (Fn);
            end Comparison_Jump;
            procedure Expression
              (Fn : in out Function_State; Id : Node_Id;
               Destination : Natural; Wanted : Integer := 1;
               Tail : Boolean := False; At_Line : Natural := 0)
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Materialization_Line : constant Natural :=
                 (if At_Line /= 0 then At_Line else End_Line (Id));
               Mark, Left, Right, Branch, Finish, Index : Natural;
               Count : Natural;
               Open_Last : Boolean;
               Immediate_Add : Boolean := False;
               Immediate : Constant_Value;
               Op : Opcode;
               Where : Lvalue;
               procedure Concatenate_Run;

               procedure Concatenate_Run is
                  First : constant Natural := Temporary (Fn);
                  Current : Node_Id := Id;
                  Right_Node, Next : Node_Id;
                  Length : Natural := 0;
                  function Right_Concat (Node : Node_Id) return Node_Id;
                  function Right_Concat (Node : Node_Id) return Node_Id is
                     Inner : Node_Id := Node;
                  begin
                     while Fetch (Inner).Kind = Parenthesized loop
                        Inner := Fetch (Inner).Children (1);
                     end loop;
                     return (if Fetch (Inner).Kind = Binary_Expression and then
                       Fetch (Inner).Operator = Concatenate then Inner
                       else No_Node);
                  end Right_Concat;
               begin
                  --  luaK_infix places each left operand in its next real
                  --  register before evaluating the RHS. luaK_posfix merges
                  --  a right-associated run into one CONCAT; a parenthesized
                  --  left expression still executes separately. Reuse only
                  --  a genuinely empty result span, never active bindings.
                  loop
                     Reserve (Fn, First + Length + 1);
                     Expression
                       (Fn, Fetch (Current).Children (1), First + Length,
                        At_Line => Fetch (Current).Site.Line);
                     Length := Length + 1;
                     Right_Node := Fetch (Current).Children (2);
                     Next := Right_Concat (Right_Node);
                     exit when Next = No_Node;
                     Current := Next;
                  end loop;
                  Reserve (Fn, First + Length + 1);
                  Expression (Fn, Right_Node, First + Length,
                              At_Line => End_Line (Right_Node));
                  Site := Fetch (Current).Site;
                  Put (Fn, ABC (Op_CONCAT, First, Length + 1));
                  --  Moving operands down before CONCAT both overwrites
                  --  earlier values and destroys their real reaching names.
                  --  Publish only the completed result into its destination.
                  Move (Fn, Destination, First);
               end Concatenate_Run;
            begin
               Site := Item.Site;
               if Item.Kind in Literal | Name_Reference | Index_Expression
               then
                  Site.Line := Materialization_Line;
               end if;
               Reserve (Fn, Destination + Natural (Integer'Max (1, Wanted)));
               Mark := Fn.Next;
               if Item.Kind in Unary_Expression | Binary_Expression and then
                 Destination >= Fn.Base and then Fn.Next =
                   Destination + Natural (Integer'Max (1, Wanted))
               then
                  --  Reserving the eventual result establishes capacity,
                  --  not a live value before the operands execute. Reuse its
                  --  still-empty top span for computed operands, as
                  --  luaK_exp2nextreg/exp2anyreg do. Otherwise a callback on
                  --  the RHS sees an artificial nil hole before the real
                  --  pending left operand, and setlocal edits the wrong
                  --  register. Never reclaim active bindings or another
                  --  already-live temporary above the requested result span.
                  Fn.Next := Destination;
               end if;
               case Item.Kind is
                  when Literal =>
                     case Item.Value.Kind is
                        when Integer_Literal =>
                           Load (Fn, Destination, Constant_Value'
                             (Integer_Constant,
                              Item.Value.Numeric.Integer_Item));
                        when Float_Literal =>
                           Load (Fn, Destination, Constant_Value'
                             (Number_Constant, Item.Value.Numeric.Real_Item));
                        when String_Literal =>
                           Load (Fn, Destination, Constant_Value'
                             (String_Constant, Intern_Text (Item.Value.Text),
                              Text_Length (Item.Value.Text) > 40));
                        when True_Word | False_Word =>
                           Load (Fn, Destination, Constant_Value'
                             (Boolean_Constant, Item.Value.Kind = True_Word));
                        when Varargs =>
                           Put (Fn, ABC (Op_VARARG, Destination,
                             Natural (Fn.Code.Parameters),
                             (if Wanted < 0 then 0 else Wanted + 1),
                             (Fn.Code.Flags and 2) /= 0));
                        when others =>
                           Load (Fn, Destination,
                                 Constant_Value'(Kind => Nil_Constant));
                     end case;
                  when Name_Reference | Index_Expression =>
                     Where := Address (Fn, Id);
                     --  Index preparation can run effectful base/key code.
                     --  Discharge the selected value only at its consumer's
                     --  real token line, after that preparation completes.
                     Site := Item.Site;
                     Site.Line := Materialization_Line;
                     Read_Target (Fn, Where, Destination);
                  when Parenthesized =>
                     Expression (Fn, Item.Children (1), Destination,
                                 At_Line => Materialization_Line);
                  when Unary_Expression =>
                     Left := Register_Operand
                       (Fn, Item.Children (1), End_Line (Item.Children (1)));
                     Op := (case Item.Operator is
                       when Minus => Op_UNM, when Bit_Xor => Op_BNOT,
                       when Not_Word => Op_NOT, when Length => Op_LEN,
                       when others => raise Program_Error);
                     Site := Item.Site;
                     Put (Fn, ABC (Op, Destination, Left));
                  when Binary_Expression =>
                     if Item.Operator in And_Word | Or_Word then
                        --  Keep the original operand, not a booleanized copy.
                        --  Only the selected RHS executes, and each operand
                        --  is scalar-adjusted before its truth is inspected.
                        if Is_Comparison (Item.Children (1)) then
                           --  Comparisons already describe a conditional
                           --  transfer. Thread their real branch into and/or
                           --  instead of materializing a boolean only to test
                           --  it again. A selected left comparison contributes
                           --  precisely true/false; other operands still keep
                           --  their original value through the path below.
                           Branch := Comparison_Jump
                             (Fn, Item.Children (1),
                              When_True => Item.Operator = Or_Word);
                           Expression (Fn, Item.Children (2), Destination);
                           Finish := Jump (Fn);
                           Patch (Fn, Branch, PC (Fn));
                           Put (Fn, ABC
                             ((if Item.Operator = Or_Word then Op_LOADTRUE
                               else Op_LOADFALSE), Destination));
                           Patch (Fn, Finish, PC (Fn));
                        else
                           Expression (Fn, Item.Children (1), Destination,
                                       At_Line => Item.Site.Line);
                           Put (Fn, ABC (Op_TEST, Destination,
                             Flag => Item.Operator = Or_Word));
                           Branch := Jump (Fn);
                           Expression (Fn, Item.Children (2), Destination);
                           Patch (Fn, Branch, PC (Fn));
                        end if;
                     elsif Is_Comparison (Id) then
                        Branch := Comparison_Jump (Fn, Id, When_True => True);
                        Put (Fn, ABC (Op_LFALSESKIP, Destination));
                        Patch (Fn, Branch, PC (Fn));
                        Put (Fn, ABC (Op_LOADTRUE, Destination));
                     elsif Item.Operator = Concatenate then
                        Concatenate_Run;
                     else
                        Left := Register_Operand
                          (Fn, Item.Children (1), Item.Site.Line);
                        --  A literal/constant integer RHS fits ADDI's real
                        --  signed byte operand. Preserve the matching MMBINI
                        --  event and original operand for fallback; no LOADK
                        --  is executed for an immediate in the pinned code.
                        Immediate_Add := Item.Operator = Plus and then
                          Fold (Fn, Item.Children (2), Immediate) and then
                          Immediate.Kind = Integer_Constant and then
                          Immediate.Integer_Data in -127 .. 128;
                        if Immediate_Add then
                           Right := Natural (Immediate.Integer_Data + 127);
                        else
                           Right := Register_Operand
                             (Fn, Item.Children (2),
                              End_Line (Item.Children (2)));
                        end if;
                        Site := Item.Site;
                        if Immediate_Add then
                           Put (Fn, ABC (Op_ADDI, Destination, Left, Right));
                           Put (Fn, ABC (Op_MMBINI, Left, Right, 6));
                        else
                           Op := (case Item.Operator is
                             when Plus => Op_ADD, when Minus => Op_SUB,
                             when Star => Op_MUL, when Slash => Op_DIV,
                             when Floor_Divide => Op_IDIV,
                             when Percent => Op_MOD, when Power => Op_POW,
                             when Bit_And => Op_BAND, when Bit_Or => Op_BOR,
                             when Bit_Xor => Op_BXOR,
                             when Shift_Left => Op_SHL,
                             when Shift_Right => Op_SHR,
                             when others => raise Program_Error);
                           Put (Fn, ABC (Op, Destination, Left, Right));
                           Put (Fn, ABC (Op_MMBIN, Left, Right,
                             6 + Opcode'Pos (Op) - Opcode'Pos (Op_ADD)));
                        end if;
                     end if;
                  when Call_Expression =>
                     declare
                        Callee : constant Nodes.Constant_Reference_Type :=
                          Fetch (Item.Children (1));
                        Receiver : constant Natural :=
                          Boolean'Pos (Callee.Kind = Method_Expression);
                     begin
                        if Receiver = 0 then
                           Expression (Fn, Item.Children (1), Destination);
                        else
                           Reserve (Fn, Destination + 2);
                           Expression (Fn, Callee.Children (1),
                                       Destination + 1);
                           if Fetch (Callee.Children (2)).Kind = Literal and
                             then Fetch (Callee.Children (2)).Value.Kind =
                               String_Literal and then
                             Text_Length (Fetch
                               (Callee.Children (2)).Value.Text) <= 40 and
                             then Fn.Code.Constants.Length < 256
                           then
                              --  SELF records an actual method call shape,
                              --  including the implicit receiver. Debug name
                              --  discovery can inspect this real instruction
                              --  rather than storing fabricated call metadata.
                              Index := Constant_Index (Fn, Constant_Value'
                                (String_Constant, Intern_Text (Fetch
                                  (Callee.Children (2)).Value.Text), False));
                              Put (Fn, ABC (Op_SELF, Destination,
                                            Destination + 1, Index));
                           else
                              --  The canonical C field is only eight bits;
                              --  long keys or a full small-constant window use
                              --  a register key, retaining the same receiver.
                              Left := Temporary (Fn);
                              Expression (Fn, Callee.Children (2), Left);
                              Put (Fn, ABC (Op_GETTABLE, Destination,
                                            Destination + 1, Left));
                           end if;
                        end if;
                        Fn.Next := Destination + Receiver + 1;
                        Values (Fn, Item.Children (2),
                          Destination + Receiver + 1, -1, Open_Last, Count);
                        Site := Item.Site;
                        if Tail then
                           Put (Fn, ABC (Op_TAILCALL, Destination,
                             (if Open_Last then 0 else Count + Receiver + 1),
                             (if (Fn.Code.Flags and 1) /= 0 then
                               Natural (Fn.Code.Parameters) + 1 else 0),
                             Flag => True));
                        else
                           Put (Fn, ABC (Op_CALL, Destination,
                             (if Open_Last then 0 else Count + Receiver + 1),
                             (if Wanted < 0 then 0 else Wanted + 1)));
                        end if;
                     end;
                  when Function_Expression =>
                     declare
                        Child : aliased Function_State;
                     begin
                        Child.Depth := Fn.Depth + 1;
                        Build_Function (Child, Id, Fn'Access);
                        Index := Natural (Fn.Code.Children.Length);
                        Fn.Code.Children.Append (Child.Code);
                        Site := Item.Site;
                        --  body consumes the closing end before codeclosure
                        --  emits the parent's instruction (lparser.c). The
                        --  closure creation line is therefore the child's
                        --  end, while its own defined line stays the opening
                        --  function token retained in the prototype.
                        Site.Line := Item.End_Line;
                        Put (Fn, ABx (Op_CLOSURE, Destination, Index));
                     end;
                  when Table_Expression =>
                     Put (Fn, Field_Set
                       (Create (Op_NEWTABLE), A, Destination));
                     Put (Fn, Create (Op_EXTRAARG));
                     Index := 1;
                     for Position in 1 .. Natural (Item.Children.Length) loop
                        declare
                           Field_Node : constant Nodes.Constant_Reference_Type
                             := Fetch (Item.Children (Position));
                        begin
                           if Field_Node.Children.Length = 1 and then
                             Position = Natural (Item.Children.Length) and
                             then Multiple (Field_Node.Children (1))
                           then
                              Fn.Next := Destination + 1;
                              Expression (Fn, Field_Node.Children (1),
                                          Destination + 1, -1);
                              --  Open SETLIST may grow an initially empty
                              --  array. Fixed stores use ordinary SETTABLE,
                              --  avoiding assumptions about preallocated size.
                              Put (Fn, Field_Set (Field_Set (Field_Set
                                (Create (Op_SETLIST), A, Destination),
                                 VC, (Index - 1) mod 1_024), K,
                                 Boolean'Pos (Index > 1_024)));
                              if Index > 1_024 then
                                 Put (Fn, Field_Set (Create (Op_EXTRAARG), Ax,
                                   (Index - 1) / 1_024));
                              end if;
                           else
                              Left := Temporary (Fn);
                              Right := Temporary (Fn);
                              if Field_Node.Children.Length = 1 then
                                 Load (Fn, Left, Constant_Value'
                                   (Integer_Constant,
                                    Lua.Numbers.Integer_Value (Index)));
                                 Expression (Fn, Field_Node.Children (1),
                                             Right);
                                 Index := Index + 1;
                              else
                                 Expression (Fn, Field_Node.Children (1),
                                   Left);
                                 Expression (Fn, Field_Node.Children (2),
                                   Right);
                              end if;
                              Put (Fn, ABC
                                (Op_SETTABLE, Destination, Left, Right));
                           end if;
                           Fn.Next := Mark;
                        end;
                     end loop;
                  when others =>
                     raise Program_Error with "non-expression resolved node";
               end case;
               if Wanted > 1 and then not Multiple (Id) then
                  Put (Fn, ABC (Op_LOADNIL, Destination + 1, Wanted - 2));
               end if;
               Fn.Next := Mark;
            end Expression;

            procedure Bind_Hidden
              (Fn : in out Function_State; Name : String; Register_Id :
                Natural;
               Lifetime : Symbol_Id := No_Symbol);
            procedure Bind_Hidden
              (Fn : in out Function_State; Name : String; Register_Id :
                Natural;
               Lifetime : Symbol_Id := No_Symbol)
            is
            begin
               if Register_Id >= 200 then Fail (Local_Limit); end if;
               Fn.Code.Locals.Append
                 (Local'(Intern (Result.Code, Name), PC (Fn) - 1, 0));
               Fn.Active.Append (Binding_Place'
                 (Lifetime, (Stack_Place, Register_Id,
                              (Kind => Nil_Constant)),
                  Natural (Fn.Code.Locals.Length), False));
               Fn.Base := Natural'Max (Fn.Base, Register_Id + 1);
               Reserve (Fn, Fn.Base);
            end Bind_Hidden;
            procedure Begin_Loop
              (Fn : in out Function_State; Base : Natural);
            procedure Begin_Loop
              (Fn : in out Function_State; Base : Natural)
            is
               State : Loop_State;
            begin
               State.Base := Base;
               State.Breaks.Set_Owner (Memory);
               Fn.Loop_Stack.Append (State);
            end Begin_Loop;
            procedure End_Loop (Fn : in out Function_State);
            procedure End_Loop (Fn : in out Function_State) is
            begin
               for Index of Fn.Loop_Stack
                 (Fn.Loop_Stack.Last_Index).Breaks
               loop
                  Patch (Fn, Index, PC (Fn));
               end loop;
               Fn.Loop_Stack.Delete_Last;
            end End_Loop;
            procedure Check_Global
              (Fn : in out Function_State; Target : Lvalue;
               Name : Text_Ref);
            procedure Check_Global
              (Fn : in out Function_State; Target : Lvalue;
               Name : Text_Ref)
            is
               Register_Id : constant Natural := Temporary (Fn);
               Index : constant Natural := Constant_Index
                 (Fn, Constant_Value'
                   (String_Constant, Intern_Text (Name), False));
            begin
               Read_Target (Fn, Target, Register_Id);
               Put (Fn, ABx (Op_ERRNNIL, Register_Id,
                             (if Index < 2 ** 17 - 1 then Index + 1 else 0)));
            end Check_Global;
            function Fold
              (Fn : Function_State; Id : Node_Id; Data : out Constant_Value)
               return Boolean
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Left, Right : Constant_Value;
               Value : Place;
            begin
               --  Fold only provably side-effect-free values. Last const
               --  declarations can then omit a stack slot/upvalue, matching
               --  Lua's compile-time-constant ownership rather than exposing
               --  a fabricated mutable cell to debug APIs.
               case Item.Kind is
                  when Literal =>
                     case Item.Value.Kind is
                        when Nil_Word => Data := (Kind => Nil_Constant);
                        when True_Word | False_Word =>
                           Data := (Boolean_Constant,
                                    Item.Value.Kind = True_Word);
                        when Integer_Literal =>
                           Data := (Integer_Constant,
                                    Item.Value.Numeric.Integer_Item);
                        when Float_Literal =>
                           Data := (Number_Constant,
                                    Item.Value.Numeric.Real_Item);
                        when String_Literal =>
                           Data := (String_Constant,
                             Intern_Text (Item.Value.Text),
                             Text_Length (Item.Value.Text) > 40);
                        when others => return False;
                     end case;
                     return True;
                  when Parenthesized =>
                     return Fold (Fn, Item.Children (1), Data);
                  when Name_Reference =>
                     if Item.Symbol /= No_Symbol then
                        Value := Locate (Fn, Item.Symbol);
                        if Value.Kind = Constant_Place then
                           Data := Value.Data;
                           return True;
                        end if;
                     end if;
                  when Unary_Expression =>
                     if Item.Operator = Minus and then
                       Fold (Fn, Item.Children (1), Left)
                     then
                        if Left.Kind = Integer_Constant then
                           Data := (Integer_Constant,
                             Lua.Integers.Negate (Left.Integer_Data));
                           return True;
                        elsif Left.Kind = Number_Constant and then
                          Left.Number_Data /= 0.0
                        then
                           Data := (Number_Constant, -Left.Number_Data);
                           return True;
                        end if;
                     end if;
                  when Binary_Expression =>
                     if Fold (Fn, Item.Children (1), Left) and then
                       Fold (Fn, Item.Children (2), Right) and then
                       Left.Kind = Integer_Constant and then
                       Right.Kind = Integer_Constant
                     then
                        case Item.Operator is
                           when Plus =>
                              Data := (Integer_Constant, Lua.Integers.Add
                                (Left.Integer_Data, Right.Integer_Data));
                           when Minus =>
                              Data := (Integer_Constant,
                                Lua.Integers.Subtract
                                  (Left.Integer_Data, Right.Integer_Data));
                           when Star =>
                              Data := (Integer_Constant,
                                Lua.Integers.Multiply
                                  (Left.Integer_Data, Right.Integer_Data));
                           when Floor_Divide | Percent =>
                              if Right.Integer_Data = 0 then
                                 return False;
                              end if;
                              Data := (Integer_Constant,
                                (if Item.Operator = Floor_Divide then
                                  Lua.Integers.Floor_Divide
                                    (Left.Integer_Data, Right.Integer_Data)
                                 else Lua.Integers.Modulo
                                    (Left.Integer_Data, Right.Integer_Data)));
                           when Shift_Left =>
                              Data := (Integer_Constant,
                                Lua.Integers.Shift_Left
                                  (Left.Integer_Data, Right.Integer_Data));
                           when Shift_Right =>
                              Data := (Integer_Constant,
                                Lua.Integers.Shift_Right
                                  (Left.Integer_Data, Right.Integer_Data));
                           when others => return False;
                        end case;
                        return True;
                     end if;
                  when others => null;
               end case;
               return False;
            end Fold;
            procedure Block
              (Fn : in out Function_State; Id : Node_Id;
               Own_Scope : Boolean := True)
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Base : constant Natural := Fn.Base;
               Active : constant Natural := Natural (Fn.Active.Length);
            begin
               for Child of Item.Children loop
                  Fn.Next := Fn.Base;
                  Statement (Fn, Child);
                  Fn.Next := Fn.Base;
               end loop;
               if Own_Scope then Leave (Fn, Base, Active); end if;
            end Block;
            procedure Statement
              (Fn : in out Function_State; Id : Node_Id)
            is
               Item : constant Nodes.Constant_Reference_Type := Fetch (Id);
               Targets : Lvalues.Vector;
               Finishes : Indices.Vector;
               Base : constant Natural := Fn.Base;
               Active : constant Natural := Natural (Fn.Active.Length);
               Left, Start, Branch, Finish, Index, Count : Natural;
               Open_Last : Boolean;
               Folded : Constant_Value;
            begin
               Site := Item.Site;
               Targets.Set_Owner (Memory);
               Finishes.Set_Owner (Memory);
               case Item.Kind is
                  when Empty_Statement => null;
                  when Block_Statement => Block (Fn, Id);
                  when Label_Statement =>
                     Fn.Targets.Append (Label_Point'(Id, PC (Fn)));
                  when Goto_Statement =>
                     Left := Fn.Base;
                     for Binding of Fn.Active loop
                        if Binding.Symbol /= No_Symbol and then
                          Binding.Value.Kind = Stack_Place and then
                          not Item.Symbols.Contains (Binding.Symbol)
                        then
                           Left := Natural'Min (Left, Binding.Value.Index);
                        end if;
                     end loop;
                     --  The parser's resolved target already supplies its
                     --  retained declaration set, including terminal labels.
                     --  Close outgoing cells before the jump, so re-entered
                     --  declarations cannot mutate an earlier capture.
                     if Left < Fn.Base then
                        Put (Fn, ABC (Op_CLOSE, Left));
                     end if;
                     Fn.Pending.Append (Pending_Jump'
                       (Item.Target, Jump (Fn)));
                  when Call_Statement =>
                     Expression (Fn, Item.Children (1), Fn.Next, 0);
                  when Assignment =>
                     for Position in 1 ..
                       Natural (Item.Children.Length) - 1
                     loop
                        Add_Target
                          (Fn, Targets,
                           Address (Fn, Item.Children (Position)));
                     end loop;
                     Left := Fn.Next;
                     if Fetch (Item.Children.Last_Element).Kind =
                       Function_Expression
                     then
                        Expression (Fn, Item.Children.Last_Element, Left);
                     else
                        Values (Fn, Item.Children.Last_Element, Left,
                          Integer (Targets.Length), Open_Last, Count);
                     end if;
                     Site := Item.Site;
                     Site.Line := End_Line (Item.Children.Last_Element);
                     if Item.Flag then
                        Check_Global (Fn, Targets (1),
                          Fetch (Item.Children (1)).Text);
                     end if;
                     for Position in reverse 1 .. Natural (Targets.Length)
                     loop
                        Store (Fn, Targets (Position), Left + Position - 1);
                     end loop;
                  when Declaration =>
                     if Item.Flag then
                        if not Item.Children.Is_Empty then
                           for Symbol of Item.Symbols loop
                              declare
                                 Target : Lvalue;
                              begin
                                 if Unit.Names (Positive (Symbol)).Kind /=
                                   Collective_Name
                                 then
                                    Target := Global_Address
                                      (Fn, Item.Environment, Unit.Names
                                        (Positive (Symbol)).Name);
                                    Targets.Append (Target);
                                 end if;
                              end;
                           end loop;
                           Left := Fn.Next;
                           Values (Fn, Item.Children (1), Left,
                             Integer (Targets.Length), Open_Last, Count);
                           Site := Item.Site;
                           Site.Line := End_Line (Item.Children (1));
                           for Position in reverse
                             1 .. Natural (Targets.Length)
                           loop
                              Check_Global (Fn, Targets (Position),
                                Unit.Names
                                  (Positive (Item.Symbols (Position))).Name);
                              Store (Fn, Targets (Position),
                                     Left + Position - 1);
                           end loop;
                        end if;
                     elsif not Item.Children.Is_Empty and then
                       Fetch (Item.Children (1)).Kind = Function_Expression
                     then
                        --  Recursive local setup is part of creating this
                        --  closure on its closing end line. Keep the nil
                        --  initialization for capture/root safety, but do
                        --  not expose an extra opening-line hook event for
                        --  this internal step before the closure instruction.
                        Site.Line := Fetch (Item.Children (1)).End_Line;
                        Bind (Fn, Item.Symbols (1), Base);
                        Load (Fn, Base,
                              Constant_Value'(Kind => Nil_Constant));
                        Expression (Fn, Item.Children (1), Base);
                     elsif not Item.Children.Is_Empty and then
                       Fetch (Item.Children (1)).Children.Length =
                         Item.Symbols.Length and then
                       not Item.Symbols.Is_Empty and then
                       Unit.Names (Positive (Item.Symbols.Last_Element)).Mode =
                         Constant_Name and then
                       Fold (Fn, Fetch (Item.Children
                         (1)).Children.Last_Element,
                             Folded)
                     then
                        --  Only the last declaration is a compile-time const
                        --  candidate in the pinned compiler. Earlier values
                        --  still evaluate and acquire ordinary lexical cells.
                        for Position in 1 .. Natural (Item.Symbols.Length) - 1
                        loop
                           Expression (Fn, Fetch (Item.Children (1)).Children
                             (Position), Base + Position - 1);
                        end loop;
                        for Position in 1 .. Natural (Item.Symbols.Length) - 1
                        loop
                           Bind (Fn, Item.Symbols (Position),
                                 Base + Position - 1);
                           if Unit.Names
                             (Positive (Item.Symbols (Position))).Mode =
                             Closing_Name
                           then
                              Fn.Has_Closing := True;
                              Put (Fn, ABC (Op_TBC, Base + Position - 1));
                           end if;
                        end loop;
                        Fn.Active.Append (Binding_Place'
                          (Item.Symbols.Last_Element,
                           (Constant_Place, 0, Folded), 0, False));
                     else
                        Left := Fn.Base;
                        Values (Fn,
                          (if Item.Children.Is_Empty then No_Node else
                           Item.Children (1)), Left,
                          Integer (Item.Symbols.Length), Open_Last, Count);
                        for Position in 1 .. Natural (Item.Symbols.Length)
                        loop
                           Bind (Fn, Item.Symbols (Position),
                                 Left + Position - 1);
                           if Unit.Names
                             (Positive (Item.Symbols (Position))).Mode =
                             Closing_Name
                           then
                              Fn.Has_Closing := True;
                              Put (Fn, ABC (Op_TBC, Left + Position - 1));
                           end if;
                        end loop;
                     end if;
                  when Return_Statement =>
                     Left := Fn.Next;
                     if not Item.Children.Is_Empty and then
                       Fetch (Item.Children (1)).Children.Length = 1 and then
                       Fetch (Fetch (Item.Children (1)).Children (1)).Kind =
                         Call_Expression and then not Fn.Has_Closing
                     then
                        Expression (Fn,
                          Fetch (Item.Children (1)).Children (1), Left, -1,
                          Tail => True);
                        Open_Last := True;
                        Count := 1;
                     else
                        Values (Fn,
                          (if Item.Children.Is_Empty then No_Node else
                           Item.Children (1)), Left, -1, Open_Last, Count);
                     end if;
                     Site := Item.Site;
                     --  retstat emits after its expression list, before
                     --  consuming an optional semicolon. An empty return
                     --  keeps the keyword line; a multiline result uses its
                     --  final token line (lparser.c:retstat/lcode:luaK_code).
                     Site.Line := Item.End_Line;
                     --  The B field encodes a fixed result count plus one.
                     --  Match luaK_ret's semantic limit before field packing
                     --  can turn a valid-source refusal into an Ada check.
                     if not Open_Last and then Count > 254 then
                        Fail (Return_Limit);
                     end if;
                     Put (Fn, ABC (Op_RETURN, Left,
                       (if Open_Last then 0 else Count + 1),
                       (if (Fn.Code.Flags and 1) /= 0 then
                         Natural (Fn.Code.Parameters) + 1 else 0),
                       Flag => True));
                  when Break_Statement =>
                     Put (Fn, ABC (Op_CLOSE,
                       Fn.Loop_Stack (Fn.Loop_Stack.Last_Index).Base));
                     Index := Jump (Fn);
                     declare
                        procedure Append (Loop_Item : in out Loop_State);
                        procedure Append (Loop_Item : in out Loop_State) is
                        begin
                           Loop_Item.Breaks.Append (Index);
                        end Append;
                     begin
                        Fn.Loop_Stack.Update_Element
                          (Fn.Loop_Stack.Last_Index, Append'Access);
                     end;
                  when If_Statement =>
                     Index := 1;
                     while Index < Natural (Item.Children.Length) loop
                        Left := Temporary (Fn);
                        Expression (Fn, Item.Children (Index), Left);
                        Put (Fn, ABC (Op_TEST, Left));
                        Branch := Jump (Fn);
                        Retire_Condition (Fn, Left);
                        Fn.Next := Fn.Base;
                        Block (Fn, Item.Children (Index + 1));
                        Finishes.Append (Jump (Fn));
                        Patch (Fn, Branch, PC (Fn));
                        Index := Index + 2;
                     end loop;
                     if Index = Natural (Item.Children.Length) then
                        Block (Fn, Item.Children (Index));
                     end if;
                     for Ending of Finishes loop
                        Patch (Fn, Ending, PC (Fn));
                     end loop;
                  when While_Statement =>
                     Start := PC (Fn);
                     Left := Temporary (Fn);
                     Expression (Fn, Item.Children (1), Left);
                     Put (Fn, ABC (Op_TEST, Left));
                     Branch := Jump (Fn);
                     Retire_Condition (Fn, Left);
                     Fn.Next := Fn.Base;
                     Begin_Loop (Fn, Base);
                     Block (Fn, Item.Children (2));
                     Finish := Jump (Fn);
                     Patch (Fn, Finish, Start);
                     Patch (Fn, Branch, PC (Fn));
                     End_Loop (Fn);
                  when Repeat_Statement =>
                     Start := PC (Fn);
                     Begin_Loop (Fn, Base);
                     Block (Fn, Item.Children (1), Own_Scope => False);
                     Fn.Next := Fn.Base;
                     Left := Temporary (Fn);
                     Expression (Fn, Item.Children (2), Left);
                     Put (Fn, ABC (Op_TEST, Left));
                     Branch := Jump (Fn);
                     Retire_Condition (Fn, Left);
                     if Fn.Base > Base then
                        Put (Fn, ABC (Op_CLOSE, Base));
                     end if;
                     Finish := Jump (Fn);
                     Patch (Fn, Branch, PC (Fn));
                     if Fn.Base > Base then
                        Put (Fn, ABC (Op_CLOSE, Base));
                     end if;
                     Index := Jump (Fn);
                     Patch (Fn, Index, Start);
                     Patch (Fn, Finish, PC (Fn));
                     Leave (Fn, Base, Active, Emit_Close => False);
                     End_Loop (Fn);
                  when Numeric_For | Generic_For =>
                     if Item.Kind = Numeric_For then
                        Expression (Fn, Item.Children (1), Base);
                        Expression (Fn, Item.Children (2), Base + 1);
                        if Item.Children.Length = 4 then
                           Expression (Fn, Item.Children (3), Base + 2);
                        else
                           Reserve (Fn, Base + 3);
                           Load (Fn, Base + 2,
                                 Constant_Value'(Integer_Constant, 1));
                        end if;
                        Bind_Hidden (Fn, "(for state)", Base,
                                     Item.Symbols (1));
                        Bind_Hidden (Fn, "(for state)", Base + 1,
                                     Item.Symbols (1));
                        Branch := PC (Fn);
                        Site.Line := Item.Header_Line;
                        Put (Fn, ABx (Op_FORPREP, Base, 0));
                        Bind (Fn, Item.Symbols (1), Base + 2);
                     else
                        Values (Fn, Item.Children (1), Base, 4,
                                Open_Last, Count);
                        Bind_Hidden (Fn, "(for state)", Base,
                                     Item.Symbols (1));
                        Bind_Hidden (Fn, "(for state)", Base + 1,
                                     Item.Symbols (1));
                        Bind_Hidden (Fn, "(for state)", Base + 2,
                                     Item.Symbols (1));
                        Fn.Has_Closing := True;
                        Reserve (Fn, Base + Natural'Max
                          (6, Natural (Item.Symbols.Length) + 3));
                        Branch := PC (Fn);
                        Site.Line := Item.Header_Line;
                        Put (Fn, ABx (Op_TFORPREP, Base, 0));
                        for Position in
                          1 .. Natural (Item.Symbols.Length)
                        loop
                           Bind (Fn, Item.Symbols (Position),
                                 Base + Position + 2);
                        end loop;
                     end if;
                     Start := PC (Fn);
                     Begin_Loop (Fn, Base);
                     Fn.Next := Fn.Base;
                     Block (Fn, Item.Children.Last_Element);
                     --  Pinned forbody leaves the visible-variable block
                     --  before FORLOOP/TFORCALL, but emits CLOSE only when a
                     --  child captured one of those cells. Body-owned locals
                     --  and closers have already left through Block above.
                     --  An uncaptured control has no cell to detach; adding
                     --  a no-op CLOSE would still add a real count-hook event.
                     declare
                        First_Control : constant Natural := Base +
                          (if Item.Kind = Numeric_For then 2 else 3);
                     begin
                        for Binding of Fn.Active loop
                           if Binding.Captured and then
                             Binding.Value.Kind = Stack_Place and then
                             Binding.Value.Index >= First_Control
                           then
                              Put (Fn, ABC (Op_CLOSE, First_Control));
                              exit;
                           end if;
                        end loop;
                     end;
                     --  Pinned forbody fixes both iterator-call and loop
                     --  words to the loop control site, independently of the
                     --  last body statement. Numeric loops revisit 'for';
                     --  generic loops revisit their first iterator token.
                     --  The separate entry preparation uses the consumed do
                     --  line above, including multiline headers.
                     Site.Line :=
                       (if Item.Kind = Numeric_For then Item.Site.Line else
                          Fetch (Item.Children (1)).Site.Line);
                     Index := PC (Fn);
                     if Item.Kind = Generic_For then
                        Put (Fn, ABC (Op_TFORCALL, Base, 0,
                                     Natural (Item.Symbols.Length)));
                     end if;
                     Fn.Code.Code.Replace_Element (Branch, Field_Set
                       (Fn.Code.Code (Branch), Bx, Index - Branch - 1));
                     Put (Fn, ABx
                       ((if Item.Kind = Numeric_For then Op_FORLOOP
                         else Op_TFORLOOP), Base, PC (Fn) - Start + 1));
                     if Item.Kind = Generic_For then
                        --  The implicit iterator closer leaves its scope
                        --  after forstat consumes end, independently of the
                        --  iterator revisit line. An initially empty loop
                        --  must go straight from preparation to this close.
                        Site.Line := Item.End_Line;
                     end if;
                     Leave (Fn, Base, Active);
                     End_Loop (Fn);
                  when others =>
                     raise Program_Error with "non-statement resolved node";
               end case;
            end Statement;

            procedure Build_Function
              (Fn : in out Function_State; Id : Node_Id;
               Parent : access Function_State := null)
            is
               Item : constant Nodes.Constant_Reference_Type :=
                 Fetch (if Id = No_Node then Unit.Root else Id);
               Last_Site : constant Source_Location := Site;
               procedure Capture (Symbol : Symbol_Id);
               procedure Capture (Symbol : Symbol_Id) is
                  Value : Place;
                  Index : Natural;
               begin
                  Value := Locate (Parent.all, Symbol);
                  if Value.Kind = Stack_Place then
                     --  Match the same live binding used by Locate, not an
                     --  unrelated earlier occupant of the reused register.
                     --  Hidden loop state shares the visible symbol solely
                     --  for debug lifetime, so its slot must match as well.
                     for Position in reverse Parent.Active.First_Index ..
                       Parent.Active.Last_Index
                     loop
                        if Parent.Active (Position).Symbol = Symbol and then
                          Parent.Active (Position).Value.Index = Value.Index
                        then
                           declare
                              Binding : Binding_Place :=
                                Parent.Active (Position);
                           begin
                              Binding.Captured := True;
                              Parent.Active.Replace_Element
                                (Position, Binding);
                           end;
                           exit;
                        end if;
                     end loop;
                  end if;
                  if Value.Kind = Constant_Place then
                     Fn.Captures.Append
                       (Binding_Place'(Symbol, Value, 0, False));
                  else
                     Index := Natural (Fn.Code.Upvalues.Length);
                     if Index = 255 then Fail (Upvalue_Limit); end if;
                     Fn.Code.Upvalues.Append (Upvalue'
                       (Value.Kind = Stack_Place, Byte (Value.Index),
                        Binding_Kind (Symbol), Intern_Text
                          (Unit.Names (Positive (Symbol)).Name)));
                     Fn.Captures.Append (Binding_Place'
                       (Symbol, (Upvalue_Place, Index,
                                 (Kind => Nil_Constant)), 0, False));
                  end if;
               end Capture;
            begin
               if Fn.Depth > Bounds.Nesting then
                  Fail (Nesting_Budget, Host => True);
               elsif Node_Count = Bounds.Prototypes then
                  Fail (Prototype_Budget, Host => True);
               end if;
               Node_Count := Node_Count + 1;
               Fn.Code := New_Prototype (Result.Code);
               Fn.Active.Set_Owner (Memory);
               Fn.String_Keys.Set_Owner (Memory);
               Fn.String_Buckets.Set_Owner (Memory);
               Fn.Captures.Set_Owner (Memory);
               Fn.Targets.Set_Owner (Memory);
               Fn.Pending.Set_Owner (Memory);
               Fn.Loop_Stack.Set_Owner (Memory);
               Fn.Code.Source := Intern (Result.Code, Source_Name);
               if Id = No_Node then
                  Fn.Code.Flags := 1;
                  Fn.Code.Upvalues.Append (Upvalue'
                    (True, 0, 0, Intern (Result.Code, "_ENV")));
                  Fn.Captures.Append (Binding_Place'
                    (Unit.Environment,
                     (Upvalue_Place, 0, (Kind => Nil_Constant)), 0, False));
               else
                  Fn.Code.First_Line := Item.Site.Line;
                  Fn.Code.Last_Line := Item.End_Line;
                  Fn.Last_Line := Item.Site.Line;
                  if Item.Symbols.Length > 200 then Fail (Local_Limit); end if;
                  Fn.Code.Parameters := Byte (Item.Symbols.Length);
                  Fn.Code.Flags :=
                    (if not Item.Flag then 0 elsif Item.Symbol = No_Symbol
                     then 1 else 2);
                  for Symbol of Item.Captures loop Capture (Symbol); end loop;
               end if;
               Site := Item.Site;
               if Id /= No_Node then
                  --  Fixed parameters are live at PC zero, including in a
                  --  not-yet-called vararg closure. Pinned parlist starts
                  --  their debug lifetimes before emitting VARARGPREP; only
                  --  the vararg table's lifetime begins after entry setup.
                  for Symbol of Item.Symbols loop
                     Bind (Fn, Symbol, Fn.Base);
                  end loop;
               end if;
               if Fn.Code.Flags /= 0 then
                  Put (Fn, ABC (Op_VARARGPREP));
               end if;
               if Id /= No_Node then
                  if Item.Flag then
                     if Item.Symbol /= No_Symbol then
                        Bind (Fn, Item.Symbol, Fn.Base);
                     else
                        Bind_Hidden (Fn, "(vararg table)", Fn.Base);
                     end if;
                  end if;
               end if;
               Block (Fn, (if Id = No_Node then Unit.Root else
                            Item.Children (1)), Own_Scope => False);
               --  close_func emits its final luaK_ret with the parser's
               --  last consumed token line (lcode.c:luaK_code). Functions
               --  retain their closing end line; the root retains its last
               --  token before EOF. The final lowered child may be an else
               --  expression on an earlier line and cannot supply this site.
               Site.Line := Item.End_Line;
               Put (Fn, ABC (Op_RETURN, Fn.Base, 1,
                 (if (Fn.Code.Flags and 1) /= 0 then
                   Natural (Fn.Code.Parameters) + 1 else 0), Flag => True));
               Leave (Fn, 0, 0, Emit_Close => False);
               --  Resolve label identities only within this function. The
               --  frontend has already rejected scope entry and cross-function
               --  jumps; source-order PCs can now be patched without parsing.
               for Jump_Item of Fn.Pending loop
                  declare
                     Found : Boolean := False;
                  begin
                     for Label of Fn.Targets loop
                        if Label.Id = Jump_Item.Target then
                           Patch (Fn, Jump_Item.PC, Label.PC);
                           Found := True;
                           exit;
                        end if;
                     end loop;
                     if not Found then
                        raise Program_Error with "resolved label missing";
                     end if;
                  end;
               end loop;
               Site := Last_Site;
            end Build_Function;
            Main : Function_State;
         begin
            Build_Function (Main, No_Node);
            Set_Root (Result.Code, Main.Code);
            Result.Outcome := Succeeded;
         exception
            when Abandon => Close (Result.Code);
            when Lua.Storage.Allocation_Error =>
               Result.Outcome := Memory_Failure;
               Result.Error := Allocation_Refused;
               Result.Location := Site;
               Close (Result.Code);
            when Storage_Error | Program_Error =>
               --  GNAT can wrap a refused controlled allocation in another
               --  exception. Only the owner's refusal witness identifies Lua
               --  memory failure; physical Ada stack exhaustion and ordinary
               --  programming errors must retain their host-abort path.
               if Lua.Storage.Refusal_Pending (Memory.all) then
                  Result.Outcome := Memory_Failure;
                  Result.Error := Allocation_Refused;
                  Result.Location := Site;
                  Close (Result.Code);
               else
                  raise;
               end if;
         end;
      end return;
   end Compile;
end Lua.Canonical_Compiler;
