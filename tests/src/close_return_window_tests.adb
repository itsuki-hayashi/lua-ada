with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Close_Return_Window_Tests is
   Preamble : constant String :=
     "local function replaceCaller(old,new)" &
     ASCII.LF &
     "  local count,slot=0,1" &
     ASCII.LF &
     "  while true do" &
     ASCII.LF &
     "    local name,value=debug.getlocal(3,slot)" &
     ASCII.LF &
     "    if name==nil then break end" &
     ASCII.LF &
     "    if value==old then assert(debug.setlocal(3,slot," &
     "new));count=count+1 end" &
     ASCII.LF &
     "    slot=slot+1" &
     ASCII.LF &
     "  end" &
     ASCII.LF &
     "  assert(count>0)" &
     ASCII.LF &
     "end" &
     ASCII.LF &
     ASCII.LF;
   --  Public debug access follows actual cells, without guessed temporary
   --  counts or private compiler layout. Each case owns a separate session.

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Preamble & Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Scalar_Result;
   procedure Scalar_Result is
   begin
      --  Deliver the actual scalar changed by the completed closer.
      Check
        ("do" &
         ASCII.LF &
         "  local f=function()" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()replaceCaller(11,37)end})" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  assert(f()==37)" &
         ASCII.LF &
         "end");
   end Scalar_Result;

   procedure Tuple_With_Nils;
   procedure Tuple_With_Nils is
   begin
      --  Preserve the return count and nil positions while editing values.
      Check
        ("do" &
         ASCII.LF &
         "  local f=function()" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()" &
         ASCII.LF &
         "      replaceCaller(11,37);replaceCaller(23,42)" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    return 11,nil,23,nil" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local r=table.pack(f())" &
         ASCII.LF &
         "  assert(r.n==4 and r[1]==37 and r[2]==nil and r[3]=" &
         "=42 and r[4]==nil)" &
         ASCII.LF &
         "end");
   end Tuple_With_Nils;

   procedure Weak_Result_Reclamation;
   procedure Weak_Result_Reclamation is
   begin
      --  Remove copied result roots before a closer collects a replaced
      --  value.
      Check
        ("do" &
         ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'})" &
         ASCII.LF &
         "  local function factory()local value={};weak[1]=val" &
         "ue;return value end" &
         ASCII.LF &
         "  local f=function()" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()" &
         ASCII.LF &
         "      replaceCaller(weak[1],nil);collectgarbage('col" &
         "lect')" &
         ASCII.LF &
         "      assert(weak[1]==nil)" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    return(factory())" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  assert(f()==nil)" &
         ASCII.LF &
         "end");
   end Weak_Result_Reclamation;

   procedure Subsequent_Return_Hook;
   procedure Subsequent_Return_Hook is
   begin
      --  A later hook must observe the closer edit and may replace it
      --  again.
      Check
        ("do" &
         ASCII.LF &
         "  local f" &
         ASCII.LF &
         "  f=function()" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()replaceCaller(11,37)end})" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local hits=0" &
         ASCII.LF &
         "  debug.sethook(function(e)" &
         ASCII.LF &
         "    if e=='return' then local i=debug.getinfo(2,'fr'" &
         ");if i.func==f then" &
         ASCII.LF &
         "      hits=hits+1;local name,value=debug.getlocal(2," &
         "i.ftransfer)" &
         ASCII.LF &
         "      assert(name and value==37);assert(debug.setloc" &
         "al(2,i.ftransfer,42))" &
         ASCII.LF &
         "    end end" &
         ASCII.LF &
         "  end,'r')" &
         ASCII.LF &
         "  local result=f();debug.sethook()" &
         ASCII.LF &
         "  assert(result==42 and hits==1)" &
         ASCII.LF &
         "end");
   end Subsequent_Return_Hook;

   procedure Close_Error_Replaces_Return;
   procedure Close_Error_Replaces_Return is
   begin
      --  A close error abandons outgoing results and retains its own
      --  identity.
      Check
        ("do" &
         ASCII.LF &
         "  local f=function()" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()" &
         ASCII.LF &
         "      replaceCaller(11,37);error(17)" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==17)" &
         ASCII.LF &
         "end");
   end Close_Error_Replaces_Return;

   procedure Reverse_Closer_Order;
   procedure Reverse_Closer_Order is
   begin
      --  Each closer sees actual edits left by the preceding inner closer.
      Check
        ("do" &
         ASCII.LF &
         "  local order={}" &
         ASCII.LF &
         "  local f=function()" &
         ASCII.LF &
         "    local outer <close> = setmetatable({},{__close=f" &
         "unction()" &
         ASCII.LF &
         "      assert(order[1]=='inner');replaceCaller(23,37)" &
         ";order[2]='outer'" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    local inner <close> = setmetatable({},{__close=f" &
         "unction()" &
         ASCII.LF &
         "      replaceCaller(11,23);order[1]='inner'" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  assert(f()==37 and order[1]=='inner' and order[2]=" &
         "='outer')" &
         ASCII.LF &
         "end");
   end Reverse_Closer_Order;

   procedure Yielding_Closer_Result;
   procedure Yielding_Closer_Result is
   begin
      --  Preserve real result cells while a closer suspends and resumes.
      Check
        ("do" &
         ASCII.LF &
         "  local f=function()" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()" &
         ASCII.LF &
         "      replaceCaller(11,23);coroutine.yield('closing'" &
         ");replaceCaller(23,37)" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local co=coroutine.create(f)" &
         ASCII.LF &
         "  local ok,value=coroutine.resume(co);assert(ok and " &
         "value=='closing')" &
         ASCII.LF &
         "  ok,value=coroutine.resume(co);assert(ok and value=" &
         "=37)" &
         ASCII.LF &
         "end");
   end Yielding_Closer_Result;

   procedure Vararg_Return_Range;
   procedure Vararg_Return_Range is
   begin
      --  Keep actual vararg result offsets and the complete return count.
      Check
        ("do" &
         ASCII.LF &
         "  local f=function(a,...)" &
         ASCII.LF &
         "    local g <close> = setmetatable({},{__close=funct" &
         "ion()replaceCaller(11,37)end})" &
         ASCII.LF &
         "    return a,..." &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local r=table.pack(f(11,nil,23))" &
         ASCII.LF &
         "  assert(r.n==3 and r[1]==37 and r[2]==nil and r[3]=" &
         "=23)" &
         ASCII.LF &
         "end");
   end Vararg_Return_Range;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "Close return: scalar result",
                        Scalar_Result'Access);
      Test_Support.Add (Suite, "Close return: tuple with nils",
                        Tuple_With_Nils'Access);
      Test_Support.Add (Suite, "Close return: weak result reclamation",
                        Weak_Result_Reclamation'Access);
      Test_Support.Add (Suite, "Close return: subsequent return hook",
                        Subsequent_Return_Hook'Access);
      Test_Support.Add (Suite, "Close return: close error replaces return",
                        Close_Error_Replaces_Return'Access);
      Test_Support.Add (Suite, "Close return: reverse closer order",
                        Reverse_Closer_Order'Access);
      Test_Support.Add (Suite, "Close return: yielding closer result",
                        Yielding_Closer_Result'Access);
      Test_Support.Add (Suite, "Close return: vararg return range",
                        Vararg_Return_Range'Access);
   end Register;
end Close_Return_Window_Tests;
