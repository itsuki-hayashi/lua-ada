with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Runtime_Configuration;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Lua.Coroutine_Portal_Tests is
   Preamble : constant String :=
     "local limit=assert(_PORTAL_LIMIT)" &
     ASCII.LF &
     "local names,values,sum={},{},{}" &
     ASCII.LF &
     "for i=1,64 do names[i]='a'..i;values[i]='1';sum[i]='" &
     "a'..i end" &
     ASCII.LF &
     "local source='return function(n,mode) local '..table" &
     ".concat(names,',')..'='.." &
     ASCII.LF &
     "  table.concat(values,',')..'; '..[[" &
     ASCII.LF &
     "local closed=0" &
     ASCII.LF &
     "local body=function()" &
     ASCII.LF &
     " local guard <close> = setmetatable({},{__close=func" &
     "tion()closed=closed+1 end})" &
     ASCII.LF &
     " if mode=='yield' or mode=='wrapped' then" &
     ASCII.LF &
     "  coroutine.yield(table.unpack({},1,n));return 37" &
     ASCII.LF &
     " end" &
     ASCII.LF &
     " return table.unpack({},1,n)" &
     ASCII.LF &
     "end" &
     ASCII.LF &
     "local co,wrapped" &
     ASCII.LF &
     "if mode=='wrapped' then" &
     ASCII.LF &
     " wrapped=coroutine.wrap(body);local name;name,co=deb" &
     "ug.getupvalue(wrapped,1)" &
     ASCII.LF &
     "else co=coroutine.create(body)end" &
     ASCII.LF &
     "if mode=='success' then" &
     ASCII.LF &
     " local count=select('#',coroutine.resume(co));assert" &
     "(count==n+1)" &
     ASCII.LF &
     "else" &
     ASCII.LF &
     " local ok,r,message" &
     ASCII.LF &
     " if wrapped then" &
     ASCII.LF &
     "  ok,message=pcall(wrapped)" &
     ASCII.LF &
     "  assert(not ok and message:find('too many results t" &
     "o resume',1,true))" &
     ASCII.LF &
     " else" &
     ASCII.LF &
     "  ok,r,message=pcall(coroutine.resume,co)" &
     ASCII.LF &
     "  assert(ok,'capacity error escaped: '..tostring(r))" &
     ASCII.LF &
     "  assert(r==false and message=='too many results to " &
     "resume')" &
     ASCII.LF &
     " end" &
     ASCII.LF &
     "end" &
     ASCII.LF &
     "if mode=='yield' or mode=='wrapped' then" &
     ASCII.LF &
     " assert(coroutine.status(co)=='suspended' and closed" &
     "==0)" &
     ASCII.LF &
     " if wrapped then assert(wrapped()==37)" &
     ASCII.LF &
     " else local ok,value=coroutine.resume(co);assert(ok " &
     "and value==37)end" &
     ASCII.LF &
     " assert(closed==1)" &
     ASCII.LF &
     "else assert(coroutine.status(co)=='dead' and closed=" &
     "=1)end" &
     ASCII.LF &
     "]]..' assert('..table.concat(sum,'+')..'==64)end'" &
     ASCII.LF &
     "local check=assert(load(source,'=resume-portal'))()" &
     ASCII.LF &
     ASCII.LF;
   --  Live named locals make the parent's result area smaller than its
   --  child's. Use the selected actual semantic limit, not a test-only VM.

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : Execution_Result;
   begin
      Universe.Set_Execution_Policy (Lua_Compatible);
      Result := Universe.Execute
        ("_PORTAL_LIMIT=" & Runtime_Configuration.Maximum_Stack'Image &
         ";" & Preamble & Source);
      Assert (Result.Status = Succeeded,
              Result.Status'Image & ": " & To_String (Result.Error.Message));
   end Check;

   procedure Completed_Result_Overflow;
   procedure Completed_Result_Overflow is
   begin
      --  A completed child cannot overflow the caller outside resume.
      Check
        ("do" &
         ASCII.LF &
         "  check(limit-30,'return')" &
         ASCII.LF &
         "end" &
         ASCII.LF &
         "collectgarbage('collect')");
   end Completed_Result_Overflow;

   procedure Yielded_Result_Overflow;
   procedure Yielded_Result_Overflow is
   begin
      --  A rejected yielded tuple leaves its child suspended and
      --  resumable.
      Check
        ("do" &
         ASCII.LF &
         "  check(limit-30,'yield')" &
         ASCII.LF &
         "end" &
         ASCII.LF &
         "collectgarbage('collect')");
   end Yielded_Result_Overflow;

   procedure Wrapped_Yield_Preserves_Child;
   procedure Wrapped_Yield_Preserves_Child is
   begin
      --  A wrapper raises the portal error without closing a healthy
      --  child.
      Check
        ("do" &
         ASCII.LF &
         "  check(limit-30,'wrapped')" &
         ASCII.LF &
         "end" &
         ASCII.LF &
         "collectgarbage('collect')");
   end Wrapped_Yield_Preserves_Child;

   procedure Sufficient_Parent_Capacity;
   procedure Sufficient_Parent_Capacity is
   begin
      --  A large tuple that fits keeps every nil position and its count.
      Check
        ("do" &
         ASCII.LF &
         "  check(limit//2,'success')" &
         ASCII.LF &
         "end");
   end Sufficient_Parent_Capacity;

   procedure Wrapped_Body_Error_Still_Closes;
   procedure Wrapped_Body_Error_Still_Closes is
   begin
      --  An actual body failure still closes and preserves replacement
      --  errors.
      Check
        ("do" &
         ASCII.LF &
         "  local closed=0" &
         ASCII.LF &
         "  local wrapped=coroutine.wrap(function()" &
         ASCII.LF &
         "    local guard <close> = setmetatable({},{__close=f" &
         "unction()" &
         ASCII.LF &
         "      closed=closed+1;error(29)" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    error(17)" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  local ok,value=pcall(wrapped)" &
         ASCII.LF &
         "  assert(not ok and value==29 and closed==1)" &
         ASCII.LF &
         "end");
   end Wrapped_Body_Error_Still_Closes;

   procedure Handoff_Budget_Is_Uncatchable;
   procedure Handoff_Budget_Is_Uncatchable is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Prepare inputs before selecting the small shared work budget.
      --  A wide handoff cannot hide host exhaustion in coroutine.resume or
      --  pcall; a subsequent finite chunk proves context/guard recovery.
      Assert (Universe.Execute
        ("wide={};for i=1,128 do wide[i]=i end;" &
         "handoff=coroutine.create(function(...)return ... end)").Status =
           Succeeded, "prepare wide handoff");
      Universe.Set_Limits ((Instructions => 650, others => <>));
      Result := Universe.Execute
        ("pcall(coroutine.resume,handoff,table.unpack(wide));" &
         "error('handoff budget was hidden')");
      Assert (Result.Status = Resource_Error,
              Result.Status'Image & ": " & To_String (Result.Error.Message));
      Universe.Set_Limits ((Instructions => 5_000, others => <>));
      Assert (Universe.Execute ("return 37").Status = Succeeded,
              "handoff host stop damaged the session");
   end Handoff_Budget_Is_Uncatchable;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "Resume portal: completed result overflow",
         Completed_Result_Overflow'Access);
      Test_Support.Add
        (Suite, "Resume portal: yielded result overflow",
         Yielded_Result_Overflow'Access);
      Test_Support.Add
        (Suite, "Resume portal: wrapped yield preserves child",
         Wrapped_Yield_Preserves_Child'Access);
      Test_Support.Add
        (Suite, "Resume portal: sufficient parent capacity",
         Sufficient_Parent_Capacity'Access);
      Test_Support.Add
        (Suite, "Resume portal: wrapped body error still closes",
         Wrapped_Body_Error_Still_Closes'Access);
      Test_Support.Add (Suite, "Resume portal: host budget escapes pcall",
                        Handoff_Budget_Is_Uncatchable'Access);
   end Register;
end Lua.Coroutine_Portal_Tests;
