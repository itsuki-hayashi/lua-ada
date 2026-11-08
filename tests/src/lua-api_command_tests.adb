with Ada.Strings.Fixed;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.API_Command_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Source : String; Interpose : Boolean := False);
   procedure Panic_Trivial;
   procedure Panic_Status;
   procedure Panic_Stack;
   procedure Panic_Argument;
   procedure Panic_Memory;
   procedure Panic_Closing;
   procedure Panic_Close_Error;
   procedure Panic_Closing_Status;
   procedure Panic_No_Error;
   procedure Count_Restores_Stack;
   procedure Child_Byte_Limit;
   procedure Child_Count_Limit;
   procedure Loaded_File;
   procedure Oversized_Userdata;
   procedure Panic_Refusal_Sweep;
   procedure Not_False;
   procedure Not_Nil;
   procedure Not_Zero;
   procedure Not_Empty_String;
   procedure Not_Table;
   procedure Not_Function;
   procedure Check_Not (Expression : String; Expected : Boolean);
   procedure Light_Upvalues;
   procedure Absent_Upvalue;
   procedure Stack_Reordering;
   procedure Raw_Table;
   procedure Integer_Self_Value;
   procedure Field_Self_Value;
   procedure Integer_Self_Handler;
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
   procedure Check (Source : String; Interpose : Boolean := False) is
      State : World;
      Success : Boolean;
   begin
      Initialize (State, (others => <>));
      if Interpose then
         Conformance_Allocator.Attach (Lua.Storage.Reference (State.Memory));
      end if;
      Conformance_Adapter.Install (State);
      Success := Execute (State, Source, "=public-api-command");
      if Interpose then
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
      end if;
      Assert (Success,
              Failure_Image (State.Current));
      Finalize (State);
      if Interpose then Conformance_Allocator.Finish; end if;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "public command retained context, value or callback ownership");
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
        (Failure_Image (State.Current), "instruction limit") > 0,
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

   procedure Panic_Trivial is
   begin
      --  An unprotected child error calls the selected real panic function.
      --  Its C-only return jump must leave the parent runtime usable.
      Check ("assert(T.checkpanic('pushstring hi;error')=='hi')", True);
   end Panic_Trivial;

   procedure Panic_Status is
   begin
      --  Reset before panic retains ERRRUN rather than normalizing the
      --  status as the public lua_closethread operation does.
      Check ("assert(T.checkpanic('pushstring hi;error'," &
             "'threadstatus;return 2')=='ERRRUN')", True);
   end Panic_Status;

   procedure Panic_Stack is
   begin
      --  Panic owns the actual child stack and may grow/concatenate it.
      Check ("assert(T.checkpanic('pushstring hi;error',[[checkstack 5 XX;" &
             "pushstring ' alo';pushstring ' mundo';concat 3]])==" &
             "'hi alo mundo')", True);
   end Panic_Stack;

   procedure Panic_Argument is
   begin
      --  A child host API call has no Lua function frame from which an
      --  auxiliary error formatter could invent a function name.
      Check ("assert(T.checkpanic('loadstring 4 name bt')==" &
             "'bad argument #4 (string expected, got no value)')", True);
   end Panic_Argument;

   procedure Panic_Memory is
   begin
      --  Parent and independently constructed child inherit one provider.
      --  The panic command restores its count before allocating its suffix.
      Check ("local x=T.checkpanic('alloccount 0;newtable'," &
             "'alloccount -1;pushstring XX;threadstatus;concat 2;return 1');" &
             "T.alloccount();assert(x=='XXnot enough memory')", True);
   end Panic_Memory;

   procedure Panic_Closing is
   begin
      --  An actual host C to-be-closed value executes its Lua handler before
      --  panic observes the global. The incoming error remains on the stack.
      Check ("assert(T.checkpanic([[pushstring ""return {__close=" &
             "function()Y='ho'end}"";newtable;loadstring -2 name t;" &
             "call 0 1;setmetatable -2;toclose -1;pushstring hi;error]]," &
             "'getglobal Y;concat 2')=='hiho')", True);
   end Panic_Closing;

   procedure Panic_Close_Error is
   begin
      --  A failing close handler replaces the incoming error before the
      --  selected panic receives it; no old error string is substituted.
      Check ("local x=T.checkpanic([[pushstring ""return {__close=" &
             "function()return 1//0 end}"";newtable;loadstring -2 name t;" &
             "call 0 1;setmetatable -2;toclose -1;pushstring hi;error]]);" &
             "assert(x:find('divide by zero',1,true))", True);
   end Panic_Close_Error;

   procedure Panic_Closing_Status is
   begin
      --  A successful close walk must still report the incoming ERRRUN to
      --  panic, rather than the reset driver's normal-completion status.
      Check ("assert(T.checkpanic([[pushstring ""return {__close=" &
             "function()end}"";newtable;loadstring -2 name t;call 0 1;" &
             "setmetatable -2;toclose -1;pushstring hi;error]]," &
             "'threadstatus;return 2')=='ERRRUN')", True);
   end Panic_Closing_Status;

   procedure Panic_No_Error is
   begin
      --  A successful command sequence closes its temporary universe without
      --  calling panic, and publishes the source helper's success message.
      Check ("assert(T.checkpanic('pushint 37')=='no errors')", True);
   end Panic_No_Error;

   procedure Count_Restores_Stack is
   begin
      --  Scalar count control must neither allocate a C call frame under
      --  refusal nor replace the original command and argument slots.
      Check ("local code='alloccount 0;pushvalue 2;alloccount -1;return 1';" &
             "local x={};T.testC(code,x);assert(T.testC(code,x)==x)", True);
   end Count_Restores_Stack;

   procedure Child_Byte_Limit is
   begin
      --  Limiting only the original Storage.Owner let newstate bypass this
      --  ceiling. The inherited real provider must refuse the child's data.
      Check ("local st=assert(T.newstate());T.loadlib(st,129,0);" &
             "assert(T.doremote(st,'return 1')=='1');collectgarbage();" &
             "local before=T.totalmem();T.totalmem(before+200000);" &
             "local ok,a,b,c=pcall(T.doremote,st," &
             """return #string.rep('x',1000000)"");T.totalmem(0);" &
             "T.closestate(st);assert(ok and a==nil and " &
             "b=='not enough memory' and c==4)", True);
   end Child_Byte_Limit;

   procedure Child_Count_Limit is
   begin
      --  The child's C leaf controls the actual inherited provider using a
      --  scalar owner binding, rather than reading the parent's Lua slots.
      Check ("local st=assert(T.newstate());T.loadlib(st,1,0);" &
             "local code=[[local ok,e=pcall(function()T.testC(" &
             "'alloccount 0');return{}end);T.testC('alloccount -1');" &
             "return(not ok and e=='not enough memory')and 37 or 0]];" &
             "local ok,a,b,c=pcall(T.doremote,st,code);T.alloccount();" &
             "T.closestate(st);assert(ok and a=='37' and b==nil and " &
             "c==nil)", True);
   end Child_Count_Limit;

   procedure Loaded_File is
   begin
      --  The command delegates to the public text-mode file loader; it does
      --  not read host files or compile source in the test driver itself.
      Check ("local f=T.testC('loadfile 2;return 1'," &
             "'tests/lua/public_panic_file.lua');" &
             "assert(type(f)=='function' and f()==37)", True);
   end Loaded_File;

   procedure Oversized_Userdata is
   begin
      --  An unrepresentable public userdata request is a runtime error,
      --  whereas a valid request refused by the provider is a memory error.
      Check ("local ok,e=pcall(T.newuserdata,math.maxinteger);" &
             "assert(not ok and e:find('block too big',1,true))", True);
   end Oversized_Userdata;

   procedure Panic_Refusal_Sweep is
   begin
      --  This additional first-party safety campaign refuses successive
      --  provider growths during construction, jump-context setup and result
      --  publication. A failed parent publication must still close its child.
      --  Finish independently checks all inherited physical blocks at exit.
      --  The pinned helper's unguarded setup is not a native oracle for this
      --  stronger cleanup extension; ordinary paired cases remain separate.
      Check ("local code='pushstring panic_fault;error';" &
             "local panic='alloccount -1';local mem='not enough memory';" &
             "assert(T.checkpanic(code,panic)=='panic_fault');" &
             "for n=0,512 do T.alloccount(n);" &
             "local ok,e=pcall(T.checkpanic,code,panic);T.alloccount();" &
             "if not(e==mem or(ok and e=='panic_fault'))then " &
             "error(n..':'..tostring(ok)..':'..tostring(e))end end", True);
   end Panic_Refusal_Sweep;

   procedure Check_Not (Expression : String; Expected : Boolean) is
   begin
      --  The operand is a parameter, so constant folding cannot remove NOT.
      --  Construct values before refusal; clear it only after the word runs.
      --  Check also validates final physical provider ownership independently.
      Check ("local function invert(x)T.alloccount(0);" &
             "local r=not x;T.alloccount();return r end;" &
             "local x=" & Expression & ";assert(invert(x)==" &
             (if Expected then "true" else "false") & ")", True);
   end Check_Not;

   procedure Not_False is
   begin
      Check_Not ("false", True);
   end Not_False;

   procedure Not_Nil is
   begin
      Check_Not ("nil", True);
   end Not_Nil;

   procedure Not_Zero is
   begin
      Check_Not ("0", False);
   end Not_Zero;

   procedure Not_Empty_String is
   begin
      Check_Not ("''", False);
   end Not_Empty_String;

   procedure Not_Table is
   begin
      --  Even a hostile handler cannot participate in logical truth.
      Check_Not ("setmetatable({},{__len=function()error('length')end})",
                 False);
   end Not_Table;

   procedure Not_Function is
   begin
      Check_Not ("function()end", False);
   end Not_Function;

   --  The destination's top cell also supplies the consumed value. Key
   --  insertion must follow that cell instead of indexing the new key.
   procedure Integer_Self_Value is
   begin
      Check ("local a={};T.testC('seti -1 200',a);assert(a[200]==a)");
   end Integer_Self_Value;

   procedure Field_Self_Value is
   begin
      Check ("local a={};T.testC('setfield -1 self',a);" &
             "assert(a.self==a)");
   end Field_Self_Value;

   --  A real callback sees identity-preserving operands and may collect.
   procedure Integer_Self_Handler is
   begin
      Check ("local a=setmetatable({},{__newindex=function(t,k,v)" &
             "assert(t==v and k==200);collectgarbage();rawset(t,k,v)" &
             "end});T.testC('seti -1 200',a);assert(a[200]==a)");
   end Integer_Self_Handler;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "API driver: integer self value",
                        Integer_Self_Value'Access);
      Test_Support.Add (Suite, "API driver: field self value",
                        Field_Self_Value'Access);
      Test_Support.Add (Suite, "API driver: integer self handler",
                        Integer_Self_Handler'Access);
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
      Test_Support.Add (Suite, "Panic: actual selected callback",
                        Panic_Trivial'Access);
      Test_Support.Add (Suite, "Panic: retained thread status",
                        Panic_Status'Access);
      Test_Support.Add (Suite, "Panic: actual usable child stack",
                        Panic_Stack'Access);
      Test_Support.Add (Suite, "Panic: argument error without frames",
                        Panic_Argument'Access);
      Test_Support.Add (Suite, "Panic: shared provider memory error",
                        Panic_Memory'Access);
      Test_Support.Add (Suite, "Panic: closes before callback",
                        Panic_Closing'Access);
      Test_Support.Add (Suite, "Panic: failing closer replaces error",
                        Panic_Close_Error'Access);
      Test_Support.Add (Suite, "Panic: status after successful close walk",
                        Panic_Closing_Status'Access);
      Test_Support.Add (Suite, "Panic: no-error cleanup",
                        Panic_No_Error'Access);
      Test_Support.Add (Suite, "API driver: count preserves actual stack",
                        Count_Restores_Stack'Access);
      Test_Support.Add (Suite, "Test provider: child byte ceiling",
                        Child_Byte_Limit'Access);
      Test_Support.Add (Suite, "Test provider: child growth countdown",
                        Child_Count_Limit'Access);
      Test_Support.Add (Suite, "API driver: public file load",
                        Loaded_File'Access);
      Test_Support.Add (Suite, "API driver: oversized userdata diagnostic",
                        Oversized_Userdata'Access);
      Test_Support.Add (Suite, "Panic: provider refusal cleanup sweep",
                        Panic_Refusal_Sweep'Access);
      Test_Support.Add (Suite, "Primitive NOT: false under refusal",
                        Not_False'Access);
      Test_Support.Add (Suite, "Primitive NOT: nil under refusal",
                        Not_Nil'Access);
      Test_Support.Add (Suite, "Primitive NOT: zero under refusal",
                        Not_Zero'Access);
      Test_Support.Add (Suite, "Primitive NOT: empty string under refusal",
                        Not_Empty_String'Access);
      Test_Support.Add (Suite, "Primitive NOT: table under refusal",
                        Not_Table'Access);
      Test_Support.Add (Suite, "Primitive NOT: function under refusal",
                        Not_Function'Access);
   end Register;
end Lua.API_Command_Tests;
