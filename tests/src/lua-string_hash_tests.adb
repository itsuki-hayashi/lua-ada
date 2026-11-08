with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Conformance_Adapter;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Engine.Machine;
with Lua.Storage;
with Test_Support;

package body Lua.String_Hash_Tests is
   use type Integer_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Storage.Byte_Count;
   package VM renames Lua.Engine.Machine;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   procedure Check (Source : String; Install : Boolean := True);
   procedure Check (Source : String; Install : Boolean := True) is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         if Install then Conformance_Adapter.Install (State); end if;
         Assert (Execute (State, Source, "=string-hash-test"),
                 Failure_Image (State.Current));
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "string hash fixture retains selected storage");
   end Check;

   procedure Public_Case (Name : String);
   procedure Public_Case (Name : String) is
   begin
      --  The same mandatory-T source runs on native T. It compares content
      --  hash invariants and real key operations, never numeric hash literals.
      Check ("assert(loadfile('tests/lua/string_hash_invariants.lua'))('" &
             Name & "')");
   end Public_Case;

   procedure Cached_Field
     (Forced : Interfaces.Unsigned_64; Expected : Integer_Value);
   procedure Cached_Field
     (Forced : Interfaces.Unsigned_64; Expected : Integer_Value)
   is
      State : World_Access := new World;
      Driver : VM.Driver;
      Subject : Value := Nil_Value;
      Helper, Module : Value;
      Original : Interfaces.Unsigned_64 := 0;
      Changed : Boolean := False;

      procedure Restore;
      procedure Restore is
      begin
         if Changed then
            Subject.Reference.String_Hash := Original;
            Changed := False;
         end if;
      end Restore;
   begin
      Initialize (State.all, (others => <>));
      begin
         Conformance_Adapter.Install (State.all);
         Module := Get (Global_Environment (State.all),
                        New_String (State.all, "T"));
         Helper := Get (Module, New_String (State.all, "hash"));
         Subject := New_String (State.all, String'(1 .. 97 => 'q'));
         Append_Root (State.all, State.Current.Arguments, Subject);
         Assert (not Subject.Reference.Interned,
                 "cached hash probe requires a noninterned long string");
         Original := Subject.Reference.String_Hash;
         Assert (Original /= Forced, "cached hash witness is unchanged");
         VM.Start (Driver, State, Helper, State.Current.Arguments);

         --  Setup/callee lookup is complete. This string is an argument and
         --  traced value, never a table key or intern-chain member. Alter only
         --  its cached field, then call the actual installed C/Ada query. A
         --  byte recomputation, constant answer or 32-bit truncation fails.
         Subject.Reference.String_Hash := Forced;
         Changed := True;
         while not VM.Is_Complete (Driver) loop
            if VM.Needs_Foreign_Call (Driver) then
               Foreign.Invoke_Borrowed (State.all, Driver);
            else
               VM.Step (Driver);
            end if;
         end loop;
         --  Restore before result inspection, any key lookup and physical
         --  cleanup, including the exceptional driver-cancellation path.
         Restore;
         Assert (VM.Outcome (Driver) = Completed and then
                 Natural (VM.Results (Driver).Length) = 1 and then
                 VM.Results (Driver).First_Element =
                   Value'(Integer_Kind, Expected),
                 "hash query did not expose the actual full cached field");
         VM.Finish (Driver);
      exception
         when others =>
            Restore;
            VM.Cancel (Driver);
            Finalize (State.all);
            Free_World (State);
            raise;
      end;
      Finalize (State.all);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "cached hash probe retains selected storage");
      Free_World (State);
   end Cached_Field;

   procedure Cached_Low;
   procedure Cached_Low is
   begin
      Cached_Field (16#0123_4567_89AB_CDEF#, 81_985_529_216_486_895);
   end Cached_Low;

   procedure Cached_High;
   procedure Cached_High is
   begin
      Cached_Field (16#FEDC_BA98_7654_3210#, -81_985_529_216_486_896);
   end Cached_High;

   procedure Length_0;
   procedure Length_0 is
   begin
      Public_Case ("Length_0");
   end Length_0;

   procedure Length_10;
   procedure Length_10 is
   begin
      Public_Case ("Length_10");
   end Length_10;

   procedure Length_39;
   procedure Length_39 is
   begin
      Public_Case ("Length_39");
   end Length_39;

   procedure Length_40;
   procedure Length_40 is
   begin
      Public_Case ("Length_40");
   end Length_40;

   procedure Length_41;
   procedure Length_41 is
   begin
      Public_Case ("Length_41");
   end Length_41;

   procedure Length_1000;
   procedure Length_1000 is
   begin
      Public_Case ("Length_1000");
   end Length_1000;

   procedure Binary_Content;
   procedure Binary_Content is
   begin
      Public_Case ("Binary");
   end Binary_Content;

   procedure Invalid_Type;
   procedure Invalid_Type is
   begin
      Public_Case ("Invalid_Type");
   end Invalid_Type;

   procedure Extra_Arguments;
   procedure Extra_Arguments is
   begin
      --  This explicitly narrower Ada invariant has no C physical-position
      --  overload. These are adapter-contract checks, not native-paired cases.
      Check ("for _,v in ipairs{false,{},'extra'}do " &
        "local ok,e=pcall(T.hash,'x',v);" &
        "assert(not ok and type(e)=='string')end;" &
        "assert(not pcall(T.hash,'x',nil));" &
        "assert(select('#',T.hash('retry'))==1)");
   end Extra_Arguments;

   procedure Default_Absent;
   procedure Default_Absent is
   begin
      --  An ordinary world never installs T. The mandatory fixture must fail
      --  there; this negative proves absence, not omitted hash coverage.
      Check ("assert(rawget(_G,'T')==nil);local f=" &
        "assert(loadfile('tests/lua/string_hash_invariants.lua'));" &
        "local ok,e=pcall(f);assert(not ok and type(e)=='string')",
        Install => False);
   end Default_Absent;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "string hash: actual cached low field",
                        Cached_Low'Access);
      Test_Support.Add (Suite, "string hash: full high-bit field",
                        Cached_High'Access);
      Test_Support.Add (Suite, "string hash: length zero", Length_0'Access);
      Test_Support.Add (Suite, "string hash: length ten", Length_10'Access);
      Test_Support.Add (Suite, "string hash: length thirty-nine",
                        Length_39'Access);
      Test_Support.Add (Suite, "string hash: length forty", Length_40'Access);
      Test_Support.Add (Suite, "string hash: length forty-one",
                        Length_41'Access);
      Test_Support.Add (Suite, "string hash: length one thousand",
                        Length_1000'Access);
      Test_Support.Add (Suite, "string hash: binary payload",
                        Binary_Content'Access);
      Test_Support.Add (Suite, "string hash: strict string type",
                        Invalid_Type'Access);
      Test_Support.Add (Suite, "string hash: extra argument rejection",
                        Extra_Arguments'Access);
      Test_Support.Add (Suite, "string hash: default absence",
                        Default_Absent'Access);
   end Register;
end Lua.String_Hash_Tests;
