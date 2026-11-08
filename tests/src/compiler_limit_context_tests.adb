with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Compiler_Limit_Context_Tests is
   Prelude : constant String :=
     "local cases={}" & ASCII.LF &
     "local function names(prefix,n)" & ASCII.LF &
     " local t={} for i=1,n do t[i]=prefix..i end retu" &
     "rn table.concat(t,',')" & ASCII.LF &
     "end" & ASCII.LF &
     "local function rejected(source,kind,where)" & ASCII.LF &
     " local f,e=load(source,'=limit-context')" & ASCII.LF &
     " assert(f==nil and type(e)=='string')" & ASCII.LF &
     " assert(e:find('too many '..kind,1,true),e)" & ASCII.LF &
     " assert(e:find(where,1,true),e)" & ASCII.LF &
     " assert(assert(load('return 42'))()==42)" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[1]=function()" & ASCII.LF &
     " rejected('local '..names('a',201),'local variab" &
     "les','in main function')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[2]=function()" & ASCII.LF &
     " rejected('\n\n\nreturn function()\nlocal '..nam" &
     "es('a',201)..'\nend'," & ASCII.LF &
     "          'local variables','in function at line" &
     " 4')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[3]=function()" & ASCII.LF &
     " rejected('\nreturn function('..names('a',201).." &
     "')end'," & ASCII.LF &
     "          'local variables','in function at line" &
     " 2')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[4]=function()" & ASCII.LF &
     " local f=assert(load('local '..names('a',200)..'" &
     ";return a200'))" & ASCII.LF &
     " assert(select('#',f())==1 and f()==nil)" & ASCII.LF &
     "end" & ASCII.LF &
     "local function captured(n)" & ASCII.LF &
     " local a,b,values={}, {},{}" & ASCII.LF &
     " for i=1,127 do a[i]='a'..i end" & ASCII.LF &
     " for i=1,n do b[i]='b'..i end" & ASCII.LF &
     " for i=1,math.max(n,127)do values[i]='0' end" & ASCII.LF &
     " local function zeros(k)return table.concat(valu" &
     "es,',',1,k)end" & ASCII.LF &
     " return 'local '..table.concat(a,',')..'='..zero" &
     "s(127)..'\n'.." & ASCII.LF &
     " 'return function()\nlocal '..table.concat(b,','" &
     ")..'='..zeros(n)..'\n'.." & ASCII.LF &
     " 'return function()return '..table.concat(a,'+')" &
     "..'+'..table.concat(b,'+')..' end\nend'" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[5]=function()" & ASCII.LF &
     " local maker=assert(load(captured(128)))()" & ASCII.LF &
     " local f=maker()" & ASCII.LF &
     " assert(debug.getinfo(f,'u').nups==255 and f()==" &
     "0)" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[6]=function()" & ASCII.LF &
     " rejected(captured(129),'upvalues','in function " &
     "at line 4')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[7]=function()" & ASCII.LF &
     " rejected('\nfunction foo()\nlocal '..names('a'," &
     "200)..',b\n'," & ASCII.LF &
     "          'local variables','in function at line" &
     " 2')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[8]=function()" & ASCII.LF &
     " rejected('\nreturn function('..names('a',201)," & ASCII.LF &
     "          'local variables','in function at line" &
     " 2')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[9]=function()" & ASCII.LF &
     " local source='do local '..names('a',200)..' end" &
     "; do local '..names('b',200)..' end'" & ASCII.LF &
     " assert(load(source))()" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[10]=function()" & ASCII.LF &
     " local source='local '..names('a',200)..';return" &
     " function()local '.." & ASCII.LF &
     "              names('b',200)..';return a1,b200 e" &
     "nd'" & ASCII.LF &
     " local f=assert(load(source))()" & ASCII.LF &
     " local result=table.pack(f())" & ASCII.LF &
     " assert(result.n==2 and result[1]==nil and resul" &
     "t[2]==nil)" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[11]=function()" & ASCII.LF &
     " local parts={}" & ASCII.LF &
     " for i=1,201 do parts[i]='local k'..i..' <const>" &
     " = '..i end" & ASCII.LF &
     " parts[#parts+1]='return k201'" & ASCII.LF &
     " local f,e=load(table.concat(parts,'\n'))" & ASCII.LF &
     " assert(f,e);assert(f()==201)" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[12]=function()" & ASCII.LF &
     " local f,e=load('local '..names('a',200)..';loca" &
     "l last<const> = 37;return last')" & ASCII.LF &
     " assert(f,e);assert(f()==37)" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[13]=function()" & ASCII.LF &
     " rejected('local '..names('a',200)..';local last" &
     "<const> = select(1,37)'," & ASCII.LF &
     "          'local variables','in main function')" & ASCII.LF &
     "end" & ASCII.LF &
     "cases[14]=function()" & ASCII.LF &
     " local f,e=load('local '..names('a',201)..' =')" & ASCII.LF &
     " assert(f==nil and type(e)=='string' and e:find(" &
     "'<eof>',1,true))" & ASCII.LF &
     " assert(not e:find('too many local variables',1," &
     "true),e)" & ASCII.LF &
     "end";
   procedure Check (Which : Positive);
   procedure Main_Locals;
   procedure Nested_Locals;
   procedure Parameters;
   procedure Local_Boundary;
   procedure Upvalue_Boundary;
   procedure Nested_Upvalues;
   procedure Incomplete_Body;
   procedure Incomplete_Parameters;
   procedure Expired_Scopes;
   procedure Outer_Locals;
   procedure Many_Folded_Constants;
   procedure Constant_After_Limit;
   procedure Dynamic_Constant_Limit;
   procedure Initializer_Syntax_First;

   procedure Check (Which : Positive) is
      State : Session;
      Result : Execution_Result;
   begin
      State.Set_Execution_Policy (Lua_Compatible);
      Result := State.Execute
        (Prelude & ASCII.LF & "cases[" & Positive'Image (Which) & "]()");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Native-paired main-chunk local overflow identifies the main function.
   procedure Main_Locals is
   begin
      Check (1);
   end Main_Locals;

   --  The native-paired nested local overflow identifies its real opener.
   procedure Nested_Locals is
   begin
      Check (2);
   end Nested_Locals;

   --  The native-paired parameter overflow identifies its function opener.
   procedure Parameters is
   begin
      Check (3);
   end Parameters;

   --  The native-paired exact two-hundred local boundary executes.
   procedure Local_Boundary is
   begin
      Check (4);
   end Local_Boundary;

   --  The native-paired exact two-hundred-fifty-five captures remain live.
   procedure Upvalue_Boundary is
   begin
      Check (5);
   end Upvalue_Boundary;

   --  The native-paired excess captures identify the inner defining function.
   procedure Nested_Upvalues is
   begin
      Check (6);
   end Nested_Upvalues;

   --  The native-paired local overflow precedes missing function end.
   procedure Incomplete_Body is
   begin
      Check (7);
   end Incomplete_Body;

   --  The native-paired parameter overflow precedes missing parenthesis.
   procedure Incomplete_Parameters is
   begin
      Check (8);
   end Incomplete_Parameters;

   --  The native-paired expired scopes do not consume later local limits.
   procedure Expired_Scopes is
   begin
      Check (9);
   end Expired_Scopes;

   --  Outer function locals do not consume the inner local limit.
   procedure Outer_Locals is
   begin
      Check (10);
   end Outer_Locals;

   --  The native-paired many folded constants require no local registers.
   procedure Many_Folded_Constants is
   begin
      Check (11);
   end Many_Folded_Constants;

   --  The native-paired a folded constant fits after two-hundred locals.
   procedure Constant_After_Limit is
   begin
      Check (12);
   end Constant_After_Limit;

   --  The native-paired a dynamic constant still consumes a local register.
   procedure Dynamic_Constant_Limit is
   begin
      Check (13);
   end Dynamic_Constant_Limit;

   --  Initializer syntax precedes register activation limits.
   procedure Initializer_Syntax_First is
   begin
      Check (14);
   end Initializer_Syntax_First;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "compiler context: main locals",
         Main_Locals'Access);
      Test_Support.Add
        (Suite, "compiler context: nested locals",
         Nested_Locals'Access);
      Test_Support.Add
        (Suite, "compiler context: parameters",
         Parameters'Access);
      Test_Support.Add
        (Suite, "compiler context: local boundary",
         Local_Boundary'Access);
      Test_Support.Add
        (Suite, "compiler context: upvalue boundary",
         Upvalue_Boundary'Access);
      Test_Support.Add
        (Suite, "compiler context: nested upvalues",
         Nested_Upvalues'Access);
      Test_Support.Add
        (Suite, "compiler context: incomplete body",
         Incomplete_Body'Access);
      Test_Support.Add
        (Suite, "compiler context: incomplete parameters",
         Incomplete_Parameters'Access);
      Test_Support.Add
        (Suite, "compiler context: expired scopes",
         Expired_Scopes'Access);
      Test_Support.Add
        (Suite, "compiler context: outer locals",
         Outer_Locals'Access);
      Test_Support.Add
        (Suite, "compiler context: many folded constants",
         Many_Folded_Constants'Access);
      Test_Support.Add
        (Suite, "compiler context: constant after limit",
         Constant_After_Limit'Access);
      Test_Support.Add
        (Suite, "compiler context: dynamic constant limit",
         Dynamic_Constant_Limit'Access);
      Test_Support.Add
        (Suite, "compiler context: initializer syntax first",
         Initializer_Syntax_First'Access);
   end Register;
end Compiler_Limit_Context_Tests;
