package Lua.Engine.Mathematics is
   procedure Reset (State : in out World);
   --  Install a fresh per-universe xoshiro256** seed. No process-wide mutable
   --  generator or host libc random state is used. This is not cryptographic.
   --  @param State Owning universe whose generator must be initialized.

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector;
   --  Execute the remaining non-callback mathematical exports and RNG.
   --  @param State Owner of generator state and execution budgets.
   --  @param Name Qualified export, including math.random or math.atan2.
   --  @param Arguments Rooted inputs; numeric strings use Lua conversion.
   --  @return Exact Lua result arity; language failures use Fail's transfer.
   --  Registration controls whether compatibility-only exports are visible.
end Lua.Engine.Mathematics;
