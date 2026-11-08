with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Table_Storage_Public_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Anonymous_Key;
   procedure Anonymous_Key is
   begin
      --  The original collectable key dies after public deletion.
      Check
        ("do" & ASCII.LF &
         "  collectgarbage('stop')" & ASCII.LF &
         "  local a = {[{}] = 4, [3] = 0, alo = 1," & ASCII.LF &
         "             a12345678901234567890123456" &
         "78901234567890 = 10}" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "})" & ASCII.LF &
         "  local count=0" & ASCII.LF &
         "  for k in pairs(a)do" & ASCII.LF &
         "    count=count+1" & ASCII.LF &
         "    if type(k)=='table'then weak[1]=k en" &
         "d" & ASCII.LF &
         "  end" & ASCII.LF &
         "  assert(count==4 and type(weak[1])=='ta" &
         "ble')" & ASCII.LF &
         "  for k in pairs(a)do a[k]=nil end" & ASCII.LF &
         "  collectgarbage()" & ASCII.LF &
         "  assert(weak[1]==nil and next(a)==nil)" & ASCII.LF &
         "  collectgarbage('restart')" & ASCII.LF &
         "end");
   end Anonymous_Key;

   procedure Live_Key;
   procedure Live_Key is
   begin
      --  An actually reachable object key and its value survive collection.
      Check
        ("do" & ASCII.LF &
         "  local key={};local value={payload=37};" &
         "local a={[key]=value}" & ASCII.LF &
         "  local weak=setmetatable({key},{__mode=" &
         "'v'})" & ASCII.LF &
         "  collectgarbage()" & ASCII.LF &
         "  assert(weak[1]==key and a[key]==value " &
         "and a[key].payload==37)" & ASCII.LF &
         "  local count=0" & ASCII.LF &
         "  for k,v in pairs(a)do" & ASCII.LF &
         "    count=count+1;assert(k==key and v==v" &
         "alue)" & ASCII.LF &
         "  end" & ASCII.LF &
         "  assert(count==1)" & ASCII.LF &
         "end");
   end Live_Key;

   procedure Same_Table;
   procedure Same_Table is
   begin
      --  A collected object key cannot corrupt later use of that table.
      Check
        ("do" & ASCII.LF &
         "  collectgarbage('stop')" & ASCII.LF &
         "  local a={[{}]=4,[3]=0,alo=1," & ASCII.LF &
         "           a1234567890123456789012345678" &
         "901234567890=10}" & ASCII.LF &
         "  local weak=setmetatable({},{__mode='v'" &
         "})" & ASCII.LF &
         "  for k in pairs(a)do if type(k)=='table" &
         "'then weak[1]=k end end" & ASCII.LF &
         "  for k in pairs(a)do a[k]=nil end" & ASCII.LF &
         "  collectgarbage()" & ASCII.LF &
         "  assert(weak[1]==nil and next(a)==nil)" & ASCII.LF &
         "  local fresh={};a[fresh]=42;a[3]=17;a.a" &
         "lo=29" & ASCII.LF &
         "  collectgarbage()" & ASCII.LF &
         "  local count=0" & ASCII.LF &
         "  for k,v in pairs(a)do" & ASCII.LF &
         "    count=count+1" & ASCII.LF &
         "    assert((k==fresh and v==42)or(k==3 a" &
         "nd v==17)or(k=='alo'and v==29))" & ASCII.LF &
         "  end" & ASCII.LF &
         "  assert(count==3 and a[fresh]==42 and a" &
         "[3]==17 and a.alo==29)" & ASCII.LF &
         "  collectgarbage('restart')" & ASCII.LF &
         "end");
   end Same_Table;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "table storage: anonymous key",
         Anonymous_Key'Access);
      Test_Support.Add
        (Suite, "table storage: live key",
         Live_Key'Access);
      Test_Support.Add
        (Suite, "table storage: same table",
         Same_Table'Access);
   end Register;
end Table_Storage_Public_Tests;
