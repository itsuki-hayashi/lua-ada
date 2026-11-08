with Ada.Strings.Fixed;
with Lua.Engine.Call_Names;
with Lua.Engine.Canonical;
with Lua.Engine.Inspection;
with Lua.Engine.Machine;
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
     (State : in out World; Target, Modules : Value) return String;
   function Global_Name
     (State : in out World; Target, Modules : Value) return String
   is
      Name : Unbounded_String;
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

   procedure Render_Argument_Error
     (State : in out World; Index : Positive; Detail : String;
      Modules : Value);
   procedure Render_Argument_Error
     (State : in out World; Index : Positive; Detail : String;
      Modules : Value)
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
             else Global_Name (State, Owner.Callee, Modules)));
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
   end Render_Argument_Error;

   procedure Argument_Error
     (State : in out World; Index : Positive; Detail : String)
   is
      Context : constant Context_Access := State.Current;
      Owner : constant Frame_Access :=
        Inspection.Logical_Frame (State, Context, 0);
      Modules : constant Value :=
        Tables.Raw_Field (State.Foreign_Registry, "_LOADED");
      Registry : constant Value := (Table_Kind, State.Foreign_Registry);
      Origin : Call_Names.Borrowed_Identity;
      Phase : Frame_Access;
      Key : Value;
   begin
      if Owner /= null then
         Machine.Prepare_Argument_Diagnostic (State, Owner);
         Origin := Inspection.Call_Identity (State, Context, Owner);
      end if;
      if Owner /= null and then
        Origin.Item.Address = System.Null_Address and then
        Modules.Kind = Nil_Kind and then
        Metafield (State, Registry, "__index").Kind /= Nil_Kind
      then
         if not Owner.Is_Native or else Context.Stack_Window /= Owner then
            raise Program_Error with "argument error has no real C window";
         end if;
         Phase := Context.Stack.Last_Element;
         Phase.Argument_Error_Detail.Set_Value (Detail);
         Phase.Argument_Error_Index := Index;
         --  This operation will raise after the lookup; its Ada computation
         --  never resumes. Retire the copied inputs before a real handler
         --  can replace C locals and collect their old sole operand edges.
         Phase.Native_Arguments.Clear;
         Phase.Native_Captures.Clear;
         --  pushglobalfuncname leaves the inspected function and getfield's
         --  key in the real C frame before invoking registry __index. These
         --  are actual operation values, not an invented debug-only view.
         Machine.Push_Native_Value (State, Owner, Owner.Callee);
         Key := New_String (State, "_LOADED");
         Machine.Push_Native_Value (State, Owner, Key);
         raise Deferred_Argument_Error;
      end if;
      Render_Argument_Error (State, Index, Detail, Modules);
   end Argument_Error;

   procedure Finish_Argument_Error
     (State : in out World; Origin : not null Frame_Access; Modules : Value)
   is
      procedure Render (Detail : String);
      procedure Render (Detail : String) is
      begin
         Render_Argument_Error
           (State, Positive (Origin.Argument_Error_Index), Detail, Modules);
      end Render;
   begin
      if Origin.Argument_Error_Index = 0 then
         raise Program_Error with "missing retained argument diagnostic";
      end if;
      Origin.Argument_Error_Detail.Query (Render'Access);
   end Finish_Argument_Error;

   procedure Type_Error
     (State : in out World; Index : Positive; Expected : String;
      Item : Value; Present : Boolean := True)
   is
      Owner : constant Frame_Access :=
        Inspection.Logical_Frame (State, State.Current, 0);
      Type_Name : constant Value :=
        (if Present then Metafield (State, Item, "__name") else Nil_Value);
      Detail : Owned_Buffer;
      Message : Value;
      procedure Publish (Text : String);
      procedure Publish (Text : String) is
      begin
         if Owner /= null and then Owner.Is_Native and then
           State.Current.Stack_Window = Owner
         then
            Message := New_String (State, Text);
            Machine.Push_Native_Value (State, Owner, Message);
         end if;
         Argument_Error (State, Index, Text);
      end Publish;
   begin
      if Owner /= null then
         Machine.Prepare_Argument_Diagnostic (State, Owner);
      end if;
      if Owner /= null and then Owner.Is_Native and then
        State.Current.Stack_Window = Owner
      then
         --  luaL_getmetafield leaves every nonnil raw __name, including a
         --  nonstring value that cannot supply the type label. A fallback
         --  registry callback can inspect/mutate those ordinary temporaries.
         if Type_Name.Kind /= Nil_Kind then
            Machine.Push_Native_Value (State, Owner, Type_Name);
         end if;
      end if;
      Detail.Set_Owner (State.Current.Memory);
      Detail.Append (Expected);
      Detail.Append (" expected, got ");
      if Type_Name.Kind = String_Kind then
         declare
            Bytes : constant Byte_String := Type_Name.Reference.Bytes;
            View : String (1 .. Bytes.Size)
              with Import, Address => Bytes.Address;
            Size : Natural := 0;
         begin
            --  Scan a borrowed C prefix before copying into selected-owner
            --  storage. A huge name cannot escape the allocator or budget
            --  through Argument_Type's ordinary Ada String return value.
            for Byte of View loop
               Work (State);
               exit when Byte = ASCII.NUL;
               Size := Size + 1;
            end loop;
            for Index in 1 .. Size loop
               Work (State);
               Detail.Append (View (Index));
            end loop;
         end;
      else
         Detail.Append (Argument_Type (State, Item, Present));
      end if;
      Detail.Query (Publish'Access);
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
