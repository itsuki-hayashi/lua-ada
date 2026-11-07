with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Lua.Condition_Root_Tests is
   procedure Succeeds (Source : String);
   procedure While_Guard;
   procedure If_Guard;
   procedure Repeat_Guard;
   procedure Repeat_Closing;
   procedure Short_Circuit_Result;

   procedure Succeeds (Source : String) is
      Self : Session;
      Result : constant Execution_Result := Execute (Self, Source);
   begin
      Assert (Result.Status = Succeeded,
              "condition roots: " & To_String (Result.Error.Message));
   end Succeeds;

   procedure While_Guard is
   begin
      --  Stop automatic GC so the weak value survives setup. The RHS then
      --  explicitly collects before the final concatenation overwrites the
      --  old condition register. A dead guard must not keep the loop alive.
      Succeeds
        ("collectgarbage('stop'); " &
         "local w=setmetatable({{}},{__mode='v'}); local n=0; " &
         "local function rhs() collectgarbage('collect'); n=n+1; " &
         "return '' end; while w[1] do local unused=''..rhs(); " &
         "if n==3 then break end end; collectgarbage('restart'); " &
         "assert(n==1 and w[1]==nil)");
   end While_Guard;

   procedure If_Guard is
   begin
      --  The same dead temporary must disappear before an if body's RHS.
      --  An explicit collection makes this independent of host allocation
      --  layout and of the automatic collector's current debt or phase.
      Succeeds
        ("collectgarbage('stop'); " &
         "local w=setmetatable({{}},{__mode='v'}); local n=0; " &
         "local function rhs() collectgarbage('collect'); n=n+1; " &
         "return '' end; if w[1] then local unused=''..rhs() end; " &
         "collectgarbage('restart'); assert(n==1 and w[1]==nil)");
   end If_Guard;

   procedure Repeat_Guard is
   begin
      --  With no closing body local, scope exit does not happen to clear the
      --  until temporary. A later nested RHS must not keep that value alive.
      Succeeds
        ("collectgarbage('stop'); " &
         "local w=setmetatable({{}},{__mode='v'}); local n=0; " &
         "local function rhs() collectgarbage('collect'); n=n+1; " &
         "return '' end; repeat until w[1]; local unused=''..rhs(); " &
         "collectgarbage('restart'); assert(n==1 and w[1]==nil)");
   end Repeat_Guard;

   procedure Repeat_Closing is
   begin
      --  Only the consumed temporary is cleared. A real repeat-body closing
      --  local remains live and its closer can collect before scope exit.
      Succeeds
        ("collectgarbage('stop'); " &
         "local w=setmetatable({{}},{__mode='v'}); local n=0; repeat " &
         "local c <close> = setmetatable({}, {__close=function(self) " &
         "assert(type(self)=='table'); collectgarbage('collect'); " &
         "n=n+1 end}); until w[1]; collectgarbage('restart'); assert(n==1)");
   end Repeat_Closing;

   procedure Short_Circuit_Result is
   begin
      --  Expression TEST operations still return their operand. Keep the
      --  actual table through or/and and collect with each result as root.
      Succeeds
        ("collectgarbage('stop'); " &
         "local w=setmetatable({{}},{__mode='v'}); " &
         "local held=w[1] or error('operand lost'); " &
         "collectgarbage('collect'); assert(w[1]==held); " &
         "local other=true and held; held=nil; " &
         "collectgarbage('collect'); assert(w[1]==other); " &
         "collectgarbage('restart')");
   end Short_Circuit_Result;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "condition roots: consumed while guard",
                        While_Guard'Access);
      Test_Support.Add (Suite, "condition roots: consumed if guard",
                        If_Guard'Access);
      Test_Support.Add (Suite, "condition roots: consumed repeat guard",
                        Repeat_Guard'Access);
      Test_Support.Add (Suite, "condition roots: repeat closing local",
                        Repeat_Closing'Access);
      Test_Support.Add (Suite, "condition roots: short circuit result",
                        Short_Circuit_Result'Access);
   end Register;
end Lua.Condition_Root_Tests;
