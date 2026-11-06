package Lua.Engine.Strings is
   function String_Argument
     (State : in out World; Item : Value) return String;
   --  Lua string-library arguments accept strings and numbers, preserving
   --  bytes and using the runtime's numeric conversion for the latter.
   procedure Query_Argument
     (State : in out World; Item : Value;
      Process : not null access procedure (Text : String));
   --  Borrow a string argument's immutable managed bytes synchronously, or
   --  supply its bounded numeric conversion. The caller must keep Item rooted
   --  while Process allocates; Process must never retain the borrowed view.
   function Integer_Argument
     (State : in out World; Item : Value) return Integer_Value;
   --  Require an exactly representable integer, including numeric strings.
   function Relative_Position
     (Index : Integer_Value; Length : Natural) return Integer_Value;
   --  Resolve negative indexes without negating the minimum int64 value.
   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector;
   --  Execute non-callback string operations. Pattern iterators and gsub
   --  replacement callbacks are VM continuations over Engine.Patterns.
end Lua.Engine.Strings;
