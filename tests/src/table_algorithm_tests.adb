with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Table_Algorithm_Tests is
   LF : constant Character := Character'Val (10);

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Ascending_Numbers;
   procedure Ascending_Numbers is
   begin
      --  Sort a nontrivial unsorted numeric sequence in place.
      --  The sequence is ascending and the function returns zero results.
      Check
        ("local t={7,2,9,1,5,3}" & LF &
         "assert(select('#',table.sort(t))==0)" & LF &
         "assert(table.concat(t,',')=='1,2,3,5,7,9')");
   end Ascending_Numbers;

   procedure Reverse_Comparator;
   procedure Reverse_Comparator is
   begin
      --  Sort with a Lua function whose order is descending.
      --  Callback result truth, arguments and in-place writes determine the
      --  order.
      Check
        ("local t={1,4,2,3};local calls=0" & LF &
         "table.sort(t,function(a,b)calls=calls+1;return a>b end)" & LF &
         "assert(calls>0 and table.concat(t,',')=='4,3,2,1')");
   end Reverse_Comparator;

   procedure Repeated_Keys;
   procedure Repeated_Keys is
   begin
      --  Sort duplicates and an already sorted sequence again.
      --  Equal values terminate sifting and retain the complete multiset.
      Check
        ("local t={3,1,3,2,1,3,2,1}" & LF &
         "table.sort(t);table.sort(t)" & LF &
         "assert(table.concat(t,',')=='1,1,1,2,2,3,3,3')");
   end Repeated_Keys;

   procedure Byte_Strings;
   procedure Byte_Strings is
   begin
      --  Sort strings with NUL and bytes beyond ASCII.
      --  Default string ordering compares all bytes rather than C-string
      --  prefixes.
      Check
        ("local t={'z','a\0z','a\0a','a','\255','\0'}" & LF &
         "table.sort(t)" & LF &
         "assert(t[1]=='\0' and t[2]=='a' and t[3]=='a\0a')" & LF &
         "assert(t[4]=='a\0z' and t[5]=='z' and t[6]=='\255')");
   end Byte_Strings;

   procedure Default_Metamethod;
   procedure Default_Metamethod is
   begin
      --  Sort table values with an ordinary __lt handler.
      --  The standard comparison dispatch runs Lua handlers in the same
      --  scheduler.
      Check
        ("local m={__lt=function(a,b)return a.n<b.n end}" & LF &
         "local t={setmetatable({n=3},m),setmetatable({n=1},m)," & LF &
         "setmetatable({n=2},m)}" & LF &
         "table.sort(t);assert(t[1].n==1 and t[2].n==2 and t[3].n==3)");
   end Default_Metamethod;

   procedure Callback_Collection;
   procedure Callback_Collection is
   begin
      --  Collect during every comparator call on captured tables.
      --  Saved heap candidates and the sifted value remain traced across
      --  callbacks.
      Check
        ("local t={};for i=1,12 do t[i]={n=13-i}end" & LF &
         "table.sort(t,function(a,b)collectgarbage()" & LF &
         "return a.n<b.n end)" & LF &
         "for i=1,12 do assert(t[i].n==i)end");
   end Callback_Collection;

   procedure Callback_Error_Object;
   procedure Callback_Error_Object is
   begin
      --  Raise a table from the comparator and catch it outside sorting.
      --  The real Lua error survives native continuation unwinding and
      --  recovery.
      Check
        ("local err={};local t={4,3,2,1}" & LF &
         "local ok,e=pcall(table.sort,t,function()error(err)end)" & LF &
         "assert(not ok and e==err)" & LF &
         "table.sort(t);assert(table.concat(t,',')=='1,2,3,4')");
   end Callback_Error_Object;

   procedure Callback_Yield_Boundary;
   procedure Callback_Yield_Boundary is
   begin
      --  Try to yield through the non-yieldable table.sort callback.
      --  A coroutine reports a protected error rather than suspending that
      --  native call.
      Check
        ("local co=coroutine.create(function()" & LF &
         "table.sort({3,2,1},function()coroutine.yield()end)end)" & LF &
         "local ok,e=coroutine.resume(co)" & LF &
         "assert(not ok and type(e)=='string')" & LF &
         "assert(coroutine.status(co)=='dead')");
   end Callback_Yield_Boundary;

   procedure Invalid_Comparator;
   procedure Invalid_Comparator is
   begin
      --  Use a comparator which claims every value is less than every other.
      --  Contradictory order is a controlled Lua error and cannot loop
      --  indefinitely.
      Check
        ("local ok,e=pcall(table.sort,{1,2,3,4},function()" & LF &
         "return true end)" & LF &
         "assert(not ok and e:find('invalid order function'))");
   end Invalid_Comparator;

   procedure Comparator_Argument_Check;
   procedure Comparator_Argument_Check is
   begin
      --  Supply an invalid comparator to empty, singleton and larger inputs.
      --  Trivial ranges do not inspect the optional comparator; larger ones
      --  reject it.
      Check
        ("assert(select('#',table.sort({},false))==0)" & LF &
         "assert(select('#',table.sort({1},false))==0)" & LF &
         "assert(not pcall(table.sort,{1,2},false))");
   end Comparator_Argument_Check;

   procedure Length_Metamethod;
   procedure Length_Metamethod is
   begin
      --  Use __len to restrict the sorted prefix of a table.
      --  The trailing item survives and the length callback runs once.
      Check
        ("local n=0;local t=setmetatable({3,2,1,99},{__len=function()" & LF &
         "n=n+1;return 3 end})" & LF &
         "table.sort(t);assert(n==1 and t[1]==1 and t[3]==3 and t[4]==99)");
   end Length_Metamethod;

   procedure Proxy_Accesses;
   procedure Proxy_Accesses is
   begin
      --  Sort a table-like boolean through all three required metamethods.
      --  Reads and writes use real handlers while preserving the receiver
      --  argument.
      Check
        ("local data={4,2,3,1};local reads,writes=0,0" & LF &
         "debug.setmetatable(false,{__len=function()return 4 end," & LF &
         "__index=function(t,k)assert(t==false);reads=reads+1" & LF &
         "return data[k]end," & LF &
         "__newindex=function(t,k,v)assert(t==false);writes=writes+1" & LF &
         "data[k]=v end})" & LF &
         "table.sort(false);assert(table.concat(data,',')=='1,2,3,4')" & LF &
         "assert(reads>0 and writes>0)");
   end Proxy_Accesses;

   procedure Huge_Length;
   procedure Huge_Length is
   begin
      --  Return an integer at the semantic sort limit from __len.
      --  The size failure happens before any attempt to index the receiver.
      Check
        ("local t=setmetatable({},{__len=function()" & LF &
         "return math.maxinteger end," & LF &
         "__index=error})" & LF &
         "local ok,e=pcall(table.sort,t)" & LF &
         "assert(not ok and e:find('too big'))");
   end Huge_Length;

   procedure Negative_Length;
   procedure Negative_Length is
   begin
      --  Return a negative length and provide an erroring comparator.
      --  A nonpositive range is empty and no comparisons or accesses are
      --  needed.
      Check
        ("local t=setmetatable({},{__len=function()return -1 end})" & LF &
         "assert(select('#',table.sort(t,error))==0)");
   end Negative_Length;

   procedure Create_Empty;
   procedure Create_Empty is
   begin
      --  Create sequence and hash capacity without adding values.
      --  Preallocation changes storage only; length, iteration and later
      --  writes work.
      Check
        ("local t=table.create(128,64)" & LF &
         "assert(#t==0 and next(t)==nil)" & LF &
         "for i=1,128 do t[i]=i end;t.name='value'" & LF &
         "assert(#t==128 and t[128]==128 and t.name=='value')");
   end Create_Empty;

   procedure Create_Optional_Size;
   procedure Create_Optional_Size is
   begin
      --  Pass nil or omit the optional hash capacity and use numeric
      --  strings.
      --  Capacity hints accept Lua integer conversion without becoming table
      --  entries.
      Check
        ("local a=table.create('8');local b=table.create(8,nil)" & LF &
         "assert(#a==0 and next(a)==nil and #b==0)");
   end Create_Optional_Size;

   procedure Create_Bad_Arguments;
   procedure Create_Bad_Arguments is
   begin
      --  Pass missing, fractional, negative and nonnumeric hints.
      --  Invalid capacities produce catchable errors and leave the session
      --  usable.
      Check
        ("assert(not pcall(table.create))" & LF &
         "assert(not pcall(table.create,0.5))" & LF &
         "assert(not pcall(table.create,-1))" & LF &
         "assert(not pcall(table.create,0,-1))" & LF &
         "assert(not pcall(table.create,false))" & LF &
         "assert(next(table.create(0,0))==nil)");
   end Create_Bad_Arguments;

   procedure Create_Semantic_Overflow;
   procedure Create_Semantic_Overflow is
   begin
      --  Request a hash hint which exceeds the pinned hash exponent.
      --  Semantic overflow is validated before host allocation limits are
      --  applied.
      Check
        ("local ok,e=pcall(table.create,0,(1<<31)-1)" & LF &
         "assert(not ok and e:find('table overflow'))" & LF &
         "local ok2,e2=pcall(table.create,1<<31)" & LF &
         "assert(not ok2 and e2:find('out of range'))");
   end Create_Semantic_Overflow;

   procedure Sort_Budget_Recovery;
   procedure Sort_Budget_Recovery is
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  Keep the input small enough for ordinary storage, but give native
      --  sift phases too little work budget. pcall cannot hide that host
      --  abort, and the next public execution must begin a usable epoch.
      Bounds.Instructions := 2_000;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local t={};for i=1,128 do t[i]=129-i end;" &
         "pcall(table.sort,t)");
      Assert (Result.Status = Resource_Error, "sort bypassed native budget");
      Result := Universe.Execute ("assert(6*7==42)");
      Assert (Result.Status = Succeeded, "sort abort poisoned the session");
   end Sort_Budget_Recovery;

   procedure Create_Budget_Recovery;
   procedure Create_Budget_Recovery is
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  Preallocation itself consumes the configured table capacity quota,
      --  even before any entries are written. Keep semantic format errors
      --  separate from this explicit, uncatchable embedding-owner limit.
      Bounds.Table_Entries := 16;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("pcall(table.create,32)");
      Assert (Result.Status = Resource_Error,
              "create ignored the owner's allocation quota");
      Result := Universe.Execute ("assert(6*7==42)");
      Assert (Result.Status = Succeeded, "create abort poisoned the session");
   end Create_Budget_Recovery;

   procedure Invalid_Length_Result;
   procedure Invalid_Length_Result is
   begin
      --  An arbitrary __len value is legal for #t, but table functions need
      --  luaL_len's integer conversion and its distinct diagnostic.
      Check
        ("local t=setmetatable({}, {__len=function() return 'abc' end}); " &
         "assert(#t=='abc'); for _,f in ipairs{table.insert,table.remove," &
         "table.concat,table.unpack} do local ok,e=pcall(f,t,1); " &
         "assert(not ok and e:find('object length is not an integer'," &
         "1,true)) end");
   end Invalid_Length_Result;

   procedure Fractional_Length_Result;
   procedure Fractional_Length_Result is
   begin
      --  Fractional/out-of-range results fail integer conversion, with the
      --  same length diagnostic rather than the ordinary argument error.
      Check
        ("for _,v in ipairs{1.5,math.huge} do local t=setmetatable({}," &
         "{__len=function() return v end}); local ok,e=" &
         "pcall(table.insert,t,1); assert(not ok and " &
         "e:find('object length is not an integer',1,true)) end");
   end Fractional_Length_Result;

   procedure Numeric_String_Length_Result;
   procedure Numeric_String_Length_Result is
   begin
      --  lua_tointegerx accepts a numeric string returned by __len. Preserve
      --  that coercion through both table operations.
      Check
        ("local t=setmetatable({7,8},{__len=function() return '2.0' end});" &
         "assert(table.concat(t,',')=='7,8'); local a,b=table.unpack(t);" &
         "assert(a==7 and b==8)");
   end Numeric_String_Length_Result;

   procedure Unpack_Length_Before_Bounds;
   procedure Unpack_Length_Before_Bounds is
   begin
      --  The pinned tunpack calls aux_getn before optional argument checks,
      --  even when explicit bounds describe an empty result range.
      Check
        ("local n=0; local t=setmetatable({9},{__len=function() " &
         "n=n+1; return 1 end}); assert(table.unpack(t,1,1)==9 and n==1);" &
         "assert(select('#',table.unpack(t,2,1))==0 and n==2); " &
         "getmetatable(t).__len=function() error('length first',0) end;" &
         "local ok,e=pcall(table.unpack,t,'bad',1); " &
         "assert(not ok and e=='length first')");
   end Unpack_Length_Before_Bounds;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "table algorithms: ascending numbers",
         Ascending_Numbers'Access);
      Test_Support.Add
        (Suite, "table algorithms: reverse comparator",
         Reverse_Comparator'Access);
      Test_Support.Add
        (Suite, "table algorithms: repeated keys",
         Repeated_Keys'Access);
      Test_Support.Add
        (Suite, "table algorithms: byte strings",
         Byte_Strings'Access);
      Test_Support.Add
        (Suite, "table algorithms: default metamethod",
         Default_Metamethod'Access);
      Test_Support.Add
        (Suite, "table algorithms: callback collection",
         Callback_Collection'Access);
      Test_Support.Add
        (Suite, "table algorithms: callback error object",
         Callback_Error_Object'Access);
      Test_Support.Add
        (Suite, "table algorithms: callback yield boundary",
         Callback_Yield_Boundary'Access);
      Test_Support.Add
        (Suite, "table algorithms: invalid comparator",
         Invalid_Comparator'Access);
      Test_Support.Add
        (Suite, "table algorithms: comparator argument check",
         Comparator_Argument_Check'Access);
      Test_Support.Add
        (Suite, "table algorithms: length metamethod",
         Length_Metamethod'Access);
      Test_Support.Add
        (Suite, "table algorithms: proxy accesses",
         Proxy_Accesses'Access);
      Test_Support.Add
        (Suite, "table algorithms: huge length",
         Huge_Length'Access);
      Test_Support.Add
        (Suite, "table algorithms: negative length",
         Negative_Length'Access);
      Test_Support.Add
        (Suite, "table algorithms: create empty",
         Create_Empty'Access);
      Test_Support.Add
        (Suite, "table algorithms: create optional size",
         Create_Optional_Size'Access);
      Test_Support.Add
        (Suite, "table algorithms: create bad arguments",
         Create_Bad_Arguments'Access);
      Test_Support.Add
        (Suite, "table algorithms: create semantic overflow",
         Create_Semantic_Overflow'Access);
      Test_Support.Add
        (Suite, "table algorithms: sort budget recovery",
         Sort_Budget_Recovery'Access);
      Test_Support.Add
        (Suite, "table algorithms: create budget recovery",
         Create_Budget_Recovery'Access);
      Test_Support.Add (Suite, "table algorithms: invalid length result",
                        Invalid_Length_Result'Access);
      Test_Support.Add (Suite, "table algorithms: fractional length result",
                        Fractional_Length_Result'Access);
      Test_Support.Add (Suite, "table algorithms: numeric string length",
                        Numeric_String_Length_Result'Access);
      Test_Support.Add (Suite, "table algorithms: unpack length before bounds",
                        Unpack_Length_Before_Bounds'Access);
   end Register;
end Table_Algorithm_Tests;
