with Lua.Numbers;
with Lua.Storage;

private package Lua.Number_Parsing is
   function Read
     (Text : String; Memory : not null Lua.Storage.Owner_Access;
      Base : Natural := 0; Decimal_Point : Character := '.')
      return Lua.Numbers.Number;
   --  Shared exact byte parser. Source is borrowed synchronously; all growing
   --  rational/rounding scratch uses Memory. Allocation_Error propagates for
   --  the runtime's semantic-memory boundary; malformed text returns Invalid.
   --
   --  Decimal_Point is an optional alternate radix point, normally the native
   --  localeconv() byte supplied by the runtime. It is honoured only for
   --  base-zero floating mantissas. Callers supply the actual native locale
   --  separator, as luaO_str2num does. An ordinary dot remains accepted, with
   --  the pinned 200-byte alternate-dot retry limit under a non-dot locale.
   --  The default '.' retains the locale-independent public grammar. Explicit
   --  bases never accept any fraction, so Decimal_Point is ignored there.
   --  Exactly one radix point may appear; mixed or repeated points are
   --  Invalid. The chosen point is the only one carried into the exact
   --  rational rounding, so comma and dot inputs round identically.
end Lua.Number_Parsing;
