with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body OS_Runtime_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Source, "os-runtime-test");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Native_Clock;
   procedure Current_Time;
   procedure Universal_Date;
   procedure Date_Table;
   procedure Date_Embedded_Nul;
   procedure Date_Table_C_Prefix;
   procedure Invalid_Date_Conversion;
   procedure Date_Integer_Argument;
   procedure Normalize_Date;
   procedure Date_Defaults;
   procedure Time_Read_Order;
   procedure Time_Write_Order;
   procedure Numeric_Date_Fields;
   procedure Missing_Date_Field;
   procedure Fractional_Date_Field;
   procedure Out_Of_Bounds_Date_Field;
   procedure Time_Setter_Failure;
   procedure Time_Callback_Cannot_Yield;
   procedure Time_Local_Roundtrip;
   procedure Native_Difference;
   procedure Locale_Query_Set;
   procedure Missing_Locale;
   procedure Missing_Environment;
   procedure Native_Remove_Failure;
   procedure Shell_Status;
   procedure Date_Argument_Order;
   procedure Locale_Argument_Order;

   procedure Native_Clock is
   begin
      --  CPU clock is a real native nonnegative number, not fabricated wall
      --  time. Do not assert a platform-dependent resolution or duration.
      Check ("local a=os.clock(); for i=1,100 do local x=i*i end; " &
             "local b=os.clock(); assert(type(a)=='number' and a>=0 and " &
             "b>=a)");
   end Native_Clock;

   procedure Current_Time is
   begin
      --  The configured native time_t is represented as a Lua integer. Both
      --  omitted and explicit nil arguments select the current clock.
      Check ("local a=os.time(); local b=os.time(nil); " &
             "assert(math.type(a)=='integer' and math.type(b)=='integer'); " &
             "assert(a>0 and b>=a)");
   end Current_Time;

   procedure Universal_Date is
   begin
      --  UTC epoch conversion is independent of the runner's local timezone.
      Check ("assert(os.date('!%Y-%m-%d %H:%M:%S',0)==" &
             "'1970-01-01 00:00:00')");
   end Universal_Date;

   procedure Date_Table is
   begin
      --  Public fields apply Lua's one-based month/week/day conventions to
      --  actual native tm fields, with isdst represented as a boolean.
      Check ("local d=os.date('!*t',0); assert(d.year==1970 and d.month==1 " &
             "and d.day==1 and d.hour==0 and d.min==0 and d.sec==0); " &
             "assert(d.wday==5 and d.yday==1 and d.isdst==false)");
   end Date_Table;

   procedure Date_Embedded_Nul is
   begin
      --  Literal formatting remains byte-counted, unlike native options.
      Check ("assert(os.date('x\0y',0)=='x\0y')");
   end Date_Embedded_Nul;

   procedure Date_Table_C_Prefix is
   begin
      --  The special *t selector is deliberately compared as a C string;
      --  bytes after its first NUL do not turn it into a format string.
      Check ("local d=os.date('!*t\0ignored',0); " &
             "assert(type(d)=='table' and d.year==1970)");
   end Date_Table_C_Prefix;

   procedure Invalid_Date_Conversion is
   begin
      --  Reject unknown/incomplete conversions before calling libc strftime.
      Check ("assert(not pcall(os.date,'%Q',0)); " &
             "assert(not pcall(os.date,'%',0)); " &
             "assert(os.date('!%%',0)=='%')");
   end Invalid_Date_Conversion;

   procedure Date_Integer_Argument is
   begin
      --  Timestamps accept numeric strings but reject fractional values.
      Check ("assert(os.date('!%Y','0')=='1970'); " &
             "assert(not pcall(os.date,'!%Y',0.5))");
   end Date_Integer_Argument;

   procedure Normalize_Date is
   begin
      --  mktime normalizes month/day and writes all resulting fields back to
      --  the same supplied table before returning its integer timestamp.
      Check ("local d={year=2023,month=13,day=32,hour=12}; " &
             "assert(math.type(os.time(d))=='integer'); " &
             "assert(d.year==2024 and d.month==2 and d.day==1); " &
             "assert(type(d.wday)=='number' and type(d.yday)=='number')");
   end Normalize_Date;

   procedure Date_Defaults is
   begin
      --  Missing hour/min/sec select noon/zero/zero rather than midnight.
      Check ("local d={year=2024,month=1,day=2}; os.time(d); " &
             "assert(d.hour==12 and d.min==0 and d.sec==0)");
   end Date_Defaults;

   procedure Time_Read_Order is
   begin
      --  Read each original date field in pinned source order through its
      --  actual __index. Intermediate continuations may not reorder reads.
      Check ("local order={}; local v={year=2024,month=1,day=2,hour=12," &
             "min=0,sec=0,isdst=false}; local d=setmetatable({}, " &
             "{__index=function(_,k) order[#order+1]=k; return v[k] end}); " &
             "os.time(d); assert(table.concat(order,',')==" &
             "'year,month,day,hour,min,sec,isdst')");
   end Time_Read_Order;

   procedure Time_Write_Order is
   begin
      --  Normalized writes also invoke real __newindex, including newly
      --  derived yday/wday and normalized isdst. No raw replacement table.
      Check ("local order={}; local v={year=2024,month=1,day=2,hour=12," &
             "min=0,sec=0,isdst=false}; local d=setmetatable({}, " &
             "{__index=v,__newindex=function(t,k,x) " &
             "order[#order+1]=k; rawset(t,k,x) end}); os.time(d); " &
             "assert(table.concat(order,',')==" &
             "'year,month,day,hour,min,sec,yday,wday,isdst')");
   end Time_Write_Order;

   procedure Numeric_Date_Fields is
   begin
      --  Exactly integral numeric strings are accepted by lua_tointegerx.
      Check ("local d={year='2024',month='1',day='2',hour='12'}; " &
             "assert(type(os.time(d))=='number'); assert(d.year==2024)");
   end Numeric_Date_Fields;

   procedure Missing_Date_Field is
   begin
      --  Mandatory omissions name the actual missing declaration field.
      Check ("local ok,e=pcall(os.time,{year=2024,month=1}); " &
             "assert(not ok and e:match(""field 'day' missing""))");
   end Missing_Date_Field;

   procedure Fractional_Date_Field is
   begin
      --  Fractional/non-numeric fields are ordinary protected Lua errors.
      Check ("local ok,e=pcall(os.time,{year=2024,month=1,day=1.5}); " &
             "assert(not ok and " &
             "e:match(""field 'day' is not an integer""))");
   end Fractional_Date_Field;

   procedure Out_Of_Bounds_Date_Field is
   begin
      --  Narrow C tm integer bounds are checked before applying year/month
      --  offsets, preventing an Ada conversion error at the native boundary.
      Check ("local ok,e=pcall(os.time," &
             "{year=math.maxinteger,month=1,day=1}); " &
             "assert(not ok and " &
             "e:match(""field 'year' is out%-of%-bound""))");
   end Out_Of_Bounds_Date_Field;

   procedure Time_Setter_Failure is
   begin
      --  A normalized field setter's own failure propagates through the
      --  state machine and leaves the session usable for later protected IO.
      Check ("local d=setmetatable({}, {__index={year=2024,month=1,day=2}, " &
             "__newindex=function() error('date setter failed') end}); " &
             "local ok,e=pcall(os.time,d); assert(not ok and " &
             "e:match('date setter failed')); " &
             "assert(os.date('!%Y',0)=='1970')");
   end Time_Setter_Failure;

   procedure Time_Callback_Cannot_Yield is
   begin
      --  Explicit continuations do not make an ordinary C-library callback
      --  yieldable. This matches os.time's direct lua_getfield boundary.
      Check ("local co=coroutine.create(function() local d=setmetatable({}, " &
             "{__index=function() coroutine.yield('forbidden') end}); " &
             "os.time(d) end); local ok,e=coroutine.resume(co); " &
             "assert(not ok and tostring(e):match('yield'))");
   end Time_Callback_Cannot_Yield;

   procedure Time_Local_Roundtrip is
   begin
      --  Real local tm information, including daylight state, round-trips
      --  through mktime without assuming the host's timezone name/offset.
      Check ("local t=1700000000; assert(os.time(os.date('*t',t))==t)");
   end Time_Local_Roundtrip;

   procedure Native_Difference is
   begin
      --  Native difftime returns a float and preserves argument order.
      Check ("assert(os.difftime(1700000001,1700000000)==1.0); " &
             "assert(os.difftime(1700000000,1700000001)==-1.0); " &
             "assert(math.type(os.difftime(1,0))=='float')");
   end Native_Difference;

   procedure Locale_Query_Set is
   begin
      --  Locale is real process state. Restore it even when the protected
      --  assertion fails, so this test cannot corrupt subsequent cases.
      Check ("local old=os.setlocale(nil,'numeric'); local ok,e=pcall(" &
             "function() assert(os.setlocale('C','numeric')); " &
             "assert(type(os.setlocale(nil,'numeric'))=='string') end); " &
             "assert(os.setlocale(old,'numeric')); assert(ok,e)");
   end Locale_Query_Set;

   procedure Missing_Locale is
   begin
      --  An actual unavailable locale returns nil and leaves the category
      --  unchanged. Do not fabricate unavailable results for real locales.
      Check ("local old=os.setlocale(nil,'numeric'); " &
             "assert(os.setlocale(" &
             "'lua_ada_nonexistent_locale_927','numeric')" &
             "==nil); assert(os.setlocale(nil,'numeric')==old)");
   end Missing_Locale;

   procedure Missing_Environment is
   begin
      --  Native getenv absence is nil, not an empty string or fake table.
      Check ("assert(os.getenv('LUA_ADA_ABSENT_FIXTURE_927_63')==nil)");
   end Missing_Environment;

   procedure Native_Remove_Failure is
   begin
      --  Real remove failure retains native errno and filename context.
      Check ("local a,b,c=os.remove('reports/no-such-directory-927/x'); " &
             "assert(a==nil and type(b)=='string' and " &
             "b:match('no%-such%-directory') and type(c)=='number' and c~=0)");
   end Native_Remove_Failure;

   procedure Shell_Status is
   begin
      --  Use the actual host shell and preserve its exit code triple. This
      --  creates no messages/files and does not invoke a reference runtime.
      Check ("assert(type(os.execute())=='boolean'); local command=" &
             "(package.config:byte(1)==92) and " &
             "'cmd /c exit /b 7' or 'exit 7';" &
             "local a,b,c=os.execute(command); " &
             "assert(a==nil and b=='exit' and c==7)");
   end Shell_Status;

   procedure Date_Argument_Order is
   begin
      --  Format validation precedes timestamp conversion, even when both
      --  arguments are invalid. Ada argument evaluation must not reorder it.
      Check ("local ok,e=pcall(os.date,{},false); " &
             "assert(not ok and e:find('string expected',1,true))");
   end Date_Argument_Order;

   procedure Locale_Argument_Order is
   begin
      --  The locale name is checked before the category option. An invalid
      --  category must not hide a first-argument type failure.
      Check ("local ok,e=pcall(os.setlocale,{},'?'); " &
             "assert(not ok and e:find('string expected',1,true))");
   end Locale_Argument_Order;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "OS: native CPU clock", Native_Clock'Access);
      Test_Support.Add (Suite, "OS: current integer time",
                        Current_Time'Access);
      Test_Support.Add (Suite, "OS: deterministic UTC date",
                        Universal_Date'Access);
      Test_Support.Add (Suite, "OS: one-based public date fields",
                        Date_Table'Access);
      Test_Support.Add (Suite, "OS: date literal embedded NUL",
                        Date_Embedded_Nul'Access);
      Test_Support.Add (Suite, "OS: special date table C prefix",
                        Date_Table_C_Prefix'Access);
      Test_Support.Add (Suite, "OS: invalid date conversions controlled",
                        Invalid_Date_Conversion'Access);
      Test_Support.Add (Suite, "OS: integral timestamp validation",
                        Date_Integer_Argument'Access);
      Test_Support.Add (Suite, "OS: actual date normalization",
                        Normalize_Date'Access);
      Test_Support.Add (Suite, "OS: date optional field defaults",
                        Date_Defaults'Access);
      Test_Support.Add (Suite, "OS: date field callback read order",
                        Time_Read_Order'Access);
      Test_Support.Add (Suite, "OS: normalized field callback write order",
                        Time_Write_Order'Access);
      Test_Support.Add (Suite, "OS: integral numeric-string fields",
                        Numeric_Date_Fields'Access);
      Test_Support.Add (Suite, "OS: missing mandatory date field",
                        Missing_Date_Field'Access);
      Test_Support.Add (Suite, "OS: fractional date field rejected",
                        Fractional_Date_Field'Access);
      Test_Support.Add (Suite, "OS: C date field bounds checked",
                        Out_Of_Bounds_Date_Field'Access);
      Test_Support.Add (Suite, "OS: normalized setter error and recovery",
                        Time_Setter_Failure'Access);
      Test_Support.Add (Suite, "OS: date callback remains nonyieldable",
                        Time_Callback_Cannot_Yield'Access);
      Test_Support.Add (Suite, "OS: local date roundtrip preserves daylight",
                        Time_Local_Roundtrip'Access);
      Test_Support.Add (Suite, "OS: native time difference",
                        Native_Difference'Access);
      Test_Support.Add (Suite, "OS: real locale query and restore",
                        Locale_Query_Set'Access);
      Test_Support.Add (Suite, "OS: unavailable locale does not change state",
                        Missing_Locale'Access);
      Test_Support.Add (Suite, "OS: absent environment value is nil",
                        Missing_Environment'Access);
      Test_Support.Add (Suite, "OS: native remove failure tuple",
                        Native_Remove_Failure'Access);
      Test_Support.Add (Suite, "OS: actual shell status triple",
                        Shell_Status'Access);
      Test_Support.Add (Suite, "OS: date checks format before timestamp",
                        Date_Argument_Order'Access);
      Test_Support.Add (Suite, "OS: locale checks name before category",
                        Locale_Argument_Order'Access);
   end Register;
end OS_Runtime_Tests;
