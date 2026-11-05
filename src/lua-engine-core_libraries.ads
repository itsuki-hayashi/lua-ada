private package Lua.Engine.Core_Libraries is
   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector;
   --  Execute the non-callback math and raw table library paths.
   --  @param State Owning universe, including allocation/work limits.
   --  @param Name Qualified export, such as math.floor or table.unpack.
   --  @param Arguments Rooted arguments belonging to State.
   --  @return Lua results; Lua errors use the engine's controlled transfer.
   --  The VM handles table-like/metamethod paths and max/min callbacks.
end Lua.Engine.Core_Libraries;
