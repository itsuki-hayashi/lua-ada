with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Runtime_Inspection_Tests is
   LF : constant Character := Character'Val (10);

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Raw_Protected_Table;
   procedure Raw_Protected_Table is
   begin
      --  Inspect a protected table through debug and ordinary base
      --  operations.
      --  Debug sees the actual table while the public protection value
      --  remains intact.
      Check
        ("local m={__metatable='locked'};local t=setmetatable({},m)" & LF &
         "assert(getmetatable(t)=='locked')" & LF &
         "assert(debug.getmetatable(t)==m)" & LF &
         "local n={};assert(debug.setmetatable(t,n)==t)" & LF &
         "assert(getmetatable(t)==n)");
   end Raw_Protected_Table;

   procedure Shared_Number_Type;
   procedure Shared_Number_Type is
   begin
      --  Install a number metatable through an integer value.
      --  Integers and floats share one type entry; primitive arithmetic still
      --  wins.
      Check
        ("local m={__index={answer=42},__add=function()return 99 end}" & LF &
         "debug.setmetatable(1,m)" & LF &
         "assert(debug.getmetatable(1.5)==m and (1.5).answer==42)" & LF &
         "assert(1+2==3)" & LF &
         "debug.setmetatable(1.5,nil);assert(getmetatable(1)==nil)");
   end Shared_Number_Type;

   procedure Nil_Type_Handlers;
   procedure Nil_Type_Handlers is
   begin
      --  Install index and call handlers on the nil type.
      --  Scalar nil values retain no object pointer and use the session type
      --  root.
      Check
        ("local m={__index={answer=42},__call=function(x,a)" & LF &
         "assert(x==nil);return a end}" & LF &
         "debug.setmetatable(nil,m);local x=nil" & LF &
         "assert(x.answer==42 and x(17)==17)" & LF &
         "assert(getmetatable(nil)==m)");
   end Nil_Type_Handlers;

   procedure Boolean_Type_Handlers;
   procedure Boolean_Type_Handlers is
   begin
      --  Attach a handler through false and operate through true.
      --  One boolean type table applies to both values with ordinary operand
      --  order.
      Check
        ("local m={__add=function(a,b)assert(a==true and b==4)" & LF &
         "return 42 end}" & LF &
         "debug.setmetatable(false,m)" & LF &
         "assert(debug.getmetatable(true)==m and true+4==42)");
   end Boolean_Type_Handlers;

   procedure Shared_Function_Type;
   procedure Shared_Function_Type is
   begin
      --  Attach metadata through a Lua closure and inspect a builtin.
      --  Lua/native function representations share the same Lua function
      --  type.
      Check
        ("local m={};local f=function()end" & LF &
         "debug.setmetatable(f,m)" & LF &
         "assert(debug.getmetatable(print)==m)" & LF &
         "assert(debug.getmetatable(string.sub)==m)" & LF &
         "assert(debug.getmetatable(function()end)==m)");
   end Shared_Function_Type;

   procedure Shared_Thread_Type;
   procedure Shared_Thread_Type is
   begin
      --  Install a thread metatable on a fresh coroutine.
      --  Main and independently created threads use the same type
      --  association.
      Check
        ("local t=coroutine.create(function()end);local m={}" & LF &
         "debug.setmetatable(t,m)" & LF &
         "assert(debug.getmetatable(coroutine.running())==m)" & LF &
         "local other=coroutine.create(function()end)" & LF &
         "assert(debug.getmetatable(other)==m)");
   end Shared_Thread_Type;

   procedure Type_Metatable_Root;
   procedure Type_Metatable_Root is
   begin
      --  Release local ownership of a type metatable and force tracing.
      --  The universe type slot roots its callbacks and captures until
      --  replacement.
      Check
        ("do local answer={42}" & LF &
         "debug.setmetatable(false,{__index=function()" & LF &
         "return answer[1]end})" & LF &
         "end" & LF &
         "collectgarbage();assert((false).value==42)" & LF &
         "debug.setmetatable(false,nil)" & LF &
         "collectgarbage();assert(debug.getmetatable(false)==nil)");
   end Type_Metatable_Root;

   procedure Metatable_Argument_Checks;
   procedure Metatable_Argument_Checks is
   begin
      --  Call debug metatable functions with absent or invalid arguments.
      --  Missing values differ from explicit nil and failure remains
      --  protected.
      Check
        ("assert(not pcall(debug.getmetatable))" & LF &
         "assert(not pcall(debug.setmetatable,{}))" & LF &
         "assert(not pcall(debug.setmetatable,{},false))" & LF &
         "assert(debug.getmetatable(nil)==nil)" & LF &
         "assert(debug.setmetatable(nil,nil)==nil)");
   end Metatable_Argument_Checks;

   procedure Join_Shared_Mutation;
   procedure Join_Shared_Mutation is
   begin
      --  Join two independently captured lexical cells.
      --  Subsequent closure writes and debug.setupvalue mutate the same real
      --  cell.
      Check
        ("local function make(x)return function(v)" & LF &
         "if v~=nil then x=v end;return x end end" & LF &
         "local a,b=make(1),make(2)" & LF &
         "debug.upvaluejoin(a,1,b,1)" & LF &
         "assert(a()==2 and a(42)==42 and b()==42)" & LF &
         "assert(debug.setupvalue(b,1,17)=='x' and a()==17)");
   end Join_Shared_Mutation;

   procedure Join_Identity;
   procedure Join_Identity is
   begin
      --  Record a surviving original cell then rebind one closure upvalue.
      --  Joining changes the actual identity without rewriting other
      --  captures.
      Check
        ("local function make(x)return function()return x end," & LF &
         "function()return x end end" & LF &
         "local a,old=make(1);local b=make(2)" & LF &
         "local first=debug.upvalueid(a,1)" & LF &
         "debug.upvaluejoin(a,1,b,1)" & LF &
         "assert(debug.upvalueid(a,1)==debug.upvalueid(b,1))" & LF &
         "assert(debug.upvalueid(old,1)==first and old()==1 and a()==2)");
   end Join_Identity;

   procedure Join_Collection;
   procedure Join_Collection is
   begin
      --  Join a table-valued cell and drop the original owner closure.
      --  The joined cell and payload survive collection independently of that
      --  closure.
      Check
        ("local function make(x)return function()return x end end" & LF &
         "local a=make({1})" & LF &
         "do local b=make({42});debug.upvaluejoin(a,1,b,1)end" & LF &
         "collectgarbage();assert(a()[1]==42)");
   end Join_Collection;

   procedure Join_Validation;
   procedure Join_Validation is
   begin
      --  Exercise invalid indexes, native functions and zero-result joining.
      --  Bad joins are protected errors and valid self-join returns no Lua
      --  values.
      Check
        ("local x=1;local function f()return x end" & LF &
         "assert(not pcall(debug.upvaluejoin,f,0,f,1))" & LF &
         "assert(not pcall(debug.upvaluejoin,f,1,f,2))" & LF &
         "assert(not pcall(debug.upvaluejoin,print,1,f,1))" & LF &
         "assert(select('#',debug.upvaluejoin(f,1,f,1))==0)");
   end Join_Validation;

   procedure Setupvalue_Requires_Value;
   procedure Setupvalue_Requires_Value is
   begin
      --  Omit a setter value, then explicitly assign nil.
      --  An absent argument fails before mutation; explicit nil remains
      --  valid.
      Check
        ("local x=42;local function f()return x end" & LF &
         "assert(not pcall(debug.setupvalue,f,1));assert(f()==42)" & LF &
         "assert(debug.setupvalue(f,1,nil)=='x')" & LF &
         "assert(f()==nil)");
   end Setupvalue_Requires_Value;

   procedure Real_Registry_Identity;
   procedure Real_Registry_Identity is
   begin
      --  Read registry roots and package registries through the Lua debug
      --  API.
      --  Repeated reads expose actual session tables and the real main
      --  thread.
      Check
        ("local r=debug.getregistry();assert(r==debug.getregistry())" & LF &
         "assert(r[2]==_G and r[3]==coroutine.running())" & LF &
         "assert(r._LOADED==package.loaded)" & LF &
         "assert(r._PRELOAD==package.preload)" & LF &
         "r.answer=42;assert(debug.getregistry().answer==42)");
   end Real_Registry_Identity;

   procedure Missing_Upvalue_Identity;
   procedure Missing_Upvalue_Identity is
   begin
      --  Ask for indexes outside Lua and native function capture ranges.
      --  Lua 5.5 returns one nil rather than raising or exposing an invalid
      --  cell.
      Check
        ("local x=1;local function f()return x end" & LF &
         "assert(debug.upvalueid(f,0)==nil)" & LF &
         "assert(debug.upvalueid(f,2)==nil)" & LF &
         "assert(debug.upvalueid(print,1)==nil)" & LF &
         "assert(select('#',debug.upvalueid(f,2))==1)" & LF &
         "assert(not pcall(debug.upvalueid,{},1))");
   end Missing_Upvalue_Identity;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "inspection: raw protected table",
         Raw_Protected_Table'Access);
      Test_Support.Add
        (Suite, "inspection: shared number type",
         Shared_Number_Type'Access);
      Test_Support.Add
        (Suite, "inspection: nil type handlers",
         Nil_Type_Handlers'Access);
      Test_Support.Add
        (Suite, "inspection: boolean type handlers",
         Boolean_Type_Handlers'Access);
      Test_Support.Add
        (Suite, "inspection: shared function type",
         Shared_Function_Type'Access);
      Test_Support.Add
        (Suite, "inspection: shared thread type",
         Shared_Thread_Type'Access);
      Test_Support.Add
        (Suite, "inspection: type metatable root",
         Type_Metatable_Root'Access);
      Test_Support.Add
        (Suite, "inspection: metatable argument checks",
         Metatable_Argument_Checks'Access);
      Test_Support.Add
        (Suite, "inspection: join shared mutation",
         Join_Shared_Mutation'Access);
      Test_Support.Add
        (Suite, "inspection: join identity",
         Join_Identity'Access);
      Test_Support.Add
        (Suite, "inspection: join collection",
         Join_Collection'Access);
      Test_Support.Add
        (Suite, "inspection: join validation",
         Join_Validation'Access);
      Test_Support.Add
        (Suite, "inspection: setupvalue requires value",
         Setupvalue_Requires_Value'Access);
      Test_Support.Add
        (Suite, "inspection: real registry identity",
         Real_Registry_Identity'Access);
      Test_Support.Add
        (Suite, "inspection: missing upvalue identity",
         Missing_Upvalue_Identity'Access);
   end Register;
end Runtime_Inspection_Tests;
