package Lua.Engine.Table_Storage_Probe is
   function Find (Table : Object_Access; Key : Value) return Natural;
   --  Test-only visibility bridge to the real private Tables.Find algorithm.
   --  Caller proves reference membership and finite valid indices first.
end Lua.Engine.Table_Storage_Probe;
