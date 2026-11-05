with Lua.Engine.Formats;
with Lua.Engine.Strings;

package body Lua.Engine.Format_Drivers is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Action : Native_Action;
      First : Positive;
      Cursor : Positive;
      procedure Work (Count : Natural := 1);
      procedure Append_Output (Text : String);

      procedure Work (Count : Natural := 1) is
      begin
         if Count > State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Count;
      end Work;

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
   begin
      if Activation.Native_Arguments.Is_Empty then
         Fail (State, "string expected");
      end if;
      if Activation.Native_Arguments (1).Kind = String_Kind then
         --  The retained format is copied once per continuation advance.
         --  Charge before obtaining that view, including callback resumes.
         Work (Length (Activation.Native_Arguments (1).Reference.Bytes));
      end if;
      if Activation.Native_Stage = 0 then
         Activation.Native_Index := 1;
         Activation.Native_Aux := 2;
         Activation.Native_Stage := 1;
      elsif Activation.Native_Stage = 2 then
         --  A %s conversion can enter arbitrary Lua through __tostring.
         --  Its specification is retained independently of parser locals;
         --  the VM roots both captures and pending results across that call.
         if Activation.Native_Results.Is_Empty or else
           Activation.Native_Results (1).Kind /= String_Kind
         then
            Fail (State, "'__tostring' must return a string");
         end if;
         Append_Output (Formats.Render
           (State, To_String
              (Activation.Native_Captures (1).Reference.Bytes),
            Activation.Native_Results (1)));
         Activation.Native_Results.Clear;
         Activation.Native_Captures.Clear;
         Activation.Native_Stage := 1;
      end if;
      declare
         Form : constant String := Strings.String_Argument
           (State, Activation.Native_Arguments (1));
      begin
         Cursor := Activation.Native_Index;
         while Cursor <= Form'Last loop
            Work;
            if Form (Cursor) /= '%' then
               Append_Output (String'(1 => Form (Cursor)));
               Cursor := Cursor + 1;
            elsif Cursor < Form'Last and then Form (Cursor + 1) = '%' then
               Append_Output ("%");
               Cursor := Cursor + 2;
            else
               First := Cursor;
               Cursor := Cursor + 1;
               while Cursor <= Form'Last and then
                 Form (Cursor) in '-' | '+' | ' ' | '#' | '0' .. '9' | '.'
               loop
                  Work;
                  Cursor := Cursor + 1;
               end loop;
               if Activation.Native_Aux >
                 Natural (Activation.Native_Arguments.Length)
               then
                  Fail (State, "no value");
               elsif Cursor > Form'Last then
                  Fail (State, "invalid conversion specification");
               end if;
               if Form (Cursor) = 's' then
                  --  Always use the ordinary tostring path, including for
                  --  strings: a per-type handler can override that behavior.
                  Activation.Native_Captures.Append
                    (New_String (State, Form (First .. Cursor)));
                  Action.Kind := Invoke;
                  Action.Function_Value := New_Native (State, "base.tostring");
                  Action.Arguments.Append
                    (Activation.Native_Arguments (Activation.Native_Aux));
                  Activation.Native_Stage := 2;
               else
                  Append_Output (Formats.Render
                    (State, Form (First .. Cursor),
                     Activation.Native_Arguments (Activation.Native_Aux)));
                  Action.Kind := Continue_Step;
               end if;
               Activation.Native_Aux := Activation.Native_Aux + 1;
               Activation.Native_Index := Cursor + 1;
               return Action;
            end if;
         end loop;
      end;
      Action.Results.Append
        (New_String (State, To_String (Activation.Native_Buffer)));
      return Action;
   end Advance;
end Lua.Engine.Format_Drivers;
