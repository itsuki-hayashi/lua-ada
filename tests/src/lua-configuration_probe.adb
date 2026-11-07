with Ada.Text_IO;
with Lua.Engine;
with Lua.Runtime_Configuration;
with Lua.Syntax;

procedure Lua.Configuration_Probe is
   use Lua.Engine;
   use type Lua.Syntax.Check_Status;
   State : World;
   Math_Table : Value;
   Exports : Natural := 0;
   function Boolean_Text (Item : Boolean) return String;
   function Boolean_Text (Item : Boolean) return String is
     (if Item then "true" else "false");
   procedure Count_Export (Name : String);
   procedure Count_Export (Name : String) is
   begin
      if Get (Math_Table, New_String (State, Name)).Kind /= Nil_Kind then
         Exports := Exports + 1;
      end if;
   end Count_Export;
begin
   Initialize (State, (others => <>));
   begin
      --  Count actual registered functions, not only the selected flag. The
      --  parser witness likewise checks whether global is a reserved keyword.
      Math_Table := Get
        (Global_Environment (State), New_String (State, "math"));
      Count_Export ("atan2");
      Count_Export ("cosh");
      Count_Export ("sinh");
      Count_Export ("tanh");
      Count_Export ("pow");
      Count_Export ("log10");
      Ada.Text_IO.Put_Line
        ("{""configuration"":""" & Lua.Runtime_Configuration.Name &
         """,""configured_stack_slots"":" &
         Positive'Image (Lua.Runtime_Configuration.Maximum_Stack) &
         ",""configured_c_calls"":" &
         Positive'Image (Lua.Runtime_Configuration.Maximum_C_Calls) &
         ",""configured_aux_buffer_bytes"":" & Positive'Image
           (Lua.Runtime_Configuration.Auxiliary_Buffer_Bytes) &
         ",""compatible_global"":" & Boolean_Text
           (Lua.Runtime_Configuration.Compatible_Global) &
         ",""world_random32"":" &
         Boolean_Text (State.Random_Use_32_Bits) &
         ",""world_compat_math"":" &
         Boolean_Text (State.Math_Compatibility) &
         ",""compatibility_exports"":" & Natural'Image (Exports) &
         ",""reserved_global"":" & Boolean_Text
           (Lua.Syntax.Check ("local global=1").Status =
            Lua.Syntax.Syntax_Error) & "}");
   exception
      when others => Finalize (State); raise;
   end;
   Finalize (State);
end Lua.Configuration_Probe;
