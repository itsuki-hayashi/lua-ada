with System;
with Lua.Engine.Tables;

package body Lua.Engine.Hooks is
   use type System.Address;

   function Enabled (Context : not null Context_Access) return Boolean is
     (Context.Lua_Hook_Installed or else
      Context.Foreign_Hook /= System.Null_Address);

   function Callback
     (State : World; Context : not null Context_Access) return Value
   is
      Table : Value;
   begin
      if Context.Foreign_Hook /= System.Null_Address then
         return Context.Hook;
      end if;
      --  Pinned ldblib.c:hookf/gethook read the actual mapping on every use.
      --  A raw registry mutation can replace or remove a callback without
      --  changing the installed mask/count. Never retain a second strong
      --  callback copy in the context: it would defeat those mutations and
      --  keep a removed closure alive through collection.
      Table := Tables.Raw_Field (State.Foreign_Registry, "_HOOKKEY");
      return Get (Table, (Thread_Kind, Context.Thread));
   end Callback;

   procedure Store_Callback
     (State : in out World; Context : not null Context_Access; Item : Value)
   is
      Registry : constant Value := (Table_Kind, State.Foreign_Registry);
      Table : Value := Tables.Raw_Field (State.Foreign_Registry, "_HOOKKEY");
   begin
      if Table.Kind /= Table_Kind then
         --  This table is the callback storage itself, not a reflection-only
         --  placeholder. Its self-metatable carries __mode='k', exactly as
         --  db_sethook initializes it. Existing collector ephemeron tracing
         --  then follows a hook only while its thread key remains reachable.
         Table := New_Table (State);
         Pin (State, Table);
         Set (State, Table, New_String (State, "__mode"),
              New_String (State, "k"));
         Set_Metatable (State, Table, Table.Reference);
         Set (State, Registry, New_String (State, "_HOOKKEY"), Table);
      end if;
      Set (State, Table, (Thread_Kind, Context.Thread), Item);
   end Store_Callback;
end Lua.Engine.Hooks;
