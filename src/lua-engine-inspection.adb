with Lua.Engine.Strings;
with Ada.Strings.Fixed;

package body Lua.Engine.Inspection is
   use type Integer_Value;

   function Short_Source (Source : String) return String;
   function Short_Source (Source : String) return String is
      Newline : constant Natural :=
        Ada.Strings.Fixed.Index (Source, "" & Character'Val (10));
      Size : Natural := Source'Length;
      Truncated : Boolean := False;
   begin
      --  A default debug identifier has 59 payload bytes plus its C NUL.
      --  File identifiers retain the tail; snippets retain the first
      --  line with a quoted prefix/suffix. No native record layout is
      --  involved.
      if Source'Length > 0 and then Source (Source'First) in '=' | '@' then
         if Source'Length <= 60 or else Source (Source'First) = '=' then
            return Source (Source'First + 1 ..
              Natural'Min (Source'Last, Source'First + 59));
         end if;
         return "..." & Source (Source'Last - 55 .. Source'Last);
      end if;
      if Newline /= 0 then
         Size := Newline - Source'First;
         Truncated := True;
      end if;
      if Source'Length >= 45 then
         Truncated := True;
      end if;
      Size := Natural'Min (45, Size);
      return "[string """ & Source (Source'First .. Source'First + Size - 1) &
        (if Truncated then "..." else "") & """]";
   end Short_Source;

   function Inspect
     (State : in out World; Activation : Frame_Access) return Values.Vector
   is
      Name : constant String := To_String (Activation.Native_Name);
      Args : constant Values.Vector := Activation.Native_Arguments;
      Context : Context_Access := State.Current;
      Base : Positive := 1;
      Result : Values.Vector;
      Selected : Frame_Access;
      Function_Value : Value;
      Code : Prototype_Access;

      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Args.Length) then Args (Index) else Nil_Value);
      function Integer_Arg (Index : Positive) return Integer_Value;
      function Logical_Frame (Level : Natural) return Frame_Access;
      function Symbol_Text
        (Prototype : Prototype_Access; Symbol : Positive) return String;
      procedure Append (Item : Value);
      procedure Work;
      procedure Field (Table : Value; Key : String; Item : Value);

      procedure Work is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
      end Work;

      function Integer_Arg (Index : Positive) return Integer_Value is
      begin
         return Strings.Integer_Argument (State, Arg (Index));
      end Integer_Arg;

      function Logical_Frame (Level : Natural) return Frame_Access is
         Remaining : Natural := Level;
         function Failed_Owner (Candidate : Frame_Access) return Boolean;
         function Failed_Owner (Candidate : Frame_Access) return Boolean is
         begin
            --  An errored Lua activation is retained only to own its closing
            --  cells. Its logical call has already unwound to protection.
            for Driver of Context.Stack loop
               if Driver.Is_Native and then Driver.Native_Name = "@unwind"
                 and then Driver.Unwind = Error_Exit and then
                 Driver.Unwind_Owner = Candidate
               then
                  return True;
               end if;
            end loop;
            return False;
         end Failed_Owner;
      begin
         --  Scheduler helper activations are implementation phases, not Lua
         --  stack frames. Public native closures retain their logical frame.
         for Item of reverse Context.Stack loop
            Work;
            if not Failed_Owner (Item) and then
              (not Item.Is_Native or else
               (Length (Item.Native_Name) > 0 and then
                Element (Item.Native_Name, 1) /= '@'))
            then
               if Remaining = 0 then
                  return Item;
               end if;
               Remaining := Remaining - 1;
            end if;
         end loop;
         return null;
      end Logical_Frame;

      function Symbol_Text
        (Prototype : Prototype_Access; Symbol : Positive) return String
      is
      begin
         if Prototype /= null then
            for Item of Prototype.Names loop
               Work;
               if Item.Symbol = Symbol then
                  return To_String (Item.Name);
               end if;
            end loop;
         end if;
         return "_ENV";
      end Symbol_Text;

      procedure Append (Item : Value) is
      begin
         Result.Append (Item);
      end Append;

      procedure Field (Table : Value; Key : String; Item : Value) is
      begin
         Set (State, Table, New_String (State, Key), Item);
      end Field;
   begin
      if Arg (1).Kind = Thread_Kind then
         Context := State.Contexts (Arg (1).Reference.Context_Index);
         Base := 2;
      end if;
      if Name = "debug.sethook" then
         if Arg (Base).Kind = Nil_Kind then
            Context.Hook := Nil_Value;
            Context.Hook_Mask := Null_Unbounded_String;
            Context.Hook_Count := 0;
            Context.Hook_Reported_Count := 0;
         else
            if Arg (Base).Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value
            then
               Fail (State, "function expected");
            end if;
            if Arg (Base + 1).Kind /= String_Kind then
               Fail (State, "string expected");
            end if;
            if Arg (Base + 2).Kind /= Nil_Kind and then
              (Integer_Arg (Base + 2) > Integer_Value (Natural'Last) or else
               Integer_Arg (Base + 2) < Integer_Value (Integer'First))
            then
               Fail (State, "hook count out of range");
            end if;
            Context.Hook := Arg (Base);
            Context.Hook_Mask := Null_Unbounded_String;
            for Mask of String'("crl") loop
               if Ada.Strings.Fixed.Index
                 (C_Option (Image (Arg (Base + 1))), "" & Mask) /= 0
               then
                  Append (Context.Hook_Mask, Mask);
               end if;
            end loop;
            --  Reflection preserves a signed requested count, while only a
            --  positive interval enables instruction-count events.
            Context.Hook_Reported_Count :=
              (if Arg (Base + 2).Kind = Nil_Kind then 0
               else Integer_Arg (Base + 2));
            Context.Hook_Count :=
              (if Arg (Base + 2).Kind = Nil_Kind then 0 else
                 Natural (Integer_Value'Max (0, Integer_Arg (Base + 2))));
            Context.Hook_Remaining := Context.Hook_Count;
            if Length (Context.Hook_Mask) = 0 and then
              Context.Hook_Count = 0
            then
               Context.Hook := Nil_Value;
            end if;
         end if;
      elsif Name = "debug.gethook" then
         Append (Context.Hook);
         --  With no hook, C Lua returns one nil, not a padded triple. Result
         --  counts remain observable through select, varargs and table.pack.
         if Context.Hook.Kind = Nil_Kind then
            return Result;
         end if;
         Append (New_String (State, To_String (Context.Hook_Mask)));
         Append ((Integer_Kind, Context.Hook_Reported_Count));
      elsif Name in "debug.getupvalue" | "debug.setupvalue" | "debug.upvalueid"
      then
         Function_Value := Arg (1);
         declare
            Index : constant Integer_Value := Integer_Arg (2);
            Cell : Object_Access;
         begin
            if Function_Value.Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value
            then
               Fail (State, "function expected");
            end if;
            if Function_Value.Kind = Native_Kind_Value or else
              Index < 1 or else Index > Integer_Value
                ((if Function_Value.Kind = Closure_Kind then
                    Function_Value.Reference.Upvalues.Length else
                    Function_Value.Reference.Captures.Length))
            then
               if Name = "debug.upvalueid" then
                  Fail (State, "invalid upvalue index");
               end if;
               return Result;
            end if;
            Cell :=
              (if Function_Value.Kind = Closure_Kind then
                 Function_Value.Reference.Upvalues (Positive (Index)) else
                 Function_Value.Reference.Captures (Positive (Index)));
            if Name = "debug.upvalueid" then
               Append ((Light_Identity_Kind, Cell.Serial));
            else
               if Function_Value.Kind = Closure_Kind then
                  Code := Function_Value.Reference.Code;
               end if;
               Append (New_String
                 (State, (if Code = null then "" else Symbol_Text
                    (Code, (if Code.Is_Main then Code.Environment_Symbol
                     else Code.Capture_Symbols (Positive (Index)))))));
               if Name = "debug.setupvalue" then
                  Cell.Cell_Value := Arg (3);
               else
                  Append (Cell.Cell_Value);
               end if;
            end if;
         end;
      elsif Name = "debug.getinfo" then
         Function_Value := Arg (Base);
         if Function_Value.Kind = Integer_Kind then
            if Function_Value.Integer_Data < 0 or else
              Function_Value.Integer_Data > Integer_Value (Natural'Last)
            then
               Append (Nil_Value);
               return Result;
            end if;
            Selected := Logical_Frame
              (Natural (Function_Value.Integer_Data));
            if Selected = null then
               Append (Nil_Value);
               return Result;
            end if;
            Function_Value := Selected.Callee;
            if Selected.Is_Native and then
              Function_Value.Kind = Nil_Kind and then
              Selected.Native_Self /= null
            then
               Function_Value := (Native_Closure_Kind, Selected.Native_Self);
            end if;
         elsif Function_Value.Kind not in Closure_Kind | Native_Closure_Kind |
           Native_Kind_Value
         then
            Fail (State, "function or level expected");
         end if;
         if Function_Value.Kind = Closure_Kind then
            Code := Function_Value.Reference.Code;
         end if;
         declare
            Options : constant String :=
              (if Arg (Base + 1).Kind = Nil_Kind then "flnSrtu"
               else C_Option (Image (Arg (Base + 1))));
            Info : constant Value := New_Table (State);
            Source : constant String :=
              (if Code = null then "=[C]" else To_String (Code.Name));
            Line : Integer_Value := -1;
            function Wants (Option : Character) return Boolean is
              (Ada.Strings.Fixed.Index (Options, "" & Option) /= 0);
         begin
            for Option of Options loop
               if Option not in 'f' | 'l' | 'n' | 'S' | 'r' | 't' | 'u' | 'L'
               then
                  Fail (State, "invalid option");
               end if;
            end loop;
            if Selected /= null and then not Selected.Is_Native and then
              Selected.PC > 1 and then
              Selected.PC - 1 <= Selected.Code.Code.Last_Index
            then
               Line := Integer_Value
                 (Selected.Code.Code (Selected.PC - 1).Location.Line);
            end if;
            if Context.Hook_Active and then Selected /= null and then
              Selected = Context.Hook_Frame and then not Selected.Is_Native
              and then Selected.PC <= Selected.Code.Code.Last_Index
            then
               Line := Integer_Value
                 (Selected.Code.Code (Selected.PC).Location.Line);
            end if;
            if Wants ('l') then
               Field (Info, "currentline", (Integer_Kind, Line));
            end if;
            if Wants ('S') then
               Field (Info, "source", New_String (State, Source));
               Field (Info, "short_src", New_String
                 (State, Short_Source (Source)));
               Field (Info, "linedefined", (Integer_Kind,
                 (if Code = null then -1 else
                    Integer_Value (Code.First_Line))));
               Field (Info, "lastlinedefined", (Integer_Kind,
                 (if Code = null then -1 else
                    Integer_Value (Code.Last_Line))));
               Field (Info, "what", New_String
                 (State, (if Code = null then "C"
                  elsif Code.Is_Main then "main" else "Lua")));
            end if;
            if Wants ('u') then
               Field (Info, "nups", (Integer_Kind,
                 (if Function_Value.Kind = Native_Closure_Kind then
                    Integer_Value (Function_Value.Reference.Captures.Length)
                  elsif Code = null then 0 else Integer_Value
                    (Function_Value.Reference.Upvalues.Length))));
               Field (Info, "nparams", (Integer_Kind,
                 (if Code = null then 0 else
                    Integer_Value (Code.Parameters.Length))));
               Field (Info, "isvararg", (Boolean_Kind,
                 Code = null or else Code.Vararg));
            end if;
            if Wants ('n') then
               Field (Info, "namewhat", New_String
                 (State, (if Selected = null then "" else
                    To_String (Selected.Name_Kind))));
               if Selected /= null and then Length (Selected.Call_Name) > 0
               then
                  Field (Info, "name", New_String
                    (State, To_String (Selected.Call_Name)));
               end if;
            end if;
            if Wants ('t') then
               Field (Info, "istailcall",
                      (Boolean_Kind, Selected /= null and then
                         Selected.Is_Tail_Call));
            end if;
            if Wants ('f') then
               Field (Info, "func", Function_Value);
            end if;
            if Wants ('r') then
               declare
                  Transferring : constant Boolean :=
                    Context.Hook_Active and then Context.Hook_Transfer
                    and then Selected /= null and then
                    Selected = Context.Hook_Frame;
               begin
                  Field (Info, "ftransfer", (Integer_Kind,
                    (if Transferring then 1 else 0)));
                  Field (Info, "ntransfer", (Integer_Kind,
                    (if Transferring then
                       Integer_Value (Selected.Transfer_Count) else 0)));
               end;
            end if;
            if Wants ('L') then
               declare
                  Lines : constant Value := New_Table (State);
               begin
                  if Code /= null then
                     for Instruction of Code.Code loop
                        Set (State, Lines,
                             (Integer_Kind,
                              Integer_Value (Instruction.Location.Line)),
                             (Boolean_Kind, True));
                     end loop;
                  end if;
                  Field (Info, "activelines", Lines);
               end;
            end if;
            Append (Info);
         end;
      elsif Name in "debug.getlocal" | "debug.setlocal" then
         if Name = "debug.getlocal" and then Arg (Base).Kind in
           Closure_Kind | Native_Closure_Kind | Native_Kind_Value
         then
            declare
               Index : constant Integer_Value := Integer_Arg (Base + 1);
            begin
               if Arg (Base).Kind = Closure_Kind then
                  Code := Arg (Base).Reference.Code;
                  if Index > 0 and then
                    Index <= Integer_Value (Code.Parameters.Length)
                  then
                     Append (New_String
                       (State, Symbol_Text
                          (Code, Code.Parameters (Positive (Index)))));
                     return Result;
                  end if;
               end if;
               Append (Nil_Value);
               return Result;
            end;
         end if;
         if Name = "debug.setlocal" and then
           Natural (Args.Length) < Base + 2
         then
            Fail (State, "value expected");
         end if;
         declare
            Level : constant Integer_Value := Integer_Arg (Base);
            Index : constant Integer_Value := Integer_Arg (Base + 1);
            Cells : Bindings.Vector;
            Scope : Object_Access;
         begin
            if Level < 0 or else Level > Integer_Value (Natural'Last) then
               Fail (State, "level out of range");
            end if;
            Selected := Logical_Frame (Natural (Level));
            if Selected = null then
               Fail (State, "level out of range");
            end if;
            if not Selected.Is_Native then
               if Index < 0 then
                  if Index >= -Integer_Value (Selected.Varargs.Length) then
                     Append (New_String (State, "(vararg)"));
                     if Name = "debug.setlocal" then
                        Selected.Varargs.Replace_Element
                          (Positive (-Index), Arg (Base + 2));
                     else
                        Append (Selected.Varargs (Positive (-Index)));
                     end if;
                  end if;
                  if Result.Is_Empty then
                     Append (Nil_Value);
                  end if;
                  return Result;
               end if;
               Scope := Selected.Scope;
               while Scope /= null and then Scope /=
                 Selected.Callee.Reference.Capture
               loop
                  --  Inner scopes are traversed first, then prepended as a
                  --  group, preserving source declaration order for locals.
                  for Binding of reverse Scope.Locals loop
                     Cells.Prepend (Binding);
                  end loop;
                  Scope := Scope.Parent;
               end loop;
               if Index > 0 and then Index <= Integer_Value (Cells.Length) then
                  Append (New_String
                    (State, Symbol_Text
                       (Selected.Code, Cells (Positive (Index)).Symbol)));
                  if Name = "debug.setlocal" then
                     Cells (Positive (Index)).Cell.Cell_Value :=
                       Arg (Base + 2);
                  else
                     Append (Cells (Positive (Index)).Cell.Cell_Value);
                  end if;
               end if;
            elsif Index > 0 and then
              Index <= Integer_Value (Selected.Native_Arguments.Length)
            then
               Append (New_String (State, "(C temporary)"));
               if Name = "debug.setlocal" then
                  Selected.Native_Arguments.Replace_Element
                    (Positive (Index), Arg (Base + 2));
               else
                  Append (Selected.Native_Arguments (Positive (Index)));
               end if;
            end if;
            if Result.Is_Empty then
               Append (Nil_Value);
            end if;
         end;
      elsif Name = "debug.traceback" then
         declare
            Text : Unbounded_String;
            Level : Natural := (if Context = State.Current then 1 else 0);
            Item : Frame_Access;
         begin
            if Arg (Base).Kind not in Nil_Kind | String_Kind |
              Integer_Kind | Real_Kind
            then
               Append (Arg (Base));
               return Result;
            end if;
            if Arg (Base).Kind /= Nil_Kind then
               Text := To_Unbounded_String (Image (Arg (Base)) &
                 Character'Val (10));
            end if;
            if Arg (Base + 1).Kind /= Nil_Kind then
               if Integer_Arg (Base + 1) > Integer_Value (Natural'Last) then
                  Fail (State, "level out of range");
               end if;
               Level := Natural (Integer_Value'Max
                 (0, Integer_Arg (Base + 1)));
            end if;
            Append (Text, "stack traceback:");
            loop
               Item := Logical_Frame (Level);
               exit when Item = null;
               Append (Text, Character'Val (10) & Character'Val (9));
               if Item.Is_Native then
                  Append (Text, "[C]: in function '" &
                    To_String (Item.Native_Name) & "'");
               else
                  Append (Text, Short_Source (To_String (Item.Code.Name)) &
                    ":" &
                    Ada.Strings.Fixed.Trim
                      (Natural'Image
                        (Item.Code.Code
                           (Positive'Max (1, Item.PC - 1)).Location.Line),
                       Ada.Strings.Both) & ": in " &
                    (if Item.Code.Is_Main then "main chunk"
                     else "function"));
               end if;
               Level := Level + 1;
            end loop;
            Append (New_String (State, To_String (Text)));
         end;
      else
         Fail (State, "debug operation not implemented");
      end if;
      return Result;
   end Inspect;
end Lua.Engine.Inspection;
