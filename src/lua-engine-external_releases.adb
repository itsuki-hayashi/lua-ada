with Lua.Storage;
with Lua.Engine.Stack_Views;

package body Lua.Engine.External_Releases is
   use type Lua.Storage.Allocation_Function;
   use type Interfaces.C.unsigned_long_long;
   use type System.Address;

   procedure Enqueue
     (State : in out World; Item : not null Object_Access) is
   begin
      if Item.Release_Queued then return; end if;
      Item.Release_Queued := True;
      Item.Release_Next := null;
      if State.External_Release_Tail = null then
         State.External_Release_Head := Item;
      else
         State.External_Release_Tail.Release_Next := Item;
      end if;
      State.External_Release_Tail := Item;
   end Enqueue;

   function Pending (State : World) return Boolean is
     (State.External_Release_Head /= null);

   procedure Prepare_Close (State : in out World) is
   begin
      --  External callbacks may use globals and invoke Lua. Do this pass
      --  before any context, table, module handle or code owner is destroyed.
      --  Queued registered headers are explicit roots; nested callback GC
      --  cannot sweep another close packet while its payload is still owned.
      for Item of State.Heap loop
         if Item /= null and then Item.Kind = String_Object and then
           Item.String_Allocator /= null and then not Item.Release_Queued
         then
            Enqueue (State, Item);
         end if;
      end loop;
   end Prepare_Close;

   function Begin_Callback (State : in out World) return Object_Access is
      Item : constant Object_Access := State.External_Release_Head;
      Context : constant Context_Access := State.Current;
   begin
      if Item = null then
         raise Program_Error with "no external release pending";
      end if;
      State.External_Release_Head := Item.Release_Next;
      if State.External_Release_Head = null then
         State.External_Release_Tail := null;
      end if;
      Item.Release_Next := null;
      Item.Release_Active_Previous := State.External_Release_Active;
      State.External_Release_Active := Item;
      --  Like warning delivery, freeing an external payload adds no debug
      --  frame. Borrow the real interrupted window for allocator API reentry.
      Stack_Views.Borrow
        (State, Context, Context.Stack_Window, Item.Release_View);
      return Item;
   end Begin_Callback;

   procedure Complete
     (State : in out World; Token : Callback_Identity) is
      Item : Object_Access := State.External_Release_Active;
   begin
      if Item = null or else Token.Activation /= Item.all'Address or else
        Token.Serial /= Interfaces.C.unsigned_long_long (Item.Serial)
      then
         raise Program_Error with "stale external release acknowledgment";
      end if;
      Stack_Views.Restore (State, Item.Release_View);
      State.External_Release_Active := Item.Release_Active_Previous;
      Item.Release_Active_Previous := null;
      Item.String_Allocator := null;
      Item.Release_Queued := False;
      if Item.Registry_Slot = 0 then
         Release_Detached_String (State, Item);
      end if;
   end Complete;
end Lua.Engine.External_Releases;
