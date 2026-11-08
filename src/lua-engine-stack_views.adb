with Ada.Containers;
with Lua.Engine.Stacks;
with System;

package body Lua.Engine.Stack_Views is
   use type Ada.Containers.Count_Type;
   use type System.Address;

   function Physical_Owner (Context : not null Context_Access)
                            return Frame_Access is
     (if Context.Foreign_View /= null then Context.Foreign_View
      else Context.Foreign_Activation);

   procedure Prepare_Hook (State : in out World; Window : not null
                           Frame_Access)
   is
      Restore_Packets : Boolean;
      procedure Reserve_Work (Amount : Ada.Containers.Count_Type);
      procedure Reserve_Work (Amount : Ada.Containers.Count_Type) is
      begin
         if State.Policy = Bounded then
            if Amount > Ada.Containers.Count_Type
              (State.Bounds.Instructions - Natural'Min
                 (State.Steps, State.Bounds.Instructions))
            then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            State.Steps := State.Steps + Natural (Amount);
         end if;
      end Reserve_Work;
   begin
      if Window.Is_Native then
         --  Budget both dropping and restoring copied roots before entering
         --  user C code. Restoration is unconditional cleanup after its guard
         --  returns and cannot discover a new quota failure halfway through
         --  releasing ownership. All packets retain their existing capacity.
         Reserve_Work (Window.Native_Arguments.Length);
         Reserve_Work (Window.Native_Captures.Length);
         Restore_Packets := Window.Foreign_Handler = System.Null_Address
           and then not Window.Return_Hook_Done and then
           not Window.Return_Window_Published;
         if Restore_Packets then
            Reserve_Work (Window.Native_Arguments.Length);
            if Window.Native_Self /= null then
               Reserve_Work (Window.Native_Self.Captures.Length);
            end if;
         end if;
      end if;
   end Prepare_Hook;

   procedure Borrow
     (State : in out World; Context : not null Context_Access;
      Window : Frame_Access; Lease : in out Stack_View_Lease;
      Kind : Stack_View_Kind := Callback_View)
   is
      Top : Natural;
      pragma Unreferenced (State);
   begin
      if Lease.Context /= null or else
        (Window /= null and then
         (Window.Context /= Context or else Window.Lifecycle /= Active or
          else Context.Stack_Window /= Window))
      then
         raise Program_Error with "invalid borrowed stack view ownership";
      elsif Kind = Hook_View and then
        (Window = null or else Context.Foreign_Activation = null or else
         Context.Foreign_Activation = Window)
      then
         raise Program_Error with "hook view has no distinct C guard";
      end if;
      Lease :=
        (Context => Context, Window => Window, Kind => Kind,
         Previous_Frame => Context.Foreign_Activation,
         Previous_View => Context.Foreign_View,
         Previous_Base => Context.Foreign_Base,
         Previous_Top => Context.Foreign_Top,
         Stack_Used => Context.Stack_Used, others => <>);
      if Window = null then return; end if;
      Lease.Window_Length := Window.Stack_Window_Length;
      Lease.Live_Top := Window.Stack_Live_Top;
      Lease.GC_Top := Window.Canonical_GC_Top;
      Top :=
        (if Window.Is_Native then Window.Stack_Live_Top else
           Window.Stack_Base +
             (if Kind = Hook_View then Window.Stack_Window_Length
              else Window.Canonical_GC_Top));
      --  Lua's open-result top is an instruction protocol field, not the
      --  live CI extent. Hooks temporarily protect the entire Lua reservation;
      --  ordinary warning/release callbacks expose its current live range.
      Window.Warning_Borrow_Depth := Window.Warning_Borrow_Depth + 1;
      Window.Stack_Live_Top := Top;
      Context.Foreign_Base := Window.Stack_Base;
      Context.Foreign_Top := Top;
      Context.Foreign_View := Window;
      if Kind = Hook_View then
         Window.Hook_View_Depth := Window.Hook_View_Depth + 1;
         --  Keep the real guard as continuation/error owner. Its temporary
         --  scalar window has already retired, so rebasing this metadata
         --  does not alias another reservation or create a public frame.
         Lease.Caller_Base := Lease.Previous_Frame.Stack_Base;
         Lease.Caller_Top := Lease.Previous_Frame.Stack_Live_Top;
         Lease.Previous_Frame.Stack_Base := Window.Stack_Base;
         Lease.Previous_Frame.Stack_Live_Top := Top;
         if Window.Is_Native then
            Lease.Argument_Count :=
              Natural (Window.Native_Arguments.Length);
            Lease.Restore_Arguments :=
              Window.Foreign_Handler = System.Null_Address and then
              not Window.Return_Hook_Done and then
              not Window.Return_Window_Published;
            Lease.Restore_Captures := Lease.Restore_Arguments and then
              Window.Native_Self /= null;
            --  Scalar arguments and real closure cells remain roots. Keeping
            --  copied packets as well would retain values replaced by the
            --  hook during an intervening collection. Capacity stays owned.
            Window.Native_Arguments.Clear;
            Window.Native_Captures.Clear;
         end if;
      else
         Context.Foreign_Activation := Window;
      end if;
   end Borrow;

   procedure Restore
     (State : in out World; Lease : in out Stack_View_Lease;
      Abandon : Boolean := False)
   is
      Context : constant Context_Access := Lease.Context;
      Window : constant Frame_Access := Lease.Window;
      Same_Caller : Boolean;
      Last : Natural;
   begin
      if Context = null then return; end if;
      Same_Caller := Window = null or else
        (if Lease.Previous_View /= null then Lease.Previous_View = Window
         else Lease.Previous_Frame = Window);
      if Window /= null then
         if Window.Warning_Borrow_Depth = 0 then
            raise Program_Error with "borrowed stack view already released";
         end if;
         Window.Warning_Borrow_Depth := Window.Warning_Borrow_Depth - 1;
         if Lease.Kind = Hook_View then
            if Window.Hook_View_Depth = 0 then
               raise Program_Error with "hook stack view already released";
            end if;
            Window.Hook_View_Depth := Window.Hook_View_Depth - 1;
         end if;
         if Context.Stack_Window = Window then
            Window.Canonical_GC_Top := Lease.GC_Top;
            if Lease.Kind = Hook_View then
               --  Only the hook's extra reservation is temporary. Preserve
               --  every original scalar (including edited locals/results)
               --  and every still-owned closing prefix. Real child scopes
               --  after an error are left for their actual unwind driver.
               Last := Natural'Max
                 (Window.Stack_Base + Window.Stack_Window_Length,
                  Window.Stack_Live_Top);
               Stacks.Clear_Range
                 (Context, Natural'Max
                    (Window.Stack_Base + Lease.Window_Length + 1,
                     Context.Closing_Stack_Prefix + 1), Last);
               Window.Stack_Window_Length := Lease.Window_Length;
               Window.Stack_Live_Top := Lease.Live_Top;
               Context.Stack_Used := Natural'Max
                 (Lease.Stack_Used, Context.Closing_Stack_Prefix);
            end if;
         end if;
         if Lease.Kind = Hook_View and then not Abandon and then
           not Window.Logically_Unwound
         then
            if Lease.Restore_Arguments then
               if Window.Native_Arguments.Capacity <
                 Ada.Containers.Count_Type (Lease.Argument_Count)
               then
                  raise Program_Error with "borrowed argument capacity lost";
               end if;
               Window.Native_Arguments.Clear;
               for Index in 1 .. Lease.Argument_Count loop
                  Append_Root
                    (State, Window.Native_Arguments,
                     Stacks.Read (Context, Window.Stack_Base + Index));
               end loop;
            end if;
            if Lease.Restore_Captures then
               if Window.Native_Captures.Capacity <
                 Window.Native_Self.Captures.Length
               then
                  raise Program_Error with "borrowed capture capacity lost";
               end if;
               Window.Native_Captures.Clear;
               for Cell of Window.Native_Self.Captures loop
                  Append_Root
                    (State, Window.Native_Captures, Cell.Cell_Value);
               end loop;
            end if;
         end if;
      end if;
      if Lease.Kind = Hook_View then
         Lease.Previous_Frame.Stack_Base := Lease.Caller_Base;
         Lease.Previous_Frame.Stack_Live_Top := Lease.Caller_Top;
      end if;
      --  A callback on its existing C CI preserves intentional stack side
      --  effects. A borrowed Lua frame instead restores the suspended caller's
      --  separate C view. Nested entries restore their own leases first.
      if Lease.Kind = Hook_View or else not Same_Caller then
         Context.Foreign_Top := Lease.Previous_Top;
      end if;
      Context.Foreign_Base := Lease.Previous_Base;
      Context.Foreign_Activation := Lease.Previous_Frame;
      Context.Foreign_View := Lease.Previous_View;
      Lease := (others => <>);
   end Restore;
end Lua.Engine.Stack_Views;
