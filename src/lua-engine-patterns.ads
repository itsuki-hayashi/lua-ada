package Lua.Engine.Patterns is
   --  Byte-based Lua patterns. Offsets are zero based and After is exclusive;
   --  only conversion to Lua captures adds the language's one-based origin.
   Maximum_Captures : constant := 32;
   type Capture is record
      First : Natural := 0;
      Length : Integer := -2;
   end record;
   --  Length=-2 is open, -1 is a position capture, otherwise a byte count.
   type Capture_Array is array (1 .. Maximum_Captures) of Capture;
   type Match_Result is record
      Found : Boolean := False;
      First, After : Natural := 0;
      Count : Natural range 0 .. Maximum_Captures := 0;
      Captures : Capture_Array;
   end record;
   function Find
     (State : in out World; Subject, Pattern : String;
      Start : Natural := 0; Allow_Anchor : Boolean := True)
      return Match_Result;
   --  Find the first match at or after Start. A leading ^ anchors at Start.
   --  gmatch passes Allow_Anchor=False, preserving its literal-^ semantics.
   function Capture_Values
     (State : in out World; Subject : String; Item : Match_Result;
      Whole_If_None : Boolean := True) return Values.Vector;
   --  Convert successful captures to owned Lua values. No heap references
   --  live inside Match_Result, so continuations can retain it directly.
end Lua.Engine.Patterns;
