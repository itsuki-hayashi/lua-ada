with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Registry_Environment_Tests is
   procedure Check (First, Second : String);
   procedure Check (First, Second : String) is
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute (First, "registry-first");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := Universe.Execute (Second, "registry-second");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Subsequent_Chunk;
   procedure Subsequent_Chunk is
   begin
      --  Replace the global registry entry while an old chunk is active.
      --  Execute a new chunk using the replacement without changing old cells.
      --  New assignments target the replacement. The old closure keeps
      --  its original _ENV cell.
      Check
        ("local r=debug.getregistry();local old=_G;local n={asser" &
         "t=assert,debug=debug};n.old=function()return _G end;r[2" &
         "]=n;assert(_G==old)",
         "assert(_G==nil and old()~=debug.getregistry()[2]);answe" &
         "r=42;assert(answer==42)");
   end Subsequent_Chunk;

   procedure Default_Load_Environment;
   procedure Default_Load_Environment is
   begin
      --  Replace the registry environment within an already running old chunk.
      --  Load with omitted and explicit nil environments, then restore
      --  the registry entry.
      --  Omitted reads the new table; explicit nil remains a nil capture.
      Check
        ("local old=_G;debug.getregistry()[2]={answer=42};local f" &
         "=assert(load('return answer'));assert(f()==42);local g=" &
         "assert(load('return answer','named','t',nil));assert(no" &
         "t pcall(g));debug.getregistry()[2]=old",
         "assert(_G==debug.getregistry()[2])");
   end Default_Load_Environment;

   procedure Replaced_Global_Collection;
   procedure Replaced_Global_Collection is
   begin
      --  Keep a weak observation of the original global table inside
      --  its replacement.
      --  End the old chunk and collect from the new environment.
      --  The registry is the owner; a stale bootstrap cache cannot retain _G.
      Check
        ("package.loaded._G=nil;local n={assert=assert,collectgar" &
         "bage=collectgarbage,weak=setmetatable({_G},{__mode='v'}" &
         ")};debug.getregistry()[2]=n",
         "collectgarbage();assert(weak[1]==nil)");
   end Replaced_Global_Collection;

   procedure Argument_Table_Target;
   procedure Argument_Table_Target is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Replace globals before the host creates a CLI-shaped arg table.
      --  Set_Arguments must publish into the current registry environment,
      --  without mutating or dereferencing its abandoned bootstrap cache.
      Result := Universe.Execute
        ("debug.getregistry()[2]={assert=assert}");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := Universe.Set_Arguments
        ([0 => To_Unbounded_String ("script.lua"),
          1 => To_Unbounded_String ("first")]);
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := Universe.Execute
        ("assert(arg[0]=='script.lua' and arg[1]=='first')");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Argument_Table_Target;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "registry: subsequent chunk follows registry",
         Subsequent_Chunk'Access);
      Test_Support.Add
        (Suite, "registry: load default follows registry",
         Default_Load_Environment'Access);
      Test_Support.Add
        (Suite, "registry: replaced globals are not immortal",
         Replaced_Global_Collection'Access);
      Test_Support.Add
        (Suite, "registry: argument table target",
         Argument_Table_Target'Access);
   end Register;
end Registry_Environment_Tests;
