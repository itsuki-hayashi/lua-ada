with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Lua.Frontend_Text;
with Lua.Lexer_Core;
with Lua.Storage;

package body Lua.Lexers is
   function Open
     (Source : String; Maximum_Tokens : Positive := 100_000) return Scanner
   is
   begin
      return Result : Scanner (Source'Length) do
         Result.Input := Source;
         Result.Maximum := Maximum_Tokens;
      end return;
   end Open;

   function Next (Self : in out Scanner) return Scan_Result is
      Memory : Lua.Storage.Owner;
      Texts : Lua.Frontend_Text.Arena;
      Cursor : Lua.Lexer_Core.Scanner_State :=
        (Cursor => Self.Cursor, Maximum => Self.Maximum,
         Count => Self.Count, others => <>);
      Step : Lua.Lexer_Core.Scan_Result;
      Result : Scan_Result;
   begin
      if Self.Finished then
         return Self.Terminal;
      end if;
      --  The public API owns independent host Tokens. Only this adapter
      --  materializes Unbounded_String/vector results; parser and execution
      --  use the very same scanner directly with their selected allocator.
      Texts.Set_Owner (Lua.Storage.Reference (Memory));
      Step := Lua.Lexer_Core.Next (Self.Input, Cursor, Texts);
      Self.Cursor := Cursor.Cursor;
      Self.Count := Cursor.Count;
      Result.Status := Step.Status;
      Result.Location := Step.Location;
      if Step.Status = Success then
         Result.Tokens.Append
           (Token'(Kind => Step.Item.Kind, Location => Step.Item.Location,
                   After => Step.Item.After, Numeric => Step.Item.Numeric,
                   Text => To_Unbounded_String
                     (Texts.Text (Step.Item.Text))));
      else
         Result.Message := To_Unbounded_String (Texts.Text (Step.Message));
      end if;
      if Cursor.Finished then
         Self.Finished := True;
         Self.Terminal := Result;
      end if;
      return Result;
   exception
      when Storage_Error | Lua.Storage.Allocation_Error =>
         Result.Tokens.Clear;
         Result.Status := Resource_Error;
         Result.Location := Self.Cursor;
         Result.Message := To_Unbounded_String ("scanner storage exhausted");
         Self.Finished := True;
         Self.Terminal := Result;
         return Result;
   end Next;

   function Scan
     (Source : String;
      Maximum_Tokens : Positive := 100_000) return Scan_Result
   is
      Reader : Scanner := Open (Source, Maximum_Tokens);
      Result : Scan_Result;
      Step : Scan_Result;
   begin
      --  Batch scanning is only an adapter over the incremental state machine.
      --  Do not retain a partial host token list after a lexical failure.
      loop
         Step := Next (Reader);
         if Step.Status /= Success then
            return Step;
         end if;
         Result.Tokens.Append (Step.Tokens.First_Element);
         exit when Step.Tokens.First_Element.Kind = End_Of_Input;
      end loop;
      return Result;
   exception
      when Storage_Error =>
         Result.Tokens.Clear;
         Result.Status := Resource_Error;
         Result.Location := Reader.Cursor;
         Result.Message := To_Unbounded_String ("scanner storage exhausted");
         return Result;
   end Scan;
end Lua.Lexers;
