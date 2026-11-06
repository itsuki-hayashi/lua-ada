with Lua.Numbers;
with Lua.Storage;

private package Lua.Number_Parsing is
   function Read
     (Text : String; Memory : not null Lua.Storage.Owner_Access;
      Base : Natural := 0) return Lua.Numbers.Number;
   --  Shared exact byte parser. Source is borrowed synchronously; all growing
   --  rational/rounding scratch uses Memory. Allocation_Error propagates for
   --  the runtime's semantic-memory boundary; malformed text returns Invalid.
end Lua.Number_Parsing;
