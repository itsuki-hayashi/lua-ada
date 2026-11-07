with Lua.Engine.Unicode;

separate (Lua.Engine.Foreign)
procedure Format_API
  (State : in out World; Context : not null Context_Access;
   Input : Request; Output : in out Response)
is
   use type Memory.Owner_Access;
   Data : Formatting_Access;

   procedure Charge (Amount : C.size_t);
   procedure Charge (Amount : C.size_t) is
   begin
      if State.Policy = Bounded then
         if State.Steps > State.Bounds.Instructions or else
           Amount > C.size_t (State.Bounds.Instructions - State.Steps)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Natural (Amount);
      end if;
   end Charge;

   procedure Append_Bytes;
   procedure Check_Size (Amount : C.size_t);
   procedure Check_Size (Amount : C.size_t) is
   begin
      if Amount > C.size_t (Natural'Last - Data.Bytes.Length) then
         raise Memory.Allocation_Error;
      elsif State.Policy = Bounded and then
        Amount > C.size_t (State.Bounds.String_Bytes - Natural'Min
        (State.Bounds.String_Bytes, Data.Bytes.Length))
      then
         Fail (State, "string byte limit exceeded", Resource => True);
      end if;
   end Check_Size;

   procedure Append (Text : String);
   procedure Append (Text : String) is
   begin
      Check_Size (C.size_t (Text'Length));
      Data.Bytes.Append (Text);
   end Append;

   procedure Append_Bytes is
   begin
      Charge (Input.Length);
      Check_Size (Input.Length);
      if Input.Length > C.size_t (Natural'Last) then
         --  A counted C extent larger than the checked byte representation
         --  is an actual semantic allocation refusal, never a host copy.
         raise Memory.Allocation_Error;
      elsif Input.Length > 0 and then Input.Name = System.Null_Address then
         raise Foreign_Error with "null counted format input";
      end if;
      declare
         Bytes : constant String (1 .. Natural (Input.Length))
           with Import, Address => Input.Name;
      begin
         Append (Bytes);
      end;
   end Append_Bytes;

   procedure Publish (Bytes : String);
   procedure Publish (Bytes : String) is
      Item : constant Value := New_String (State, Bytes);
   begin
      --  The operation epoch retains the new object until its public scalar
      --  slot owns it. The caller sees exactly one result, with no temporary
      --  Lua values, additional native frame, or larger C-stack requirement.
      Push (State, Context, Item);
      Output.Pointer := Item.Reference.C_Bytes;
   end Publish;
begin
   if Input.Operation = Charge_Aux_Work then
      Charge (Input.Length);
      return;
   elsif Input.Operation = Create_Formatter then
      Data := new (Memory.Handle (State.Memory)) Formatting_Data;
      begin
         Data.Owner := Memory.Reference (State.Memory);
         Data.Bytes.Set_Owner (Data.Owner);
      exception
         when others =>
            --  Ownership is not published to C until initialization ends.
            --  Keep that handoff exception-safe if owner setup ever changes.
            Free_Formatting (Data);
            raise;
      end;
      Output.Pointer := Data.all'Address;
      return;
   end if;
   if Input.Operation = Release_Formatter then
      if Input.Pointer /= System.Null_Address then
         Data := Formatting_Handle
           (Formatting_Views.To_Pointer (Input.Pointer));
         if Data.Owner /= Memory.Reference (State.Memory) then
            raise Foreign_Error with "format temporary has wrong owner";
         end if;
         --  This also releases a partially filled buffer after refusal. No
         --  allocator request or Lua callback occurs on this cleanup path.
         Free_Formatting (Data);
      end if;
      if Input.Count = 1 then
         --  Pinned clearbuff returns NULL without adding a public stack
         --  slot. Restore its entry extent and clear the caught failure;
         --  the variadic throwing API deliberately does not take this path.
         --  A null handle means even construction was refused.
         Set_C_Top (State, Context, Natural (Input.Integer_Data));
         Context.Failure := Nil_Value;
         Context.Has_Failure_Value := False;
         Context.Failure_Class := No_Failure;
         Context.Failure_Handled := False;
         Context.Failure_Text := Null_Unbounded_String;
      end if;
      return;
   end if;
   if Input.Pointer = System.Null_Address then
      raise Foreign_Error with "missing format temporary";
   end if;
   Data := Formatting_Handle (Formatting_Views.To_Pointer (Input.Pointer));
   if Data.Owner /= Memory.Reference (State.Memory) then
      raise Foreign_Error with "format temporary belongs to another state";
   end if;
   case Input.Operation is
      when Append_Format_Value =>
         case Input.Count is
            when 0 => Append_Bytes;
            when 1 =>
               Charge (1);
               Append
                 (Image (Data.Owner,
                         Value'(Integer_Kind, Integer_Value
                           (Input.Integer_Data))));
            when 2 =>
               Charge (1);
               Append
                 (Image (Data.Owner,
                         Value'(Real_Kind, Real_Value (Input.Number_Data))));
            when others =>
               raise Foreign_Error with "invalid format scalar";
         end case;
      when Append_Format_UTF8 =>
         Charge (1);
         if Input.Integer_Data not in 0 .. 16#7FFF_FFFF# then
            raise Foreign_Error with "invalid format UTF-8 code point";
         end if;
         Check_Size
           ((if Input.Integer_Data < 16#80# then 1
             elsif Input.Integer_Data < 16#800# then 2
             elsif Input.Integer_Data < 16#1_0000# then 3
             elsif Input.Integer_Data < 16#20_0000# then 4
             elsif Input.Integer_Data < 16#400_0000# then 5 else 6));
         Unicode.Emit (Natural (Input.Integer_Data), Data.Bytes);
      when Finish_Formatter =>
         Data.Bytes.Query (Publish'Access);
      when others =>
         raise Foreign_Error with "invalid format operation";
   end case;
end Format_API;
