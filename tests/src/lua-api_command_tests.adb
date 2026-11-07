with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.API_Command_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Source : String);
   procedure Light_Upvalues;
   procedure Absent_Upvalue;
   procedure Stack_Reordering;
   procedure Raw_Table;
   procedure Metatable_Delegation;
   procedure Arithmetic_Commands;
   procedure C_Function_Identity;
   procedure Length_Commands;
   procedure Loaded_Source;
   procedure Formatting_Commands;
   procedure Userdata_Metatable;
   procedure References;
   procedure Double_Bytes;
   procedure Mutable_Upvalues;
   procedure New_Stack;
   procedure External_String;
   procedure Warning_Fragments;
   procedure Hook_Command;
   procedure Stack_Reservation;
   procedure Driver_Rejection;
   procedure Shared_Cross_Budget;
   procedure Coroutine_Cross_Budget;
   procedure Nested_Cross_Budget;
   procedure Budget_Check (Source : String);
   procedure Check (Source : String) is
      State : World;
   begin
      Initialize (State, (others => <>));
      Conformance_Adapter.Install (State);
      Assert (Execute (State, Source, "=public-api-command"),
              To_String (State.Current.Failure_Text));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "public command retained context, value or callback ownership");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State);
         raise;
   end Check;

   procedure Light_Upvalues is
   begin
      --  Native testC is a light C function. Adapter implementation metadata
      --  must not become user-visible captures; U0 is the actual registry.
      Check
        ("assert(debug.getupvalue(T.testC,1)==nil);" &
         "assert(T.testC('isnull U1;return 1'));" &
         "assert(T.testC('pushvalue U0;return 1')==debug.getregistry());" &
         "assert(T.testC('pushcclosure 0;return 1')==T.testC)");
   end Light_Upvalues;

   procedure Absent_Upvalue is
   begin
      --  U256 is acceptable but absent even for a 255-upvalue closure.
      --  An absent index has type none, which differs from an actual nil.
      Check
        ("local f=T.makeCfunc('isnull U256;isnil U256;return 2');" &
         "local a,b=f();assert(a==true and b==false)");
   end Absent_Upvalue;

   procedure Stack_Reordering is
   begin
      --  Rotate and copy consume current physical indices. Subsequent
      --  values must observe the actual edited argument window.
      Check
        ("local a,b,c=T.testC('rotate 2 1;copy 2 3;return 3',10,20,30);" &
         "assert(a==30 and b==30 and c==20);" &
         "assert(T.testC('settop 10;absindex -1;return 1')==10)");
   end Stack_Reordering;

   procedure Raw_Table is
   begin
      --  Raw field/pointer operations bypass a hostile __index and retain
      --  actual pointer keys. Get operations report their actual result type.
      Check
        ("local t=setmetatable({},{__index=function()error('raw')end});" &
         "T.testC('pushint 37;rawsetp 2 19',t);" &
         "assert(T.testC('rawgetp 2 19;return 1',t)==37);" &
         "T.testC('pushstring x;pushint 23;rawset 2',t);" &
         "assert(T.testC('pushstring x;rawget 2;return 1',t)==23)");
   end Raw_Table;

   procedure Metatable_Delegation is
   begin
      --  Public get/set commands invoke actual collecting Lua handlers;
      --  no driver-side table emulation can satisfy the forwarded mutation.
      Check
        ("local target={};local t=setmetatable({},{__index=function(_,k)" &
         "collectgarbage();return target[k]end,__newindex=function(_,k,v)" &
         "target[k]=v end});T.testC('pushint 37;setfield 2 value',t);" &
         "assert(T.testC('getfield 2 value;return 1',t)==37)");
   end Metatable_Delegation;

   procedure Arithmetic_Commands is
   begin
      --  The command encoding maps to the real public operation numbers.
      --  Unary handlers and mixed number classes execute in the same runtime.
      Check
        ("assert(T.testC('pushint 10;pushint 3;arith +;return 1')==13);" &
         "local t=setmetatable({},{__unm=function()return 37 end});" &
         "assert(T.testC('arith _;return 1',t)==37);" &
         "assert(T.testC('compare LT 2 3;return 1',1,2))");
   end Arithmetic_Commands;

   procedure C_Function_Identity is
   begin
      --  A builtin round-trips through its genuine C address, retaining
      --  callability and light-function identity instead of a marker pointer.
      Check
        ("local f=T.testC('tocfunction 2;return 1',math.deg);" &
         "assert(f==math.deg and f(3)==math.deg(3));" &
         "assert(T.testC('func2num 2;return 1',f)~=0)");
   end C_Function_Identity;

   procedure Length_Commands is
   begin
      --  lua_len preserves arbitrary handler values; luaL_len then performs
      --  its real integer check. Raw length bypasses that handler.
      Check
        ("local t=setmetatable({1},{__len=function()return '234'end});" &
         "local a,b,c=T.testC('len 2;Llen 2;objsize 2;return 3',t);" &
         "assert(a=='234' and b==234 and c==1)");
   end Length_Commands;

   procedure Loaded_Source is
   begin
      --  The named buffer is loaded by the actual shared frontend and its
      --  returned closure executes through the ordinary C call protocol.
      Check
        ("assert(T.testC('loadstring 2 named t;call 0 1;return 1'," &
         "'return 37')==37);local f=T.testC('loadstring 2 named t;" &
         "return 1','return 23');assert(f()==23)");
   end Loaded_Source;

   procedure Formatting_Commands is
   begin
      --  The public auxiliary buffer and native varargs facade own the
      --  actual resulting bytes; replacements are literal, not patterns.
      Check
        ("assert(T.testC('gsub 2 3 4;return 1','a.b.a','a','XX')==" &
         "'XX.b.XX');" &
         "assert(T.testC('pushfstringI;return 1','value=%d',37)=='value=37')");
   end Formatting_Commands;

   procedure Userdata_Metatable is
   begin
      --  The registry metatable and real userdata are created by exports.
      --  Named tests must observe that same public metatable identity.
      Check
        ("local u=T.testC('newuserdata 17;newmetatable TestCommand;" &
         "pop 1;setmetatable -2;return 1');" &
         "assert(T.testC('testudata 2 TestCommand;return 1',u));" &
         "assert(T.testC('objsize 2;return 1',u)==17)");
   end Userdata_Metatable;

   procedure References is
   begin
      --  Nil references and a caller-provided reference table retain the
      --  real auxiliary free list; collection cannot discard a live reference.
      Check
        ("local t={};local item={};local n=T.ref(item,t);collectgarbage();" &
         "assert(T.getref(n,t)==item);T.unref(n,t);" &
         "assert(T.ref({},t)==n);assert(T.ref(nil)==-1);" &
         "assert(T.getref(-1)==nil)");
   end References;

   procedure Double_Bytes is
   begin
      --  These are actual host-double bytes, including signed zero, checked
      --  independently by the runtime's packing library and numeric reader.
      Check
        ("local n=12458954321123.0;assert(T.d2s(n)==string.pack('d',n));" &
         "assert(T.s2d(T.d2s(n))==n);" &
         "assert(1/T.s2d(T.d2s(-0.0))==-math.huge)");
   end Double_Bytes;

   procedure Mutable_Upvalues is
   begin
      --  Public setupvalue edits the actual cells of the newly created C
      --  closure. Missing captures return no values, preserving native arity.
      Check
        ("local f=T.testC('pushint 10;pushint 20;pushcclosure 2;return 1');" &
         "assert(T.upvalue(f,1)==10 and T.upvalue(f,2)==20);" &
         "assert(select('#',T.upvalue(f,3))==0);T.upvalue(f,2,'changed');" &
         "assert(f('pushvalue U2;return 1')=='changed')");
   end Mutable_Upvalues;

   procedure New_Stack is
   begin
      --  The helper creates a genuine same-world thread, then loads/calls
      --  through the real C APIs. Its global write is shared with its parent.
      Check
        ("assert(T.doonnewstack('command_global=37')==0);" &
         "assert(command_global==37);assert(T.doonnewstack('error(17)')==2)");
   end New_Stack;

   procedure External_String is
   begin
      --  Binary external bytes belong to the selected allocator and survive
      --  a collection while rooted; world finalization releases them once.
      Check
        ("local s='a'..string.char(0)..string.rep('b',100);" &
         "local x=T.externstr(s);s=nil;collectgarbage();" &
         "assert(#x==102 and x:byte(2)==0 and x:sub(3)==string.rep('b',100))");
   end External_String;

   procedure Warning_Fragments is
   begin
      --  Continuation and final warning commands use the real installed
      --  warning callback and preserve one combined stored delivery.
      Check
        ("if T._installwarning then T._installwarning()end;" &
         "warn('@store');T.testC(" &
         "[[warningC hello;warning world]]);assert(_WARN=='helloworld');" &
         "_WARN=false;warn('@normal')");
   end Warning_Fragments;

   procedure Hook_Command is
   begin
      --  The command stores its actual script and installs a real count
      --  hook. Removing it must preserve the callback's global mutation.
      Check
        ("T.testC([[sethook 8 1 'pushint 77;setglobal command_hook']]);" &
         "local x=1;T.sethook();assert(command_hook==77 and x==1)");
   end Hook_Command;

   procedure Stack_Reservation is
   begin
      --  Oversized nonthrowing reservation returns false; the throwing
      --  auxiliary command raises its message and remains recoverable.
      --  INT_MAX exceeds both normal and native overflow-reserve capacity;
      --  max+23 could fit a previously reserved native default error stack.
      Check
        ("assert(T.testC('rawcheckstack 32;return 1'));" &
         "assert(not T.testC('rawcheckstack 2147483647;return 1'));" &
         "local ok,e=pcall(T.testC,'checkstack 2147483647 required');" &
         "assert(not ok and e:find('required'))");
   end Stack_Reservation;

   procedure Driver_Rejection is
   begin
      --  Extra first-party operand/token checks raise ordinary recoverable
      --  Lua errors instead of overflowing native ints or reading past tokens.
      Check
        ("local ok,e=pcall(T.testC,'compare BAD 1 1');" &
         "assert(not ok and e:find('comparison expected'));" &
         "ok,e=pcall(T.testC,'pushint 999999999999999999999999');" &
         "assert(not ok and e:find('overflows int'));" &
         "assert(T.testC('pushint 37;return 1')==37)");
   end Driver_Rejection;

   procedure Budget_Check (Source : String) is
      State : World;
   begin
      --  A protected C call on another context shares the original host
      --  budget. Its lack of a local C callback guard must not turn a typed
      --  host stop into process panic or a catchable Lua memory/runtime error.
      Initialize (State, (Instructions => 1_000, others => <>));
      Conformance_Adapter.Install (State);
      Assert (not Execute (State, Source, "=cross-context-quota"),
        "cross-context execution escaped the original host budget");
      Assert (State.Current.Failure_Class = Host_Abort,
              "cross-context host quota became a catchable error");
      Assert (Ada.Strings.Fixed.Index
        (To_String (State.Current.Failure_Text), "instruction limit") > 0,
        "cross-context transfer lost the original host failure diagnostic");
      Assert (Execute (State, "return 37", "=cross-context-recovery"),
              "cross-context host stop did not restore the original driver");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "cross-context host stop leaked driver/scope ownership");
   exception
      when others => Finalize (State); raise;
   end Budget_Check;

   procedure Shared_Cross_Budget is
   begin
      Budget_Check
        ("pcall(T.doonnewstack,'while true do end');" &
         "error('cross-context quota was caught')");
   end Shared_Cross_Budget;

   procedure Coroutine_Cross_Budget is
   begin
      --  The genuine live caller guard is on a coroutine, while the main
      --  surface has no guard. A main-state fallback would skip that owner.
      Budget_Check
        ("local co=coroutine.create(function()T.doonnewstack(" &
         "'while true do end')end);pcall(coroutine.resume,co);" &
         "error('coroutine cross-context quota was caught')");
   end Coroutine_Cross_Budget;

   procedure Nested_Cross_Budget is
   begin
      --  Two entry switches unwind their actual C guards and restore each
      --  scalar driver owner before the original Ada host receives its stop.
      Budget_Check
        ("pcall(T.doonnewstack,[[T.doonnewstack('while true do end')]]);" &
         "error('nested cross-context quota was caught')");
   end Nested_Cross_Budget;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "API driver: light C upvalues",
                        Light_Upvalues'Access);
      Test_Support.Add (Suite, "API driver: acceptable absent upvalue",
                        Absent_Upvalue'Access);
      Test_Support.Add (Suite, "API driver: physical stack edits",
                        Stack_Reordering'Access);
      Test_Support.Add (Suite, "API driver: raw pointer table keys",
                        Raw_Table'Access);
      Test_Support.Add (Suite, "API driver: real table handlers",
                        Metatable_Delegation'Access);
      Test_Support.Add (Suite, "API driver: actual arithmetic",
                        Arithmetic_Commands'Access);
      Test_Support.Add (Suite, "API driver: callable C identity",
                        C_Function_Identity'Access);
      Test_Support.Add (Suite, "API driver: length value and conversion",
                        Length_Commands'Access);
      Test_Support.Add (Suite, "API driver: actual loaded source",
                        Loaded_Source'Access);
      Test_Support.Add (Suite, "API driver: buffer and varargs",
                        Formatting_Commands'Access);
      Test_Support.Add (Suite, "API driver: userdata metatable",
                        Userdata_Metatable'Access);
      Test_Support.Add (Suite, "API driver: actual references",
                        References'Access);
      Test_Support.Add (Suite, "API driver: native double bytes",
                        Double_Bytes'Access);
      Test_Support.Add (Suite, "API driver: mutable captured cells",
                        Mutable_Upvalues'Access);
      Test_Support.Add (Suite, "API driver: actual new thread call",
                        New_Stack'Access);
      Test_Support.Add (Suite, "API driver: owned external bytes",
                        External_String'Access);
      Test_Support.Add (Suite, "API driver: warning fragments",
                        Warning_Fragments'Access);
      Test_Support.Add (Suite, "API driver: real command hook",
                        Hook_Command'Access);
      Test_Support.Add (Suite, "API driver: stack reservation failures",
                        Stack_Reservation'Access);
      Test_Support.Add (Suite, "API driver: safe operand rejection",
                        Driver_Rejection'Access);
      Test_Support.Add (Suite, "API driver: shared cross-context budget",
                        Shared_Cross_Budget'Access);
      Test_Support.Add (Suite, "API driver: coroutine cross-context budget",
                        Coroutine_Cross_Budget'Access);
      Test_Support.Add (Suite, "API driver: nested cross-context budget",
                        Nested_Cross_Budget'Access);
   end Register;
end Lua.API_Command_Tests;
