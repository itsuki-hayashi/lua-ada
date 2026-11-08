with Lua.Engine.Tables;

package body Lua.Engine.Table_Storage_Probe is
   --  Conformance_Adapter is a child of Lua, not Engine; it cannot directly
   --  name Engine's private Tables child. Keep this sole delegation in the
   --  test source directory instead of exporting a production debug API or
   --  duplicating its key hashing/lookup implementation in the inspector.
   function Find (Table : Object_Access; Key : Value) return Natural is
     (Tables.Find (Table, Key));
end Lua.Engine.Table_Storage_Probe;
