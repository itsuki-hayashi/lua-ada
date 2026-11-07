with Ada.Strings.Fixed;
with Lua.Engine.Call_Names;
with Lua.Engine.Canonical;
with Lua.Engine.Inspection;
with Lua.Engine.Tables;
with Lua.Prototypes;
with System;

package body Lua.Engine.Diagnostics is
   use type Call_Names.Name_Kind;
   use type System.Address;
   use type Lua.Prototypes.Prototype_Access;
   use type Lua.Numbers.Number_Kind;
   use type Real_Value;

   procedure Work (State : in out World);
   procedure Work (State : in out World) is
   begin
      if State.Policy = Bounded then
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + 1;
      end if;
   end Work;

   function Global_Name
     (State : in out World; Target : Value) return String;
   function Global_Name
     (State : in out World; Target : Value) return String
   is
      Name : Unbounded_String;
      Modules : constant Value :=
        Tables.Raw_Field (State.Foreign_Registry, "_LOADED");
      function Find (Table : Object_Access; Depth : Natural) return Boolean;
      function Find (Table : Object_Access; Depth : Natural) return Boolean is
      begin
         if Table = null or else Depth = 0 then return False; end if;
         --  luaL_argerror searches the actual loaded-module graph to depth
         --  two. Borrow existing rows; no value snapshot or name cache can
         --  retain deleted members or hide later registry/module mutations.
         for Member of Table.Members loop
            Work (State);
            if Member.Item.Kind /= Nil_Kind and then
              Member.Key.Kind = String_Kind
            then
               if Equal (Member.Item, Target) then
                  Name := To_Unbounded_String
                    (To_String (Member.Key.Reference.Bytes));
                  return True;
               elsif Depth > 1 and then Member.Item.Kind = Table_Kind and then
                 Find (Member.Item.Reference, Depth - 1)
               then
                  Name := To_Unbounded_String
                    (To_String (Member.Key.Reference.Bytes) & "." &
                     To_String (Name));
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Find;
   begin
      if Modules.Kind = Table_Kind and then Find (Modules.Reference, 2) then
         declare
            Text : constant String := To_String (Name);
            Rendered : constant String := Call_Names.Name_Image
              (((Text'Address, Text'Length), Call_Names.Global_Field));
         begin
            if Rendered'Length >= 3 and then
              Rendered (Rendered'First .. Rendered'First + 2) = "_G."
            then
               return Rendered (Rendered'First + 3 .. Rendered'Last);
            end if;
            return Rendered;
         end;
      end if;
      return "?";
   end Global_Name;

   procedure Argument_Error
     (State : in out World; Index : Positive; Detail : String)
   is
      Context : constant Context_Access := State.Current;
      Owner : constant Frame_Access :=
        Inspection.Logical_Frame (State, Context, 0);
      Origin : Call_Names.Borrowed_Identity;
      Caller : Frame_Access;
      Position : Natural := Index;
      Extra : Boolean := False;
      Description : Unbounded_String;
      Label : Unbounded_String;
   begin
      if Owner = null then
         Description := To_Unbounded_String
           ("bad argument #" & Ada.Strings.Fixed.Trim
              (Index'Image, Ada.Strings.Both) & " (" & Detail & ")");
      else
         Origin := Inspection.Call_Identity (State, Context, Owner);
         Caller := Inspection.Caller_Frame (State, Context, Owner);
         Label := To_Unbounded_String
           ((if Origin.Item.Address /= System.Null_Address then
                Call_Names.Name_Image (Origin)
             else Global_Name (State, Owner.Callee)));
         Extra := Index <= Owner.Call_Metamethod_Count;
         if not Extra then
            Position := Index - Owner.Call_Metamethod_Count;
            if Origin.Kind = Call_Names.Method_Call then
               Position := Position - 1;
            end if;
         end if;
         --  Extra __call values keep their original indices. Colon self is
         --  removed only after those values, and its own error has a distinct
         --  spelling. These are actual activation counts, not value guesses.
         if not Extra and then Position = 0 then
            Description := To_Unbounded_String
              ("calling '" & To_String (Label) & "' on bad self (" &
               Detail & ")");
         else
            Description := To_Unbounded_String
              ("bad " & (if Extra then "extra argument #" else "argument #") &
               Ada.Strings.Fixed.Trim (Position'Image, Ada.Strings.Both) &
               " to '" & To_String (Label) & "' (" & Detail & ")");
         end if;
      end if;
      if Caller /= null and then not Caller.Is_Native then
         declare
            PC : constant Natural := Natural'Max (1, Caller.PC - 1);
            Line : constant Natural :=
              (if Caller.Code.Canonical_Node /= null then
                  Canonical.Source_Line (Caller, PC - 1)
               else Caller.Code.Code (PC).Location.Line);
         begin
            --  luaL_where omits unknown/stripped lines, unlike a VM type
            --  error's explicit ?:?: prefix. Never borrow an older Lua frame
            --  through an immediate C caller to manufacture a location.
            if Line > 0 then
               Fail (State, Inspection.Short_Source
                 ((if Caller.Code.Canonical_Node /= null then
                     To_String (Canonical.Source_Bytes (Caller.Code))
                   else To_String (Caller.Code.Name))) & ":" &
                 Ada.Strings.Fixed.Trim (Line'Image, Ada.Strings.Both) &
                 ": " & To_String (Description));
            end if;
         end;
      end if;
      Fail (State, To_String (Description));
   end Argument_Error;

   procedure Type_Error
     (State : in out World; Index : Positive; Expected : String;
      Item : Value; Present : Boolean := True) is
   begin
      Argument_Error
        (State, Index, Expected & " expected, got " &
         Argument_Type (State, Item, Present));
   end Type_Error;

   function Integer_Argument
     (State : in out World; Index : Positive; Item : Value;
      Present : Boolean := True) return Integer_Value
   is
      Number : Lua.Numbers.Number;
   begin
      case Item.Kind is
         when Integer_Kind => return Item.Integer_Data;
         when Real_Kind =>
            Number := (Lua.Numbers.Real_Number, Item.Real_Data);
         when String_Kind =>
            Number := Read_Number (State, Item.Reference.Bytes);
         when others => Number := (Kind => Lua.Numbers.Invalid);
      end case;
      if Number.Kind = Lua.Numbers.Integer_Number then
         return Number.Integer_Item;
      elsif Number.Kind = Lua.Numbers.Invalid then
         Type_Error (State, Index, "number", Item, Present);
      elsif Number.Real_Item >= -(2.0 ** 63) and then
        Number.Real_Item < 2.0 ** 63 and then
        Real_Value'Truncation (Number.Real_Item) = Number.Real_Item
      then
         --  The upper endpoint is strict: binary64 rounds int64'Last to
         --  2**63. Guard range/NaN before the checked integer conversion;
         --  parsed integers preserve all 64 bits without a float roundtrip.
         return Integer_Value (Number.Real_Item);
      end if;
      Argument_Error (State, Index, "number has no integer representation");
      return 0;
   end Integer_Argument;
end Lua.Engine.Diagnostics;
