with Lua.Storage.Conformance;

package body Lua.Conformance_Memory is
   use Lua.Engine;

   procedure Verify (State : World) is
      Registered_Finalizers, Listed_Finalizers : Natural := 0;
      procedure Check (Condition : Boolean);
      procedure Object (Item : Object_Access);
      procedure Scalar (Item : Value);
      procedure Packet (Items : Values.Vector);
      procedure Code (Item : Prototype_Access);
      procedure Context (Item : not null Context_Access);
      procedure Finalizers (Head : Object_Access; Pending : Boolean);

      procedure Check (Condition : Boolean) is
      begin
         if not Condition then
            raise Program_Error with "conformance heap invariant failed";
         end if;
      end Check;

      procedure Object (Item : Object_Access) is
      begin
         if Item = null then return; end if;
         --  Test pointer membership before dereferencing it. A stale edge
         --  must be diagnosed rather than interpreted as a reclaimed object.
         Check (State.Heap.Contains (Item));
         Check (Item.Registry_Slot in 1 .. Natural (State.Heap.Length));
         Check (State.Heap.Element (Item.Registry_Slot) = Item);
      end Object;

      procedure Scalar (Item : Value) is
      begin
         if Item.Kind in String_Kind | Table_Kind | Closure_Kind |
           Native_Closure_Kind | Thread_Kind | Userdata_Kind
         then
            Check (Item.Reference /= null);
            Object (Item.Reference);
            Check (case Item.Kind is
               when String_Kind => Item.Reference.Kind = String_Object,
               when Table_Kind => Item.Reference.Kind = Table_Object,
               when Closure_Kind => Item.Reference.Kind = Closure,
               when Native_Closure_Kind =>
                  Item.Reference.Kind = Native_Closure,
               when Thread_Kind => Item.Reference.Kind = Thread_Object,
               when Userdata_Kind => Item.Reference.Kind = Userdata_Object,
               when others => False);
         end if;
      end Scalar;

      procedure Packet (Items : Values.Vector) is
      begin
         for Item of Items loop Scalar (Item); end loop;
      end Packet;

      procedure Code (Item : Prototype_Access) is
      begin
         if Item /= null then
            Check (State.Programs.Contains (Item));
         end if;
      end Code;

      procedure Context (Item : not null Context_Access) is
         Initialized : constant Natural :=
           Natural (Item.Foreign_Stack.Length);
         First, Last, Previous_First : Natural := 0;
         procedure Window (Low, High : Natural);
         procedure Window (Low, High : Natural) is
         begin
            Check (High <= Initialized);
            for Index in Natural'Max (1, Low) .. High loop
               declare
                  Cell : constant Object_Access :=
                    Item.Stack_Cells.Element (Index);
               begin
                  if Cell = null then
                     Scalar (Item.Foreign_Stack.Element (Index));
                  else
                     Object (Cell);
                     Check (Cell.Kind = Cell_Object);
                     Scalar (Cell.Cell_Value);
                  end if;
               end;
            end loop;
         end Window;
      begin
         Check (Natural (Item.Stack_Cells.Length) = Initialized);
         Check (Item.Foreign_Base <= Item.Foreign_Top);
         Check (Item.Foreign_Top <= Initialized);
         Packet (Item.Arguments);
         Packet (Item.Boundary_Results);
         Packet (Item.Transfer.Results);
         Scalar (Item.Entry_Function);
         Scalar (Item.Hook);
         Scalar (Item.Failure);
         Window (1, (if Item.Stack.Is_Empty then Item.Foreign_Top
                     else Item.Host_Stack_Top));
         for Activation of Item.Stack loop
            Check (Activation /= null);
            Check (Activation.Context = Item);
            Check (Activation.Lifecycle = Active);
            Code (Activation.Code);
            Object (Activation.Scope);
            Object (Activation.Native_Self);
            Object (Activation.Vararg_Table);
            Scalar (Activation.Callee);
            Scalar (Activation.Message_Handler);
            Scalar (Activation.Warning_Root);
            Packet (Activation.Native_Arguments);
            Packet (Activation.Native_Results);
            Packet (Activation.Native_Captures);
            Packet (Activation.Error_Packet);
            Packet (Activation.Varargs);
            Packet (Activation.Unwind_Results);
            Scalar (Activation.Unwind_Error);
            for Closing of Activation.Closers loop
               Object (Closing.Cell);
               if Closing.Frozen then Scalar (Closing.Frozen_Value); end if;
            end loop;
            for Index in 1 .. Activation.Active_Registers loop
               Packet (Activation.Slots.Element (Index));
            end loop;
            if Activation.Has_Stack_Window then
               First := Natural'Max
                 (1, (if Activation.Hidden_Varargs then Activation.Call_Base
                      else Activation.Stack_Base));
               Last := (if Activation.Is_Native then
                 (if Activation = Item.Foreign_Activation and then
                    Activation.Foreign_Entered and then
                    Activation = Item.Stack.Last_Element
                  then Item.Foreign_Top else Activation.Stack_Live_Top)
                 else Activation.Stack_Base + Activation.Canonical_GC_Top);
               if Activation.Warning_Borrow_Depth /= 0 then
                  Last := Natural'Max (Last, Activation.Stack_Live_Top);
               end if;
               Check (First >= Previous_First);
               Previous_First := First;
               Window (First, Last);
            end if;
         end loop;
      end Context;

      procedure Finalizers (Head : Object_Access; Pending : Boolean) is
         Item : Object_Access := Head;
         Previous : Object_Access;
         Count : Natural := 0;
      begin
         while Item /= null loop
            Check (Count < State.Live_Objects);
            Object (Item);
            Check (Item.Kind in Table_Object | Userdata_Object);
            Check (Item.Finalizer_Registered);
            Previous := Item;
            Item := Item.Finalizer_Next;
            Count := Count + 1;
         end loop;
         if Pending then Check (Previous = State.Finalizer_Tail); end if;
         Listed_Finalizers := Listed_Finalizers + Count;
      end Finalizers;
   begin
      Lua.Storage.Conformance.Verify (State.Memory);
      for Item of State.Heap loop
         if Item /= null then
            if Item.Finalizer_Registered then
               Registered_Finalizers := Registered_Finalizers + 1;
            end if;
            --  During sweep, an unreachable object's edges may already name
            --  reclaimed nodes. Those objects are not live graphs. Deleted
            --  table rows likewise retain historical keys, not owning edges.
            if State.GC.Phase not in Sweeping_Objects | Sweeping_Programs |
              Finishing_Sweep | Finalizers_Ready or else
              Item.Color not in White_0 | White_1 or else
              Item.Color = State.GC.Current_White
            then
               case Item.Kind is
                  when String_Object => null;
                  when Cell_Object => Scalar (Item.Cell_Value);
                  when Userdata_Object =>
                     Object (Item.Userdata_Metatable);
                     Packet (Item.Uservalues);
                  when Table_Object =>
                     Object (Item.Metatable);
                     for Member of Item.Members loop
                        if Member.Item.Kind /= Nil_Kind then
                           Scalar (Member.Key);
                           Scalar (Member.Item);
                        end if;
                     end loop;
                  when Environment =>
                     Object (Item.Parent);
                     for Local of Item.Locals loop
                        Object (Local.Cell);
                     end loop;
                  when Closure =>
                     Code (Item.Code);
                     Object (Item.Capture);
                     for Cell of Item.Upvalues loop Object (Cell); end loop;
                  when Native_Closure =>
                     for Cell of Item.Captures loop Object (Cell); end loop;
                  when Thread_Object =>
                     Check (Item.Context_Index <=
                              Natural (State.Contexts.Length));
                     declare
                        Owner : constant Context_Access :=
                          State.Contexts.Element (Item.Context_Index);
                     begin
                        Check (Owner /= null);
                        Check (Owner.Thread = Item);
                        Context (Owner);
                     end;
               end case;
            end if;
         end if;
      end loop;
      Finalizers (State.Finalizable_Head, Pending => False);
      Finalizers (State.Finalizer_Head, Pending => True);
      Check (Registered_Finalizers = Listed_Finalizers);
      Object (State.Finalizing_Object);
      Scalar (State.Finalizing_Handler);
      Object (State.Main_Thread);
      Object (State.Foreign_Registry);
      Object (State.Loaded_Modules);
      Object (State.Preload_Modules);
      Object (State.String_Metatable);
      for Meta of State.Type_Metatables loop Object (Meta); end loop;
      Packet (State.Operation_Roots);
      Code (State.Entry_Code);
      for Item of State.Operation_Programs loop Code (Item); end loop;
      for Index in 1 .. Natural (State.Programs.Length) loop
         declare
            Item : constant Prototype_Access :=
              State.Programs.Element (Index);
         begin
            if Item /= null then
               Check (Item.Registry_Slot = Index);
               if State.GC.Phase not in Sweeping_Objects | Sweeping_Programs |
                 Finishing_Sweep | Finalizers_Ready or else
                 Item.Color not in White_0 | White_1 or else
                 Item.Color = State.GC.Current_White
               then
                  for Constant_Value of Item.Canonical_Constants loop
                     Scalar (Constant_Value);
                  end loop;
                  for Instruction_Value of Item.Code loop
                     Code (Instruction_Value.Nested);
                  end loop;
               end if;
               if Item.Canonical_Owner /= null then
                  Check (Item.Canonical_Owner.Wrappers.Contains (Item));
               end if;
            end if;
         end;
      end loop;
      declare
         Item : Prototype_Access := State.GC.Code_Gray;
         Count : Natural := 0;
      begin
         while Item /= null loop
            Check (Count < Natural (State.Programs.Length));
            Code (Item);
            Check (Item.Color = Gray);
            Item := Item.Mark_Next;
            Count := Count + 1;
         end loop;
      end;
   end Verify;
end Lua.Conformance_Memory;
