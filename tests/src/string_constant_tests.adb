with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body String_Constant_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Large_Prefix_Count;
   procedure Large_Prefix_Count is
      Source : Unbounded_String;
   begin
      --  Repeated earlier global keys retain the same live call shape.
      for Index in 1 .. 300 loop
         Append (Source, "assert(true);");
      end loop;
      Append (Source,
        ("local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for" &
         " i=1,1000 do end;assert(1000<a and a<1012);debug.sethook(" &
         ")"));
      Check (To_String (Source));
   end Large_Prefix_Count;

   procedure Exact_Byte_Values;
   procedure Exact_Byte_Values is
   begin
      --  String keys distinguish case and embedded NUL bytes.
      Check
        ("local a,b,c,d='key','Key','key\0x','key\0y';assert(a~=b a" &
         "nd c~=d and #c==5 and #d==5);assert(select(1,'key','key')" &
         "=='key')");
   end Exact_Byte_Values;

   procedure Long_String_Values;
   procedure Long_String_Values is
   begin
      --  Repeated long literals keep their bytes through collection.
      Check
        ("local function f()return 'abcdefghijklmnopqrstuvwxyz01234" &
         "56789ABCDEFGHIJKLMN','abcdefghijklmnopqrstuvwxyz012345678" &
         "9ABCDEFGHIJKLMN' end;local a,b=f();collectgarbage();asser" &
         "t(a==b and #a==50 and a:sub(-3)=='LMN')");
   end Long_String_Values;

   procedure Function_Local_Indexes;
   procedure Function_Local_Indexes is
   begin
      --  Children keep independent constant indexes and literal order.
      Check
        ("local root='root';local function a()return 'left','right'" &
         ",'left' end;local function b()return 'right','left','righ" &
         "t' end;local x,y,z=a();local p,q,r=b();assert(root=='root" &
         "' and x=='left' and y=='right' and z=='left' and p=='righ" &
         "t' and q=='left' and r=='right')");
   end Function_Local_Indexes;

   procedure Exact_Index_Keys;
   procedure Exact_Index_Keys is
   begin
      --  Indexed field lookups preserve case and NUL identity.
      Check
        ("local seen={};local t=setmetatable({},{__index=function(_" &
         ",k)seen[#seen+1]=k;return k end});assert(t.key=='key' and" &
         " t.Key=='Key' and t['key\0x']=='key\0x' and t['key\0y']==" &
         "'key\0y');assert(#seen==4 and seen[1]~=seen[2] and seen[3" &
         "]~=seen[4])");
   end Exact_Index_Keys;

   procedure Typed_Constants;
   procedure Typed_Constants is
   begin
      --  String reuse cannot collapse integer and floating constants.
      Check
        ("local function f()return '1',1,1.0,'1' end;local a,b,c,d=" &
         "f();assert(a==d and type(a)=='string' and math.type(b)=='" &
         "integer' and math.type(c)=='float')");
   end Typed_Constants;

   procedure Source_Anchor_Retention;
   procedure Source_Anchor_Retention is
   begin
      --  A retained child keeps source anchors after key-cache growth.
      Check
        ("local src=string.rep('assert(true)\n',300)..""return funct" &
         "ion()return 'kept'end"";local f=assert(load(src,'=cache-li" &
         "nes'))();collectgarbage();local i=debug.getinfo(f,'S');as" &
         "sert(i.source=='=cache-lines' and i.linedefined==301 and " &
         "i.lastlinedefined==301 and f()=='kept')");
   end Source_Anchor_Retention;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "string constant: Large_Prefix_Count",
         Large_Prefix_Count'Access);
      Test_Support.Add
        (Suite, "string constant: Exact_Byte_Values",
         Exact_Byte_Values'Access);
      Test_Support.Add
        (Suite, "string constant: Long_String_Values",
         Long_String_Values'Access);
      Test_Support.Add
        (Suite, "string constant: Function_Local_Indexes",
         Function_Local_Indexes'Access);
      Test_Support.Add
        (Suite, "string constant: Exact_Index_Keys",
         Exact_Index_Keys'Access);
      Test_Support.Add
        (Suite, "string constant: Typed_Constants",
         Typed_Constants'Access);
      Test_Support.Add
        (Suite, "string constant: Source_Anchor_Retention",
         Source_Anchor_Retention'Access);
   end Register;
end String_Constant_Tests;
