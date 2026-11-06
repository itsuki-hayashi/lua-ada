with Lua.Engine.Tables;

package body Lua.Engine.Finalizers is
   function As_Value (Item : Object_Access) return Value;
   function As_Value (Item : Object_Access) return Value is
   begin
      if Item = null then
         return Nil_Value;
      elsif Item.Kind = Table_Object then
         return (Table_Kind, Item);
      elsif Item.Kind = Userdata_Object then
         return (Userdata_Kind, Item);
      end if;
      raise Program_Error with "invalid finalizer object kind";
   end As_Value;

   procedure Register (State : in out World; Item : Value) is
      Meta : Object_Access;
   begin
      if State.State_Close_Phase or else
        Item.Kind not in Table_Kind | Userdata_Kind
      then
         return;
      end if;
      Meta := Raw_Metatable (State, Item);
      if Item.Reference.Finalizer_Registered or else
        Tables.Raw_Field (Meta, "__gc").Kind = Nil_Kind
      then
         return;
      end if;
      --  Registration follows the event, not object creation serials. A
      --  metatable can bless an older userdata after a younger one, and Lua
      --  then invokes the older object's finalizer first. No auxiliary list
      --  allocation is allowed while recording this lifetime obligation.
      Item.Reference.Finalizer_Registered := True;
      Item.Reference.Finalizer_Next := State.Finalizable_Head;
      State.Finalizable_Head := Item.Reference;
   end Register;

   procedure Queue_Unreachable
     (State : in out World;
      Is_Unreachable : not null access function
        (Item : Object_Access) return Boolean;
      All_Objects : Boolean := False)
   is
      Item : Object_Access := State.Finalizable_Head;
      Previous : Object_Access;
      Following : Object_Access;
   begin
      while Item /= null loop
         Following := Item.Finalizer_Next;
         if All_Objects or else Is_Unreachable (Item) then
            --  Preserve the remaining registration chain before transferring
            --  this node. Queue links and gray-work links are independent;
            --  the collector immediately remarks every queued object graph.
            if Previous = null then
               State.Finalizable_Head := Following;
            else
               Previous.Finalizer_Next := Following;
            end if;
            Item.Finalizer_Next := null;
            if State.Finalizer_Tail = null then
               State.Finalizer_Head := Item;
            else
               State.Finalizer_Tail.Finalizer_Next := Item;
            end if;
            State.Finalizer_Tail := Item;
         else
            Previous := Item;
         end if;
         Item := Following;
      end loop;
   end Queue_Unreachable;

   function Has_Pending (State : World) return Boolean is
     (State.Finalizer_Head /= null);

   procedure Begin_Next (State : in out World) is
      Item : constant Object_Access := State.Finalizer_Head;
   begin
      if Item = null or else State.Finalizing_Object /= null then
         raise Program_Error with "invalid finalizer transition";
      end if;
      State.Finalizer_Head := Item.Finalizer_Next;
      if State.Finalizer_Head = null then
         State.Finalizer_Tail := null;
      end if;
      Item.Finalizer_Next := null;
      Item.Finalizer_Registered := False;
      State.Finalizing_Object := Item;
      State.Finalizing_Handler := Tables.Raw_Field
        (Raw_Metatable (State, As_Value (Item)), "__gc");
      --  This value may come from a weak metatable. Keep the chosen handler
      --  independently rooted before argument or protection-frame allocation.
      --  A nil handler means enrollment was removed after registration; it
      --  needs no invented fallback destructor or synthesized success call.
   end Begin_Next;

   function Current_Target (State : World) return Value is
     (As_Value (State.Finalizing_Object));
   function Current_Handler (State : World) return Value is
     (State.Finalizing_Handler);

   procedure Finish_Current (State : in out World) is
   begin
      State.Finalizing_Object := null;
      State.Finalizing_Handler := Nil_Value;
      State.Finalizer_Active := False;
   end Finish_Current;

   procedure Abandon_Current (State : in out World) is
      Item : constant Object_Access := State.Finalizing_Object;
   begin
      if Item /= null and then Item.Kind = Userdata_Object and then
        Item.Cleanup_Resource /= null
      then
         Item.Finalization_Aborted := True;
      end if;
      Finish_Current (State);
   end Abandon_Current;

   procedure Trace_Roots
     (State : World;
      Mark : not null access procedure (Item : Object_Access))
   is
      Item : Object_Access := State.Finalizer_Head;
   begin
      while Item /= null loop
         Mark (Item);
         Item := Item.Finalizer_Next;
      end loop;
      Mark (State.Finalizing_Object);
      if State.Finalizing_Handler.Kind in String_Kind | Table_Kind |
        Closure_Kind | Native_Closure_Kind | Thread_Kind | Userdata_Kind
      then
         Mark (State.Finalizing_Handler.Reference);
      end if;
   end Trace_Roots;
end Lua.Engine.Finalizers;
