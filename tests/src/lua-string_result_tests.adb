with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.String_Result_Tests is
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
      Success := Execute (State, Source, "=string-result");
      if Interpose then
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
      end if;
      Assert (Success, To_String (State.Current.Failure_Text));
      Finalize (State);
      if Interpose then Conformance_Allocator.Finish; end if;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "string result retained its frame or scalar output");
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

   procedure Cold_Find;
   procedure Cold_Find is
   begin
      --  A fresh scalar producer delivers both indices and an absent result.
      Check
        ("do" & ASCII.LF &
         "  local a,b=string.find('abc','bc',1,tru" &
         "e);assert(a==2 and b==3)" & ASCII.LF &
         "  assert(string.find('abc','missing',1,t" &
         "rue)==nil)" & ASCII.LF &
         "end");
   end Cold_Find;

   procedure Cold_Empty_Byte;
   procedure Cold_Empty_Byte is
   begin
      --  An empty range returns zero values through the owned arena.
      Check
        ("do" & ASCII.LF &
         "  assert(select('#',string.byte('',1,0))" &
         "==0)" & ASCII.LF &
         "end");
   end Cold_Empty_Byte;

   procedure Warm_Find;
   procedure Warm_Find is
   begin
      --  Repeated protected scalar delivery reuses the actual waiting
      --  caller.
      Check
        ("do" & ASCII.LF &
         "  local f,s,p=string.find,'abc','bc'" & ASCII.LF &
         "  for i=1,100 do local ok,a,b=pcall(f,s," &
         "p);assert(ok and a==2 and b==3)end" & ASCII.LF &
         "end");
   end Warm_Find;

   procedure Multiple_Status;
   procedure Multiple_Status is
   begin
      --  A success prefix retains nil and false child results exactly once.
      Check
        ("do" & ASCII.LF &
         "  local r=table.pack(pcall(function()ret" &
         "urn nil,false,7,9 end))" & ASCII.LF &
         "  assert(r.n==5 and r[1]==true and r[2]=" &
         "=nil and r[3]==false and r[4]==7 and r[5" &
         "]==9)" & ASCII.LF &
         "end");
   end Multiple_Status;

   procedure Zero_Status;
   procedure Zero_Status is
   begin
      --  A child with no values still contributes exactly one success
      --  boolean.
      Check
        ("do" & ASCII.LF &
         "  local r=table.pack(pcall(function()end" &
         "));assert(r.n==1 and r[1]==true)" & ASCII.LF &
         "end");
   end Zero_Status;

   procedure Xpcall_Status;
   procedure Xpcall_Status is
   begin
      --  Xpcall publishes its own success status and preserves false
      --  results.
      Check
        ("do" & ASCII.LF &
         "  local r=table.pack(xpcall(function(a,b" &
         ")return false,a,b end,function(e)return " &
         "e end,7,9))" & ASCII.LF &
         "  assert(r.n==4 and r[1]==true and r[2]=" &
         "=false and r[3]==7 and r[4]==9)" & ASCII.LF &
         "end");
   end Xpcall_Status;

   procedure Repeated_Status;
   procedure Repeated_Status is
   begin
      --  Reusing a protected frame cannot accumulate success prefixes.
      Check
        ("do" & ASCII.LF &
         "  local f=function()return false,7 end" & ASCII.LF &
         "  for i=1,100 do local r=table.pack(pcal" &
         "l(f));assert(r.n==3 and r[1]==true and r" &
         "[2]==false and r[3]==7)end" & ASCII.LF &
         "end");
   end Repeated_Status;

   procedure Yield_Status;
   procedure Yield_Status is
   begin
      --  A suspended protected call prefixes success only after final
      --  completion.
      Check
        ("do" & ASCII.LF &
         "  local co=coroutine.create(function()re" &
         "turn pcall(function()local x=coroutine.y" &
         "ield(7);return false,x end)end)" & ASCII.LF &
         "  local ok,v=coroutine.resume(co);assert" &
         "(ok and v==7)" & ASCII.LF &
         "  local resumed,protected,raw,last=corou" &
         "tine.resume(co,9)" & ASCII.LF &
         "  assert(resumed and protected and raw==" &
         "false and last==9 and coroutine.status(c" &
         "o)=='dead')" & ASCII.LF &
         "end");
   end Yield_Status;

   procedure Protected_Error;
   procedure Protected_Error is
   begin
      --  The existing arbitrary error packet receives no success prefix.
      Check
        ("do" & ASCII.LF &
         "  local marker={};local ok,e=pcall(funct" &
         "ion()error(marker,0)end)" & ASCII.LF &
         "  assert(not ok and e==marker)" & ASCII.LF &
         "end");
   end Protected_Error;

   procedure Xpcall_Error;
   procedure Xpcall_Error is
   begin
      --  An error handler's arbitrary result remains an error result.
      Check
        ("do" & ASCII.LF &
         "  local marker,changed={},{};local ok,e=" &
         "xpcall(function()error(marker,0)end,func" &
         "tion(v)assert(v==marker);return changed " &
         "end)" & ASCII.LF &
         "  assert(not ok and e==changed)" & ASCII.LF &
         "end");
   end Xpcall_Error;

   procedure Weak_Output;
   procedure Weak_Output is
   begin
      --  Reused native output arenas retain no values after actual callers
      --  depart.
      Check
        ("do" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "})" & ASCII.LF &
         "  local function make()return {} end" & ASCII.LF &
         "  local function produce()" & ASCII.LF &
         "    local ok,inner,value=pcall(pcall,mak" &
         "e);assert(ok and inner)" & ASCII.LF &
         "    weak[1]=value;collectgarbage();asser" &
         "t(weak[1]==value)" & ASCII.LF &
         "  end" & ASCII.LF &
         "  produce();collectgarbage();assert(weak" &
         "[1]==nil)" & ASCII.LF &
         "end");
   end Weak_Output;

   procedure Refused_Find;
   procedure Refused_Find is
   begin
      --  The unchanged memerr scalar pattern succeeds under permanent
      --  refusal.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  collectgarbage('stop')" & ASCII.LF &
         "  local s,p='not enough memory','not eno" &
         "ugh memory'" & ASCII.LF &
         "  local f,control=string.find,T.alloccou" &
         "nt" & ASCII.LF &
         "  control();assert(pcall(f,s,p));control(0)" & ASCII.LF &
         "  local ok,a,b=pcall(f,s,p);control()" & ASCII.LF &
         "  assert(ok and a==1 and b==#s)" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Find;

   procedure Refused_Length;
   procedure Refused_Length is
   begin
      --  A warmed one-integer producer needs no fresh output container.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  collectgarbage('stop')" & ASCII.LF &
         "  local f,s,control=string.len,'existing" &
         " subject',T.alloccount" & ASCII.LF &
         "  control();assert(pcall(f,s));control(0)" & ASCII.LF &
         "  local ok,n=pcall(f,s);control();assert" &
         "(ok and n==#s)" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Length;

   procedure Refused_Zero;
   procedure Refused_Zero is
   begin
      --  A warmed zero-result producer still returns its protected true
      --  status.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  collectgarbage('stop')" & ASCII.LF &
         "  local f,s,control=string.byte,'',T.all" &
         "occount" & ASCII.LF &
         "  control();assert(pcall(f,s));control(0)" & ASCII.LF &
         "  local ok,extra=pcall(f,s);control();as" &
         "sert(ok and extra==nil)" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Zero;

   procedure Refused_Error;
   procedure Refused_Error is
   begin
      --  The preexisting protected error owner remains usable with no
      --  growth.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  collectgarbage('stop')" & ASCII.LF &
         "  local marker={};local f,control=error," &
         "T.alloccount" & ASCII.LF &
         "  control();assert(not pcall(f,marker,0));" &
         "control(" &
         "0)" & ASCII.LF &
         "  local ok,e=pcall(f,marker,0);control()" &
         ";assert(not ok and e==marker)" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Error;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "results: cold find",
         Cold_Find'Access);
      Test_Support.Add
        (Suite, "results: cold empty byte",
         Cold_Empty_Byte'Access);
      Test_Support.Add
        (Suite, "results: warm find",
         Warm_Find'Access);
      Test_Support.Add
        (Suite, "results: multiple status",
         Multiple_Status'Access);
      Test_Support.Add
        (Suite, "results: zero status",
         Zero_Status'Access);
      Test_Support.Add
        (Suite, "results: xpcall status",
         Xpcall_Status'Access);
      Test_Support.Add
        (Suite, "results: repeated status",
         Repeated_Status'Access);
      Test_Support.Add
        (Suite, "results: yield status",
         Yield_Status'Access);
      Test_Support.Add
        (Suite, "results: protected error",
         Protected_Error'Access);
      Test_Support.Add
        (Suite, "results: xpcall error",
         Xpcall_Error'Access);
      Test_Support.Add
        (Suite, "results: weak output",
         Weak_Output'Access);
      Test_Support.Add
        (Suite, "results: refused find",
         Refused_Find'Access);
      Test_Support.Add
        (Suite, "results: refused length",
         Refused_Length'Access);
      Test_Support.Add
        (Suite, "results: refused zero",
         Refused_Zero'Access);
      Test_Support.Add
        (Suite, "results: refused error",
         Refused_Error'Access);
   end Register;
end Lua.String_Result_Tests;
