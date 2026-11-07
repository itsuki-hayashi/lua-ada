with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Native_Return_Window_Tests is
   Capture : constant String :=
     "local function capture(fn,...)local record;debug.sethook(" &
     "function(event)if event=='return' then local info=debug.g" &
     "etinfo(2,'fr');if info.func==fn then local values={n=info" &
     ".ntransfer};for i=info.ftransfer,info.ftransfer+info.ntra" &
     "nsfer-1 do local n,v=debug.getlocal(2,i);assert(n=='(C te" &
     "mporary)');values[i-info.ftransfer+1]=v end;record={first" &
     "=info.ftransfer,count=info.ntransfer,values=values}end en" &
     "d end,'r');local result=table.pack(fn(...));debug.sethook" &
     "();assert(record);return record,result end;";
   --  Observe a real builtin return through the public Lua hook/local APIs.
   --  Preserve nil results explicitly and compare them with the caller's
   --  independently received packet. No synthetic event/value is supplied.

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Capture & Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Math_Appended_Result;
   procedure Math_Appended_Result is
   begin
      --  A builtin publishes its actual numeric result after its arguments.
      --  The return hook reads the same result returned to the Lua caller.
      Check
        ("local p,r=capture(math.sin,3);assert(p.first==2 and p.cou" &
         "nt==1 and p.values[1]==r[1] and p.values[1]~=3)");
   end Math_Appended_Result;

   procedure Equal_Math_Result_Appends;
   procedure Equal_Math_Result_Appends is
   begin
      --  Equal argument/result values do not determine return placement.
      --  math.abs appends even when the returned number equals its input.
      Check
        ("local p,r=capture(math.abs,4);assert(p.first==2 and p.cou" &
         "nt==1 and p.values[1]==4 and r[1]==4)");
   end Equal_Math_Result_Appends;

   procedure Assert_Existing_Arguments;
   procedure Assert_Existing_Arguments is
   begin
      --  Assert returns its actual existing argument range.
      --  Its return hook sees the original boolean and trailing values.
      Check
        ("local p,r=capture(assert,true,12,13);assert(p.first==1 an" &
         "d p.count==3 and p.values[1]==true and p.values[2]==12 an" &
         "d p.values[3]==13 and r.n==3)");
   end Assert_Existing_Arguments;

   procedure Select_Existing_Suffix;
   procedure Select_Existing_Suffix is
   begin
      --  Numeric select returns an existing suffix of the argument window.
      --  Inspect its actual start and all selected values.
      Check
        ("local p,r=capture(select,2,10,20,30,40);assert(p.first==3" &
         " and p.count==3 and p.values[1]==20 and p.values[2]==30 a" &
         "nd p.values[3]==40 and r.n==3)");
   end Select_Existing_Suffix;

   procedure Select_Count_Appends;
   procedure Select_Count_Appends is
   begin
      --  Count-form select creates a new result after its arguments.
      --  Its placement differs from the numeric existing-suffix operation.
      Check
        ("local p,r=capture(select,'#',10,20);assert(p.first==4 and" &
         " p.count==1 and p.values[1]==2 and r[1]==2)");
   end Select_Count_Appends;

   procedure Tonumber_Numeric_Reuse;
   procedure Tonumber_Numeric_Reuse is
   begin
      --  Tonumber retains an already numeric argument as its result.
      --  Its actual result slot stays at the first argument.
      Check
        ("local p,r=capture(tonumber,12);assert(p.first==1 and p.co" &
         "unt==1 and p.values[1]==12 and r[1]==12)");
   end Tonumber_Numeric_Reuse;

   procedure Tonumber_Text_Appends;
   procedure Tonumber_Text_Appends is
   begin
      --  Converting text creates a new numeric result after the input.
      --  The return hook must not read the original string argument.
      Check
        ("local p,r=capture(tonumber,'12');assert(p.first==2 and p." &
         "count==1 and type(p.values[1])=='number' and p.values[1]=" &
         "=12 and r[1]==12)");
   end Tonumber_Text_Appends;

   procedure Rawget_Replaces_Key;
   procedure Rawget_Replaces_Key is
   begin
      --  Rawget consumes its key and places the looked-up value there.
      --  The hook observes the real result in that second slot.
      Check
        ("local p,r=capture(rawget,{x=41},'x');assert(p.first==2 an" &
         "d p.count==1 and p.values[1]==41 and r[1]==41)");
   end Rawget_Replaces_Key;

   procedure Rawset_Returns_Table;
   procedure Rawset_Returns_Table is
   begin
      --  Rawset consumes the key/value and returns the original table.
      --  Both hook and caller receive that same table identity.
      Check
        ("local t={};local p,r=capture(rawset,t,'x',41);assert(p.fi" &
         "rst==1 and p.count==1 and p.values[1]==t and r[1]==t and " &
         "t.x==41)");
   end Rawset_Returns_Table;

   procedure Pcall_Success_Prefix;
   procedure Pcall_Success_Prefix is
   begin
      --  Protected success publishes its status and actual child results.
      --  The return hook reads that complete existing result range.
      Check
        ("local p,r=capture(pcall,function()return 11,22 end);asser" &
         "t(p.first==1 and p.count==3 and p.values[1]==true and p.v" &
         "alues[2]==11 and p.values[3]==22 and r.n==3)");
   end Pcall_Success_Prefix;

   procedure Pcall_Error_Range;
   procedure Pcall_Error_Range is
   begin
      --  Protected failure publishes the status and original error object.
      --  Its actual result range differs from the success path.
      Check
        ("local p,r=capture(pcall,function()error(17)end);assert(p." &
         "first==3 and p.count==2 and p.values[1]==false and p.valu" &
         "es[2]==17 and r[1]==false and r[2]==17)");
   end Pcall_Error_Range;

   procedure Gmatch_Argument_Replacement;
   procedure Gmatch_Argument_Replacement is
   begin
      --  The gmatch iterator replaces the actual argument window.
      --  The hook and caller retain one real callable closure and its state.
      Check
        ("local p,r=capture(string.gmatch,'abc','.');assert(p.first" &
         "==1 and p.count==1 and type(p.values[1])=='function' and " &
         "p.values[1]==r[1]);assert(r[1]()=='a')");
   end Gmatch_Argument_Replacement;

   procedure Pairs_Four_Results;
   procedure Pairs_Four_Results is
   begin
      --  Lua 5.5 default pairs publishes four results, including its closer.
      --  The two trailing nils retain their explicit result count.
      Check
        ("local t={};local p,r=capture(pairs,t);assert(p.first==2 a" &
         "nd p.count==4 and p.values.n==4 and type(p.values[1])=='f" &
         "unction' and p.values[2]==t and p.values[3]==nil and p.va" &
         "lues[4]==nil and r.n==4)");
   end Pairs_Four_Results;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "native return: Math_Appended_Result",
         Math_Appended_Result'Access);
      Test_Support.Add
        (Suite, "native return: Equal_Math_Result_Appends",
         Equal_Math_Result_Appends'Access);
      Test_Support.Add
        (Suite, "native return: Assert_Existing_Arguments",
         Assert_Existing_Arguments'Access);
      Test_Support.Add
        (Suite, "native return: Select_Existing_Suffix",
         Select_Existing_Suffix'Access);
      Test_Support.Add
        (Suite, "native return: Select_Count_Appends",
         Select_Count_Appends'Access);
      Test_Support.Add
        (Suite, "native return: Tonumber_Numeric_Reuse",
         Tonumber_Numeric_Reuse'Access);
      Test_Support.Add
        (Suite, "native return: Tonumber_Text_Appends",
         Tonumber_Text_Appends'Access);
      Test_Support.Add
        (Suite, "native return: Rawget_Replaces_Key",
         Rawget_Replaces_Key'Access);
      Test_Support.Add
        (Suite, "native return: Rawset_Returns_Table",
         Rawset_Returns_Table'Access);
      Test_Support.Add
        (Suite, "native return: Pcall_Success_Prefix",
         Pcall_Success_Prefix'Access);
      Test_Support.Add
        (Suite, "native return: Pcall_Error_Range",
         Pcall_Error_Range'Access);
      Test_Support.Add
        (Suite, "native return: Gmatch_Argument_Replacement",
         Gmatch_Argument_Replacement'Access);
      Test_Support.Add
        (Suite, "native return: Pairs_Four_Results",
         Pairs_Four_Results'Access);
   end Register;
end Native_Return_Window_Tests;
