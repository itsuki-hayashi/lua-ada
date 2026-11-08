with Lua.Storage.Buffers;

package Lua.Engine.Unicode is
   procedure Emit
     (Code : Natural; Text : in out Lua.Storage.Buffers.Buffer);
   --  Append one extended UTF-8 code point through Text's managed owner.
   --  @param Code Valid pinned UTF-8 range 0 .. 16#7FFF_FFFF#.
   Charpattern : constant String :=
     "[" & Character'Val (0) & "-" & Character'Val (16#7F#) &
     Character'Val (16#C2#) & "-" & Character'Val (16#FD#) & "][" &
     Character'Val (16#80#) & "-" & Character'Val (16#BF#) & "]*";
   --  Lua's byte pattern includes extended five/six-byte UTF-8 sequences.

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector;
   --  Implement char, len, codepoint, and offset. The private "step" action
   --  takes source/control/lax and returns the next iterator pair; "codes"
   --  validates its source and returns source/zero for the VM's iterator.
   --  @param State Owning universe and shared native-work budget.
   --  @param Name Library action selected by the native dispatcher.
   --  @param Arguments Rooted arguments owned by the caller activation.
   --  @return Owned result values; ordinary errors use the engine boundary.
end Lua.Engine.Unicode;
