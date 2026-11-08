with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Stripped_Line_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure First_Stripped_Line;
   procedure First_Stripped_Line is
   begin
      --  An unknown source line still causes the first real line event.
      Check
        ("local f=assert(load(string.dump(function()local x=1;retur" &
         "n x end,true)));local n=0;debug.sethook(function(e,l)if d" &
         "ebug.getinfo(2,'f').func==f then assert(e=='line' and l==" &
         "nil);n=n+1 end end,'l');assert(f()==1);debug.sethook();as" &
         "sert(n==1)");
   end First_Stripped_Line;

   procedure Stripped_Back_Edges;
   procedure Stripped_Back_Edges is
   begin
      --  Unknown-line events recur at actual backward control transfers.
      Check
        ("local f=assert(load(string.dump(function()for i=1,3 do en" &
         "d;return 9 end,true)));local n=0;debug.sethook(function(e" &
         ",l)if debug.getinfo(2,'f').func==f then assert(e=='line' " &
         "and l==nil);n=n+1 end end,'l');assert(f()==9);debug.setho" &
         "ok();assert(n==3)");
   end Stripped_Back_Edges;

   procedure Stripped_Vararg_Entry;
   procedure Stripped_Vararg_Entry is
   begin
      --  Vararg setup precedes the single unknown-line user event.
      Check
        ("local f=assert(load(string.dump(function(...)return ... e" &
         "nd,true)));local n=0;debug.sethook(function(e,l)if debug." &
         "getinfo(2,'f').func==f then assert(e=='line' and l==nil);" &
         "n=n+1 end end,'l');local a,b,c=f(4,nil,6);debug.sethook()" &
         ";assert(a==4 and b==nil and c==6 and n==1)");
   end Stripped_Vararg_Entry;

   procedure Stripped_Frame_Reuse;
   procedure Stripped_Frame_Reuse is
   begin
      --  A reused activation forgets its previous unknown-line check.
      Check
        ("local f=assert(load(string.dump(function()return 7 end,tr" &
         "ue)));local n=0;debug.sethook(function(e,l)if debug.getin" &
         "fo(2,'f').func==f then assert(e=='line' and l==nil);n=n+1" &
         " end end,'l');assert(f()==7);assert(f()==7);assert(f()==7" &
         ");debug.sethook();assert(n==3)");
   end Stripped_Frame_Reuse;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "stripped line: First_Stripped_Line",
         First_Stripped_Line'Access);
      Test_Support.Add
        (Suite, "stripped line: Stripped_Back_Edges",
         Stripped_Back_Edges'Access);
      Test_Support.Add
        (Suite, "stripped line: Stripped_Vararg_Entry",
         Stripped_Vararg_Entry'Access);
      Test_Support.Add
        (Suite, "stripped line: Stripped_Frame_Reuse",
         Stripped_Frame_Reuse'Access);
   end Register;
end Stripped_Line_Tests;
