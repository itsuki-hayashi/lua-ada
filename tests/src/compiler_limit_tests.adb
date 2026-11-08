with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Compiler_Limit_Tests is
   Prelude : constant String :=
     "local shapes = {" & ASCII.LF &
     " {'local a', ',a', ';', ''}," & ASCII.LF &
     " {'local a', ',a', '= 1', ',1'}," & ASCII.LF &
     " {'local a', ',a', '= f()', ''}," & ASCII.LF &
     " {'local a; a', ',a', '= 1', ',1'}," & ASCII.LF &
     " {'local a; a=', '{', '0', '}'}," & ASCII.LF &
     " {'return ', '(', '2', ')', 2}," & ASCII.LF &
     " {'local function a(x)return x end; return ', " &
     "'a(', '2.2', ')', 2.2}," & ASCII.LF &
     " {'', 'do ', '', ' end'}," & ASCII.LF &
     " {'', 'while a do ', '', ' end'}," & ASCII.LF &
     " {'local a; ', 'if a then else ', '', ' end'}," & ASCII.LF &
     " {'', 'function foo() ', '', ' end'}," & ASCII.LF &
     " {""local a=''; return "", 'a..', ""'a'"", '', 'a'}," & ASCII.LF &
     " {'local a=1; return ', 'a^', 'a', '', 1}," & ASCII.LF &
     "}" & ASCII.LF &
     "local function check(i)" & ASCII.LF &
     " local p=shapes[i]" & ASCII.LF &
     " local function code(n)return p[1]..p[2]:rep(n).." &
     "p[3]..p[4]:rep(n)end" & ASCII.LF &
     " local f,e=load(code(100),'=compiler-limit')" & ASCII.LF &
     " assert(f,e)" & ASCII.LF &
     " if p[5]~=nil then assert(f()==p[5])end" & ASCII.LF &
     " local ok,f,e=pcall(load,code(500),'=compiler-limit')" & ASCII.LF &
     " assert(ok and f==nil and type(e)=='string')" & ASCII.LF &
     " assert(e:find('too many',1,true) or " &
     "e:find('overflow',1,true),e)" & ASCII.LF &
     " assert(assert(load('return 37'))()==37)" & ASCII.LF &
     "end" & ASCII.LF &
     "local cases={}" & ASCII.LF &
     "for i=1,#shapes do local n=i;" &
     "cases[n]=function()check(n)end end" & ASCII.LF &
     "local source='return '..('('):rep(500)..'1'..(')'):rep(500)" & ASCII.LF &
     "local function reader()" & ASCII.LF &
     " local sent=false" & ASCII.LF &
     " return function()if not sent then sent=true;" &
     "return source end end" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[14]=function()" & ASCII.LF &
     "local ok,f,e=pcall(load,reader(),'=reader-limit')" & ASCII.LF &
     "assert(ok and f==nil and type(e)=='string')" & ASCII.LF &
     "assert(e:find('too many',1,true) or " &
     "e:find('overflow',1,true))" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[15]=function()" & ASCII.LF &
     "local saved=load" & ASCII.LF &
     "local function invoke(f,...)return f(...)end" & ASCII.LF &
     "local ok,f,e=pcall(invoke,saved,reader()," &
     "'=direct-reader-limit')" & ASCII.LF &
     "assert(ok and f==nil and type(e)=='string')" & ASCII.LF &
     "assert(e:find('too many',1,true) or " &
     "e:find('overflow',1,true))" & ASCII.LF &
     "end";
   procedure Check (Which : Positive);
   procedure Uninitialized_Locals;
   procedure Initialized_Locals;
   procedure Call_Initialized_Locals;
   procedure Assignments;
   procedure Constructors;
   procedure Parentheses;
   procedure Nested_Calls;
   procedure Do_Blocks;
   procedure While_Blocks;
   procedure Conditional_Blocks;
   procedure Function_Bodies;
   procedure Concatenations;
   procedure Powers;
   procedure Reader;
   procedure Saved_Reader;
   procedure Bounded_Quota;

   procedure Check (Which : Positive) is
      State : Session;
      Result : Execution_Result;
   begin
      --  Real compatible compilation accepts the small program, catches the
      --  excessive one through load, then compiles and runs a fresh chunk.
      State.Set_Execution_Policy (Lua_Compatible);
      Result := State.Execute
        (Prelude & ASCII.LF & "cases[" & Positive'Image (Which) & "]()");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Protect the native-paired uninitialized locals limit contract.
   procedure Uninitialized_Locals is
   begin
      Check (1);
   end Uninitialized_Locals;

   --  Protect the native-paired initialized locals limit contract.
   procedure Initialized_Locals is
   begin
      Check (2);
   end Initialized_Locals;

   --  Protect the native-paired call initialized locals limit contract.
   procedure Call_Initialized_Locals is
   begin
      Check (3);
   end Call_Initialized_Locals;

   --  Protect the native-paired assignments limit contract.
   procedure Assignments is
   begin
      Check (4);
   end Assignments;

   --  Protect the native-paired constructors limit contract.
   procedure Constructors is
   begin
      Check (5);
   end Constructors;

   --  Protect the native-paired parentheses limit contract.
   procedure Parentheses is
   begin
      Check (6);
   end Parentheses;

   --  Protect the native-paired nested calls limit contract.
   procedure Nested_Calls is
   begin
      Check (7);
   end Nested_Calls;

   --  Protect the native-paired do blocks limit contract.
   procedure Do_Blocks is
   begin
      Check (8);
   end Do_Blocks;

   --  Protect the native-paired while blocks limit contract.
   procedure While_Blocks is
   begin
      Check (9);
   end While_Blocks;

   --  Protect the native-paired conditional blocks limit contract.
   procedure Conditional_Blocks is
   begin
      Check (10);
   end Conditional_Blocks;

   --  Protect the native-paired function bodies limit contract.
   procedure Function_Bodies is
   begin
      Check (11);
   end Function_Bodies;

   --  Protect the native-paired concatenations limit contract.
   procedure Concatenations is
   begin
      Check (12);
   end Concatenations;

   --  Protect the native-paired powers limit contract.
   procedure Powers is
   begin
      Check (13);
   end Powers;

   --  Protect the native-paired reader limit contract.
   procedure Reader is
   begin
      Check (14);
   end Reader;

   --  Protect the native-paired saved reader limit contract.
   procedure Saved_Reader is
   begin
      Check (15);
   end Saved_Reader;

   procedure Bounded_Quota is
      State : Session;
      Result : Execution_Result;
   begin
      --  Lua protection cannot absorb the host's explicit nesting quota.
      State.Set_Limits ((Syntax_Depth => 20, others => <>));
      Result := State.Execute
        ("local s='return '..string.rep('(',100)..'1'.." &
         "string.rep(')',100);pcall(load,s);" &
         "error('host quota became catchable')");
      Assert (Result.Status = Resource_Error,
              "bounded nesting remains a typed host resource failure");
      Result := State.Execute ("assert(6*7==42)");
      Assert (Result.Status = Succeeded,
              "bounded host recovers after compilation quota rejection");
   end Bounded_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "compiler limit: uninitialized locals",
         Uninitialized_Locals'Access);
      Test_Support.Add
        (Suite, "compiler limit: initialized locals",
         Initialized_Locals'Access);
      Test_Support.Add
        (Suite, "compiler limit: call initialized locals",
         Call_Initialized_Locals'Access);
      Test_Support.Add
        (Suite, "compiler limit: assignments",
         Assignments'Access);
      Test_Support.Add
        (Suite, "compiler limit: constructors",
         Constructors'Access);
      Test_Support.Add
        (Suite, "compiler limit: parentheses",
         Parentheses'Access);
      Test_Support.Add
        (Suite, "compiler limit: nested calls",
         Nested_Calls'Access);
      Test_Support.Add
        (Suite, "compiler limit: do blocks",
         Do_Blocks'Access);
      Test_Support.Add
        (Suite, "compiler limit: while blocks",
         While_Blocks'Access);
      Test_Support.Add
        (Suite, "compiler limit: conditional blocks",
         Conditional_Blocks'Access);
      Test_Support.Add
        (Suite, "compiler limit: function bodies",
         Function_Bodies'Access);
      Test_Support.Add
        (Suite, "compiler limit: concatenations",
         Concatenations'Access);
      Test_Support.Add
        (Suite, "compiler limit: powers",
         Powers'Access);
      Test_Support.Add
        (Suite, "compiler limit: reader",
         Reader'Access);
      Test_Support.Add
        (Suite, "compiler limit: saved reader",
         Saved_Reader'Access);
      Test_Support.Add
        (Suite, "compiler limit: bounded quota",
         Bounded_Quota'Access);
   end Register;
end Compiler_Limit_Tests;
