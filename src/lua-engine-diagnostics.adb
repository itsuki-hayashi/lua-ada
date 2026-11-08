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

   function C_Length
     (State : in out World; Bytes : Byte_String) return Natural;
   procedure Append_Bytes
     (State : in out World; Output : in out Owned_Buffer;
      Bytes : Byte_String; Size : Natural);
   procedure Global_Name
     (State : in out World; Target, Modules : Value;
      Output : in out Owned_Buffer);

   function C_Length
     (State : in out World; Bytes : Byte_String) return Natural
   is
      View : String (1 .. Bytes.Size)
        with Import, Address => Bytes.Address;
      Size : Natural := 0;
   begin
      for Byte of View loop
         Work (State);
         exit when Byte = ASCII.NUL;
         Size := Size + 1;
      end loop;
      return Size;
   end C_Length;

   procedure Append_Bytes
     (State : in out World; Output : in out Owned_Buffer;
      Bytes : Byte_String; Size : Natural)
   is
      View : String (1 .. Size) with Import, Address => Bytes.Address;
   begin
      for Byte of View loop
         Work (State);
         Output.Append (Byte);
      end loop;
   end Append_Bytes;

   procedure Global_Name
     (State : in out World; Target, Modules : Value;
      Output : in out Owned_Buffer)
   is
      type Located_Name is record
         First, Second : Value := Nil_Value;
      end record;
      Found : Located_Name;
      First_Size : Natural;
      function Find
        (Table : Object_Access; Depth : Natural) return Located_Name;
      function Find
        (Table : Object_Access; Depth : Natural) return Located_Name
      is
      begin
         if Table = null or else Depth = 0 then return (others => <>); end if;
         --  Borrow at most two matching keys. Speculative traversal never
         --  creates a text snapshot or an additional Lua graph root.
         for Member of Table.Members loop
            Work (State);
            if Member.Item.Kind /= Nil_Kind and then
              Member.Key.Kind = String_Kind
            then
               if Equal (Member.Item, Target) then
                  return (Member.Key, Nil_Value);
               elsif Depth > 1 and then Member.Item.Kind = Table_Kind then
                  declare
                     Suffix : constant Located_Name :=
                       Find (Member.Item.Reference, Depth - 1);
                  begin
                     if Suffix.First.Kind /= Nil_Kind then
                        return (Member.Key, Suffix.First);
                     end if;
                  end;
               end if;
            end if;
         end loop;
         return (others => <>);
      end Find;
   begin
      if Modules.Kind = Table_Kind then
         Found := Find (Modules.Reference, 2);
      end if;
      if Found.First.Kind = Nil_Kind then
         Output.Append ("?");
         return;
      end if;
      First_Size := C_Length (State, Found.First.Reference.Bytes);
      Append_Bytes (State, Output, Found.First.Reference.Bytes, First_Size);
      --  Native concatenation joins counted keys, then consumes a C prefix.
      --  A NUL in the first key already ends that prefix: no suffix need be
      --  scanned or materialized, even when its immutable bytes are huge.
      if First_Size = Found.First.Reference.Bytes.Size and then
        Found.Second.Kind /= Nil_Kind
      then
         Output.Append ('.');
         Append_Bytes
           (State, Output, Found.Second.Reference.Bytes,
            C_Length (State, Found.Second.Reference.Bytes));
      end if;
      if Output.Length >= 3 and then Output.Element (1) = '_' and then
        Output.Element (2) = 'G' and then Output.Element (3) = '.'
      then
         Output.Delete (1, 3);
      end if;
   end Global_Name;

   procedure Append_Location
     (State : in out World; Output : in out Owned_Buffer;
      Owner : Frame_Access);
   procedure Append_Location
     (State : in out World; Output : in out Owned_Buffer;
      Owner : Frame_Access)
   is
      Caller : Frame_Access;
      function Source return String;
      function Source return String is
      begin
         if Caller.Code.Canonical_Node /= null then
            declare
               Bytes : constant Byte_String :=
                 Canonical.Source_Bytes (Caller.Code);
               View : String (1 .. Bytes.Size)
                 with Import, Address => Bytes.Address;
            begin
               return Inspection.Short_Source (View);
            end;
         end if;
         return Inspection.Short_Source (To_String (Caller.Code.Name));
      end Source;
   begin
      if Owner /= null then
         Caller := Inspection.Caller_Frame (State, State.Current, Owner);
      end if;
      if Caller /= null and then not Caller.Is_Native then
         declare
            PC : constant Natural := Natural'Max (1, Caller.PC - 1);
            Line : constant Natural :=
              (if Caller.Code.Canonical_Node /= null then
                  Canonical.Source_Line (Caller, PC - 1)
               else Caller.Code.Code (PC).Location.Line);
         begin
            --  luaL_where uses only the immediate public caller. Preserve
            --  the actual immutable function source and current instruction;
            --  the enclosing host session's chunk name may be unrelated.
            --  Short_Source bounds this prefix before the owned message grows.
            if Line > 0 then
               declare
                  Prefix : constant String := Source & ":" &
                    Ada.Strings.Fixed.Trim
                      (Line'Image, Ada.Strings.Both) & ": ";
               begin
                  for Byte of Prefix loop
                     Work (State);
                     Output.Append (Byte);
                  end loop;
               end;
            end if;
         end;
      end if;
   end Append_Location;

   procedure Raise_Error (State : in out World; Message : String) is
      Text : Owned_Buffer;
      procedure Raise_Message (Bytes : String);
      procedure Raise_Message (Bytes : String) is
      begin
         Fail (State, Bytes);
      end Raise_Message;
   begin
      --  Own all formatting storage on the selected universe. Source lookup
      --  never invokes Lua or retires the caller; Message stays borrowed from
      --  its live native phase until Fail publishes the managed diagnostic.
      Text.Set_Owner (State.Current.Memory);
      Append_Location
        (State, Text, Inspection.Logical_Frame (State, State.Current, 0));
      for Byte of Message loop
         Work (State);
         Text.Append (Byte);
      end loop;
      Text.Query (Raise_Message'Access);
   end Raise_Error;

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
      Position : Natural := Index;
      Extra : Boolean := False;
      Description, Label : Owned_Buffer;
      procedure Put (Text : String);
      procedure Put_Label (Text : String);
      procedure Raise_Error (Text : String);

      procedure Put (Text : String) is
      begin
         for Byte of Text loop
            Work (State);
            Description.Append (Byte);
         end loop;
      end Put;
      procedure Put_Label (Text : String) is
      begin
         Put (Text);
      end Put_Label;
      procedure Raise_Error (Text : String) is
      begin
         Fail (State, Text);
      end Raise_Error;
   begin
      Description.Set_Owner (Context.Memory);
      Label.Set_Owner (Context.Memory);
      if Owner /= null then
         Origin := Inspection.Call_Identity (State, Context, Owner);
      end if;
      Append_Location (State, Description, Owner);
      if Owner = null then
         Put ("bad argument #" & Ada.Strings.Fixed.Trim
           (Index'Image, Ada.Strings.Both) & " (");
      else
         if Origin.Item.Address /= System.Null_Address then
            Append_Bytes
              (State, Label, Origin.Item, C_Length (State, Origin.Item));
         else
            Global_Name (State, Owner.Callee, Modules, Label);
         end if;
         Extra := Index <= Owner.Call_Metamethod_Count;
         if not Extra then
            Position := Index - Owner.Call_Metamethod_Count;
            if Origin.Kind = Call_Names.Method_Call then
               Position := Position - 1;
            end if;
         end if;
         --  Extra __call values keep their actual indices. Colon self is
         --  removed only after them, and its own error has distinct spelling.
         if not Extra and then Position = 0 then
            Put ("calling '");
            Label.Query (Put_Label'Access);
            Put ("' on bad self (");
         else
            Put ("bad " &
              (if Extra then "extra argument #" else "argument #") &
              Ada.Strings.Fixed.Trim (Position'Image, Ada.Strings.Both) &
              " to '");
            Label.Query (Put_Label'Access);
            Put ("' (");
         end if;
      end if;
      Put (Detail);
      Put (")");
      --  Fail still owns the context's diagnostic delivery policy. This
      --  borrowed view removes growing formatter intermediates; migration of
      --  the final context failure-text store is a separate ownership gate.
      Description.Query (Raise_Error'Access);
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
         --  Scan and copy the C prefix through the same owned-name helpers
         --  as inferred labels. The raw string remains in its real C slot.
         Append_Bytes
           (State, Detail, Type_Name.Reference.Bytes,
            C_Length (State, Type_Name.Reference.Bytes));
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
