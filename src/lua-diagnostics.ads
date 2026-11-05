with Ada.Strings.Unbounded;

package Lua.Diagnostics is
   type Diagnostic is record
      Source : Ada.Strings.Unbounded.Unbounded_String;
      Line : Positive := 1;
      Column : Positive := 1;
      Message : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Source labels and byte positions are independent of message wording.
   --  This value owns its strings; it never borrows frontend/runtime storage.
end Lua.Diagnostics;
