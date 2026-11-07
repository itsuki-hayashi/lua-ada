with Lua.Engine.Call_Names;
with Lua.Engine.Inspection;

separate (Lua.Engine.Foreign)
procedure Inspect_API
  (State : in out World; Context : not null Context_Access;
   Input : Request; Output : in out Response)
is
   use type Call_Names.Name_Kind;
   package Information_Views is new
     System.Address_To_Access_Conversions (Debug_Information);
   Selected : Frame_Access;

   function Find_Frame (Address : System.Address) return Frame_Access;
   function Current_PC (Item : Frame_Access) return Natural;
   function Caller_Of (Item : Frame_Access) return Frame_Access;
   function Cell (Item : Value; Index : C.long_long) return Object_Access;
   function Upvalue_Name (Item : Value; Index : Positive)
                          return System.Address;
   procedure Describe;
   procedure Local;
   procedure Work;

   procedure Work is
   begin
      if State.Policy = Bounded then
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + 1;
      end if;
   end Work;

   function Find_Frame (Address : System.Address) return Frame_Access is
   begin
      --  An opaque lua_Debug token is a borrowed active-frame identity. A
      --  stale token or one from another thread never becomes an unchecked
      --  dereference, even though native C callers must obey that lifetime.
      for Item of Context.Stack loop
         if Item.all'Address = Address then
            return Item;
         end if;
      end loop;
      return null;
   end Find_Frame;

   function Current_PC (Item : Frame_Access) return Natural is
     (if (Context.Hook_Active or else Context.Hook_Suspended) and then
         Item = Context.Hook_Frame then Item.PC - 1
      else Natural'Max (1, Item.PC - 1) - 1);

   function Caller_Of (Item : Frame_Access) return Frame_Access is
   begin
      return Inspection.Caller_Frame (State, Context, Item);
   end Caller_Of;

   function Cell (Item : Value; Index : C.long_long) return Object_Access is
   begin
      if Index < 1 then
         return null;
      elsif Item.Kind = Closure_Kind and then
        Index <= C.long_long (Item.Reference.Upvalues.Length)
      then
         return Item.Reference.Upvalues (Positive (Index));
      elsif Item.Kind = Native_Closure_Kind and then
        Index <= C.long_long (Item.Reference.Captures.Length)
      then
         return Item.Reference.Captures (Positive (Index));
      end if;
      return null;
   end Cell;

   function Upvalue_Name (Item : Value; Index : Positive)
                          return System.Address is
   begin
      if Item.Kind /= Closure_Kind then
         return Debug_Empty_Name'Address;
      end if;
      return Canonical.Upvalue_Bytes (Item.Reference.Code, Index).Address;
   end Upvalue_Name;

   procedure Describe is
      Info : Debug_Information renames
        Information_Views.To_Pointer (Input.Debug_Data).all;
      Options : constant String := Read_Name (Input.Name, "");
      Function_Item : Value;
      Code : Prototype_Access;
      Valid : Boolean := True;
      function Wants (Option : Character) return Boolean;
      procedure Source (Bytes : Byte_String);
      function Origin_Kind (Text : String) return C.int;

      function Wants (Option : Character) return Boolean is
      begin
         for Item of Options loop
            if Item = Option then return True; end if;
         end loop;
         return False;
      end Wants;

      procedure Source (Bytes : Byte_String) is
         Text : constant String (1 .. Bytes.Size)
           with Import, Address => Bytes.Address;
         Short : constant String := Inspection.Short_Source (Text);
      begin
         Info.Source := Bytes.Address;
         Info.Source_Length := C.size_t (Bytes.Size);
         Info.Short_Source := [others => C.nul];
         for Index in Short'Range loop
            Info.Short_Source (C.size_t (Index - Short'First)) :=
              C.To_C (Short (Index));
         end loop;
      end Source;

      function Origin_Kind (Text : String) return C.int is
      begin
         return
           (if Text = "local" then 1 elsif Text = "upvalue" then 2
            elsif Text = "constant" then 3 elsif Text = "global" then 4
            elsif Text = "field" then 5 elsif Text = "method" then 6
            elsif Text = "for iterator" then 7
            elsif Text = "metamethod" then 8 elsif Text = "hook" then 9
            else 0);
      end Origin_Kind;
   begin
      Info := (others => <>);
      if Options'Length > 0 and then Options (Options'First) = '>' then
         Function_Item := At_Index (State, Context, -1);
         if Type_Code (Function_Item) /= 6 then
            raise Foreign_Error with "function expected";
         end if;
         --  Native consumes the function before interpreting selectors. In
         --  particular, invalid options still consume it and honor f/L.
         Pop (Context);
      else
         Selected := Find_Frame (Input.Pointer);
         if Selected = null then return; end if;
         Function_Item := Selected.Callee;
         if Function_Item.Kind = Nil_Kind and then
           Selected.Native_Self /= null
         then
            Function_Item := (Native_Closure_Kind, Selected.Native_Self);
         end if;
      end if;
      if Function_Item.Kind = Closure_Kind then
         Code := Function_Item.Reference.Code;
      end if;
      for Index in Options'Range loop
         if not (Index = Options'First and then Options (Index) = '>') and
           then Options (Index) not in 'S' | 'l' | 'u' | 'n' | 't' | 'r' |
                                      'f' | 'L'
         then
            Valid := False;
         end if;
      end loop;
      if Wants ('S') then
         if Code = null then
            Source
              ((Debug_Native_Source'Address, Debug_Native_Source'Length - 1));
         else
            Source (Canonical.Source_Bytes (Code));
            Info.What := (if Code.Canonical_Node.First_Line = 0 then 1
                          else 2);
            Info.First_Line := C.int (Code.First_Line);
            Info.Last_Line := C.int (Code.Last_Line);
         end if;
      end if;
      if Wants ('l') and then Selected /= null and then
        not Selected.Is_Native
      then
         Info.Current_Line := C.int
           (Canonical.Source_Line (Selected, Current_PC (Selected)));
      end if;
      if Wants ('u') then
         if Code /= null then
            Info.Upvalues := C.int (Function_Item.Reference.Upvalues.Length);
            Info.Parameters := C.int (Code.Canonical_Node.Parameters);
            Info.Vararg := Boolean'Pos (Code.Vararg);
         elsif Function_Item.Kind = Native_Closure_Kind then
            Info.Upvalues := C.int (Function_Item.Reference.Captures.Length);
         end if;
      end if;
      if Wants ('t') and then Selected /= null then
         Info.Tail := Boolean'Pos (Selected.Is_Tail_Call);
         Info.Extra_Arguments := C.int (Selected.Call_Metamethod_Count);
      end if;
      if Wants ('n') and then Selected /= null then
         if Selected.Is_Finalizer_Call and then not Selected.Is_Tail_Call then
            if Context.Hook_Active and then
              Caller_Of (Selected) = Context.Hook_Frame
            then
               Info.Name := Call_Names.Hook_Name.Address;
               Info.Name_Kind :=
                 Call_Names.Name_Kind'Pos (Call_Names.Hook_Call);
            else
               Info.Name := Call_Names.Finalizer_Name.Address;
               Info.Name_Kind :=
                 Call_Names.Name_Kind'Pos (Call_Names.Metamethod_Call);
            end if;
         elsif Length (Selected.Name_Kind) > 0 then
            Info.Name_Kind := Origin_Kind (To_String (Selected.Name_Kind));
            if Length (Selected.Call_Name) > 0 then
               Info.Name := Selected.Call_Name_Bytes.Address;
            end if;
         elsif not Selected.Is_Tail_Call then
            declare
               Caller : constant Frame_Access := Caller_Of (Selected);
               Inferred : Call_Names.Borrowed_Identity;
            begin
               if Caller /= null and then not Caller.Is_Native and then
                 Caller.Code.Canonical_Node /= null
               then
                  Inferred := Call_Names.View_From_Caller (State, Caller);
                  if Inferred.Kind /= Call_Names.Unknown then
                     Info.Name := Inferred.Item.Address;
                     Info.Name_Kind :=
                       Call_Names.Name_Kind'Pos (Inferred.Kind);
                  end if;
               end if;
            end;
         end if;
      end if;
      if Wants ('r') and then Context.Hook_Active and then
        Context.Hook_Transfer and then Selected /= null and then
        Selected = Context.Hook_Frame
      then
         Info.First_Transfer := C.int (Selected.Transfer_First);
         Info.Transfer_Count := C.int (Selected.Transfer_Count);
      end if;
      if Wants ('f') then
         Push (State, Context, Function_Item);
      end if;
      if Wants ('L') then
         if Code = null then
            Push (State, Context, Nil_Value);
         else
            declare
               Lines : constant Value := New_Table (State);
            begin
               --  VARARGPREP is setup, not an active source line. Preserve
               --  the pinned collectvalidlines exclusion for both vararg
               --  forms while using the real model's remaining line data.
               for PC in (if Code.Vararg then 2 else 1) ..
                 Code.Canonical_Node.Lines.Last_Index
               loop
                  Work;
                  Set (State, Lines, (Integer_Kind, Integer_Value
                    (Canonical.Source_Line (Code, PC - 1))),
                    (Boolean_Kind, True));
               end loop;
               Push (State, Context, Lines);
            end;
         end if;
      end if;
      Output.Length := 1;
      Output.Integer_Data := Boolean'Pos (Valid);
   end Describe;

   procedure Local is
      Index : constant C.long_long := C.long_long (Input.Count);
      Name : System.Address := System.Null_Address;
      Item : Value;
      Setting : constant Boolean := Input.Operation = Set_Local;
   begin
      if Input.Pointer = System.Null_Address and then not Setting then
         Item := At_Index (State, Context, -1);
         if Item.Kind = Closure_Kind and then Index > 0 then
            Output.Pointer := Canonical.Local_Bytes
              (Item.Reference.Code, Positive (Index), 0).Address;
         end if;
         return;
      end if;
      Selected := Find_Frame (Input.Pointer);
      if Selected = null or else Index = 0 then return; end if;
      if Setting then
         if Context.Foreign_Top = Context.Foreign_Base then
            raise Foreign_Error with "missing local value";
         end if;
         Item := At_Index (State, Context, -1);
      end if;
      if not Selected.Is_Native then
         if Index < 0 then
            if Index >= -C.long_long (Canonical.Vararg_Length (Selected))
            then
               Name := Debug_Vararg_Name'Address;
               if Setting then
                  Canonical.Write_Vararg
                    (State, Selected, Positive (-Index), Item);
               else
                  Item := Canonical.Read_Vararg
                    (State, Selected, Positive (-Index));
               end if;
            end if;
         elsif Index <= C.long_long
           (Inspection.Visible_Local_Top (Context, Selected))
         then
            Name := Canonical.Local_Bytes
              (Selected.Code, Positive (Index), Current_PC (Selected)).Address;
            if Name = System.Null_Address then Name := Debug_Temporary'Address;
            end if;
            if Setting then
               Canonical.Write_Register
                 (State, Selected, Natural (Index) - 1, Item);
            else
               Item := Canonical.Read_Register
                 (State, Selected, Natural (Index) - 1);
            end if;
         end if;
      elsif Index > 0 and then Index <= C.long_long
        (Inspection.Visible_Local_Top (Context, Selected))
      then
         Name := Debug_C_Temporary'Address;
         if Setting then
            if Index <= C.long_long (Selected.Native_Arguments.Length) then
               Replace_Root
                 (State, Selected.Native_Arguments, Positive (Index), Item);
            end if;
            Stacks.Write
              (State, Context, Selected.Stack_Base + Positive (Index), Item);
         else
            Item := Stacks.Read
              (Context, Selected.Stack_Base + Positive (Index));
         end if;
      end if;
      if Name /= System.Null_Address then
         if Setting then Pop (Context); else Push (State, Context, Item);
         end if;
         Output.Pointer := Name;
      end if;
   end Local;
begin
   case Input.Operation is
      when Get_Debug_Info => Describe;
      when Get_Local | Set_Local => Local;
      when Get_Upvalue | Set_Upvalue | Upvalue_Id =>
         declare
            Item : constant Value := At_Index (State, Context, Input.Index);
            Slot : constant Object_Access :=
              Cell (Item, C.long_long (Input.Count));
         begin
            if Slot /= null then
               if Input.Operation = Upvalue_Id then
                  Output.Pointer := Slot.all'Address;
               else
                  Output.Pointer :=
                    Upvalue_Name (Item, Positive (Input.Count));
                  if Input.Operation = Get_Upvalue then
                     Push (State, Context, Slot.Cell_Value);
                  else
                     if Context.Foreign_Top = Context.Foreign_Base then
                        raise Foreign_Error with "missing upvalue value";
                     end if;
                     Store_Cell (State, Slot, At_Index (State, Context, -1));
                     Pop (Context);
                  end if;
               end if;
            end if;
         end;
      when Join_Upvalues =>
         declare
            Target : constant Value := At_Index (State, Context, Input.Index);
            Source : constant Value :=
              At_Index (State, Context, Input.Error_Index);
            Into : constant Object_Access :=
              Cell (Target, C.long_long (Input.Count));
            From : constant Object_Access := Cell (Source, Input.Integer_Data);
         begin
            if Target.Kind /= Closure_Kind or else
              Source.Kind /= Closure_Kind or else Into = null or else
              From = null
            then
               raise Foreign_Error with "invalid Lua upvalue join";
            end if;
            --  Redirect the actual stable cell edge, never copy its value.
            --  The shared barrier preserves old-to-young and active marking
            --  invariants across collection after the source closure dies.
            Replace_Object_Edge
              (State, Target.Reference, Target.Reference.Upvalues,
               Positive (Input.Count), From);
         end;
      when others => raise Program_Error with "invalid inspection operation";
   end case;
end Inspect_API;
