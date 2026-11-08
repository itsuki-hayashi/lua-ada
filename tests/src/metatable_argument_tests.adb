with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Metatable_Argument_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Missing_Receiver;
   procedure Missing_Receiver is
   begin
      --  The required receiver distinguishes no value from nil.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[setmetatable()]" &
         "=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #1 to 'setmetatable" &
         "' (table expected, got no value)]=],tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Missing_Receiver;

   procedure Nil_Receiver;
   procedure Nil_Receiver is
   begin
      --  An explicit nil receiver keeps the first argument's actual type.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[setmetatable(ni" &
         "l)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #1 to 'setmetatable" &
         "' (table expected, got nil)]=],tostring(" &
         "e))" & ASCII.LF &
         "end");
   end Nil_Receiver;

   procedure Receiver_First;
   procedure Receiver_First is
   begin
      --  An invalid receiver is checked before an invalid metatable.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[setmetatable(7," &
         "false)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #1 to 'setmetatable" &
         "' (table expected, got number)]=],tostri" &
         "ng(e))" & ASCII.LF &
         "end");
   end Receiver_First;

   procedure Named_Receiver;
   procedure Named_Receiver is
   begin
      --  The receiver check preserves its raw auxiliary type name.
      Check
        ("do" & ASCII.LF &
         "  local previous=debug.getmetatable(fals" &
         "e);debug.setmetatable(false,{__name='Seq" &
         "uence'})" & ASCII.LF &
         "  local f=assert(load([=[setmetatable(fa" &
         "lse,nil)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  debug.setmetatable(false,previous)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #1 to 'setmetatable" &
         "' (table expected, got Sequence)]=],tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Named_Receiver;

   procedure Missing_Metatable;
   procedure Missing_Metatable is
   begin
      --  An absent metatable is rejected rather than treated as explicit
      --  nil.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[setmetatable({}" &
         ")]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #2 to 'setmetatable" &
         "' (nil or table expected, got no value)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Missing_Metatable;

   procedure Boolean_Metatable;
   procedure Boolean_Metatable is
   begin
      --  The second argument retains its allowed categories and type.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[setmetatable({}" &
         ",false)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #2 to 'setmetatable" &
         "' (nil or table expected, got boolean)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Boolean_Metatable;

   procedure Number_Metatable;
   procedure Number_Metatable is
   begin
      --  A numeric metatable is rejected without string coercion.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[setmetatable({}" &
         ",7)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #2 to 'setmetatable" &
         "' (nil or table expected, got number)]=]" &
         ",tostring(e))" & ASCII.LF &
         "end");
   end Number_Metatable;

   procedure Named_Metatable;
   procedure Named_Metatable is
   begin
      --  The invalid metatable check shares the raw auxiliary type policy.
      Check
        ("do" & ASCII.LF &
         "  local previous=debug.getmetatable(fals" &
         "e);debug.setmetatable(false,{__name='Met" &
         "adata'})" & ASCII.LF &
         "  local f=assert(load([=[setmetatable({}" &
         ",false)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  debug.setmetatable(false,previous)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #2 to 'setmetatable" &
         "' (nil or table expected, got Metadata)]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Named_Metatable;

   procedure Argument_Before_Protection;
   procedure Argument_Before_Protection is
   begin
      --  Second-argument validation precedes the protected-metatable lookup.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[local t=setmeta" &
         "table({},{__metatable='locked'});setmeta" &
         "table(t,false)]=],'=metatable-argument')" &
         ")" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #2 to 'setmetatable" &
         "' (nil or table expected, got boolean)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Argument_Before_Protection;

   procedure Method_Self;
   procedure Method_Self is
   begin
      --  A colon call diagnoses its actual invalid self.
      Check
        ("do" & ASCII.LF &
         "  string.setmetatable=setmetatable" & ASCII.LF &
         "  local f=assert(load([=[('abc'):setmeta" &
         "table({})]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  string.setmetatable=nil" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: calling 'setmetatable' on bad se" &
         "lf (table expected, got string)]=],tostr" &
         "ing(e))" & ASCII.LF &
         "end");
   end Method_Self;

   procedure Method_Argument;
   procedure Method_Argument is
   begin
      --  A valid table self shifts the metatable's regular argument index.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[local t={setmet" &
         "atable=setmetatable};t:setmetatable(fals" &
         "e)]=],'=metatable-argument'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[metatable-argu" &
         "ment:1: bad argument #1 to 'setmetatable" &
         "' (nil or table expected, got boolean)]=" &
         "],tostring(e))" & ASCII.LF &
         "end");
   end Method_Argument;

   procedure Gsub_Callback;
   procedure Gsub_Callback is
   begin
      --  A real gsub C caller obtains the actual setmetatable registry name.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load([=[string.gsub('s'" &
         ",'s',setmetatable)]=],'=metatable-argume" &
         "nt'))" & ASCII.LF &
         "  local ok,e=pcall(f)" & ASCII.LF &
         "  assert(not ok and e==[=[bad argument #" &
         "1 to 'setmetatable' (table expected, got" &
         " string)]=],tostring(e))" & ASCII.LF &
         "end");
   end Gsub_Callback;

   procedure Explicit_Nil;
   procedure Explicit_Nil is
   begin
      --  Explicit nil removes the actual metatable and returns the receiver.
      Check
        ("do" & ASCII.LF &
         "  local t=setmetatable({},{__index={valu" &
         "e=7}})" & ASCII.LF &
         "  assert(t.value==7 and setmetatable(t,n" &
         "il)==t and getmetatable(t)==nil and t.va" &
         "lue==nil)" & ASCII.LF &
         "end");
   end Explicit_Nil;

   procedure Actual_Table;
   procedure Actual_Table is
   begin
      --  A valid table installs actual lookup behavior and preserves
      --  identity.
      Check
        ("do" & ASCII.LF &
         "  local t,mt={},{__index={value=7}}" & ASCII.LF &
         "  assert(setmetatable(t,mt)==t and getme" &
         "tatable(t)==mt and t.value==7)" & ASCII.LF &
         "end");
   end Actual_Table;

   procedure Registry_Roots;
   procedure Registry_Roots is
   begin
      --  Diagnostic lookup sees actual slot mutation and no stale operand
      --  edge.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local load" &
         "ed,mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "});local calls=0" & ASCII.LF &
         "  local function make()local value=funct" &
         "ion()end;weak[1]=value;return value end" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=" &
         "function(_,k)" & ASCII.LF &
         "    assert(k=='_LOADED' and debug.getinf" &
         "o(2,'f').func==setmetatable)" & ASCII.LF &
         "    assert(debug.setlocal(2,2,nil)=='(C " &
         "temporary)')" & ASCII.LF &
         "    collectgarbage();assert(weak[1]==nil" &
         ");calls=calls+1;return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(setmetatable,{},make(" &
         "))" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==1 and e==""bad" &
         " argument #2 to 'setmetatable' (nil or t" &
         "able expected, got function)"",tostring(e" &
         "))" & ASCII.LF &
         "end");
   end Registry_Roots;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "metatable arguments: missing receiver",
         Missing_Receiver'Access);
      Test_Support.Add
        (Suite, "metatable arguments: nil receiver",
         Nil_Receiver'Access);
      Test_Support.Add
        (Suite, "metatable arguments: receiver first",
         Receiver_First'Access);
      Test_Support.Add
        (Suite, "metatable arguments: named receiver",
         Named_Receiver'Access);
      Test_Support.Add
        (Suite, "metatable arguments: missing metatable",
         Missing_Metatable'Access);
      Test_Support.Add
        (Suite, "metatable arguments: boolean metatable",
         Boolean_Metatable'Access);
      Test_Support.Add
        (Suite, "metatable arguments: number metatable",
         Number_Metatable'Access);
      Test_Support.Add
        (Suite, "metatable arguments: named metatable",
         Named_Metatable'Access);
      Test_Support.Add
        (Suite, "metatable arguments: argument before protection",
         Argument_Before_Protection'Access);
      Test_Support.Add
        (Suite, "metatable arguments: method self",
         Method_Self'Access);
      Test_Support.Add
        (Suite, "metatable arguments: method argument",
         Method_Argument'Access);
      Test_Support.Add
        (Suite, "metatable arguments: gsub callback",
         Gsub_Callback'Access);
      Test_Support.Add
        (Suite, "metatable arguments: explicit nil",
         Explicit_Nil'Access);
      Test_Support.Add
        (Suite, "metatable arguments: actual table",
         Actual_Table'Access);
      Test_Support.Add
        (Suite, "metatable arguments: registry roots",
         Registry_Roots'Access);
   end Register;
end Metatable_Argument_Tests;
