with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Process_Exit_Tests is
   use type Process_Exit_Code;
   procedure Check
     (Source : String; Code : Process_Exit_Code; Closing : Boolean;
      Output : String);
   procedure Check
     (Source : String; Code : Process_Exit_Code; Closing : Boolean;
      Output : String)
   is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  The action executes ordinary Lua source through the public API.
      --  The result must carry the request, never exit or raise in Ada.
      Result := Universe.Execute (Source, "process-exit");
      Assert (Result.Status = Exit_Requested,
              Result.Status'Image & ": " & To_String (Result.Error.Message));
      Assert (Result.Exit_Request.Code = Code and then
                Result.Exit_Request.Close_State = Closing,
              "typed exit request changed");
      Assert (To_String (Result.Output) = Output, "exit output/order");
      Result := Universe.Execute ("assert(1+1==2)");
      Assert (Result.Status = (if Closing then Runtime_Error else Succeeded),
              "exit changed the promised session ownership");
      Universe.Reset;
      Result := Universe.Execute ("assert(os and 1+1==2)");
      Assert (Result.Status = Succeeded, "reset after process request");
   end Check;

   procedure False_Request;
   procedure False_Request is
      --  The host receives status 23 and keeps ownership of the session.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("print(""before"");os.exit(23,false);error(""unreachable" &
         """)",
         23, False, "before" & ASCII.LF & "");
   end False_Request;

   procedure Protected_Request;
   procedure Protected_Request is
      --  A Lua protected boundary cannot turn process exit into a return.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("pcall(function()os.exit(7,false)end);error(""caught e" &
         "xit"")",
         7, False, "");
   end Protected_Request;

   procedure Coroutine_Request;
   procedure Coroutine_Request is
      --  Exit abandons the active coroutine/resumer chain as a whole.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("local c=coroutine.create(function()os.exit(8,false)e" &
         "nd);coroutine.resume(c);error(""resumed"")",
         8, False, "");
   end Coroutine_Request;

   procedure Main_Close_Order;
   procedure Main_Close_Order is
      --  State close visits main-thread declarations in reverse order.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("local a <close> = setmetatable({},{__close=function(" &
         "_,e)print(""A"",e)end});local b <close> = setmetatable" &
         "({},{__close=function(_,e)print(""B"",e)end});os.exit(" &
         "23,true)",
         23, True, "B" & ASCII.HT & "nil" & ASCII.LF & "A" & ASCII.HT & "nil" & ASCII.LF & "");
   end Main_Close_Order;

   procedure Close_Error_Status;
   procedure Close_Error_Status is
      --  A close error reaches outer handlers without replacing exit 
      --  status.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("local a <close> = setmetatable({},{__close=function(" &
         "_,e)print(""A"",type(e))end});local b <close> = setmet" &
         "atable({},{__close=function()error(""close"")end});os." &
         "exit(23,true)",
         23, True, "A" & ASCII.HT & "string" & ASCII.LF & "");
   end Close_Error_Status;

   procedure Finalizer_Order;
   procedure Finalizer_Order is
      --  State close drains actual registered objects in reverse 
      --  enrollment.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("a=setmetatable({},{__gc=function()print(""A"")end});b=" &
         "setmetatable({},{__gc=function()print(""B"")end});os.e" &
         "xit(23,true)",
         23, True, "B" & ASCII.LF & "A" & ASCII.LF & "");
   end Finalizer_Order;

   procedure Abandoned_Coroutine_Close;
   procedure Abandoned_Coroutine_Close is
      --  State close frees suspended coroutine storage without closing its 
      --  locals.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("c=coroutine.create(function()local x <close> = setme" &
         "tatable({},{__close=function()print(""wrong"")end});co" &
         "routine.yield()end);assert(coroutine.resume(c));os.e" &
         "xit(0,true)",
         0, True, "");
   end Abandoned_Coroutine_Close;

   procedure Nested_Close_Exit;
   procedure Nested_Close_Exit is
      --  A replacement exit request continues the remaining main close 
      --  entries once.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("local a <close> = setmetatable({},{__close=function(" &
         ")print(""A"")end});local b <close> = setmetatable({},{" &
         "__close=function()print(""B"");os.exit(9,true);print(""" &
         "wrong"")end});os.exit(23,true)",
         9, True, "B" & ASCII.LF & "A" & ASCII.LF & "");
   end Nested_Close_Exit;

   procedure Nested_Finalizer_Exit;
   procedure Nested_Finalizer_Exit is
      --  A replacement request cannot repeat the currently consumed 
      --  finalizer.
      --  Execute the chunk, check status/output, then verify host recovery.
   begin
      Check
        ("a=setmetatable({},{__gc=function()print(""A"")end});b=" &
         "setmetatable({},{__gc=function()print(""B"");os.exit(1" &
         "3,true);print(""wrong"")end});os.exit(23,true)",
         13, True, "B" & ASCII.LF & "A" & ASCII.LF & "");
   end Nested_Finalizer_Exit;

   procedure Host_Abort_During_Close;
   procedure Host_Abort_During_Close is
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  A close callback loops under the existing bounded chunk budget.
      --  Host quota exhaustion abandons cleanup without converting to exit.
      --  A later public chunk can execute normally with its fresh budget.
      Bounds.Instructions := 300;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local x <close> = setmetatable({},{__close=function()" &
         "while true do end end});os.exit(23,true)");
      Assert (Result.Status = Resource_Error, "closing restarted quota");
      Result := Universe.Execute ("assert(2+2==4)");
      Assert (Result.Status = Succeeded, "closing abort poisoned session");
   end Host_Abort_During_Close;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "process exit: False_Request", False_Request'Access);
      Test_Support.Add
        (Suite, "process exit: Protected_Request", Protected_Request'Access);
      Test_Support.Add
        (Suite, "process exit: Coroutine_Request", Coroutine_Request'Access);
      Test_Support.Add
        (Suite, "process exit: Main_Close_Order", Main_Close_Order'Access);
      Test_Support.Add
        (Suite, "process exit: Close_Error_Status", Close_Error_Status'Access);
      Test_Support.Add
        (Suite, "process exit: Finalizer_Order", Finalizer_Order'Access);
      Test_Support.Add
        (Suite, "process exit: Abandoned_Coroutine_Close", Abandoned_Coroutine_Close'Access);
      Test_Support.Add
        (Suite, "process exit: Nested_Close_Exit", Nested_Close_Exit'Access);
      Test_Support.Add
        (Suite, "process exit: Nested_Finalizer_Exit", Nested_Finalizer_Exit'Access);
      Test_Support.Add
        (Suite, "process exit: host abort during close",
         Host_Abort_During_Close'Access);
   end Register;
end Process_Exit_Tests;
