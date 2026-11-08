separate (Lua.Engine.Foreign)
procedure Reader_API
  (State : in out World; Context : not null Context_Access;
   Input : Request; Output : in out Response)
is
   Phase : constant Frame_Access := Context.Foreign_Activation;
   Window : constant Frame_Access := Stack_Views.Physical_Owner (Context);

   procedure Invalid_Result;
   procedure Invalid_Result is
      Owner : constant Frame_Access :=
        Inspection.Logical_Frame (State, Context, 0);
      Caller : Frame_Access;

      function Source return String;
      function Source return String is
      begin
         if Caller.Code.Canonical_Node /= null then
            declare
               Bytes : constant Byte_String :=
                 Canonical.Source_Bytes (Caller.Code);
               View : constant String (1 .. Bytes.Size)
                 with Import, Address => Bytes.Address;
            begin
               return Inspection.Short_Source (View);
            end;
         end if;
         return Inspection.Short_Source (To_String (Caller.Code.Name));
      end Source;
   begin
      --  generic_reader uses luaL_error after its child has returned. Only
      --  the immediate public Lua caller of this actual load/C activation
      --  contributes luaL_where; a direct saved builtin keeps its C caller.
      if Owner /= null then
         Caller := Inspection.Caller_Frame (State, Context, Owner);
      end if;
      if Caller /= null and then not Caller.Is_Native then
         declare
            PC : constant Positive := Positive'Max (1, Caller.PC - 1);
            Line : constant Natural :=
              (if Caller.Code.Canonical_Node /= null then
                  Canonical.Source_Line (Caller, PC - 1)
               else Caller.Code.Code (PC).Location.Line);
         begin
            if Line > 0 then
               Fail (State, Source & ":" & Ada.Strings.Fixed.Trim
                 (Line'Image, Ada.Strings.Both) &
                 ": reader function must return a string");
            end if;
         end;
      end if;
      Fail (State, "reader function must return a string");
   end Invalid_Result;
begin
   if Phase = null or else not Phase.Load_Reader_Portal or else
     not Phase.Foreign_Entered or else Window = null
   then
      raise Foreign_Error with "Lua reader portal has no active owner";
   end if;
   case Input.Operation is
      when Prepare_Lua_Reader =>
         if Input.Count = 0 then
            --  These selected-owned bytes belong to this activation until
            --  its guarded parser/reader has acknowledged every transfer.
            --  Reader mutation of argument slots cannot invalidate them.
            Output.Pointer := Phase.Native_Buffer.C_Address;
            Output.Length := C.size_t (Phase.Load_Reader_Mode_Offset);
         else
            --  The ABI trampoline needs a function/result slot on every
            --  refill. Reserve before entering user code, through the actual
            --  physical C owner (including a direct builtin's borrowed CI).
            VM.Resize_Stack_Window
              (State, Window, Natural'Max
                 (Window.Stack_Window_Length,
                  Context.Foreign_Top - Context.Foreign_Base + 2));
         end if;
      when Observe_Lua_Reader_Piece =>
         declare
            Item : Value := At_Index (State, Context, -1);
         begin
            if Item.Kind in Integer_Kind | Real_Kind then
               Item := New_String (State, Image (Context.Memory, Item));
               Stacks.Write (State, Context, Context.Foreign_Top, Item);
            end if;
            if Item.Kind = Nil_Kind then
               null;
            elsif Item.Kind = String_Kind then
               Output.Pointer := Item.Reference.C_Bytes;
               Output.Length := C.size_t (Item.Reference.Bytes.Size);
            else
               Invalid_Result;
            end if;
         end;
      when Finish_Lua_Reader =>
         if Input.Index not in 0 | 2 | 3 | 4 | 5 then
            raise Foreign_Error with "invalid Lua reader parser status";
         elsif Input.Index = 0 then
            declare
               Callee : constant Value := At_Index (State, Context, -1);
            begin
               if Callee.Kind /= Closure_Kind then
                  raise Program_Error with "reader returned no Lua closure";
               end if;
               if Phase.Load_Reader_Arguments >= 4 and then
                 not Callee.Reference.Upvalues.Is_Empty
               then
                  --  Lua load_aux observes the current actual argument-four
                  --  cell after all reader callbacks. Nil differs from an
                  --  omitted environment, and binary functions without a
                  --  first upvalue keep their unchanged capture graph.
                  Store_Cell
                    (State, Callee.Reference.Upvalues.First_Element,
                     At_Index (State, Context, 4));
               end if;
            end;
            Output.Integer_Data := 1;
         else
            declare
               Message : constant Value := At_Index (State, Context, -1);
               Position : constant Natural := Context.Foreign_Top;
            begin
               --  The parser has released its source/partial graph. Publish
               --  nil and the exact protected error object on real slots;
               --  no string coercion or extra owning packet is introduced.
               Push (State, Context, Nil_Value);
               Stacks.Write (State, Context, Position, Nil_Value);
               Stacks.Write (State, Context, Position + 1, Message);
            end;
            Output.Integer_Data := 2;
         end if;
      when others =>
         raise Program_Error with "invalid Lua reader portal operation";
   end case;
end Reader_API;
