with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Metamethod_Name_Tests is
   Inspect_Origin : constant String :=
     "local seen=0;local function inspect(expected,result)retur" &
     "n function(...)local i=debug.getinfo(1,'n');assert(i.name" &
     "what=='metamethod' and i.name==expected);seen=seen+1;retu" &
     "rn result end end;";
   --  Inspect only the actual callback frame and count real invocations.

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Inspect_Origin & Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Index_Field;
   procedure Index_Field is
   begin
      --  A field read enters the actual __index callback from GETFIELD.
      Check
        ("local t=setmetatable({},{__index=inspect('index',7)});ass" &
         "ert(t.x==7 and seen==1)");
   end Index_Field;

   procedure Index_Integer;
   procedure Index_Integer is
   begin
      --  An immediate integer read has the same index origin through GETI.
      Check
        ("local t=setmetatable({},{__index=inspect('index',7)});ass" &
         "ert(t[1]==7 and seen==1)");
   end Index_Integer;

   procedure Index_Register;
   procedure Index_Register is
   begin
      --  A register-key read enters index without inventing a call site.
      Check
        ("local t=setmetatable({},{__index=inspect('index',7)});loc" &
         "al k='x';assert(t[k]==7 and seen==1)");
   end Index_Register;

   procedure Index_Environment;
   procedure Index_Environment is
   begin
      --  A captured environment lookup identifies the real GETTABUP origin.
      Check
        ("local env=setmetatable({},{__index=inspect('index',7)});l" &
         "ocal function make()local _ENV=env;return function()retur" &
         "n missing end end;assert(make()()==7 and seen==1)");
   end Index_Environment;

   procedure Newindex_Field;
   procedure Newindex_Field is
   begin
      --  A field store enters its real newindex metamethod.
      Check
        ("local t=setmetatable({},{__newindex=inspect('newindex')})" &
         ";t.x=7;assert(seen==1)");
   end Newindex_Field;

   procedure Newindex_Integer;
   procedure Newindex_Integer is
   begin
      --  An immediate integer store retains the newindex origin.
      Check
        ("local t=setmetatable({},{__newindex=inspect('newindex')})" &
         ";t[1]=7;assert(seen==1)");
   end Newindex_Integer;

   procedure Newindex_Register;
   procedure Newindex_Register is
   begin
      --  A register-key store retains the newindex origin.
      Check
        ("local t=setmetatable({},{__newindex=inspect('newindex')})" &
         ";local k='x';t[k]=7;assert(seen==1)");
   end Newindex_Register;

   procedure Newindex_Environment;
   procedure Newindex_Environment is
   begin
      --  A captured environment store identifies its SETTABUP origin.
      Check
        ("local env=setmetatable({},{__newindex=inspect('newindex')" &
         "});local function make()local _ENV=env;return function()m" &
         "issing=7 end end;make()();assert(seen==1)");
   end Newindex_Environment;

   procedure Add_Registers;
   procedure Add_Registers is
   begin
      --  A normal arithmetic companion selects its actual event field.
      Check
        ("local a=setmetatable({},{__add=inspect('add',7)});local b" &
         "={};assert(a+b==7 and seen==1)");
   end Add_Registers;

   procedure Add_Immediate;
   procedure Add_Immediate is
   begin
      --  An immediate arithmetic companion retains the add event.
      Check
        ("local a=setmetatable({},{__add=inspect('add',7)});assert(" &
         "a+1==7 and seen==1)");
   end Add_Immediate;

   procedure Add_Constant;
   procedure Add_Constant is
   begin
      --  A constant arithmetic companion retains the add event.
      Check
        ("local a=setmetatable({},{__add=inspect('add',7)});assert(" &
         "a+5.5==7 and seen==1)");
   end Add_Constant;

   procedure Subtract;
   procedure Subtract is
   begin
      --  The sub arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__sub=inspect('sub',7)});assert(" &
         "a - 1==7 and seen==1)");
   end Subtract;

   procedure Multiply;
   procedure Multiply is
   begin
      --  The mul arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__mul=inspect('mul',7)});assert(" &
         "a * 1==7 and seen==1)");
   end Multiply;

   procedure Modulo;
   procedure Modulo is
   begin
      --  The mod arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__mod=inspect('mod',7)});assert(" &
         "a % 1==7 and seen==1)");
   end Modulo;

   procedure Power;
   procedure Power is
   begin
      --  The pow arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__pow=inspect('pow',7)});assert(" &
         "a ^ 1==7 and seen==1)");
   end Power;

   procedure Divide;
   procedure Divide is
   begin
      --  The div arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__div=inspect('div',7)});assert(" &
         "a / 1==7 and seen==1)");
   end Divide;

   procedure Floor_Divide;
   procedure Floor_Divide is
   begin
      --  The idiv arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__idiv=inspect('idiv',7)});asser" &
         "t(a // 1==7 and seen==1)");
   end Floor_Divide;

   procedure Bit_And;
   procedure Bit_And is
   begin
      --  The band arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__band=inspect('band',7)});asser" &
         "t(a & 1==7 and seen==1)");
   end Bit_And;

   procedure Bit_Or;
   procedure Bit_Or is
   begin
      --  The bor arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__bor=inspect('bor',7)});assert(" &
         "a | 1==7 and seen==1)");
   end Bit_Or;

   procedure Bit_Xor;
   procedure Bit_Xor is
   begin
      --  The bxor arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__bxor=inspect('bxor',7)});asser" &
         "t(a ~ 1==7 and seen==1)");
   end Bit_Xor;

   procedure Shift_Left;
   procedure Shift_Left is
   begin
      --  The shl arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__shl=inspect('shl',7)});assert(" &
         "a << 1==7 and seen==1)");
   end Shift_Left;

   procedure Shift_Right;
   procedure Shift_Right is
   begin
      --  The shr arithmetic companion exposes its actual metamethod name.
      Check
        ("local a=setmetatable({},{__shr=inspect('shr',7)});assert(" &
         "a >> 1==7 and seen==1)");
   end Shift_Right;

   procedure Unary_Minus;
   procedure Unary_Minus is
   begin
      --  The unm unary opcode exposes its actual metamethod origin.
      Check
        ("local a=setmetatable({},{__unm=inspect('unm',7)});assert(" &
         "-a==7 and seen==1)");
   end Unary_Minus;

   procedure Bit_Not;
   procedure Bit_Not is
   begin
      --  The bnot unary opcode exposes its actual metamethod origin.
      Check
        ("local a=setmetatable({},{__bnot=inspect('bnot',7)});asser" &
         "t(~a==7 and seen==1)");
   end Bit_Not;

   procedure Length;
   procedure Length is
   begin
      --  The len unary opcode exposes its actual metamethod origin.
      Check
        ("local a=setmetatable({},{__len=inspect('len',7)});assert(" &
         "#a==7 and seen==1)");
   end Length;

   procedure Concatenate;
   procedure Concatenate is
   begin
      --  A concatenation callback is named by the actual CONCAT instruction.
      Check
        ("local a=setmetatable({},{__concat=inspect('concat',7)});a" &
         "ssert(a..a==7 and seen==1)");
   end Concatenate;

   procedure Equal;
   procedure Equal is
   begin
      --  The eq comparison opcode reports its actual event.
      Check
        ("local mt={__eq=inspect('eq',true)};local a,b=setmetatable" &
         "({},mt),setmetatable({},mt);assert(a==b and seen==1)");
   end Equal;

   procedure Less;
   procedure Less is
   begin
      --  The lt comparison opcode reports its actual event.
      Check
        ("local mt={__lt=inspect('lt',true)};local a,b=setmetatable" &
         "({},mt),setmetatable({},mt);assert(a<b and seen==1)");
   end Less;

   procedure Less_Equal;
   procedure Less_Equal is
   begin
      --  The le comparison opcode reports its actual event.
      Check
        ("local mt={__le=inspect('le',true)};local a,b=setmetatable" &
         "({},mt),setmetatable({},mt);assert(a<=b and seen==1)");
   end Less_Equal;

   procedure Less_Immediate;
   procedure Less_Immediate is
   begin
      --  Immediate comparison variants retain their real event origin.
      Check
        ("local a=setmetatable({},{__lt=inspect('lt',true)});assert" &
         "(a<1 and seen==1)");
   end Less_Immediate;

   procedure Greater_Immediate;
   procedure Greater_Immediate is
   begin
      --  Immediate comparison variants retain their real event origin.
      Check
        ("local a=setmetatable({},{__lt=inspect('lt',true)});assert" &
         "(1<a and seen==1)");
   end Greater_Immediate;

   procedure Less_Equal_Immediate;
   procedure Less_Equal_Immediate is
   begin
      --  Immediate comparison variants retain their real event origin.
      Check
        ("local a=setmetatable({},{__le=inspect('le',true)});assert" &
         "(a<=1 and seen==1)");
   end Less_Equal_Immediate;

   procedure Greater_Equal_Immediate;
   procedure Greater_Equal_Immediate is
   begin
      --  Immediate comparison variants retain their real event origin.
      Check
        ("local a=setmetatable({},{__le=inspect('le',true)});assert" &
         "(1<=a and seen==1)");
   end Greater_Equal_Immediate;

   procedure Close_Scope;
   procedure Close_Scope is
   begin
      --  A normal scope's CLOSE word names its actual close handler.
      Check
        ("do local x <close> =setmetatable({},{__close=inspect('clo" &
         "se')})end;assert(seen==1)");
   end Close_Scope;

   procedure Close_Return;
   procedure Close_Return is
   begin
      --  A RETURN that closes a binding retains the close origin.
      Check
        ("local function f()local x <close> =setmetatable({},{__clo" &
         "se=inspect('close')});return 7 end;assert(f()==7 and seen" &
         "==1)");
   end Close_Return;

   procedure Close_Error;
   procedure Close_Error is
   begin
      --  An owner unwound to protection cannot supply the error() call name.
      Check
        ("local got;local function f()local x <close> =setmetatable" &
         "({},{__close=function()got=debug.getinfo(1,'n')end});erro" &
         "r('boom')end;assert(not pcall(f));assert(got.namewhat==''" &
         " and got.name==nil)");
   end Close_Error;

   procedure Close_Coroutine;
   procedure Close_Coroutine is
   begin
      --  Coroutine closing has unwound its old yield caller to the base.
      Check
        ("local got;local co=coroutine.create(function()local x <cl" &
         "ose> =setmetatable({},{__close=function()got=debug.getinf" &
         "o(1,'n')end});coroutine.yield()end);assert(coroutine.resu" &
         "me(co));assert(coroutine.close(co));assert(got.namewhat==" &
         "'' and got.name==nil)");
   end Close_Coroutine;

   procedure Close_Tail_Replacement;
   procedure Close_Tail_Replacement is
   begin
      --  A closer tail-calling a helper loses its original call origin.
      Check
        ("local got;local function child()got=debug.getinfo(1,'nt')" &
         "end;do local x <close> =setmetatable({},{__close=function" &
         "()return child()end})end;assert(got.istailcall and got.na" &
         "mewhat=='' and got.name==nil)");
   end Close_Tail_Replacement;

   procedure Close_Descendant;
   procedure Close_Descendant is
   begin
      --  An ordinary descendant of a closer retains its own binding name.
      Check
        ("local got;local function child()got=debug.getinfo(1,'n')e" &
         "nd;do local x <close> =setmetatable({},{__close=function(" &
         ")child()end})end;assert(got.namewhat=='upvalue' and got.n" &
         "ame=='child')");
   end Close_Descendant;

   procedure Close_Traceback;
   procedure Close_Traceback is
   begin
      --  A failed closer remains a real close origin in the error traceback.
      Check
        ("local function f(...)local x <close> =setmetatable({},{__" &
         "close=function()error('@x123')end})end;local ok,msg=xpcal" &
         "l(f,debug.traceback);assert(not ok and msg:find(""in metam" &
         "ethod 'close'"",1,true))");
   end Close_Traceback;

   procedure Finalizer_Origin;
   procedure Finalizer_Origin is
   begin
      --  An actual finalizer entry has the special __gc origin without a PC.
      Check
        ("local got;setmetatable({},{__gc=function()got=debug.getin" &
         "fo(1,'n')end});collectgarbage();assert(got and got.namewh" &
         "at=='metamethod' and got.name=='__gc')");
   end Finalizer_Origin;

   procedure Finalizer_Descendant;
   procedure Finalizer_Descendant is
   begin
      --  An ordinary descendant does not inherit the finalizer origin.
      Check
        ("local got;local function child()got=debug.getinfo(1,'n')e" &
         "nd;setmetatable({},{__gc=function()child()end});collectga" &
         "rbage();assert(got and got.namewhat=='upvalue' and got.na" &
         "me=='child')");
   end Finalizer_Descendant;

   procedure Finalizer_Tail_Replacement;
   procedure Finalizer_Tail_Replacement is
   begin
      --  A finalizer's Lua tail replacement discards its original entry tag.
      Check
        ("local got;local function child()got=debug.getinfo(1,'nt')" &
         "end;setmetatable({},{__gc=function()return child()end});c" &
         "ollectgarbage();assert(got and got.istailcall and got.nam" &
         "ewhat=='' and got.name==nil)");
   end Finalizer_Tail_Replacement;

   procedure Finalizer_Cache_Reset;
   procedure Finalizer_Cache_Reset is
   begin
      --  Later ordinary activations cannot inherit a retired finalizer tag.
      Check
        ("local got;setmetatable({},{__gc=function()got=debug.getin" &
         "fo(1,'n')end});collectgarbage();assert(got and got.name==" &
         "'__gc');local function f()local i=debug.getinfo(1,'n');as" &
         "sert(i.namewhat=='local' and i.name=='f')end;for i=1,5 do" &
         " f()end");
   end Finalizer_Cache_Reset;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "metamethod name: Index_Field", Index_Field'Access);
      Test_Support.Add
        (Suite, "metamethod name: Index_Integer", Index_Integer'Access);
      Test_Support.Add
        (Suite, "metamethod name: Index_Register", Index_Register'Access);
      Test_Support.Add
        (Suite, "metamethod name: Index_Environment",
         Index_Environment'Access);
      Test_Support.Add
        (Suite, "metamethod name: Newindex_Field", Newindex_Field'Access);
      Test_Support.Add
        (Suite, "metamethod name: Newindex_Integer", Newindex_Integer'Access);
      Test_Support.Add
        (Suite, "metamethod name: Newindex_Register",
         Newindex_Register'Access);
      Test_Support.Add
        (Suite, "metamethod name: Newindex_Environment",
         Newindex_Environment'Access);
      Test_Support.Add
        (Suite, "metamethod name: Add_Registers", Add_Registers'Access);
      Test_Support.Add
        (Suite, "metamethod name: Add_Immediate", Add_Immediate'Access);
      Test_Support.Add
        (Suite, "metamethod name: Add_Constant", Add_Constant'Access);
      Test_Support.Add
        (Suite, "metamethod name: Subtract", Subtract'Access);
      Test_Support.Add
        (Suite, "metamethod name: Multiply", Multiply'Access);
      Test_Support.Add
        (Suite, "metamethod name: Modulo", Modulo'Access);
      Test_Support.Add
        (Suite, "metamethod name: Power", Power'Access);
      Test_Support.Add
        (Suite, "metamethod name: Divide", Divide'Access);
      Test_Support.Add
        (Suite, "metamethod name: Floor_Divide", Floor_Divide'Access);
      Test_Support.Add
        (Suite, "metamethod name: Bit_And", Bit_And'Access);
      Test_Support.Add
        (Suite, "metamethod name: Bit_Or", Bit_Or'Access);
      Test_Support.Add
        (Suite, "metamethod name: Bit_Xor", Bit_Xor'Access);
      Test_Support.Add
        (Suite, "metamethod name: Shift_Left", Shift_Left'Access);
      Test_Support.Add
        (Suite, "metamethod name: Shift_Right", Shift_Right'Access);
      Test_Support.Add
        (Suite, "metamethod name: Unary_Minus", Unary_Minus'Access);
      Test_Support.Add
        (Suite, "metamethod name: Bit_Not", Bit_Not'Access);
      Test_Support.Add
        (Suite, "metamethod name: Length", Length'Access);
      Test_Support.Add
        (Suite, "metamethod name: Concatenate", Concatenate'Access);
      Test_Support.Add
        (Suite, "metamethod name: Equal", Equal'Access);
      Test_Support.Add
        (Suite, "metamethod name: Less", Less'Access);
      Test_Support.Add
        (Suite, "metamethod name: Less_Equal", Less_Equal'Access);
      Test_Support.Add
        (Suite, "metamethod name: Less_Immediate", Less_Immediate'Access);
      Test_Support.Add
        (Suite, "metamethod name: Greater_Immediate",
         Greater_Immediate'Access);
      Test_Support.Add
        (Suite, "metamethod name: Less_Equal_Immediate",
         Less_Equal_Immediate'Access);
      Test_Support.Add
        (Suite, "metamethod name: Greater_Equal_Immediate",
         Greater_Equal_Immediate'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Scope", Close_Scope'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Return", Close_Return'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Error", Close_Error'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Coroutine", Close_Coroutine'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Tail_Replacement",
         Close_Tail_Replacement'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Descendant", Close_Descendant'Access);
      Test_Support.Add
        (Suite, "metamethod name: Close_Traceback", Close_Traceback'Access);
      Test_Support.Add
        (Suite, "metamethod name: Finalizer_Origin", Finalizer_Origin'Access);
      Test_Support.Add
        (Suite, "metamethod name: Finalizer_Descendant",
         Finalizer_Descendant'Access);
      Test_Support.Add
        (Suite, "metamethod name: Finalizer_Tail_Replacement",
         Finalizer_Tail_Replacement'Access);
      Test_Support.Add
        (Suite, "metamethod name: Finalizer_Cache_Reset",
         Finalizer_Cache_Reset'Access);
   end Register;
end Metamethod_Name_Tests;
