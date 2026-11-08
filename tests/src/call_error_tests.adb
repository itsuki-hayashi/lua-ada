with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Call_Error_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Local_Nil;
   procedure Local_Nil is
   begin
      --  A direct nil local uses its real caller name and source.
      Check
        ("local f=assert(load(""local x;x()"",'=callcase'));local ok," &
         "e=pcall(f);assert(not ok and e==""callcase:1: attempt to c" &
         "all a nil value (local 'x')"",tostring(e))");
   end Local_Nil;

   procedure Global_Nil;
   procedure Global_Nil is
   begin
      --  A missing global resolves from the actual calling register.
      Check
        ("local f=assert(load(""missing_call()"",'=callcase'));local " &
         "ok,e=pcall(f);assert(not ok and e==""callcase:1: attempt t" &
         "o call a nil value (global 'missing_call')"",tostring(e))");
   end Global_Nil;

   procedure Field_Nil;
   procedure Field_Nil is
   begin
      --  A noncallable field retains its field provenance.
      Check
        ("local f=assert(load(""local t={};t.missing()"",'=callcase')" &
         ");local ok,e=pcall(f);assert(not ok and e==""callcase:1: a" &
         "ttempt to call a nil value (field 'missing')"",tostring(e)" &
         ")");
   end Field_Nil;

   procedure Method_Nil;
   procedure Method_Nil is
   begin
      --  A method call retains its actual method name.
      Check
        ("local f=assert(load(""local t={};t:missing()"",'=callcase')" &
         ");local ok,e=pcall(f);assert(not ok and e==""callcase:1: a" &
         "ttempt to call a nil value (method 'missing')"",tostring(e" &
         "))");
   end Method_Nil;

   procedure Upvalue_Nil;
   procedure Upvalue_Nil is
   begin
      --  An invalid captured callee reports its upvalue identity.
      Check
        ("local f=assert(load(""local x;local function f()x()end;f()" &
         """,'=callcase'));local ok,e=pcall(f);assert(not ok and e==" &
         """callcase:1: attempt to call a nil value (upvalue 'x')"",t" &
         "ostring(e))");
   end Upvalue_Nil;

   procedure Custom_Type;
   procedure Custom_Type is
   begin
      --  Call diagnostics honor a raw string type name.
      Check
        ("local f=assert(load(""local x=setmetatable({},{__name='exa" &
         "mple'});x()"",'=callcase'));local ok,e=pcall(f);assert(not" &
         " ok and e==""callcase:1: attempt to call a example value (" &
         "local 'x')"",tostring(e))");
   end Custom_Type;

   procedure Removed_Close;
   procedure Removed_Close is
   begin
      --  A removed handler is called as nil at the real close opcode.
      Check
        ("local f=assert(load(""local x <close> =setmetatable({},{__" &
         "close=function()end});getmetatable(x).__close=nil"",'=call" &
         "case'));local ok,e=pcall(f);assert(not ok and e==""callcas" &
         "e:1: attempt to call a nil value (metamethod 'close')"",to" &
         "string(e))");
   end Removed_Close;

   procedure Numeric_Close;
   procedure Numeric_Close is
   begin
      --  A numeric replacement retains normal close provenance.
      Check
        ("local f=assert(load(""local x <close> =setmetatable({},{__" &
         "close=function()end});getmetatable(x).__close=4"",'=callca" &
         "se'));local ok,e=pcall(f);assert(not ok and e==""callcase:" &
         "1: attempt to call a number value (metamethod 'close')"",t" &
         "ostring(e))");
   end Numeric_Close;

   procedure Boolean_Close;
   procedure Boolean_Close is
   begin
      --  A false replacement remains a noncallable handler value.
      Check
        ("local f=assert(load(""local x <close> =setmetatable({},{__" &
         "close=function()end});getmetatable(x).__close=false"",'=ca" &
         "llcase'));local ok,e=pcall(f);assert(not ok and e==""callc" &
         "ase:1: attempt to call a boolean value (metamethod 'close" &
         "')"",tostring(e))");
   end Boolean_Close;

   procedure Error_Removed_Close;
   procedure Error_Removed_Close is
   begin
      --  An error close has unwound to C protection before its call.
      Check
        ("local f=assert(load(""local x <close> =setmetatable({},{__" &
         "close=function()end});getmetatable(x).__close=nil;error('" &
         "original')"",'=callcase'));local ok,e=pcall(f);assert(not " &
         "ok and e==""attempt to call a nil value"",tostring(e))");
   end Error_Removed_Close;

   procedure Error_Numeric_Close;
   procedure Error_Numeric_Close is
   begin
      --  A replacement error close cannot borrow its retired Lua site.
      Check
        ("local f=assert(load(""local x <close> =setmetatable({},{__" &
         "close=function()end});getmetatable(x).__close=4;error('or" &
         "iginal')"",'=callcase'));local ok,e=pcall(f);assert(not ok" &
         " and e==""attempt to call a number value"",tostring(e))");
   end Error_Numeric_Close;

   procedure Coroutine_Removed_Close;
   procedure Coroutine_Removed_Close is
   begin
      --  Coroutine closing uses its surviving native call boundary.
      Check
        ("local co=coroutine.create(function()local x <close> =setm" &
         "etatable({},{__close=function()end});getmetatable(x).__cl" &
         "ose=nil;coroutine.yield()end);assert(coroutine.resume(co)" &
         ");local ok,e=coroutine.close(co);assert(not ok and e=='at" &
         "tempt to call a nil value',tostring(e))");
   end Coroutine_Removed_Close;

   procedure Protected_Nil;
   procedure Protected_Nil is
   begin
      --  A direct protected nil call adds no invented Lua caller.
      Check
        ("local ok,e=pcall(nil);assert(not ok and e=='attempt to ca" &
         "ll a nil value',tostring(e))");
   end Protected_Nil;

   procedure Invalid_Call_Handler;
   procedure Invalid_Call_Handler is
   begin
      --  A noncallable call handler preserves its original calling site.
      Check
        ("local f=assert(load(""local x=setmetatable({},{__call=4});" &
         "x()"",'=callcase'));local ok,e=pcall(f);assert(not ok and " &
         "e==""callcase:1: attempt to call a number value (local 'x'" &
         ")"",tostring(e))");
   end Invalid_Call_Handler;

   procedure Stripped_Call;
   procedure Stripped_Call is
   begin
      --  A stripped caller retains unknown source and line markers.
      Check
        ("local f=assert(load(string.dump(function()local x;x()end," &
         "true)));local ok,e=pcall(f);assert(not ok and e=='?:?: at" &
         "tempt to call a nil value',tostring(e))");
   end Stripped_Call;

   procedure Close_Error_Replacement;
   procedure Close_Error_Replacement is
   begin
      --  An outer closer receives the actual replacement call error.
      Check
        ("local got;local f=assert(load(""local outer <close> =setme" &
         "tatable({},{__close=function(_,e)captured_error=e end});l" &
         "ocal inner <close> =setmetatable({},{__close=function()en" &
         "d});getmetatable(inner).__close=nil"",'=callcase'));local " &
         "ok,e=pcall(f);assert(not ok and e==""callcase:1: attempt t" &
         "o call a nil value (metamethod 'close')"" and captured_err" &
         "or==e,tostring(e))");
   end Close_Error_Replacement;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "call error: Local_Nil",
         Local_Nil'Access);
      Test_Support.Add
        (Suite, "call error: Global_Nil",
         Global_Nil'Access);
      Test_Support.Add
        (Suite, "call error: Field_Nil",
         Field_Nil'Access);
      Test_Support.Add
        (Suite, "call error: Method_Nil",
         Method_Nil'Access);
      Test_Support.Add
        (Suite, "call error: Upvalue_Nil",
         Upvalue_Nil'Access);
      Test_Support.Add
        (Suite, "call error: Custom_Type",
         Custom_Type'Access);
      Test_Support.Add
        (Suite, "call error: Removed_Close",
         Removed_Close'Access);
      Test_Support.Add
        (Suite, "call error: Numeric_Close",
         Numeric_Close'Access);
      Test_Support.Add
        (Suite, "call error: Boolean_Close",
         Boolean_Close'Access);
      Test_Support.Add
        (Suite, "call error: Error_Removed_Close",
         Error_Removed_Close'Access);
      Test_Support.Add
        (Suite, "call error: Error_Numeric_Close",
         Error_Numeric_Close'Access);
      Test_Support.Add
        (Suite, "call error: Coroutine_Removed_Close",
         Coroutine_Removed_Close'Access);
      Test_Support.Add
        (Suite, "call error: Protected_Nil",
         Protected_Nil'Access);
      Test_Support.Add
        (Suite, "call error: Invalid_Call_Handler",
         Invalid_Call_Handler'Access);
      Test_Support.Add
        (Suite, "call error: Stripped_Call",
         Stripped_Call'Access);
      Test_Support.Add
        (Suite, "call error: Close_Error_Replacement",
         Close_Error_Replacement'Access);
   end Register;
end Call_Error_Tests;
