with Lua.Storage.Buffers;
with Lua.Engine.Patterns;
with Lua.Engine.Strings;

package body Lua.Engine.Pattern_Drivers is
   package Managed renames Lua.Storage.Buffers;
   use type Integer_Value;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := To_String (Activation.Native_Name);
      Action : Native_Action := New_Action (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length) then
           Activation.Native_Arguments (Index) else Nil_Value);
      procedure Work (Count : Natural);
      function Copy_Bytes (Text : Byte_String) return String;
      function Copy_Argument (Item : Value) return String;
      procedure Append_Output (Text : String);
      procedure Finish (Subject : String);

      procedure Work (Count : Natural) is
      begin
         if Count > State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + Count;
         end if;
      end Work;

      function Copy_Bytes (Text : Byte_String) return String is
      begin
         --  Continuations root immutable managed byte strings. The matcher
         --  currently consumes String values. Charge that whole-subject copy
         --  before doing it on every resume: many tiny matches must not hide
         --  quadratic copying behind a small number of VM instructions.
         Work (Length (Text));
         return To_String (Text);
      end Copy_Bytes;

      function Copy_Argument (Item : Value) return String is
      begin
         if Item.Kind = String_Kind then
            return Copy_Bytes (Item.Reference.Bytes);
         end if;
         return Strings.String_Argument (State, Item);
      end Copy_Argument;

      procedure Append_Output (Text : String) is
      begin
         Work (Text'Length);
         if Text'Length > State.Bounds.String_Bytes - Natural'Min
           (Length (Activation.Native_Buffer), State.Bounds.String_Bytes)
         then
            Fail (State, "string byte limit exceeded", Resource => True);
         end if;
         Append (Activation.Native_Buffer, Text);
      end Append_Output;

      procedure Finish (Subject : String) is
      begin
         Append_Output (Subject (Activation.Native_Index + 1 .. Subject'Last));
         Action.Results.Append
           (New_String (State, Activation.Native_Buffer));
         Action.Results.Append
           (Value'(Integer_Kind, Integer_Value (Activation.Native_Aux)));
      end Finish;
   begin
      if Name in "gmatch" | "string.gmatch" then
         declare
            Captures : Values.Vector := Owned_Values (State);
            Subject : constant String := Copy_Argument (Arg (1));
            Initial : Integer_Value := 1;
         begin
            if Arg (3).Kind /= Nil_Kind then
               Initial := Strings.Relative_Position
                 (Strings.Integer_Argument (State, Arg (3)), Subject'Length);
            end if;
            Initial := Integer_Value'Max (1, Initial);
            Captures.Append (New_String (State, Subject));
            Captures.Append (New_String
              (State, Copy_Argument (Arg (2))));
            Captures.Append (Value'(Integer_Kind, Initial - 1));
            Captures.Append (Value'(Integer_Kind, -1));
            Action.Results.Append
              (New_Native (State, "gmatch.iterator", Captures));
         end;
         return Action;
      elsif Name = "gmatch.iterator" then
         declare
            Closure : constant Object_Access := Activation.Native_Self;
            Subject : constant String :=
              Copy_Bytes (Closure.Captures (1).Cell_Value.Reference.Bytes);
            Pattern : constant String :=
              Copy_Bytes (Closure.Captures (2).Cell_Value.Reference.Bytes);
            Position : Integer_Value := Closure.Captures
              (3).Cell_Value.Integer_Data;
            Last : constant Integer_Value := Closure.Captures
              (4).Cell_Value.Integer_Data;
            Found : Patterns.Match_Result;
         begin
            --  Retain positions in the native closure, not the call frame:
            --  each invocation gets a fresh frame but continues one iterator.
            while Position <= Integer_Value (Subject'Length) loop
               Found := Patterns.Find
                 (State, Subject, Pattern, Natural (Position),
                  Allow_Anchor => False);
               exit when not Found.Found;
               if Integer_Value (Found.After) /= Last then
                  Store_Cell (State, Closure.Captures (3),
                              (Integer_Kind, Integer_Value (Found.After)));
                  Store_Cell (State, Closure.Captures (4),
                              (Integer_Kind, Integer_Value (Found.After)));
                  Action.Results := Patterns.Capture_Values
                    (State, Subject, Found);
                  return Action;
               end if;
               Position := Position + 1;
            end loop;
            Store_Cell (State, Closure.Captures (3),
                        (Integer_Kind, Integer_Value (Subject'Length) + 1));
            return Action;
         end;
      end if;
      declare
         Subject : constant String := Copy_Argument (Arg (1));
         Pattern : constant String := Copy_Argument (Arg (2));
         Replacement : constant Value := Arg (3);
         Limit : Integer_Value := Integer_Value (Subject'Length) + 1;
         Anchored : constant Boolean := Pattern'Length > 0 and then
           Pattern (Pattern'First) = '^';
         Found : Patterns.Match_Result;
         Captures : Values.Vector := Owned_Values (State);
         Whole : Managed.Buffer;
         Last : Integer_Value;
         Changed : Value;
      begin
         Whole.Set_Owner (Lua.Storage.Reference (State.Memory));
         if Arg (4).Kind /= Nil_Kind then
            Limit := Strings.Integer_Argument (State, Arg (4));
         end if;
         if Replacement.Kind not in String_Kind | Integer_Kind | Real_Kind |
           Table_Kind | Closure_Kind | Native_Kind_Value |
           Native_Closure_Kind | Foreign_Function_Kind
         then
            Fail (State, "string/function/table expected");
         end if;
         if Activation.Native_Stage = 0 then
            --  Slot one is the last accepted end position. It prevents an
            --  empty match from being accepted repeatedly at the same byte.
            Append_Root
              (State, Activation.Native_Captures,
               Value'(Integer_Kind, -1));
            Activation.Native_Stage := 1;
         elsif Activation.Native_Stage = 2 then
            --  A callback may have run arbitrary Lua and forced collection.
            --  The original match and pending capture values remained rooted
            --  in this activation throughout the call.
            Changed := (if Activation.Native_Results.Is_Empty then Nil_Value
                        else Activation.Native_Results.First_Element);
            Whole.Set_Value
              (To_String (Activation.Native_Captures (2).Reference.Bytes));
            if not Truth (Changed) then
               Whole.Query (Append_Output'Access);
            elsif Changed.Kind in String_Kind | Integer_Kind | Real_Kind then
               Append_Output (Strings.String_Argument (State, Changed));
            else
               Fail (State, "invalid replacement value");
            end if;
            Activation.Native_Results.Clear;
            Activation.Native_Stage := 1;
            Action.Kind := Continue_Step;
            return Action;
         end if;
         if Integer_Value (Activation.Native_Aux) >= Limit or else
           (Anchored and then Activation.Native_Aux > 0)
         then
            Finish (Subject);
            return Action;
         end if;
         Found := Patterns.Find
           (State, Subject, Pattern, Activation.Native_Index);
         if not Found.Found then
            Finish (Subject);
            return Action;
         end if;
         Last := Activation.Native_Captures (1).Integer_Data;
         if Integer_Value (Found.After) = Last then
            if Activation.Native_Index < Subject'Length then
               Append_Output (String'(1 =>
                 Subject (Activation.Native_Index + 1)));
               Activation.Native_Index := Activation.Native_Index + 1;
               Action.Kind := Continue_Step;
            else
               Finish (Subject);
            end if;
            return Action;
         end if;
         Append_Output
           (Subject (Activation.Native_Index + 1 .. Found.First));
         Whole.Set_Value (Subject (Found.First + 1 .. Found.After));
         Captures := Patterns.Capture_Values (State, Subject, Found);
         Activation.Native_Index := Found.After;
         Activation.Native_Aux := Activation.Native_Aux + 1;
         Activation.Native_Captures.Clear;
         Append_Root
           (State, Activation.Native_Captures,
            Value'(Integer_Kind, Integer_Value (Found.After)));
         Append_Root
           (State, Activation.Native_Captures,
            New_String (State, Whole));
         for Item of Captures loop
            Append_Root
              (State, Activation.Native_Captures,
               Item);
         end loop;
         if Replacement.Kind in String_Kind | Integer_Kind | Real_Kind then
            declare
               Text : constant String := Strings.String_Argument
                 (State, Replacement);
               Cursor : Positive := Text'First;
               Capture_Index : Natural;
            begin
               while Cursor <= Text'Last loop
                  if Text (Cursor) /= '%' then
                     Append_Output (String'(1 => Text (Cursor)));
                  else
                     Cursor := Cursor + 1;
                     if Cursor > Text'Last then
                        Fail (State,
                              "invalid use of '%' in replacement string");
                     elsif Text (Cursor) = '%' then
                        Append_Output ("%");
                     elsif Text (Cursor) in '0' .. '9' then
                        Capture_Index := Character'Pos (Text (Cursor)) - 48;
                        if Capture_Index = 0 then
                           Whole.Query (Append_Output'Access);
                        elsif Capture_Index > Natural (Captures.Length) then
                           Fail (State, "invalid capture index");
                        else
                           Append_Output (Strings.String_Argument
                             (State, Captures (Capture_Index)));
                        end if;
                     else
                        Fail (State,
                              "invalid use of '%' in replacement string");
                     end if;
                  end if;
                  Cursor := Cursor + 1;
               end loop;
            end;
            Action.Kind := Continue_Step;
         elsif Replacement.Kind = Table_Kind then
            Action.Kind := Invoke;
            Action.Function_Value := New_Native (State, "@get");
            Action.Arguments.Append (Replacement);
            Action.Arguments.Append (Captures.First_Element);
            Activation.Native_Stage := 2;
         elsif Replacement.Kind in Closure_Kind | Native_Kind_Value |
           Native_Closure_Kind | Foreign_Function_Kind
         then
            Action.Kind := Invoke;
            Action.Function_Value := Replacement;
            Action.Arguments := Captures;
            Activation.Native_Stage := 2;
         else
            Fail (State, "string/function/table expected");
         end if;
      end;
      return Action;
   end Advance;
end Lua.Engine.Pattern_Drivers;
