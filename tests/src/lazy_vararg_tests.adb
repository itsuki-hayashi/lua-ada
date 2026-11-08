with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Lazy_Vararg_Tests is
   Prelude : constant String :=
     "local cases={" & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(keys,t,...v)" & ASCII.LF &
     "      for _,k in pairs(keys)do assert(t[k]==v[k])end" & ASCII.LF &
     "      assert(t.n==v.n)" & ASCII.LF &
     "      return ..." & ASCII.LF &
     "    end" & ASCII.LF &
     "    local t=table.pack(10,20,30)" & ASCII.LF &
     "    local keys={-1,0,1,3,4,1.0,1.1,'n',print,'k','1'}" & ASCII.LF &
     "    f(keys,t,10,20,30)" & ASCII.LF &
     "    local before=collectgarbage('count')" & ASCII.LF &
     "    f(keys,t,10,20,30)" & ASCII.LF &
     "    assert(before==collectgarbage('count'))" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(...v)" & ASCII.LF &
     "      local n,x=debug.getlocal(1,1)" & ASCII.LF &
     "      assert(n=='v' and x==nil)" & ASCII.LF &
     "      return v[1],v.n" & ASCII.LF &
     "    end" & ASCII.LF &
     "    local a,n=f(17,nil,31)" & ASCII.LF &
     "    assert(a==17 and n==3)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(...v)return v end" & ASCII.LF &
     "    local a,b=f(17,nil,31),f(17,nil,31)" & ASCII.LF &
     "    assert(type(a)=='table' and a~=b and a.n==3)" & ASCII.LF &
     "    assert(a[1]==17 and a[2]==nil and a[3]==31)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(...v)v[1]=v[1]+10;v.n=1;return ... end" & ASCII.LF &
     "    local a,b=f(17,31)" & ASCII.LF &
     "    assert(a==27 and b==nil)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(...v)" & ASCII.LF &
     "      return function()return v[1],v.n end" & ASCII.LF &
     "    end" & ASCII.LF &
     "    local g=f(17,nil,31)" & ASCII.LF &
     "    collectgarbage()" & ASCII.LF &
     "    local a,n=g()" & ASCII.LF &
     "    assert(a==17 and n==3)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local count=0" & ASCII.LF &
     "    local function key()count=count+1;return 'n' end" & ASCII.LF &
     "    local function f(...v)return v[key()] end" & ASCII.LF &
     "    assert(f(17,nil,31)==3 and count==1)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(...v)" & ASCII.LF &
     "      assert(debug.setlocal(1,1,{99,n=1})=='v')" & ASCII.LF &
     "      return v[1],v.n" & ASCII.LF &
     "    end" & ASCII.LF &
     "    local a,n=f(17,nil,31)" & ASCII.LF &
     "    assert(a==17 and n==3)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local function f(...v)" & ASCII.LF &
     "      local keys={0,-1,2^63,0/0,1.1,'1',false,print,{}}" & ASCII.LF &
     "      for _,k in ipairs(keys)do assert(v[k]==nil)end" & ASCII.LF &
     "      return v[1],v[2.0],v.n" & ASCII.LF &
     "    end" & ASCII.LF &
     "    local a,b,n=f(17,31)" & ASCII.LF &
     "    assert(a==17 and b==31 and n==2)" & ASCII.LF &
     "  end," & ASCII.LF &
     "  function()" & ASCII.LF &
     "    local out={}" & ASCII.LF &
     "    local function f(...v)" & ASCII.LF &
     "      out[1]=v[1]" & ASCII.LF &
     "      out[v[2]]=v.n" & ASCII.LF &
     "      v[3][1]=37" & ASCII.LF &
     "      local name,value=debug.getlocal(1,1)" & ASCII.LF &
     "      assert(name=='v' and value==nil)" & ASCII.LF &
     "    end" & ASCII.LF &
     "    local nested={}" & ASCII.LF &
     "    f(17,'count',nested)" & ASCII.LF &
     "    assert(out[1]==17 and out.count==3 and nested[1]==37)" & ASCII.LF &
     "  end," & ASCII.LF &
     "}" & ASCII.LF;
   procedure Indexed_No_Table;
   procedure Debug_Nil_Slot;
   procedure Escaping_Table;
   procedure Writable_Table;
   procedure Captured_Table;
   procedure Key_Effects;
   procedure Debug_Write_Ignored;
   procedure Key_Boundaries;
   procedure Assignment_Reads;
   procedure Check (Which : Positive);

   procedure Check (Which : Positive) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        (Prelude & "cases[" & Positive'Image (Which) & "]()");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Warmed direct indexing and expansion create no vararg table object.
   procedure Indexed_No_Table is
   begin
      Check (1);
   end Indexed_No_Table;

   --  A virtual named vararg retains the actual native nil debug slot.
   procedure Debug_Nil_Slot is
   begin
      Check (2);
   end Debug_Nil_Slot;

   --  Bare escaping values use fresh real tables with counted nil holes.
   procedure Escaping_Table is
   begin
      Check (3);
   end Escaping_Table;

   --  Writes materialize the table and expansion obeys its modified n.
   procedure Writable_Table is
   begin
      Check (4);
   end Writable_Table;

   --  Captured named varargs remain rooted real tables after return and GC.
   procedure Captured_Table is
   begin
      Check (5);
   end Captured_Table;

   --  An effectful index expression runs once in the original order.
   procedure Key_Effects is
   begin
      Check (6);
   end Key_Effects;

   --  Debug edits to an optimized nil slot do not replace hidden arguments.
   procedure Debug_Write_Ignored is
   begin
      Check (7);
   end Debug_Write_Ignored;

   --  Integral, fractional, huge, NaN and nonnumeric keys match native.
   procedure Key_Boundaries is
   begin
      Check (8);
   end Key_Boundaries;

   --  RHS values, lvalue keys and nested receivers remain hidden reads.
   procedure Assignment_Reads is
   begin
      Check (9);
   end Assignment_Reads;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "named vararg: indexed no table",
                        Indexed_No_Table'Access);
      Test_Support.Add (Suite, "named vararg: debug nil slot",
                        Debug_Nil_Slot'Access);
      Test_Support.Add (Suite, "named vararg: escaping table",
                        Escaping_Table'Access);
      Test_Support.Add (Suite, "named vararg: writable table",
                        Writable_Table'Access);
      Test_Support.Add (Suite, "named vararg: captured table",
                        Captured_Table'Access);
      Test_Support.Add (Suite, "named vararg: key effects",
                        Key_Effects'Access);
      Test_Support.Add (Suite, "named vararg: debug write ignored",
                        Debug_Write_Ignored'Access);
      Test_Support.Add (Suite, "named vararg: key boundaries",
                        Key_Boundaries'Access);
      Test_Support.Add (Suite, "named vararg: assignment reads",
                        Assignment_Reads'Access);
   end Register;
end Lazy_Vararg_Tests;
