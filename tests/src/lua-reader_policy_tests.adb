with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.Reader_Policy_Tests is
   use type Lua.Storage.Byte_Count;

   procedure Check_Abort (Source : String; Bounds : Limits);
   procedure Check_Abort (Source : String; Bounds : Limits) is
      State : World;
   begin
      Initialize (State, Bounds);
      Assert (not Execute (State, Source, "=reader-policy"),
              "the configured reader budget must stop the host execution");
      Assert (State.Current.Failure_Class = Host_Abort,
              "Lua pcall cannot convert a host quota into load results");
      Assert (State.Native_Depth = 0 and then
              State.Current.Non_Yieldable = 0 and then
              State.Current.Foreign_Activation = null and then
              State.Current.Foreign_View = null,
              "the actual C guard releases its charges and borrowed view");
      Assert (Execute (State, "assert(7*6==42)", "=reader-recovery"),
              "the same host recovers with a fresh execution budget");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "aborted reader/parser/guard storage was released");
   exception
      when others => Finalize (State); raise;
   end Check_Abort;

   procedure Source_Work;
   procedure Source_Work is
   begin
      --  The callback itself is short. Acquisition of its actual 3-KiB
      --  source piece exhausts the existing budget above the waiting parser.
      Check_Abort
        ("pcall(function()load(function()return " &
         "string.rep(' ',3000)..'return 1' end)end);" &
         "error('reader work quota was caught')",
         (Instructions => 1_500, others => <>));
   end Source_Work;

   procedure Callback_Work;
   procedure Callback_Work is
   begin
      --  Ordinary Lua work inside the C reader guard shares the outer VM
      --  budget. A typed host stop returns through the parser's C portal.
      Check_Abort
        ("pcall(function()load(function()for i=1,10000 do end " &
         "return nil end)end);error('callback quota was caught')",
         (Instructions => 400, others => <>));
   end Callback_Work;

   procedure Source_Extent;
   procedure Source_Extent is
   begin
      --  A source-size limit belongs to the host, independently of memory
      --  allocation or Lua's protected syntax-error nil/message protocol.
      Check_Abort
        ("pcall(function()load(function()return " &
         "string.rep(' ',512)end)end);error('source quota was caught')",
         (Source_Bytes => 256, others => <>));
   end Source_Extent;

   procedure Managed_Release;
   procedure Managed_Release is
      State : World;
   begin
      --  Repeated successful and failing parses retain no source/model or
      --  actual borrowed C surface after the owning universe is finalized.
      Initialize (State, (others => <>));
      Assert (Execute (State,
        "for i=1,4 do local n=0;local f=assert(load(function()" &
        "n=n+1;if n==1 then return 'return 37' end end));" &
        "assert(f()==37);local marker={};local ok,g,e=pcall(load," &
        "function()error(marker,0)end);assert(ok and g==nil and e==marker)end",
        "=reader-release"), "real protected reader parses must succeed");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "all selected-owned reader storage was released");
   exception
      when others => Finalize (State); raise;
   end Managed_Release;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "reader policy: source work shares host budget",
         Source_Work'Access);
      Test_Support.Add
        (Suite, "reader policy: callback work shares host budget",
         Callback_Work'Access);
      Test_Support.Add
        (Suite, "reader policy: source extent remains host abort",
         Source_Extent'Access);
      Test_Support.Add
        (Suite, "reader policy: selected owned storage releases",
         Managed_Release'Access);
   end Register;
end Lua.Reader_Policy_Tests;
