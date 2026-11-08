with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Reader_Portal_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Reader_Identity;
   procedure Reader_Identity is
   begin
      --  The actual load activation stays visible during the reader.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    local i=debug.getinfo(2,'fSu')" & ASCII.LF &
         "    assert(i.func==load and i.what=='C' " &
         "and i.nparams==0 and i.isvararg)" & ASCII.LF &
         "    calls=calls+1;if calls==1 then retur" &
         "n 'return 37' end" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(f and f()==37 and calls==2,tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Reader_Identity;

   procedure Mutable_Reader;
   procedure Mutable_Reader is
   begin
      --  Each refill reads the current actual reader argument cell.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    assert(debug.setlocal(2,1,function()" &
         "calls=calls+1;return nil end))" & ASCII.LF &
         "    return 'return 41'" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(f and f()==41 and calls==2,tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Mutable_Reader;

   procedure Retired_Reader_Root;
   procedure Retired_Reader_Root is
   begin
      --  Replacing the actual reader removes its obsolete root.
      Check
        ("do" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "})" & ASCII.LF &
         "  local function make_reader()" & ASCII.LF &
         "    local function old()" & ASCII.LF &
         "      assert(debug.setlocal(2,1,function" &
         "()" & ASCII.LF &
         "        collectgarbage();assert(weak[1]=" &
         "=nil);return nil" & ASCII.LF &
         "      end))" & ASCII.LF &
         "      return 'return 43'" & ASCII.LF &
         "    end" & ASCII.LF &
         "    weak[1]=old;return old" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local f,e=load(make_reader());assert(f" &
         " and f()==43,tostring(e))" & ASCII.LF &
         "end");
   end Retired_Reader_Root;

   procedure Mutable_Environment;
   procedure Mutable_Environment is
   begin
      --  load_aux reads argument four after reader callbacks.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then" & ASCII.LF &
         "      assert(debug.setlocal(2,4,{value=4" &
         "7}))" & ASCII.LF &
         "      return 'return value'" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'=reader-env','t',{value=7})" & ASCII.LF &
         "  assert(f and f()==47 and calls==2,tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Mutable_Environment;

   procedure Text_Mode_Stop;
   procedure Text_Mode_Stop is
   begin
      --  Mode selection rejects text before another reader callback.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1;if calls==1 then retur" &
         "n 'return 37' end" & ASCII.LF &
         "    error('read after text mode rejectio" &
         "n',0)" & ASCII.LF &
         "  end,nil,'b')" & ASCII.LF &
         "  assert(f==nil and calls==1 and" & ASCII.LF &
         "    e==""attempt to load a text chunk (mo" &
         "de is 'b')"",tostring(e))" & ASCII.LF &
         "end");
   end Text_Mode_Stop;

   procedure Binary_Mode_Stop;
   procedure Binary_Mode_Stop is
   begin
      --  The signature selects binary before text parsing or refill.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1;if calls==1 then retur" &
         "n '\27' end" & ASCII.LF &
         "    error('read after binary mode reject" &
         "ion',0)" & ASCII.LF &
         "  end,nil,'t')" & ASCII.LF &
         "  assert(f==nil and calls==1 and" & ASCII.LF &
         "    e==""attempt to load a binary chunk (" &
         "mode is 't')"",tostring(e))" & ASCII.LF &
         "end");
   end Binary_Mode_Stop;

   procedure Binary_Trailing;
   procedure Binary_Trailing is
   begin
      --  A complete binary prototype leaves unrelated bytes unread.
      Check
        ("do" & ASCII.LF &
         "  local source=string.dump(function()ret" &
         "urn 53 end)..'unread trailing bytes'" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1;if calls==1 then retur" &
         "n source end" & ASCII.LF &
         "    error('read after binary prototype'," &
         "0)" & ASCII.LF &
         "  end,nil,'b')" & ASCII.LF &
         "  assert(f and f()==53 and calls==1,tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Binary_Trailing;

   procedure Reader_Yield;
   procedure Reader_Yield is
   begin
      --  The parser guard rejects suspension across its live C body.
      Check
        ("do" & ASCII.LF &
         "  local thread=coroutine.create(function" &
         "()" & ASCII.LF &
         "    return load(function()coroutine.yiel" &
         "d('wrong suspension')end)" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  local ok,f,e=coroutine.resume(thread)" & ASCII.LF &
         "  assert(ok and f==nil and e=='attempt t" &
         "o yield across a C-call boundary'," & ASCII.LF &
         "    tostring(e))" & ASCII.LF &
         "  assert(coroutine.status(thread)=='dead" &
         "')" & ASCII.LF &
         "end");
   end Reader_Yield;

   procedure Protected_Nil_Error;
   procedure Protected_Nil_Error is
   begin
      --  A nil reader error uses Lua's exact fallback and arity.
      Check
        ("do" & ASCII.LF &
         "  local result=table.pack(pcall(load,fun" &
         "ction()error(nil,0)end))" & ASCII.LF &
         "  assert(result.n==3 and result[1]==true" &
         " and" & ASCII.LF &
         "    result[2]==nil and result[3]=='<no e" &
         "rror object>')" & ASCII.LF &
         "end");
   end Protected_Nil_Error;

   procedure Return_Hook_Result;
   procedure Return_Hook_Result is
   begin
      --  A load return hook can replace the actual result slot.
      Check
        ("do" & ASCII.LF &
         "  local replacement=function()return 59 " &
         "end" & ASCII.LF &
         "  local calls,hits=0,0" & ASCII.LF &
         "  debug.sethook(function(event)" & ASCII.LF &
         "    if event=='return' then local i=debu" &
         "g.getinfo(2,'fr')" & ASCII.LF &
         "      if i.func==load then" & ASCII.LF &
         "        hits=hits+1;assert(i.ntransfer==" &
         "1)" & ASCII.LF &
         "        assert(debug.setlocal(2,i.ftrans" &
         "fer,replacement))" & ASCII.LF &
         "      end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'r')" & ASCII.LF &
         "  local f=load(function()" & ASCII.LF &
         "    calls=calls+1;if calls==1 then retur" &
         "n 'return 1' end" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  debug.sethook();assert(f==replacement " &
         "and f()==59 and hits==1)" & ASCII.LF &
         "end");
   end Return_Hook_Result;

   procedure Return_Hook_Nil_Tuple;
   procedure Return_Hook_Nil_Tuple is
   begin
      --  Failed load retains both editable return slots.
      Check
        ("do" & ASCII.LF &
         "  local hits=0" & ASCII.LF &
         "  debug.sethook(function(event)" & ASCII.LF &
         "    if event=='return' then local i=debu" &
         "g.getinfo(2,'fr')" & ASCII.LF &
         "      if i.func==load then" & ASCII.LF &
         "        hits=hits+1;assert(i.ntransfer==" &
         "2)" & ASCII.LF &
         "        assert(debug.setlocal(2,i.ftrans" &
         "fer,false))" & ASCII.LF &
         "        assert(debug.setlocal(2,i.ftrans" &
         "fer+1,nil))" & ASCII.LF &
         "      end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'r')" & ASCII.LF &
         "  local result=table.pack(load(function(" &
         ")return 'local = x' end))" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(result.n==2 and result[1]==fals" &
         "e and result[2]==nil and hits==1)" & ASCII.LF &
         "end");
   end Return_Hook_Nil_Tuple;

   procedure Single_Public_Call;
   procedure Single_Public_Call is
   begin
      --  The portal adds no public call or return event.
      Check
        ("do" & ASCII.LF &
         "  local calls,entries,returns=0,0,0" & ASCII.LF &
         "  debug.sethook(function(event)" & ASCII.LF &
         "    local i=debug.getinfo(2,'f')" & ASCII.LF &
         "    if i.func==load then" & ASCII.LF &
         "      if event=='call' then entries=entr" &
         "ies+1" & ASCII.LF &
         "      elseif event=='return' then return" &
         "s=returns+1 end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'cr')" & ASCII.LF &
         "  local f=load(function()" & ASCII.LF &
         "    calls=calls+1;if calls==1 then retur" &
         "n 'return 61' end" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(f and f()==61 and entries==1 an" &
         "d returns==1)" & ASCII.LF &
         "end");
   end Single_Public_Call;

   procedure Nested_Reader_Load;
   procedure Nested_Reader_Load is
   begin
      --  A reader can stream another load on the same driver.
      Check
        ("do" & ASCII.LF &
         "  local outer,inner=0,0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    outer=outer+1" & ASCII.LF &
         "    if outer==1 then" & ASCII.LF &
         "      local g,m=load(function()" & ASCII.LF &
         "        inner=inner+1;if inner==1 then r" &
         "eturn 'return 67' end" & ASCII.LF &
         "      end)" & ASCII.LF &
         "      assert(g and g()==67,tostring(m));" &
         "return 'return 71'" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(f and f()==71 and outer==2 and " &
         "inner==2,tostring(e))" & ASCII.LF &
         "end");
   end Nested_Reader_Load;

   procedure Inherited_Handler;
   procedure Inherited_Handler is
   begin
      --  Reader errors use the actual surrounding message handler.
      Check
        ("do" & ASCII.LF &
         "  local original,replacement={},{};local" &
         " calls=0" & ASCII.LF &
         "  local ok,f,e=xpcall(function()" & ASCII.LF &
         "    return load(function()error(original" &
         ",0)end)" & ASCII.LF &
         "  end,function(value)" & ASCII.LF &
         "    calls=calls+1;assert(value==original" &
         ");return replacement" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(ok and f==nil and e==replacemen" &
         "t and calls==1)" & ASCII.LF &
         "end");
   end Inherited_Handler;

   procedure Numeric_Chunk_Name;
   procedure Numeric_Chunk_Name is
   begin
      --  Numeric names are strings in the actual reader-visible CI.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    local _,value=debug.getlocal(2,2)" & ASCII.LF &
         "    assert(type(value)=='string' and val" &
         "ue=='37')" & ASCII.LF &
         "    if calls==1 then return 'return 73' " &
         "end" & ASCII.LF &
         "  end,37)" & ASCII.LF &
         "  assert(f and f()==73 and calls==2,tost" &
         "ring(e))" & ASCII.LF &
         "  assert(debug.getinfo(f,'S').source=='3" &
         "7')" & ASCII.LF &
         "end");
   end Numeric_Chunk_Name;

   procedure Numeric_Mode;
   procedure Numeric_Mode is
   begin
      --  Numeric mode coercion is visible before signature rejection.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    local _,value=debug.getlocal(2,3)" & ASCII.LF &
         "    assert(type(value)=='string' and val" &
         "ue=='42')" & ASCII.LF &
         "    return 'return 79'" & ASCII.LF &
         "  end,nil,42)" & ASCII.LF &
         "  assert(f==nil and calls==1 and" & ASCII.LF &
         "    e==""attempt to load a text chunk (mo" &
         "de is '42')"",tostring(e))" & ASCII.LF &
         "end");
   end Numeric_Mode;

   procedure Retired_Extra_Argument;
   procedure Retired_Extra_Argument is
   begin
      --  Replaced extra arguments leave no stale phase root.
      Check
        ("do" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "})" & ASCII.LF &
         "  local function make_extra()local value" &
         "={};weak[1]=value;return value end" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then" & ASCII.LF &
         "      assert(debug.setlocal(2,5,nil))" & ASCII.LF &
         "      collectgarbage();assert(weak[1]==n" &
         "il);return 'return 83'" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,nil,'t',_ENV,make_extra())" & ASCII.LF &
         "  assert(f and f()==83 and calls==2,tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Retired_Extra_Argument;

   procedure Protected_Success_Hook;
   procedure Protected_Success_Hook is
   begin
      --  A raw load result edit retains one private true prefix.
      Check
        ("do" & ASCII.LF &
         "  local replacement=function()return 89 " &
         "end;local count=0" & ASCII.LF &
         "  debug.sethook(function(event)" & ASCII.LF &
         "    if event=='return' then local i=debu" &
         "g.getinfo(2,'fr')" & ASCII.LF &
         "      if i.func==load then" & ASCII.LF &
         "        assert(i.ntransfer==1)" & ASCII.LF &
         "        assert(debug.setlocal(2,i.ftrans" &
         "fer,replacement))" & ASCII.LF &
         "      end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'r')" & ASCII.LF &
         "  local result=table.pack(pcall(load,fun" &
         "ction()" & ASCII.LF &
         "    count=count+1;if count==1 then retur" &
         "n 'return 1' end" & ASCII.LF &
         "  end))" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(result.n==2 and result[1]==true" &
         " and result[2]==replacement)" & ASCII.LF &
         "end");
   end Protected_Success_Hook;

   procedure Protected_Failure_Hook;
   procedure Protected_Failure_Hook is
   begin
      --  Internal status stays separate from an editable nil tuple.
      Check
        ("do" & ASCII.LF &
         "  debug.sethook(function(event)" & ASCII.LF &
         "    if event=='return' then local i=debu" &
         "g.getinfo(2,'fr')" & ASCII.LF &
         "      if i.func==load then" & ASCII.LF &
         "        assert(i.ntransfer==2)" & ASCII.LF &
         "        assert(debug.setlocal(2,i.ftrans" &
         "fer,false))" & ASCII.LF &
         "        assert(debug.setlocal(2,i.ftrans" &
         "fer+1,nil))" & ASCII.LF &
         "      end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'r')" & ASCII.LF &
         "  local result=table.pack(pcall(load,fun" &
         "ction()return 'local = x' end))" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(result.n==3 and result[1]==true" &
         " and" & ASCII.LF &
         "    result[2]==false and result[3]==nil)" & ASCII.LF &
         "end");
   end Protected_Failure_Hook;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "reader portal: reader identity",
         Reader_Identity'Access);
      Test_Support.Add
        (Suite, "reader portal: mutable reader",
         Mutable_Reader'Access);
      Test_Support.Add
        (Suite, "reader portal: retired reader root",
         Retired_Reader_Root'Access);
      Test_Support.Add
        (Suite, "reader portal: mutable environment",
         Mutable_Environment'Access);
      Test_Support.Add
        (Suite, "reader portal: text mode stop",
         Text_Mode_Stop'Access);
      Test_Support.Add
        (Suite, "reader portal: binary mode stop",
         Binary_Mode_Stop'Access);
      Test_Support.Add
        (Suite, "reader portal: binary trailing",
         Binary_Trailing'Access);
      Test_Support.Add
        (Suite, "reader portal: reader yield",
         Reader_Yield'Access);
      Test_Support.Add
        (Suite, "reader portal: protected nil error",
         Protected_Nil_Error'Access);
      Test_Support.Add
        (Suite, "reader portal: return hook result",
         Return_Hook_Result'Access);
      Test_Support.Add
        (Suite, "reader portal: return hook nil tuple",
         Return_Hook_Nil_Tuple'Access);
      Test_Support.Add
        (Suite, "reader portal: single public call",
         Single_Public_Call'Access);
      Test_Support.Add
        (Suite, "reader portal: nested reader load",
         Nested_Reader_Load'Access);
      Test_Support.Add
        (Suite, "reader portal: inherited handler",
         Inherited_Handler'Access);
      Test_Support.Add
        (Suite, "reader portal: numeric chunk name",
         Numeric_Chunk_Name'Access);
      Test_Support.Add
        (Suite, "reader portal: numeric mode",
         Numeric_Mode'Access);
      Test_Support.Add
        (Suite, "reader portal: retired extra argument",
         Retired_Extra_Argument'Access);
      Test_Support.Add
        (Suite, "reader portal: protected success hook",
         Protected_Success_Hook'Access);
      Test_Support.Add
        (Suite, "reader portal: protected failure hook",
         Protected_Failure_Hook'Access);
   end Register;
end Reader_Portal_Tests;
