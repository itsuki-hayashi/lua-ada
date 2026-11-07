with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Engine.Machine;
with Lua.Sessions; use Lua.Sessions;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Pointer_Identity_Tests is
   use type Interfaces.C.int;
   use type Interfaces.C.size_t;
   use type Lua.Storage.Byte_Count;
   use type System.Address;
   Refusing : Boolean := False;
   Refusals : Natural := 0;
   function Surface_Allocator
     (Data, Block : System.Address; Old_Size, New_Size : Interfaces.C.size_t)
      return System.Address with Convention => C;
   function C_Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_identity";
   function Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_identity_callback";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Check (Source : String);
   procedure Late_C_Thread;
   procedure Name_Scan_Quota;
   procedure Short_C_Prefix;
   procedure Weak_Thread;
   procedure First_Surface_Refusal;
   procedure Name_Check (Short : Boolean);
   procedure Primitive_Text;
   procedure Table_Text;
   procedure Named_Table;
   procedure Nul_Name;
   procedure Empty_Name;
   procedure Leading_Nul_Name;
   procedure Nonstring_Name;
   procedure Raw_Name_Lookup;
   procedure Lua_Function;
   procedure Builtin_Function;
   procedure Named_Function;
   procedure Thread_Identity;
   procedure Long_String;
   procedure Handler_Long_String;
   procedure Handler_Integer;
   procedure Handler_Real;
   procedure Handler_Type_Error;
   procedure Missing_Value;
   procedure Null_Format;
   procedure Field_Widths;
   procedure Primitive_Name_Ignored;
   procedure String_Handler;
   procedure C_Table;
   procedure C_Userdata;
   procedure C_Light_Userdata;
   procedure C_Null_Pointer;
   procedure C_Light_Function;
   procedure C_Captured_Function;
   procedure C_Thread;
   procedure C_String;

   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   function Surface_Allocator
     (Data, Block : System.Address; Old_Size, New_Size : Interfaces.C.size_t)
      return System.Address
   is
   begin
      if Refusing and then New_Size > 0 and then
        (Block = System.Null_Address or else New_Size > Old_Size)
      then
         Refusals := Refusals + 1;
         return System.Null_Address;
      end if;
      return Lua.Storage.Default_Allocator (Data, Block, Old_Size, New_Size);
   end Surface_Allocator;

   procedure First_Surface_Refusal is
      State : World;
      Drive : Machine.Driver;
      Args : Values.Vector;
      Target : Value;
      Injected : Boolean := False;
      Steps : Natural := 0;
   begin
      Initialize (State, (others => <>));
      Assert (Execute (State,
        "co=coroutine.create(function()end); " &
        "function first() return pcall(tostring,co) end",
        "first-surface-setup"), "cached first rendering setup failed");
      Begin_Operation (State);
      Target := Get (Global_Environment (State), New_String (State, "first"));
      Args.Set_Owner (Lua.Storage.Reference (State.Memory));
      End_Operation (State);
      Lua.Storage.Set_Allocator (State.Memory, Surface_Allocator'Access);
      Machine.Start_Foreign (Drive, State, Target, Args);
      while not Machine.Is_Complete (Drive) loop
         Steps := Steps + 1;
         Assert (Steps < 1_000, "first-render fixture failed to terminate");
         if not Injected and then not State.Current.Stack.Is_Empty and then
           State.Current.Stack.Last_Element.Is_Native and then
           Native_Operation_Name (State.Current.Stack.Last_Element) =
             "base.tostring"
         then
            --  Parsing, the Lua pcall boundary and the real argument frame
            --  already exist. Refuse actual first C-surface growth alone,
            --  not an earlier parser/driver request that hides this edge.
            Assert (State.Main_Context.Foreign_State = System.Null_Address,
                    "test accidentally materialized a C surface early");
            Refusals := 0;
            Refusing := True;
            begin
               Machine.Step (Drive);
            exception
               when others => Refusing := False; raise;
            end;
            Refusing := False;
            Injected := True;
            Assert (Refusals > 0, "first surface did not actually refuse");
         else
            Machine.Step (Drive);
         end if;
      end loop;
      Assert (Injected and then Machine.Outcome (Drive) = Completed,
              "first surface refusal escaped Lua's protected call");
      declare
         Result : constant Values.Vector := Machine.Results (Drive);
      begin
         --  Start_Foreign prefixes its own successful entry status. The
         --  following false/message pair must come from the inner Lua pcall.
         Assert (Natural (Result.Length) = 3 and then
                   Result (1).Kind = Boolean_Kind and then
                   Result (1).Boolean_Data and then
                   Result (2).Kind = Boolean_Kind and then
                   not Result (2).Boolean_Data and then
                   Result (3).Kind = String_Kind and then
                   Image (State.Current.Memory, Result (3)) =
                     "not enough memory",
                 "first surface refusal lost its actual memory error");
      end;
      Machine.Finish (Drive);
      Lua.Storage.Set_Allocator
        (State.Memory, Lua.Storage.Default_Allocator'Access);
      Assert (Execute (State,
        "assert(tostring(co)=='thread: '..string.format('%p',co))",
        "first-surface-recovery"), "first surface refusal damaged retry");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "failed first surface retained provider ownership");
   exception
      when others =>
         Refusing := False;
         Machine.Cancel (Drive);
         Finalize (State);
         raise;
   end First_Surface_Refusal;

   --  The native-paired Lua case compares public results inside one image.
   procedure Primitive_Text is
   begin
      Check
        ("    assert(tostring(nil)=='nil' and tostring(fal" &
         "se)=='false')" & ASCII.LF &
         "    assert(tostring(true)=='true' and tostring(1" &
         "7)=='17')" & ASCII.LF &
         "    assert(tostring(17.0)=='17.0')");
   end Primitive_Text;

   --  The native-paired Lua case compares public results inside one image.
   procedure Table_Text is
   begin
      Check
        ("    local t={};assert(tostring(t)=='table: '..st" &
         "ring.format('%p',t))");
   end Table_Text;

   --  The native-paired Lua case compares public results inside one image.
   procedure Named_Table is
   begin
      Check
        ("    local t=setmetatable({},{__name='My Type'})" & ASCII.LF &
         "    assert(tostring(t)=='My Type: '..string.form" &
         "at('%p',t))");
   end Named_Table;

   --  The native-paired Lua case compares public results inside one image.
   procedure Nul_Name is
   begin
      Check
        ("    local t=setmetatable({},{__name='Box\0unprin" &
         "ted'})" & ASCII.LF &
         "    assert(tostring(t)=='Box: '..string.format('" &
         "%p',t))");
   end Nul_Name;

   --  The native-paired Lua case compares public results inside one image.
   procedure Empty_Name is
   begin
      Check
        ("    local t=setmetatable({},{__name=''})" & ASCII.LF &
         "    assert(tostring(t)==': '..string.format('%p'" &
         ",t))");
   end Empty_Name;

   --  The native-paired Lua case compares public results inside one image.
   procedure Leading_Nul_Name is
   begin
      Check
        ("    local t=setmetatable({},{__name='\0unprinted" &
         "'})" & ASCII.LF &
         "    assert(tostring(t)==': '..string.format('%p'" &
         ",t))");
   end Leading_Nul_Name;

   --  The native-paired Lua case compares public results inside one image.
   procedure Nonstring_Name is
   begin
      Check
        ("    local t=setmetatable({},{__name=42})" & ASCII.LF &
         "    assert(tostring(t)=='table: '..string.format" &
         "('%p',t))");
   end Nonstring_Name;

   --  The native-paired Lua case compares public results inside one image.
   procedure Raw_Name_Lookup is
   begin
      Check
        ("    local n=0;local mt=setmetatable({},{__index=" &
         "function()n=n+1 end})" & ASCII.LF &
         "    local t=setmetatable({},mt)" & ASCII.LF &
         "    assert(tostring(t)=='table: '..string.format" &
         "('%p',t) and n==0)");
   end Raw_Name_Lookup;

   --  The native-paired Lua case compares public results inside one image.
   procedure Lua_Function is
   begin
      Check
        ("    local f=function()end" & ASCII.LF &
         "    assert(tostring(f)=='function: '..string.for" &
         "mat('%p',f))");
   end Lua_Function;

   --  The native-paired Lua case compares public results inside one image.
   procedure Builtin_Function is
   begin
      Check
        ("    assert(tostring(assert)=='function: '..strin" &
         "g.format('%p',assert))");
   end Builtin_Function;

   --  The native-paired Lua case compares public results inside one image.
   procedure Named_Function is
   begin
      Check
        ("    local old=debug.getmetatable(assert)" & ASCII.LF &
         "    debug.setmetatable(assert,{__name='Callable\" &
         "0unprinted'})" & ASCII.LF &
         "    local s=tostring(assert);debug.setmetatable(" &
         "assert,old)" & ASCII.LF &
         "    assert(s=='Callable: '..string.format('%p',a" &
         "ssert))");
   end Named_Function;

   --  The native-paired Lua case compares public results inside one image.
   procedure Thread_Identity is
   begin
      Check
        ("    local co=coroutine.create(function()coroutin" &
         "e.yield(1);return 2 end)" & ASCII.LF &
         "    local p=string.format('%p',co)" & ASCII.LF &
         "    assert(tostring(co)=='thread: '..p)" & ASCII.LF &
         "    assert(coroutine.resume(co));assert(string.f" &
         "ormat('%p',co)==p)" & ASCII.LF &
         "    assert(coroutine.resume(co));assert(tostring" &
         "(co)=='thread: '..p)");
   end Thread_Identity;

   --  The native-paired Lua case compares public results inside one image.
   procedure Long_String is
   begin
      Check
        ("    local s=string.rep('long',100)" & ASCII.LF &
         "    assert(string.format('%p',tostring(s))==stri" &
         "ng.format('%p',s))");
   end Long_String;

   --  The native-paired Lua case compares public results inside one image.
   procedure Handler_Long_String is
   begin
      Check
        ("    local s=string.rep('result',100)" & ASCII.LF &
         "    local t=setmetatable({},{__tostring=function" &
         "()return s end})" & ASCII.LF &
         "    assert(string.format('%p',tostring(t))==stri" &
         "ng.format('%p',s))");
   end Handler_Long_String;

   --  The native-paired Lua case compares public results inside one image.
   procedure Handler_Integer is
   begin
      Check
        ("    local t=setmetatable({},{__tostring=function" &
         "()return 42 end})" & ASCII.LF &
         "    assert(tostring(t)=='42')");
   end Handler_Integer;

   --  The native-paired Lua case compares public results inside one image.
   procedure Handler_Real is
   begin
      Check
        ("    local t=setmetatable({},{__tostring=function" &
         "()return 42.0 end})" & ASCII.LF &
         "    assert(tostring(t)=='42.0')");
   end Handler_Real;

   --  The native-paired Lua case compares public results inside one image.
   procedure Handler_Type_Error is
   begin
      Check
        ("    local t=setmetatable({},{__tostring=function" &
         "()return false end})" & ASCII.LF &
         "    local ok,e=pcall(tostring,t)" & ASCII.LF &
         "    assert(not ok and e==""'__tostring' must ret" &
         "urn a string"",tostring(e))");
   end Handler_Type_Error;

   --  The native-paired Lua case compares public results inside one image.
   procedure Missing_Value is
   begin
      Check
        ("    local ok,e=pcall(tostring)" & ASCII.LF &
         "    assert(not ok and e==""bad argument #1 to 't" &
         "ostring' (value expected)"",e)");
   end Missing_Value;

   --  The native-paired Lua case compares public results inside one image.
   procedure Null_Format is
   begin
      Check
        ("    for _,v in ipairs({false,17,17.0})do" & ASCII.LF &
         "      assert(string.format('%p',v)=='(null)')" & ASCII.LF &
         "    end" & ASCII.LF &
         "    assert(string.format('%p',nil)=='(null)')");
   end Null_Format;

   --  The native-paired Lua case compares public results inside one image.
   procedure Field_Widths is
   begin
      Check
        ("    local t={}" & ASCII.LF &
         "    assert(#string.format('%20p',t)==20)" & ASCII.LF &
         "    assert(#string.format('%-20p',t)==20)" & ASCII.LF &
         "    assert(string.format('%20p',nil)==string.rep" &
         "(' ',14)..'(null)')");
   end Field_Widths;

   --  The native-paired Lua case compares public results inside one image.
   procedure Primitive_Name_Ignored is
   begin
      Check
        ("    local old=debug.getmetatable(0)" & ASCII.LF &
         "    debug.setmetatable(0,{__name='Named Number'}" &
         ")" & ASCII.LF &
         "    local a,b=tostring(17),tostring(17.0)" & ASCII.LF &
         "    debug.setmetatable(0,old);assert(a=='17' and" &
         " b=='17.0')");
   end Primitive_Name_Ignored;

   --  The native-paired Lua case compares public results inside one image.
   procedure String_Handler is
   begin
      Check
        ("    local s=string.rep('handler',100);local old=" &
         "debug.getmetatable('')" & ASCII.LF &
         "    debug.setmetatable('',{__tostring=function()" &
         "return s end})" & ASCII.LF &
         "    local result=tostring('input');debug.setmeta" &
         "table('',old)" & ASCII.LF &
         "    assert(string.format('%p',result)==string.fo" &
         "rmat('%p',s))");
   end String_Handler;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Table is
   begin
      Assert (C_Check (0) = 1, "C table");
   end C_Table;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Userdata is
   begin
      Assert (C_Check (1) = 1, "C userdata payload");
   end C_Userdata;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Light_Userdata is
   begin
      Assert (C_Check (2) = 1, "C light userdata");
   end C_Light_Userdata;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Null_Pointer is
   begin
      Assert (C_Check (3) = 1, "C null light userdata");
   end C_Null_Pointer;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Light_Function is
   begin
      Assert (C_Check (4) = 1, "C light function");
   end C_Light_Function;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Captured_Function is
   begin
      Assert (C_Check (5) = 1, "C captured function");
   end C_Captured_Function;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_Thread is
   begin
      Assert (C_Check (6) = 1, "C thread lifecycle");
   end C_Thread;

   --  Reuse the actual identical-source C API case and balanced provider.
   procedure C_String is
   begin
      Assert (C_Check (7) = 1, "C string identity");
   end C_String;

   procedure Late_C_Thread is
      State : World;
      Item : Value;
   begin
      Initialize (State, (others => <>));
      --  Render before there is any C borrow. The subsequent actual C call
      --  must report those same stable identities, including the main thread.
      Assert (Execute (State,
        "co=coroutine.create(function()end); main=coroutine.running(); " &
        "before=string.format('%p',co); text=tostring(co); " &
        "main_before=string.format('%p',main)", "identity-before-C"),
        "initial Ada-only thread rendering failed");
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback);
      Set (State, Global_Environment (State), New_String (State, "c_pointer"),
           Item);
      End_Operation (State);
      Assert (Execute (State,
        "assert(before==c_pointer(co)); " &
        "assert(text=='thread: '..c_pointer(co)); " &
        "assert(main_before==c_pointer(main))", "identity-after-C"),
        "first actual C borrow changed a saved Lua thread identity");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "lazily materialized thread surfaces leaked provider storage");
   exception
      when others => Finalize (State); raise;
   end Late_C_Thread;

   procedure Weak_Thread is
   begin
      --  Lazily reserved C metadata must not root an otherwise dead thread.
      Check
        ("local weak=setmetatable({},{__mode='v'}); " &
         "local function make() local co=coroutine.create(function()end);" &
         "weak[1]=co;tostring(co)end;make();collectgarbage();" &
         "collectgarbage();assert(weak[1]==nil)");
   end Weak_Thread;

   procedure Name_Check (Short : Boolean) is
      State : World;
      Item, Meta : Value;
   begin
      Initialize (State, (Instructions => 500, others => <>));
      Begin_Operation (State);
      Item := New_Table (State);
      Meta := New_Table (State);
      Set (State, Meta, New_String (State, "__name"),
           New_String (State,
             (if Short then "n" & Character'Val (0) else "") &
             String'(1 .. 20_000 => 'x')));
      Set_Metatable (State, Item, Meta.Reference);
      Set (State, Global_Environment (State), New_String (State, "named"),
           Item);
      End_Operation (State);
      if Short then
         --  A huge suffix after NUL is neither scanned nor copied as a name.
         Assert (Execute (State,
           "assert(tostring(named)=='n: '..string.format('%p',named))",
           "short-C-name"), "unprinted name suffix consumed the work quota");
      else
         --  An actually long prefix must charge work and stop even in pcall.
         Assert (not Execute (State,
           "pcall(tostring,named);error('name quota was caught')",
           "long-C-name"), "name scan escaped the host work limit");
         Assert (State.Current.Failure_Class = Host_Abort,
                 "name quota became a catchable Lua runtime error");
      end if;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "default description source/output survived disposal");
   exception
      when others => Finalize (State); raise;
   end Name_Check;

   procedure Name_Scan_Quota is
   begin
      Name_Check (False);
   end Name_Scan_Quota;

   procedure Short_C_Prefix is
   begin
      Name_Check (True);
   end Short_C_Prefix;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "identity: primitive text",
                        Primitive_Text'Access);
      Test_Support.Add (Suite, "identity: table identity text",
                        Table_Text'Access);
      Test_Support.Add (Suite, "identity: named table",
                        Named_Table'Access);
      Test_Support.Add (Suite, "identity: NUL name prefix",
                        Nul_Name'Access);
      Test_Support.Add (Suite, "identity: empty name prefix",
                        Empty_Name'Access);
      Test_Support.Add (Suite, "identity: leading NUL prefix",
                        Leading_Nul_Name'Access);
      Test_Support.Add (Suite, "identity: nonstring name fallback",
                        Nonstring_Name'Access);
      Test_Support.Add (Suite, "identity: raw name lookup",
                        Raw_Name_Lookup'Access);
      Test_Support.Add (Suite, "identity: Lua function identity",
                        Lua_Function'Access);
      Test_Support.Add (Suite, "identity: builtin function identity",
                        Builtin_Function'Access);
      Test_Support.Add (Suite, "identity: named function",
                        Named_Function'Access);
      Test_Support.Add (Suite, "identity: thread identity across resume",
                        Thread_Identity'Access);
      Test_Support.Add (Suite, "identity: long string identity",
                        Long_String'Access);
      Test_Support.Add (Suite, "identity: handler long string identity",
                        Handler_Long_String'Access);
      Test_Support.Add (Suite, "identity: handler integer",
                        Handler_Integer'Access);
      Test_Support.Add (Suite, "identity: handler real",
                        Handler_Real'Access);
      Test_Support.Add (Suite, "identity: handler type error",
                        Handler_Type_Error'Access);
      Test_Support.Add (Suite, "identity: missing value error",
                        Missing_Value'Access);
      Test_Support.Add (Suite, "identity: null pointer format",
                        Null_Format'Access);
      Test_Support.Add (Suite, "identity: native pointer field widths",
                        Field_Widths'Access);
      Test_Support.Add (Suite, "identity: primitive name ignored",
                        Primitive_Name_Ignored'Access);
      Test_Support.Add (Suite, "identity: string handler identity",
                        String_Handler'Access);
      Test_Support.Add (Suite, "identity: C table",
                        C_Table'Access);
      Test_Support.Add (Suite, "identity: C userdata payload",
                        C_Userdata'Access);
      Test_Support.Add (Suite, "identity: C light userdata",
                        C_Light_Userdata'Access);
      Test_Support.Add (Suite, "identity: C null light userdata",
                        C_Null_Pointer'Access);
      Test_Support.Add (Suite, "identity: C light function",
                        C_Light_Function'Access);
      Test_Support.Add (Suite, "identity: C captured function",
                        C_Captured_Function'Access);
      Test_Support.Add (Suite, "identity: C thread lifecycle",
                        C_Thread'Access);
      Test_Support.Add (Suite, "identity: C string identity",
                        C_String'Access);
      Test_Support.Add (Suite, "identity: before first C borrow",
                        Late_C_Thread'Access);
      Test_Support.Add (Suite, "identity: actual first surface refusal",
                        First_Surface_Refusal'Access);
      Test_Support.Add (Suite, "identity: formatted weak thread collected",
                        Weak_Thread'Access);
      Test_Support.Add (Suite, "identity: long name host quota",
                        Name_Scan_Quota'Access);
      Test_Support.Add (Suite, "identity: short C prefix huge suffix",
                        Short_C_Prefix'Access);
   end Register;
end Lua.Pointer_Identity_Tests;
