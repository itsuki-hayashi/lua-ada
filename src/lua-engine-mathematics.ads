package Lua.Engine.Mathematics is
   procedure Reset (State : in out World);
   --  Install a fresh per-universe xoshiro256** seed. No process-wide mutable
   --  generator or host libc random state is used. This is not cryptographic.
   --  @param State Owning universe whose generator must be initialized.

   function New_Generator (State : in out World) return Value;
   --  Create one fully initialized, allocator-owned RNG userdata. A module's
   --  random and randomseed closures retain this same traced value; another
   --  module receives an independent generator, even in the same universe.
   --  @return Stable userdata payload containing the four actual RNG words.
   --  @exception Lua.Storage.Allocation_Error Allocation or root refusal.

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector;
      Generator : Value := Nil_Value)
      return Values.Vector;
   --  Execute the remaining non-callback mathematical exports and RNG.
   --  @param State Owner of generator state and execution budgets.
   --  @param Name Qualified export, including math.random or math.atan2.
   --  @param Arguments Rooted inputs; numeric strings use Lua conversion.
   --  @param Generator Retained module RNG userdata for random/seed; nil
   --  selects the private per-universe inspection/test generator.
   --  @return Exact Lua result arity; language failures use Fail's transfer.
   --  Registration controls whether compatibility-only exports are visible.
end Lua.Engine.Mathematics;
