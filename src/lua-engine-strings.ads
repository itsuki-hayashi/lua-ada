package Lua.Engine.Strings is
   function String_Argument
     (State : in out World; Item : Value; Index : Natural := 0;
      Present : Boolean := True) return String;
   --  Lua string-library arguments accept strings and numbers, preserving
   --  bytes and using the runtime's numeric conversion for the latter.
   --  A positive Index selects auxiliary argument diagnostics for an actual
   --  public call. Zero retains internal value-conversion diagnostics.
   procedure Query_Argument
     (State : in out World; Item : Value;
      Process : not null access procedure (Text : String);
      Index : Natural := 0; Present : Boolean := True);
   --  Borrow a string argument's immutable managed bytes synchronously, or
   --  supply its bounded numeric conversion. The caller must keep Item rooted
   --  while Process allocates; Process must never retain the borrowed view.
   function Integer_Argument
     (State : in out World; Item : Value; Index : Natural := 0;
      Present : Boolean := True) return Integer_Value;
   --  Require an exactly representable integer, including numeric strings.
   function Relative_Position
     (Index : Integer_Value; Length : Natural) return Integer_Value;
   --  Resolve negative indexes without negating the minimum int64 value.
   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector;
   --  Execute non-callback string operations. Pattern iterators and gsub
   --  replacement callbacks are VM continuations over Engine.Patterns.
   procedure Run
     (State : in out World; Name : String; Arguments : Values.Vector;
      Result : in out Values.Vector);
   --  Fill a distinct caller-owned result arena, retaining warmed capacity.
   --  Runtime scalar operations must not allocate a temporary result vector
   --  when their actual activation already owns enough output storage.
end Lua.Engine.Strings;
