with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Library_Runtime_Tests is
   procedure Check (Source : String);
   procedure Text_Load;
   procedure Reader_Pieces;
   procedure Reader_Empty_Ends;
   procedure Reader_Type_Error;
   procedure Reader_Callback_Failure;
   procedure Repeated_Reader_Failures;
   procedure Reader_Requires_Function;
   procedure Reader_Options_Precede_Call;
   procedure Raw_Load_Has_No_Preamble;
   procedure Explicit_Environment;
   procedure Persistent_Environment_Cell;
   procedure Shared_Environment_Capture;
   procedure Explicit_Nil_Environment;
   procedure Omitted_Environment;
   procedure Load_Syntax_Failure;
   procedure Load_Mode_Filter;
   procedure Binary_Load_Boundary;
   procedure Nested_Loads;
   procedure Preload_Cache;
   procedure Binary_Lua_Module;
   procedure Preload_False_Reload;
   procedure Preload_Nil_Default;
   procedure Loaded_Registry_Identity;
   procedure Preload_Registry_Identity;
   procedure Custom_Searcher_Data;
   procedure Package_Not_Found;
   procedure Searchpath_Failure;
   procedure Loadfile_Failure;
   procedure Resource_Recovery;
   procedure Compilation_Work_Budget;
   procedure Retained_Load_Environment;
   procedure Reset_Module_State;
   procedure Integer_Absolute_Boundary;
   procedure Directed_Rounding;
   procedure Fmod_Sign;
   procedure Modf_Integer_Boundary;
   procedure Numeric_Classification;
   procedure Unsigned_Comparison;
   procedure Table_Pack_Nils;
   procedure Table_Move_Overlap;
   procedure Table_Insert_Remove;
   procedure Table_Concat_Empty_First;
   procedure Table_Concat_Events;
   procedure Table_Unpack_Events;
   procedure Table_Insert_Events;
   procedure Table_Remove_Events;
   procedure Table_Move_Equality_Order;
   procedure Table_Callback_Failure;
   procedure Table_Unpack_Explicit_End;
   procedure Table_Move_Maximum_Destination;

   procedure Compilation_Work_Budget is
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  Retaining a source string avoids allocation inside the loop, but
      --  each load still scans its bytes. Protecting the operation cannot
      --  restart that work allowance or turn exhaustion into nil/message.
      Bounds.Instructions := 2_000;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local s=string.rep(' ',300)..'return 1'; " &
         "pcall(function() for i=1,100 do assert(load(s)) end end)");
      Assert (Result.Status = Resource_Error, "compilation charges bytes");
      Result := Universe.Execute ("assert(assert(load('return 42'))()==42)");
      Assert (Result.Status = Succeeded, "next chunk gets a fresh budget");
   end Compilation_Work_Budget;

   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source, "test");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Assert (Length (Result.Output) = 0, "unexpected library output");
   end Check;

   procedure Text_Load is
      --  Compilation returns an unexecuted closure. Calling it later must
      --  preserve all result slots, including a nil between two values.
   begin
      Check ("local f=assert(load('return 12,nil,14')); " &
             "local a,b,c=f(); assert(a==12 and b==nil and c==14)");
   end Text_Load;

   procedure Reader_Pieces is
      --  Reader callbacks cross native/Lua frames repeatedly. Source pieces
      --  need not coincide with token boundaries, and nil terminates input.
   begin
      Check ("local a={'ret','urn ', '37'}; local n=0; " &
             "local f=assert(load(function() n=n+1; return a[n] end)); " &
             "assert(n==4 and f()==37)");
   end Reader_Pieces;

   procedure Reader_Empty_Ends is
      --  An empty reader result ends the source; the callback must not be
      --  resumed to read a deliberately invalid trailing third piece.
   begin
      Check ("local n=0; local f=assert(load(function() n=n+1; " &
             "if n==1 then return 'return 8' elseif n==2 then return '' " &
             "else error('read past end') end end)); assert(f()==8 and n==2)");
   end Reader_Empty_Ends;

   procedure Reader_Type_Error is
      --  Reader result checks occur inside C Lua's protected parser. load
      --  therefore returns nil/message instead of failing its outer pcall.
   begin
      Check ("local ok,f,e=pcall(load,function() return {} end); " &
             "assert(ok and f==nil and type(e)=='string'); " &
             "assert(assert(load('return 1'))()==1)");
   end Reader_Type_Error;

   procedure Reader_Callback_Failure is
      --  load catches reader failures at its parser boundary and returns
      --  the original error object; the enclosing pcall itself succeeds.
   begin
      Check ("local marker={}; local ok,f,e=pcall(load,function() " &
             "error(marker) end); assert(ok and f==nil and e==marker)");
   end Reader_Callback_Failure;

   procedure Repeated_Reader_Failures is
      --  Fail after retaining an initial source piece, repeat the operation,
      --  then compile successfully. Each abandoned continuation must release
      --  its partial source and preserve the exact arbitrary error object.
   begin
      Check ("local marker={}; for i=1,3 do local n=0; " &
             "local ok,f,e=pcall(load,function() n=n+1; " &
             "if n==1 then return 'return 7' end; error(marker) end); " &
             "assert(ok and f==nil and e==marker and n==2) end; " &
             "assert(assert(load('return 9'))()==9)");
   end Repeated_Reader_Failures;

   procedure Reader_Requires_Function is
      --  Callable tables are useful elsewhere but are not accepted by the
      --  base load contract, which explicitly requires a reader function.
   begin
      Check ("local r=setmetatable({}, {__call=function() return nil end}); " &
             "assert(not pcall(load,r))");
   end Reader_Requires_Function;

   procedure Reader_Options_Precede_Call is
      --  Invalid mode/chunk-name arguments fail before invoking a reader.
      --  This preserves C Lua's argument-error ordering and side effects.
   begin
      Check ("local n=0; local function reader() n=n+1; return nil end; " &
             "assert(not pcall(load,reader,nil,{})); assert(n==0); " &
             "assert(not pcall(load,reader,{})); assert(n==0)");
   end Reader_Options_Precede_Call;

   procedure Raw_Load_Has_No_Preamble is
      --  File preambles are an I/O policy. Raw load strings must preserve
      --  leading hash/BOM bytes for the scanner instead of accepting them.
   begin
      Check ("local f=load('#!/lua\nreturn 1'); assert(f==nil); " &
             "f=load('\239\187\191return 1'); assert(f==nil)");
   end Raw_Load_Has_No_Preamble;

   procedure Explicit_Environment is
      --  A loaded main closure owns an _ENV cell initialized from argument
      --  four. Neither session globals nor caller lexical locals replace it.
   begin
      Check ("local env={answer=9}; local answer=3; " &
             "local f=assert(load('return answer','env','t',env)); " &
             "env.answer=41; assert(f()==41 and answer==3)");
   end Explicit_Environment;

   procedure Persistent_Environment_Cell is
      --  Rebinding _ENV belongs to the loaded closure's captured cell, not
      --  a temporary activation. A second invocation must read that new
      --  environment without mutating the original environment table.
   begin
      Check
        ("local original={}; local f=assert(load(" &
         "'local old=_ENV; _ENV={value=(old.value or 0)+1}; " &
         "return _ENV','env','t',original)); " &
         "local a=f(); local b=f(); " &
         "assert(a.value==1 and b.value==2); " &
         "assert(original.value==nil)");
   end Persistent_Environment_Cell;

   procedure Shared_Environment_Capture is
      --  A previously returned Lua closure shares the loaded function's
      --  _ENV binding. Rebinding during a later call must also change what
      --  that older closure observes, instead of preserving a per-call copy.
   begin
      Check
        ("local f=assert(load('local old=_ENV; " &
         "_ENV={value=(old.value or 0)+1}; " &
         "return function() return value end','env','t',{})); " &
         "local first=f(); local second=f(); " &
         "assert(first()==2 and second()==2)");
   end Shared_Environment_Capture;

   procedure Explicit_Nil_Environment is
      --  Explicit nil differs from omitted environment. A constant-only
      --  chunk works, while a global lookup fails at execution time.
   begin
      Check ("assert(assert(load('return 17','nil-env','t',nil))()==17); " &
             "local f=assert(load('return print','nil-env','t',nil)); " &
             "assert(not pcall(f))");
   end Explicit_Nil_Environment;

   procedure Omitted_Environment is
      --  The default is the session global environment and remains live;
      --  compilation must not snapshot individual global values.
   begin
      Check ("loaded_global=7; " &
             "local f=assert(load('return loaded_global')); " &
             "loaded_global=11; assert(f()==11)");
   end Omitted_Environment;

   procedure Load_Syntax_Failure is
      --  Syntax diagnostics are values returned by load. A following valid
      --  load proves temporary compiler-failure flags have been restored.
   begin
      Check ("local f,e=load('local =','broken','t'); " &
             "assert(f==nil and type(e)=='string'); " &
             "assert(assert(load('return 4'))()==4)");
   end Load_Syntax_Failure;

   procedure Load_Mode_Filter is
      --  A valid text chunk is still rejected when its requested mode admits
      --  only binary chunks; the failure is catchable as nil/message.
   begin
      Check ("local f,e=load('return 1','mode','b'); " &
             "assert(f==nil and type(e)=='string')");
   end Load_Mode_Filter;

   procedure Binary_Load_Boundary is
      --  A signature alone is a truncated binary chunk. Recognition must
      --  return a controlled decoder failure without executing partial code.
   begin
      Check ("local f,e=load('\27Lua','binary','bt'); " &
             "assert(f==nil and type(e)=='string')");
   end Binary_Load_Boundary;

   procedure Nested_Loads is
      --  Loaded code may load another chunk through native continuations.
      --  This guards against recursive VM entry and reset execution budgets.
   begin
      Check ("local f=assert(load('return assert(load(""return 23""))()')); " &
             "assert(f()==23)");
   end Nested_Loads;

   procedure Preload_Cache is
      --  A successful preload loader runs once, receives module name/data,
      --  and supplies loader data only on the first require call.
   begin
      Check ("local n=0; package.preload.test_module=function(name,data) " &
             "assert(name=='test_module' and data==':preload:'); n=n+1; " &
             "return {} end; local a,d=require('test_module'); " &
             "local b,e=require('test_module'); " &
             "assert(a==b and n==1 and d==':preload:' and e==nil)");
   end Preload_Cache;

   procedure Binary_Lua_Module is
      --  Write an actual dumped module to the search path, then require it.
      --  The searcher must select the binary decoder, preserve loader data
      --  and cache the result. Remove the file before reporting a failure.
   begin
      Check ("local path='lua_ada_binary_module_test.lc'; " &
             "local f=assert(io.open(path,'wb')); " &
             "f:write(string.dump(function() return {answer=42} end)); " &
             "assert(f:close()); package.path=path; " &
             "local ok,value,data=pcall(require,'binary_fixture'); " &
             "assert(os.remove(path)); assert(ok,value); " &
             "assert(value.answer==42 and data==path); " &
             "assert(require('binary_fixture')==value)");
   end Binary_Lua_Module;

   procedure Preload_False_Reload is
      --  False is a legitimate stored module result but does not satisfy
      --  require's truthy-cache test; a second require invokes the loader.
   begin
      Check ("local n=0; package.preload.falsy=function() n=n+1; " &
             "return false end; assert(require('falsy')==false); " &
             "assert(require('falsy')==false and n==2)");
   end Preload_False_Reload;

   procedure Preload_Nil_Default is
      --  Nil loader results fall back to the registry entry; absent entries
      --  become true without introducing a Lua 5.1 loading sentinel.
   begin
      Check ("package.preload.empty=function() end; " &
             "assert(require('empty')==true); " &
             "package.preload.manual=function() " &
             "package.loaded.manual=19 end; " &
             "assert(require('manual')==19)");
   end Preload_Nil_Default;

   procedure Loaded_Registry_Identity is
      --  Replacing the public field must not redirect require's registry.
      --  The original table remains authoritative for subsequent caching.
   begin
      Check ("local original=package.loaded; local n=0; " &
             "package.preload.stable=function() n=n+1; return 42 end; " &
             "package.loaded={stable=0}; assert(require('stable')==42); " &
             "assert(original.stable==42 and n==1)");
   end Loaded_Registry_Identity;

   procedure Preload_Registry_Identity is
      --  The preload searcher retains the original registry table even when
      --  Lua replaces the visible package.preload field.
   begin
      Check ("local original=package.preload; " &
             "original.stable=function() return 43 end; " &
             "package.preload={}; assert(require('stable')==43)");
   end Preload_Registry_Identity;

   procedure Custom_Searcher_Data is
      --  Searchers and loaders are ordinary Lua callbacks. Both loader
      --  arguments and require's second return preserve arbitrary values.
   begin
      Check ("local marker={}; package.searchers={function(name) " &
             "assert(name=='custom'); return function(n,d) " &
             "assert(n=='custom' and d==marker); " &
             "return 29 end, marker end}; " &
             "local x,d=require('custom'); assert(x==29 and d==marker)");
   end Custom_Searcher_Data;

   procedure Package_Not_Found is
      --  Exhausting custom searchers raises a protected language failure.
      --  It must not poison the session or create a cached loading sentinel.
   begin
      Check ("package.searchers={function() return 'missing fixture' end}; " &
             "assert(not pcall(require,'missing')); " &
             "assert(package.loaded.missing==nil)");
   end Package_Not_Found;

   procedure Searchpath_Failure is
      --  An explicit nonexistent template has deterministic nil/message
      --  results independent of each machine's installation prefix.
   begin
      Check ("local f,e=package.searchpath('a.b','./missing-m2b/?.lua'); " &
             "assert(f==nil and type(e)=='string')");
   end Searchpath_Failure;

   procedure Loadfile_Failure is
      --  File I/O failures are ordinary loadfile nil/message results, while
      --  dofile raises the same class of failure through protected calls.
   begin
      Check ("local f,e=loadfile('./missing-m2b/no-file.lua'); " &
             "assert(f==nil and type(e)=='string'); " &
             "assert(not pcall(dofile,'./missing-m2b/no-file.lua'))");
   end Loadfile_Failure;

   procedure Resource_Recovery is
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  An endless reader cannot restart instruction accounting on each
      --  callback. After controlled abort, a later execution is still usable.
      Bounds.Instructions := 100;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("load(function() return ' ' end)");
      Assert (Result.Status = Resource_Error, "reader escaped work quota");
      Result := Universe.Execute ("assert(2+2==4)");
      Assert (Result.Status = Succeeded, "reader failure poisoned session");
   end Resource_Recovery;

   procedure Retained_Load_Environment is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  A loaded closure's private environment is a traced capture. A full
      --  host collection between executions must preserve it and its values.
      Result := Universe.Execute
        ("retained=assert(load('return item','gc','t',{item={n=31}}))");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Universe.Collect;
      Result := Universe.Execute ("assert(retained().n==31)");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Retained_Load_Environment;

   procedure Reset_Module_State is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Reset reinstalls fresh libraries and registry tables. A previously
      --  cached module or removed default searcher must not leak across it.
      Result := Universe.Execute
        ("package.loaded.old_module=55; package.searchers={}");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Universe.Reset;
      Result := Universe.Execute
        ("assert(package.loaded.old_module==nil); " &
         "assert(type(package.searchers[1])=='function')");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Reset_Module_State;

   procedure Integer_Absolute_Boundary is
      --  Integer abs preserves Lua's wrapping minimum-integer behavior;
      --  float abs remains a float and clears negative zero's sign.
   begin
      Check ("assert(math.abs(math.mininteger)==math.mininteger); " &
             "assert(math.type(math.abs(-2.0))=='float')");
   end Integer_Absolute_Boundary;

   procedure Directed_Rounding is
      --  Floor/ceil produce integers when representable and preserve large
      --  integer inputs without first rounding through binary64.
   begin
      Check ("assert(math.floor(-1.2)==-2 and math.ceil(-1.2)==-1); " &
             "assert(math.floor(math.maxinteger)==math.maxinteger); " &
             "assert(math.type(math.ceil(1.1))=='integer')");
   end Directed_Rounding;

   procedure Fmod_Sign is
      --  fmod follows the numerator's sign, unlike Lua's modulo operator.
      --  Integer min/-1 is defined as zero without an Ada overflow trap.
   begin
      Check ("assert(math.fmod(-7,3)==-1 and math.fmod(7,-3)==1); " &
             "assert(math.fmod(math.mininteger,-1)==0); " &
             "assert(math.fmod(-7.5,3.0)==-1.5)");
   end Fmod_Sign;

   procedure Modf_Integer_Boundary is
      --  modf's first result retains an integer input exactly; fractional
      --  results are floats, including zero at the 64-bit integer boundary.
   begin
      Check ("local a,b=math.modf(math.maxinteger); " &
             "assert(a==math.maxinteger and b==0 " &
             "and math.type(b)=='float'); " &
             "a,b=math.modf(-2.75); assert(a==-2 and b==-0.75)");
   end Modf_Integer_Boundary;

   procedure Numeric_Classification is
      --  tointeger permits numeric-string conversion but type classifies
      --  the actual value and never calls numeric coercion.
   begin
      Check ("assert(math.tointeger('12')==12); " &
             "assert(math.tointeger(1.5)==nil and math.type('12')==nil); " &
             "assert(math.type(12)=='integer' and math.type(12.0)=='float')");
   end Numeric_Classification;

   procedure Unsigned_Comparison is
      --  ult compares the same 64-bit integer representation as unsigned.
      --  Negative values therefore follow all nonnegative integer values.
   begin
      Check ("assert(math.ult(0,-1) and not math.ult(-1,0)); " &
             "assert(not math.ult(-1,-1))");
   end Unsigned_Comparison;

   procedure Table_Pack_Nils is
      --  Explicit n retains nil result slots that a sequence length cannot
      --  encode. unpack's requested bounds must reproduce all three results.
   begin
      Check ("local t=table.pack(1,nil,3); assert(t.n==3); " &
             "local a,b,c=table.unpack(t,1,t.n); " &
             "assert(a==1 and b==nil and c==3)");
   end Table_Pack_Nils;

   procedure Table_Move_Overlap is
      --  Moving forward through an overlapping destination must copy in
      --  reverse order. The returned destination is the original table.
   begin
      Check ("local t={1,2,3,4}; assert(table.move(t,1,3,2)==t); " &
             "assert(t[1]==1 and t[2]==1 and t[3]==2 and t[4]==3)");
   end Table_Move_Overlap;

   procedure Table_Insert_Remove is
      --  Insertion and removal shift the intervening sequence entries and
      --  return the removed value without retaining a stale terminal entry.
   begin
      Check ("local t={1,3}; table.insert(t,2,2); " &
             "assert(table.remove(t,2)==2 and t[2]==3 and t[3]==nil)");
   end Table_Insert_Remove;

   procedure Table_Concat_Empty_First is
      --  Separator placement depends on element position, not accumulated
      --  output length: an empty first string still needs its separator.
   begin
      Check ("assert(table.concat({'','b',''},':')==':b:'); " &
             "assert(table.concat({1,2},',')=='1,2')");
   end Table_Concat_Empty_First;

   procedure Table_Concat_Events is
      --  Even an explicit end bound does not bypass the initial length
      --  operation. Missing sequence entries use __index in forward order.
   begin
      Check ("local events=''; local t=setmetatable({}, {" &
             "__len=function() events=events..'L'; return 3 end," &
             "__index=function(_,i) events=events..i; return i end}); " &
             "assert(table.concat(t,':',1,2)=='1:2' and events=='L12')");
   end Table_Concat_Events;

   procedure Table_Unpack_Events is
      --  Unpack retains nil results from a Lua __index callback and adjusts
      --  only the final requested result count, without using raw storage.
   begin
      Check ("local t=setmetatable({}, {__len=function() return 3 end," &
             "__index=function(_,i) if i~=2 then return i end end}); " &
             "local a,b,c=table.unpack(t); " &
             "assert(a==1 and b==nil and c==3)");
   end Table_Unpack_Events;

   procedure Table_Insert_Events is
      --  A proxy records all writes in a backing table. Insertion must read
      --  and shift from the end so a later read sees its original source.
   begin
      Check ("local data={1,3}; local t=setmetatable({}, {" &
             "__len=function() return 2 end,__index=data," &
             "__newindex=function(_,k,v) data[k]=v end}); " &
             "table.insert(t,2,2); " &
             "assert(data[1]==1 and data[2]==2 and data[3]==3)");
   end Table_Insert_Events;

   procedure Table_Remove_Events is
      --  Removal owns the initial result across subsequent Lua writes;
      --  shifting then clears the previous final entry through __newindex.
   begin
      Check ("local data={1,2,3}; local t=setmetatable({}, {" &
             "__len=function() return 3 end,__index=data," &
             "__newindex=function(_,k,v) data[k]=v end}); " &
             "assert(table.remove(t,2)==2); " &
             "assert(data[1]==1 and data[2]==3 and data[3]==nil)");
   end Table_Remove_Events;

   procedure Table_Move_Equality_Order is
      --  The pinned implementation compares explicit destinations with Lua
      --  equality. An __eq handler can therefore select backward traversal
      --  even for distinct proxy tables; callbacks expose that exact order.
   begin
      Check ("local order=''; local src=setmetatable({}, {" &
             "__index=function(_,i) order=order..i; return i end," &
             "__eq=function() return true end}); " &
             "local data={}; local dst=setmetatable({}, {" &
             "__newindex=function(_,k,v) data[k]=v end}); " &
             "assert(rawequal(table.move(src,1,3,2,dst),dst)); " &
             "assert(order=='321' and data[2]==1 and data[4]==3)");
   end Table_Move_Equality_Order;

   procedure Table_Callback_Failure is
      --  A failing __index abandons the native traversal and partial string.
      --  The enclosing protected call handles it and later helpers still run.
   begin
      Check ("local marker={}; local t=setmetatable({}, {" &
             "__len=function() return 2 end," &
             "__index=function() error(marker) end}); " &
             "local ok,e=pcall(table.concat,t); " &
             "assert(not ok and e==marker); " &
             "assert(table.concat({'a','b'})=='ab')");
   end Table_Callback_Failure;

   procedure Table_Unpack_Explicit_End is
      --  An explicit end bypasses __len even on a nonempty traversal. Empty
      --  ranges must additionally bypass receiver indexing/type checks; an
      --  invalid start is rejected before requesting a default length.
   begin
      Check
        ("local calls=0; local t=setmetatable({1,2},{__len=function() " &
         "calls=calls+1; error('unexpected length') end}); " &
         "local a,b=table.unpack(t,1,2); assert(a==1 and b==2); " &
         "assert(select('#',table.unpack(t,3,2))==0); " &
         "assert(select('#',table.unpack(nil,3,2))==0); " &
         "assert(not pcall(table.unpack,t,{})); assert(calls==0); " &
         "assert(not pcall(table.unpack,t)); assert(calls==1)");
   end Table_Unpack_Explicit_End;

   procedure Table_Move_Maximum_Destination is
      --  The backward copy ends exactly at maxinteger. Parenthesizing the
      --  validated Count-1 offset prevents an intermediate overflow while
      --  preserving both values across the overlapping source/destination.
   begin
      Check
        ("local m=math.maxinteger; local t=setmetatable({" &
         "[m-2]='a',[m-1]='b'},{}); " &
         "assert(rawequal(table.move(t,m-2,m-1,m-1),t)); " &
         "assert(t[m-1]=='a' and t[m]=='b')");
   end Table_Move_Maximum_Destination;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "load text closure",
                        Text_Load'Access);
      Test_Support.Add (Suite, "load reader pieces",
                        Reader_Pieces'Access);
      Test_Support.Add (Suite, "load empty reader end",
                        Reader_Empty_Ends'Access);
      Test_Support.Add (Suite, "load reader result type",
                        Reader_Type_Error'Access);
      Test_Support.Add (Suite, "load reader callback error",
                        Reader_Callback_Failure'Access);
      Test_Support.Add (Suite, "load repeated reader failure recovery",
                        Repeated_Reader_Failures'Access);
      Test_Support.Add (Suite, "load requires reader function",
                        Reader_Requires_Function'Access);
      Test_Support.Add (Suite, "load reader option ordering",
                        Reader_Options_Precede_Call'Access);
      Test_Support.Add (Suite, "load raw source preamble boundary",
                        Raw_Load_Has_No_Preamble'Access);
      Test_Support.Add (Suite, "load explicit environment",
                        Explicit_Environment'Access);
      Test_Support.Add (Suite, "load persistent environment cell",
                        Persistent_Environment_Cell'Access);
      Test_Support.Add (Suite, "load shared environment capture",
                        Shared_Environment_Capture'Access);
      Test_Support.Add (Suite, "load explicit nil environment",
                        Explicit_Nil_Environment'Access);
      Test_Support.Add (Suite, "load omitted environment",
                        Omitted_Environment'Access);
      Test_Support.Add (Suite, "load syntax failure",
                        Load_Syntax_Failure'Access);
      Test_Support.Add (Suite, "load mode filtering",
                        Load_Mode_Filter'Access);
      Test_Support.Add (Suite, "load binary boundary",
                        Binary_Load_Boundary'Access);
      Test_Support.Add (Suite, "load nested calls",
                        Nested_Loads'Access);
      Test_Support.Add (Suite, "require preload cache",
                        Preload_Cache'Access);
      Test_Support.Add (Suite, "require native binary Lua module",
                        Binary_Lua_Module'Access);
      Test_Support.Add (Suite, "require false reload",
                        Preload_False_Reload'Access);
      Test_Support.Add (Suite, "require nil default",
                        Preload_Nil_Default'Access);
      Test_Support.Add (Suite, "require loaded registry identity",
                        Loaded_Registry_Identity'Access);
      Test_Support.Add (Suite, "require preload registry identity",
                        Preload_Registry_Identity'Access);
      Test_Support.Add (Suite, "require custom loader data",
                        Custom_Searcher_Data'Access);
      Test_Support.Add (Suite, "require missing module",
                        Package_Not_Found'Access);
      Test_Support.Add (Suite, "package searchpath failure",
                        Searchpath_Failure'Access);
      Test_Support.Add (Suite, "loadfile I/O failure",
                        Loadfile_Failure'Access);
      Test_Support.Add (Suite, "load reader budget recovery",
                        Resource_Recovery'Access);
      Test_Support.Add (Suite, "load compilation work budget",
                        Compilation_Work_Budget'Access);
      Test_Support.Add (Suite, "load environment GC roots",
                        Retained_Load_Environment'Access);
      Test_Support.Add (Suite, "reset module registry",
                        Reset_Module_State'Access);
      Test_Support.Add (Suite, "math abs integer boundary",
                        Integer_Absolute_Boundary'Access);
      Test_Support.Add (Suite, "math directed rounding",
                        Directed_Rounding'Access);
      Test_Support.Add (Suite, "math fmod sign",
                        Fmod_Sign'Access);
      Test_Support.Add (Suite, "math modf integer boundary",
                        Modf_Integer_Boundary'Access);
      Test_Support.Add (Suite, "math numeric classification",
                        Numeric_Classification'Access);
      Test_Support.Add (Suite, "math unsigned comparison",
                        Unsigned_Comparison'Access);
      Test_Support.Add (Suite, "table pack nil slots",
                        Table_Pack_Nils'Access);
      Test_Support.Add (Suite, "table move overlap",
                        Table_Move_Overlap'Access);
      Test_Support.Add (Suite, "table insert remove",
                        Table_Insert_Remove'Access);
      Test_Support.Add (Suite, "table concat empty first",
                        Table_Concat_Empty_First'Access);
      Test_Support.Add (Suite, "table concat metamethod events",
                        Table_Concat_Events'Access);
      Test_Support.Add (Suite, "table unpack metamethod events",
                        Table_Unpack_Events'Access);
      Test_Support.Add (Suite, "table insert metamethod events",
                        Table_Insert_Events'Access);
      Test_Support.Add (Suite, "table remove metamethod events",
                        Table_Remove_Events'Access);
      Test_Support.Add (Suite, "table move equality traversal",
                        Table_Move_Equality_Order'Access);
      Test_Support.Add (Suite, "table metamethod callback failure",
                        Table_Callback_Failure'Access);
      Test_Support.Add (Suite, "table unpack explicit end bypass",
                        Table_Unpack_Explicit_End'Access);
      Test_Support.Add (Suite, "table move maximum destination",
                        Table_Move_Maximum_Destination'Access);
   end Register;
end Library_Runtime_Tests;
