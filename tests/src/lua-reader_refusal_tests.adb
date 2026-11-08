with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.Reader_Refusal_Tests is
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
      Success := Execute (State, Source, "=reader-refusal");
      if Interpose then
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
      end if;
      Assert (Success, Failure_Image (State.Current));
      Assert (Conformance_Allocator.Measurements.Refusals > 0,
              "the real reader did not encounter provider refusal");
      Finalize (State);
      if Interpose then Conformance_Allocator.Finish; end if;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "reader refusal retained its source, frame or result");
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

   procedure Refused_Cold_Reader;
   procedure Refused_Cold_Reader is
   begin
      --  A cold completion preserves load's protected memory tuple.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  local control=T.alloccount;control()" & ASCII.LF &
         "  local reader=function()control(0);retu" &
         "rn 'return 37' end" & ASCII.LF &
         "  local ok,f,e=pcall(load,reader)" & ASCII.LF &
         "  control()" & ASCII.LF &
         "  assert(ok and f==nil and e=='not enoug" &
         "h memory')" & ASCII.LF &
         "  assert(assert(load('return 41'))()==41" &
         ")" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Cold_Reader;

   procedure Refused_Warm_Reader;
   procedure Refused_Warm_Reader is
   begin
      --  Reusing a reader cannot move refusal outside its parser.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  local control=T.alloccount;control()" & ASCII.LF &
         "  local count,inject=0,false" & ASCII.LF &
         "  local reader=function()" & ASCII.LF &
         "    count=count+1" & ASCII.LF &
         "    if count==1 then" & ASCII.LF &
         "      if inject then control(0)end" & ASCII.LF &
         "      return 'return 43'" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  assert(assert(load(reader))()==43)" & ASCII.LF &
         "  count=0;inject=true" & ASCII.LF &
         "  local ok,f,e=pcall(load,reader)" & ASCII.LF &
         "  control()" & ASCII.LF &
         "  assert(ok and f==nil and e=='not enoug" &
         "h memory')" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Warm_Reader;

   procedure Refused_Partial_Source;
   procedure Refused_Partial_Source is
   begin
      --  A retained parser prefix is released after refusal.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  local control=T.alloccount;control()" & ASCII.LF &
         "  local count=0" & ASCII.LF &
         "  local reader=function()" & ASCII.LF &
         "    count=count+1" & ASCII.LF &
         "    if count==1 then return 'local value" &
         " = ' end" & ASCII.LF &
         "    control(0);return '47;return value'" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local ok,f,e=pcall(load,reader)" & ASCII.LF &
         "  control()" & ASCII.LF &
         "  assert(ok and f==nil and e=='not enoug" &
         "h memory' and count==2)" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Partial_Source;

   procedure Refused_Binary_Reader;
   procedure Refused_Binary_Reader is
   begin
      --  Binary decoding retains the same protected error policy.
      Check
        ("assert(T and type(T.alloccount)=='functi" &
         "on');" & ASCII.LF &
         "do" & ASCII.LF &
         "  local control=T.alloccount;control()" & ASCII.LF &
         "  local source=string.dump(function()ret" &
         "urn 53 end)" & ASCII.LF &
         "  local reader=function()control(0);retu" &
         "rn source end" & ASCII.LF &
         "  local ok,f,e=pcall(load,reader,nil,'b'" &
         ")" & ASCII.LF &
         "  control()" & ASCII.LF &
         "  assert(ok and f==nil and e=='not enoug" &
         "h memory')" & ASCII.LF &
         "end", Interpose => True);
   end Refused_Binary_Reader;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "reader refusal: refused cold reader",
         Refused_Cold_Reader'Access);
      Test_Support.Add
        (Suite, "reader refusal: refused warm reader",
         Refused_Warm_Reader'Access);
      Test_Support.Add
        (Suite, "reader refusal: refused partial source",
         Refused_Partial_Source'Access);
      Test_Support.Add
        (Suite, "reader refusal: refused binary reader",
         Refused_Binary_Reader'Access);
   end Register;
end Lua.Reader_Refusal_Tests;
