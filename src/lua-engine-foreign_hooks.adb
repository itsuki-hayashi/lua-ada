with Ada.Unchecked_Conversion;
with Interfaces.C;
with Lua.Engine.Canonical;
with Lua.Prototypes;
with System;

package body Lua.Engine.Foreign_Hooks is
   package C renames Interfaces.C;
   use type C.int;
   use type C.long_long;
   use type C.unsigned;
   use type Lua.Prototypes.Prototype_Access;
   use type System.Address;

   function Function_Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);

   function Public_Frame (Item : Frame_Access) return Boolean;
   function Public_Frame (Item : Frame_Access) return Boolean is
     (not Item.Is_Native or else
      (Length (Item.Native_Name) > 0 and then
       Element (Item.Native_Name, 1) /= '@'));

   procedure Handle
     (State : in out World; Context : not null Context_Access;
      Input : Foreign.Request; Output : in out Foreign.Response)
   is
      pragma Unreferenced (State);
      Selected : Frame_Access;
   begin
      case Input.Operation is
         when Foreign.Set_Hook =>
            --  C Lua stores the low byte of the mask. Keep its signed base
            --  count for reflection, but enable count events only for a
            --  positive interval. Installing a C hook allocates no closure:
            --  the scalar callback identifies the shared C trampoline and
            --  the owning context retains the actual lua_Hook separately.
            Context.Foreign_Hook := Input.Pointer;
            Context.Foreign_Hook_Mask :=
              C.int (C.unsigned'Mod (Input.Index) mod 256);
            if Context.Foreign_Hook = System.Null_Address or else
              Context.Foreign_Hook_Mask = 0
            then
               Context.Foreign_Hook := System.Null_Address;
               Context.Foreign_Hook_Mask := 0;
               Context.Hook := Nil_Value;
            else
               Context.Hook :=
                 (Foreign_Function_Kind,
                  Function_Address (Input.Function_Data));
            end if;
            Context.Hook_Mask := Null_Unbounded_String;
            Context.Hook_Reported_Count := Integer_Value (Input.Count);
            Context.Hook_Count :=
              (if Input.Count > 0 and then
                 (Context.Foreign_Hook_Mask / 8) mod 2 /= 0
               then Natural (Input.Count) else 0);
            Context.Hook_Remaining := Context.Hook_Count;
         when Foreign.Get_Hook =>
            Output.Pointer := Context.Foreign_Hook;
         when Foreign.Get_Hook_Mask =>
            Output.Integer_Data :=
              C.long_long (Context.Foreign_Hook_Mask);
         when Foreign.Get_Hook_Count =>
            Output.Integer_Data :=
              C.long_long (Context.Hook_Reported_Count);
         when Foreign.Get_Debug_Frame =>
            if Input.Index = -1 and then Context.Hook_Active then
               --  The trampoline's synthetic callback is transport. Its
               --  lua_Debug identifies the actual interrupted Lua/C frame.
               Selected := Context.Hook_Frame;
            elsif Input.Index >= 0 then
               declare
                  Remaining : C.int := Input.Index;
               begin
                  for Item of reverse Context.Stack loop
                     if Public_Frame (Item) and then not
                       (Context.Hook_Active and then
                        Context.Foreign_Hook /= System.Null_Address and then
                        Item.Is_Native and then Item.Callee = Context.Hook)
                     then
                        --  A C hook borrows its interrupted frame. The
                        --  foreign trampoline is scheduler transport and
                        --  cannot become public stack level zero.
                        if Remaining = 0 then
                           Selected := Item;
                           exit;
                        end if;
                        Remaining := Remaining - 1;
                     end if;
                  end loop;
               end;
            end if;
            if Selected /= null then
               Output.Pointer := Selected.all'Address;
               Output.Integer_Data := 1;
            end if;
         when Foreign.Get_Debug_Line =>
            --  Never dereference a caller-supplied frame token directly. A
            --  stale lua_Debug, another coroutine's token or an arbitrary C
            --  address cannot grant access to an inactive Ada activation.
            for Item of Context.Stack loop
               if Item.all'Address = Input.Pointer then
                  Selected := Item;
                  exit;
               end if;
            end loop;
            if Selected /= null then
               Output.Length := 1;
               Output.Integer_Data := -1;
               if not Selected.Is_Native then
                  declare
                     PC : constant Natural :=
                        (if (Context.Hook_Active or else
                             Context.Hook_Suspended) and then
                          Selected = Context.Hook_Frame
                        then Selected.PC - 1
                        else Natural'Max (1, Selected.PC - 1) - 1);
                     Line : constant Natural :=
                       (if Selected.Code.Canonical_Node /= null then
                           Canonical.Source_Line (Selected, PC)
                        elsif PC < Selected.Code.Code.Last_Index then
                           Selected.Code.Code (PC + 1).Location.Line
                        else 0);
                  begin
                     if Line > 0 then
                        Output.Integer_Data := C.long_long (Line);
                     end if;
                  end;
               end if;
            end if;
         when others =>
            raise Program_Error with "invalid foreign hook operation";
      end case;
   end Handle;
end Lua.Engine.Foreign_Hooks;
