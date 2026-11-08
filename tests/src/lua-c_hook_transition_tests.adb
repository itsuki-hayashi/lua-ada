with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.C_Hook_Transition_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Source : String; Interpose : Boolean := False);
   procedure Check (Source : String; Interpose : Boolean := False) is
      State : World;
      Success : Boolean;
   begin
      Initialize (State, (others => <>));
      if Interpose then
         Conformance_Allocator.Attach (Lua.Storage.Reference (State.Memory));
         Conformance_Adapter.Install (State);
      end if;
      Success := Execute (State, Source, "=hook-transition");
      if Interpose then
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
      end if;
      Assert (Success, Failure_Image (State.Current));
      Finalize (State);
      if Interpose then Conformance_Allocator.Finish; end if;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "hook transition retained its callback or scalar frame");
   exception
      when others =>
         if Interpose then
            Conformance_Allocator.Clear_Count_Limit;
            Conformance_Allocator.Set_Byte_Limit (0);
         end if;
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State);
         if Interpose then Conformance_Allocator.Finish; end if;
         raise;
   end Check;

   procedure C_Count_To_Line;
   procedure C_Count_To_Line is
   begin
      --  Preserve the original API count-to-line source sequence.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  _G.TT={}" & ASCII.LF &
         "  T.sethook([[sethook 4 0 '" & ASCII.LF &
         "    getglobal TT; pushvalue -3; append -" &
         "2; pushvalue -2; append -2" & ASCII.LF &
         "  ']],'c',3)" & ASCII.LF &
         "  local a=1" & ASCII.LF &
         "  a=1" & ASCII.LF &
         "  a=1" & ASCII.LF &
         "  a=1" & ASCII.LF &
         "  a=1" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  local t=TT;local first=t[2]" & ASCII.LF &
         "  assert(t[1]=='line' and t[3]=='line' a" &
         "nd t[4]==first+1)" & ASCII.LF &
         "  assert(t[5]=='line' and t[6]==first+2 " &
         "and t[7]==nil)" & ASCII.LF &
         "  TT=nil" & ASCII.LF &
         "end", Interpose => True);
   end C_Count_To_Line;

   procedure C_Same_Line;
   procedure C_Same_Line is
   begin
      --  A direct C count callback does not advance the Lua trace PC.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  _G.TT={}" & ASCII.LF &
         "  local origin=debug.getinfo(1,'l').curr" &
         "entline" & ASCII.LF &
         "  T.sethook([[sethook 4 0 'getglobal TT;" &
         "pushvalue -3;append -2;pushvalue -2;appe" &
         "nd -2']],'',2)" & ASCII.LF &
         "  local a=1;a=1;a=1;a=1;a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  local t=TT" & ASCII.LF &
         "  assert(t[1]=='line' and t[2]==origin+2" &
         ")" & ASCII.LF &
         "  assert(t[3]=='line' and t[4]==origin+3" &
         ")" & ASCII.LF &
         "  assert(t[5]=='line' and t[6]==origin+4" &
         " and t[7]==nil)" & ASCII.LF &
         "  TT=nil" & ASCII.LF &
         "end", Interpose => True);
   end C_Same_Line;

   procedure C_Count_Removes_Line;
   procedure C_Count_Removes_Line is
   begin
      --  An old line phase invokes the new count-only callback.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  _G.TT={}" & ASCII.LF &
         "  local origin=debug.getinfo(1,'l').curr" &
         "entline" & ASCII.LF &
         "  T.sethook([[sethook 8 1000 'getglobal " &
         "TT;pushvalue -3;append -2;pushvalue -2;a" &
         "ppend -2']],'l',1)" & ASCII.LF &
         "  local a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(TT[1]=='line' and TT[2]==origin" &
         "+2 and TT[3]==nil)" & ASCII.LF &
         "  TT=nil" & ASCII.LF &
         "end", Interpose => True);
   end C_Count_Removes_Line;

   procedure C_Count_Removes_All;
   procedure C_Count_Removes_All is
   begin
      --  A captured mask cannot invoke a removed hook pointer.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  _G.TT={}" & ASCII.LF &
         "  T.sethook([[sethook 0 0 '']],'l',1)" & ASCII.LF &
         "  local a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(TT[1]==nil)" & ASCII.LF &
         "  TT=nil" & ASCII.LF &
         "end", Interpose => True);
   end C_Count_Removes_All;

   procedure C_Line_To_Count;
   procedure C_Line_To_Count is
   begin
      --  A line callback's new interval starts on later instructions.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  _G.TT={}" & ASCII.LF &
         "  T.sethook([[sethook 8 3 'getglobal TT;" &
         "pushvalue -3;append -2;pushvalue -2;appe" &
         "nd -2;sethook 0 0 """"']],'l',0)" & ASCII.LF &
         "  local a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  a=3" & ASCII.LF &
         "  a=4" & ASCII.LF &
         "  a=5" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(TT[1]=='count' and TT[2]==-1 an" &
         "d TT[3]==nil)" & ASCII.LF &
         "  TT=nil" & ASCII.LF &
         "end", Interpose => True);
   end C_Line_To_Count;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "C hook transition: c count to line",
         C_Count_To_Line'Access);
      Test_Support.Add
        (Suite, "C hook transition: c same line",
         C_Same_Line'Access);
      Test_Support.Add
        (Suite, "C hook transition: c count removes line",
         C_Count_Removes_Line'Access);
      Test_Support.Add
        (Suite, "C hook transition: c count removes all",
         C_Count_Removes_All'Access);
      Test_Support.Add
        (Suite, "C hook transition: c line to count",
         C_Line_To_Count'Access);
   end Register;
end Lua.C_Hook_Transition_Tests;
