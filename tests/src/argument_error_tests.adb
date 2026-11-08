with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Argument_Error_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Math_File;
   procedure Math_File is
   begin
      --  A full userdata numeric argument reports its actual FILE* name.
      Check
        ("  local f=assert(load([=[math.sin(io.stdin)]=],'" &
         "=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got FILE*)]=],tostring(e))");
   end Math_File;

   procedure Math_Abs_File;
   procedure Math_Abs_File is
   begin
      --  The core numeric path uses the same userdata diagnostic policy.
      Check
        ("  local f=assert(load([=[math.abs(io.stdin)]=],'" &
         "=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'abs' (number expec" &
         "ted, got FILE*)]=],tostring(e))");
   end Math_Abs_File;

   procedure Math_Named_Table;
   procedure Math_Named_Table is
   begin
      --  Auxiliary numeric checks honor a raw table type name.
      Check
        ("  local f=assert(load([=[math.sin(setmetatable({" &
         "},{__name='Box'}))]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got Box)]=],tostring(e))");
   end Math_Named_Table;

   procedure Math_Primitive_Name;
   procedure Math_Primitive_Name is
   begin
      --  Auxiliary checks honor primitive metatable names unlike VM
      --  faults.
      Check
        ("  local f=assert(load([=[local old=debug.getmeta" &
         "table(false);debug.setmetatable(false,{__name='F" &
         "lag'});local ok,e=pcall(function()math.sin(false" &
         ")end);debug.setmetatable(false,old);error(e,0)]=" &
         "],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got Flag)]=],tostring(e))");
   end Math_Primitive_Name;

   procedure Math_Nul_Name;
   procedure Math_Nul_Name is
   begin
      --  An auxiliary type name ends at its first embedded NUL.
      Check
        ("  local f=assert(load([=[math.sin(setmetatable({" &
         "},{__name='A\0B'}))]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got A)]=],tostring(e))");
   end Math_Nul_Name;

   procedure Math_Nonstring_Name;
   procedure Math_Nonstring_Name is
   begin
      --  A nonstring type-name field leaves the primitive table category.
      Check
        ("  local f=assert(load([=[math.sin(setmetatable({" &
         "},{__name=23}))]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got table)]=],tostring(e))");
   end Math_Nonstring_Name;

   procedure Math_Raw_Name;
   procedure Math_Raw_Name is
   begin
      --  Type-name lookup never invokes an index handler on the metatable.
      Check
        ("  local f=assert(load([=[local mt=setmetatable({" &
         "},{__index={__name='Fake'}});math.sin(setmetatab" &
         "le({},mt))]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got table)]=],tostring(e))");
   end Math_Raw_Name;

   procedure Math_Missing;
   procedure Math_Missing is
   begin
      --  An absent numeric argument remains distinct from explicit nil.
      Check
        ("  local f=assert(load([=[math.sin()]=],'=argumen" &
         "t'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got no value)]=],tostring(e))");
   end Math_Missing;

   procedure Math_Explicit_Nil;
   procedure Math_Explicit_Nil is
   begin
      --  An explicit nil numeric argument retains its nil category.
      Check
        ("  local f=assert(load([=[math.sin(nil)]=],'=argu" &
         "ment'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'sin' (number expec" &
         "ted, got nil)]=],tostring(e))");
   end Math_Explicit_Nil;

   procedure Math_Second;
   procedure Math_Second is
   begin
      --  A later numeric argument preserves its actual position.
      Check
        ("  local f=assert(load([=[math.atan(1,{})]=],'=ar" &
         "gument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #2 to 'atan' (number expe" &
         "cted, got table)]=],tostring(e))");
   end Math_Second;

   procedure Math_Integer;
   procedure Math_Integer is
   begin
      --  Integer conversion retains its argument index and actual call
      --  name.
      Check
        ("  local f=assert(load([=[math.random(1.1)]=],'=a" &
         "rgument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'random' (number ha" &
         "s no integer representation)]=],tostring(e))");
   end Math_Integer;

   procedure Debug_Light_Userdata;
   procedure Debug_Light_Userdata is
   begin
      --  Setting a light userdata reports its auxiliary special type name.
      Check
        ("  local f=assert(load([=[local x=debug.upvalueid" &
         "(function()return debug end,1);debug.setuservalu" &
         "e(x,{})]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'setuservalue' (use" &
         "rdata expected, got light userdata)]=],tostring(" &
         "e))");
   end Debug_Light_Userdata;

   procedure Debug_Explicit_Nil;
   procedure Debug_Explicit_Nil is
   begin
      --  Setting explicit nil reports userdata expected and nil received.
      Check
        ("  local f=assert(load([=[debug.setuservalue(nil," &
         "{})]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'setuservalue' (use" &
         "rdata expected, got nil)]=],tostring(e))");
   end Debug_Explicit_Nil;

   procedure Debug_Missing;
   procedure Debug_Missing is
   begin
      --  A missing userdata argument reports no value.
      Check
        ("  local f=assert(load([=[debug.setuservalue()]=]" &
         ",'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'setuservalue' (use" &
         "rdata expected, got no value)]=],tostring(e))");
   end Debug_Missing;

   procedure Debug_Missing_Value;
   procedure Debug_Missing_Value is
   begin
      --  A valid full userdata requires its second value before slot
      --  lookup.
      Check
        ("  local f=assert(load([=[debug.setuservalue(io.s" &
         "tdin)]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #2 to 'setuservalue' (val" &
         "ue expected)]=],tostring(e))");
   end Debug_Missing_Value;

   procedure IO_Named_Table;
   procedure IO_Named_Table is
   begin
      --  IO handle checks preserve raw names of rejected table arguments.
      Check
        ("  local f=assert(load([=[io.input(setmetatable({" &
         "},{__name='Box'}))]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'input' (FILE* expe" &
         "cted, got Box)]=],tostring(e))");
   end IO_Named_Table;

   procedure IO_Primitive_Name;
   procedure IO_Primitive_Name is
   begin
      --  IO auxiliary type checks honor primitive metatable names.
      Check
        ("  local f=assert(load([=[local old=debug.getmeta" &
         "table(false);debug.setmetatable(false,{__name='F" &
         "lag'});local ok,e=pcall(function()io.input(false" &
         ")end);debug.setmetatable(false,old);error(e,0)]=" &
         "],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'input' (FILE* expe" &
         "cted, got Flag)]=],tostring(e))");
   end IO_Primitive_Name;

   procedure IO_Explicit_Nil;
   procedure IO_Explicit_Nil is
   begin
      --  Explicit nil is rejected by io.close rather than selecting its
      --  default.
      Check
        ("  local f=assert(load([=[io.close(nil)]=],'=argu" &
         "ment'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'close' (FILE* expe" &
         "cted, got nil)]=],tostring(e))");
   end IO_Explicit_Nil;

   procedure IO_Missing_File;
   procedure IO_Missing_File is
   begin
      --  A missing file-method argument retains its real call identity.
      Check
        ("  local f=assert(load([=[getmetatable(io.stdin)." &
         "__gc()]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to '__gc' (FILE* expec" &
         "ted, got no value)]=],tostring(e))");
   end IO_Missing_File;

   procedure Method_Self;
   procedure Method_Self is
   begin
      --  A bad colon-call self has its distinct diagnostic spelling.
      Check
        ("  local f=assert(load([=[local t={bad=math.sin};" &
         "t:bad()]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: calling 'bad' on bad self (number expe" &
         "cted, got table)]=],tostring(e))");
   end Method_Self;

   procedure Method_Regular_Index;
   procedure Method_Regular_Index is
   begin
      --  A regular colon-call argument is counted after self.
      Check
        ("  local f=assert(load([=[local old=debug.getmeta" &
         "table(0);debug.setmetatable(0,{__index={go=math." &
         "atan}});local ok,e=pcall(function()local n=1;n:g" &
         "o({})end);debug.setmetatable(0,old);error(e,0)]=" &
         "],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'go' (number expect" &
         "ed, got table)]=],tostring(e))");
   end Method_Regular_Index;

   procedure Callable_Extra;
   procedure Callable_Extra is
   begin
      --  A prepended callable-object value has an extra-argument index.
      Check
        ("  local f=assert(load([=[local m=setmetatable({}" &
         ",{__call=math.sin});m()]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad extra argument #1 to 'm' (number e" &
         "xpected, got table)]=],tostring(e))");
   end Callable_Extra;

   procedure Callable_Method_Extra;
   procedure Callable_Method_Extra is
   begin
      --  Extra callable values precede method self in diagnostic
      --  numbering.
      Check
        ("  local f=assert(load([=[local m=setmetatable({}" &
         ",{__call=math.sin});local t={f=setmetatable({},{" &
         "__call=m})};t:f()]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad extra argument #1 to 'f' (number e" &
         "xpected, got table)]=],tostring(e))");
   end Callable_Method_Extra;

   procedure Global_Fallback;
   procedure Global_Fallback is
   begin
      --  A C caller obtains the actual function name from loaded modules.
      Check
        ("  local f=assert(load([=[local ok,e=pcall(math.s" &
         "in,{});error(e,0)]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ba" &
         "d argument #1 to 'math.sin' (number expected, go" &
         "t table)]=],tostring(e))");
   end Global_Fallback;

   procedure Nul_Call_Name;
   procedure Nul_Call_Name is
   begin
      --  A field call name has the same rendered C prefix as debug
      --  metadata.
      Check
        ("  local f=assert(load([=[local t={['a\0b']=math." &
         "sin};t['a\0b']({})]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #1 to 'a' (number expecte" &
         "d, got table)]=],tostring(e))");
   end Nul_Call_Name;

   procedure Loaded_Modules_Name;
   procedure Loaded_Modules_Name is
   begin
      --  Fallback name lookup observes the actual registry table and its C
      --  name.
      Check
        ("  local f=assert(load([=[local registry=debug.ge" &
         "tregistry();local old=registry._LOADED;registry." &
         "_LOADED={['a\0b']={f=math.sin}};local ok,e=pcall" &
         "(math.sin,{});registry._LOADED=old;error(e,0)]=]" &
         ",'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ba" &
         "d argument #1 to 'a' (number expected, got table" &
         ")]=],tostring(e))");
   end Loaded_Modules_Name;

   procedure Stripped_Source;
   procedure Stripped_Source is
   begin
      --  Auxiliary errors omit stripped source while retaining the
      --  callable field.
      Check
        ("  local f=assert(load([=[local f=function()math." &
         "sin({})end;f=assert(load(string.dump(f,true)));f" &
         "()]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ba" &
         "d argument #1 to 'sin' (number expected, got tab" &
         "le)]=],tostring(e))");
   end Stripped_Source;

   procedure Debug_Index_Type_Order;
   procedure Debug_Index_Type_Order is
   begin
      --  Optional uservalue index conversion occurs before target
      --  validation.
      Check
        ("  local f=assert(load([=[debug.setuservalue(nil," &
         "{},false)]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #3 to 'setuservalue' (num" &
         "ber expected, got boolean)]=],tostring(e))");
   end Debug_Index_Type_Order;

   procedure Debug_Index_Representation_Order;
   procedure Debug_Index_Representation_Order is
   begin
      --  A nonintegral optional slot reports its own representation
      --  failure.
      Check
        ("  local f=assert(load([=[debug.setuservalue(nil," &
         "{},1.5)]=],'=argument'))" & ASCII.LF &
         "  local ok,e=pcall(f);assert(not ok and e==[=[ar" &
         "gument:1: bad argument #3 to 'setuservalue' (num" &
         "ber has no integer representation)]=],tostring(e" &
         "))");
   end Debug_Index_Representation_Order;

   procedure Debug_String_Slot;
   procedure Debug_String_Slot is
   begin
      --  Numeric string slot coercion keeps the real userdata operation.
      Check
        ("  assert(debug.setuservalue(io.stdin,{},'1')==ni" &
         "l)");
   end Debug_String_Slot;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "argument error: Math_File",
         Math_File'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Abs_File",
         Math_Abs_File'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Named_Table",
         Math_Named_Table'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Primitive_Name",
         Math_Primitive_Name'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Nul_Name",
         Math_Nul_Name'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Nonstring_Name",
         Math_Nonstring_Name'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Raw_Name",
         Math_Raw_Name'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Missing",
         Math_Missing'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Explicit_Nil",
         Math_Explicit_Nil'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Second",
         Math_Second'Access);
      Test_Support.Add
        (Suite, "argument error: Math_Integer",
         Math_Integer'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_Light_Userdata",
         Debug_Light_Userdata'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_Explicit_Nil",
         Debug_Explicit_Nil'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_Missing",
         Debug_Missing'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_Missing_Value",
         Debug_Missing_Value'Access);
      Test_Support.Add
        (Suite, "argument error: IO_Named_Table",
         IO_Named_Table'Access);
      Test_Support.Add
        (Suite, "argument error: IO_Primitive_Name",
         IO_Primitive_Name'Access);
      Test_Support.Add
        (Suite, "argument error: IO_Explicit_Nil",
         IO_Explicit_Nil'Access);
      Test_Support.Add
        (Suite, "argument error: IO_Missing_File",
         IO_Missing_File'Access);
      Test_Support.Add
        (Suite, "argument error: Method_Self",
         Method_Self'Access);
      Test_Support.Add
        (Suite, "argument error: Method_Regular_Index",
         Method_Regular_Index'Access);
      Test_Support.Add
        (Suite, "argument error: Callable_Extra",
         Callable_Extra'Access);
      Test_Support.Add
        (Suite, "argument error: Callable_Method_Extra",
         Callable_Method_Extra'Access);
      Test_Support.Add
        (Suite, "argument error: Global_Fallback",
         Global_Fallback'Access);
      Test_Support.Add
        (Suite, "argument error: Nul_Call_Name",
         Nul_Call_Name'Access);
      Test_Support.Add
        (Suite, "argument error: Loaded_Modules_Name",
         Loaded_Modules_Name'Access);
      Test_Support.Add
        (Suite, "argument error: Stripped_Source",
         Stripped_Source'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_Index_Type_Order",
         Debug_Index_Type_Order'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_Index_Representation_Order",
         Debug_Index_Representation_Order'Access);
      Test_Support.Add
        (Suite, "argument error: Debug_String_Slot",
         Debug_String_Slot'Access);
   end Register;
end Argument_Error_Tests;
