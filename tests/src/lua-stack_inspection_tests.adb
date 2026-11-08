with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.Stack_Inspection_Tests is
   use type Lua.Storage.Byte_Count;
   Prelude : constant String :=
     "local cases={" & ASCII.LF &
     " function()" & ASCII.LF &
     "  local a,b,c,d,e=T.stacklevel()" & ASCII.LF &
     "  for _,v in ipairs{a,b,c,d,e}do " &
     "assert(math.type(v)=='integer')end" & ASCII.LF &
     "  assert(a>=0 and b>0 and c>=0 and d>0 and e~=0)" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local pos,top=0,nil" & ASCII.LF &
     "  local text='return 121'" & ASCII.LF &
     "  local function read()" & ASCII.LF &
     "   pos=pos+1" & ASCII.LF &
     "   local current=T.stacklevel()" & ASCII.LF &
     "   if top then assert(current==top)else top=current end" & ASCII.LF &
     "   return text:sub(pos,pos)" & ASCII.LF &
     "  end" & ASCII.LF &
     "  assert(assert(load(read))()==121)" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local text=string.dump(assert(load('return 37')))" & ASCII.LF &
     "  local pos,top=0,nil" & ASCII.LF &
     "  local function read()" & ASCII.LF &
     "   pos=pos+1" & ASCII.LF &
     "   local current=T.stacklevel()" & ASCII.LF &
     "   if top then assert(current==top)else top=current end" & ASCII.LF &
     "   return text:sub(pos,pos)" & ASCII.LF &
     "  end" & ASCII.LF &
     "  assert(assert(load(read))()==37)" & ASCII.LF &
     " end," & ASCII.LF &
     " function()" & ASCII.LF &
     "  local _,_,before=T.stacklevel()" & ASCII.LF &
     "  local observed" & ASCII.LF &
     "  local ok,e=pcall(function()" & ASCII.LF &
     "   local _,_,inside=T.stacklevel()" & ASCII.LF &
     "   observed=inside" & ASCII.LF &
     "   error('expected',0)" & ASCII.LF &
     "  end)" & ASCII.LF &
     "  assert(not ok and e=='expected' and observed>before)" & ASCII.LF &
     "  local _,_,after=T.stacklevel()" & ASCII.LF &
     "  assert(before==after)" & ASCII.LF &
     " end," & ASCII.LF &
     "}" & ASCII.LF;
   procedure Check (Which : Positive);
   procedure Shape;
   procedure Text_Reader;
   procedure Binary_Reader;
   procedure Protected_Depth;

   procedure Check (Which : Positive) is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Lua.Conformance_Adapter.Install (State);
         Assert (Execute (State, Prelude & "cases[" &
                   Positive'Image (Which) & "]()", "=stack-inspection"),
                 Failure_Image (State.Current));
      exception
         when others =>
            Lua.Storage.Clear_Failures (State.Memory);
            Finalize (State);
            raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "stack inspection retained owned storage");
   end Check;

   --  The test driver reports actual typed arena and activation counters.
   procedure Shape is
   begin
      Check (1);
   end Shape;

   --  Repeated text reader callbacks keep the same actual stack top.
   procedure Text_Reader is
   begin
      Check (2);
   end Text_Reader;

   --  Binary readers use the same iterative continuation invariant.
   procedure Binary_Reader is
   begin
      Check (3);
   end Binary_Reader;

   --  A protected native portal increases nesting and restores it on error.
   procedure Protected_Depth is
   begin
      Check (4);
   end Protected_Depth;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "stack inspection: actual counter shape",
                        Shape'Access);
      Test_Support.Add (Suite, "stack inspection: text reader stability",
                        Text_Reader'Access);
      Test_Support.Add (Suite, "stack inspection: binary reader stability",
                        Binary_Reader'Access);
      Test_Support.Add (Suite, "stack inspection: protected depth recovery",
                        Protected_Depth'Access);
   end Register;
end Lua.Stack_Inspection_Tests;
