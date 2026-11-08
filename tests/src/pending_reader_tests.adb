with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Pending_Reader_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Extended_Name;
   procedure Extended_Name is
   begin
      --  A prefix ending inside a name cannot finalize that name.
      Check
        ("do" & ASCII.LF &
         "  local pieces={'local ret','urned=37;re" &
         "turn returned'}" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()calls=calls+1" &
         ";return pieces[calls]end)" & ASCII.LF &
         "  assert(f and f()==37 and calls==3,tost" &
         "ring(e))" & ASCII.LF &
         "end");
   end Extended_Name;

   procedure Extended_Number;
   procedure Extended_Number is
   begin
      --  A numeric spelling may continue in another reader piece.
      Check
        ("do" & ASCII.LF &
         "  local pieces={'return 0x1','p+2'}" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()calls=calls+1" &
         ";return pieces[calls]end)" & ASCII.LF &
         "  assert(f and f()==4 and calls==3,tostr" &
         "ing(e))" & ASCII.LF &
         "end");
   end Extended_Number;

   procedure Split_Escape;
   procedure Split_Escape is
   begin
      --  A short string's hexadecimal escape remains pending.
      Check
        ("do" & ASCII.LF &
         "  local pieces={[[return '\x]],[[41']]}" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()calls=calls+1" &
         ";return pieces[calls]end)" & ASCII.LF &
         "  assert(f and f()=='A' and calls==3,tos" &
         "tring(e))" & ASCII.LF &
         "end");
   end Split_Escape;

   procedure Split_Long_String;
   procedure Split_Long_String is
   begin
      --  Long delimiter bytes may cross reader pieces.
      Check
        ("do" & ASCII.LF &
         "  local pieces={'return [=','[value]', '" &
         "=]'}" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()calls=calls+1" &
         ";return pieces[calls]end)" & ASCII.LF &
         "  assert(f and f()=='value' and calls==4" &
         ",tostring(e))" & ASCII.LF &
         "end");
   end Split_Long_String;

   procedure Split_Comment;
   procedure Split_Comment is
   begin
      --  A comment cannot manufacture EOF or consume a following line.
      Check
        ("do" & ASCII.LF &
         "  local pieces={'--[','[not code]',']\nr" &
         "eturn 9'}" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()calls=calls+1" &
         ";return pieces[calls]end)" & ASCII.LF &
         "  assert(f and f()==9 and calls==4,tostr" &
         "ing(e))" & ASCII.LF &
         "end");
   end Split_Comment;

   procedure Pending_Error_Object;
   procedure Pending_Error_Object is
   begin
      --  An unfinished token still requests the real reader.
      Check
        ("do" & ASCII.LF &
         "  local marker={};local calls=0" & ASCII.LF &
         "  local ok,f,e=pcall(load,function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then return 'return 1e' " &
         "end" & ASCII.LF &
         "    error(marker,0)" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(ok and f==nil and e==marker and" &
         " calls==2)" & ASCII.LF &
         "end");
   end Pending_Error_Object;

   procedure Definite_Escape;
   procedure Definite_Escape is
   begin
      --  An invalid escape wins before a later reader failure.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then return [[return '\q" &
         "X]] end" & ASCII.LF &
         "    error('read after invalid escape',0)" & ASCII.LF &
         "  end,'=reader-invalid')" & ASCII.LF &
         "  assert(f==nil and calls==1 and" & ASCII.LF &
         "    e==[[reader-invalid:1: invalid escap" &
         "e sequence near ''\q']],tostring(e))" & ASCII.LF &
         "end");
   end Definite_Escape;

   procedure Delimiter_Demand;
   procedure Delimiter_Demand is
   begin
      --  A consumed token requires its real following byte.
      Check
        ("do" & ASCII.LF &
         "  local marker={};local calls=0" & ASCII.LF &
         "  local ok,f,e=pcall(load,function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then return 'local <clos" &
         "e> a,b;' end" & ASCII.LF &
         "    error(marker,0)" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(ok and f==nil and e==marker and" &
         " calls==2)" & ASCII.LF &
         "end");
   end Delimiter_Demand;

   procedure One_Byte_Text;
   procedure One_Byte_Text is
   begin
      --  Token, comment, escape and operator boundaries use one grammar.
      Check
        ("do" & ASCII.LF &
         "  local source=""-- comment\nlocal s='\\x" &
         "41';local n=0x1p+2;return s,n//2""" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1;return source:sub(call" &
         "s,calls)" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(f and calls==#source+1,tostring" &
         "(e))" & ASCII.LF &
         "  local a,b=f();assert(a=='A' and b==2)" & ASCII.LF &
         "end");
   end One_Byte_Text;

   procedure One_Byte_Binary;
   procedure One_Byte_Binary is
   begin
      --  A binary signature is never sent through the text probe.
      Check
        ("do" & ASCII.LF &
         "  local source=string.dump(function()ret" &
         "urn 37,nil,41 end)" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1;return source:sub(call" &
         "s,calls)" & ASCII.LF &
         "  end,nil,'b')" & ASCII.LF &
         "  assert(f and calls==#source,tostring(e" &
         "))" & ASCII.LF &
         "  local a,b,c=f();assert(a==37 and b==ni" &
         "l and c==41)" & ASCII.LF &
         "end");
   end One_Byte_Binary;

   procedure Actual_Empty_End;
   procedure Actual_Empty_End is
   begin
      --  Empty input supplies genuine EOF and forbids another call.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then return 'return 8' e" &
         "lseif calls==2 then return '' end" & ASCII.LF &
         "    error('read after empty input',0)" & ASCII.LF &
         "  end)" & ASCII.LF &
         "  assert(f and f()==8 and calls==2,tostr" &
         "ing(e))" & ASCII.LF &
         "end");
   end Actual_Empty_End;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "reader pending: extended name",
         Extended_Name'Access);
      Test_Support.Add
        (Suite, "reader pending: extended number",
         Extended_Number'Access);
      Test_Support.Add
        (Suite, "reader pending: split escape",
         Split_Escape'Access);
      Test_Support.Add
        (Suite, "reader pending: split long string",
         Split_Long_String'Access);
      Test_Support.Add
        (Suite, "reader pending: split comment",
         Split_Comment'Access);
      Test_Support.Add
        (Suite, "reader pending: pending error object",
         Pending_Error_Object'Access);
      Test_Support.Add
        (Suite, "reader pending: definite escape",
         Definite_Escape'Access);
      Test_Support.Add
        (Suite, "reader pending: delimiter demand",
         Delimiter_Demand'Access);
      Test_Support.Add
        (Suite, "reader pending: one byte text",
         One_Byte_Text'Access);
      Test_Support.Add
        (Suite, "reader pending: one byte binary",
         One_Byte_Binary'Access);
      Test_Support.Add
        (Suite, "reader pending: actual empty end",
         Actual_Empty_End'Access);
   end Register;
end Pending_Reader_Tests;
