with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces.C;
with Lua.Runtime_Configuration;
with Lua.Storage.Conformance;
with System;

package body Lua.Conformance_Allocator is
   use type Lua.Storage.Byte_Count;
   use type Interfaces.C.size_t;
   use type Lua.Storage.Owner_Access;
   use type System.Address;
   subtype Count is Lua.Storage.Byte_Count;

   --  This observer belongs to the single-universe test process driver, not
   --  to the runtime. In particular production sessions keep their original
   --  providers and independently owned accounting. The owner borrow below
   --  is used only during a live allocator callback, never by Finish.
   Memory : Lua.Storage.Owner_Access;
   Provider : Lua.Storage.Allocation_Function;
   Provider_Data : System.Address;
   Live_Bytes, Live_Blocks, Peak_Bytes, Refusals : Count := 0;
   Attached, Finished, Fault : Boolean := False;
   Host_Limit, Test_Limit : Count := Count'Last;
   Countdown, Provider_Refusals : Count := 0;
   Injecting : Boolean := False;

   function Attached_To (Memory : not null Lua.Storage.Owner_Access)
                         return Boolean is
     (Attached and then not Finished and then
      Memory = Conformance_Allocator.Memory);

   function Measurements return Provider_Statistics is
     ((Live_Bytes, Live_Blocks, Peak_Bytes, Provider_Refusals));

   procedure Set_Byte_Limit (Bytes : Count) is
   begin
      Test_Limit := (if Bytes = 0 then Count'Last else Bytes);
   end Set_Byte_Limit;

   procedure Set_Count_Limit (Growths : Count) is
   begin
      Countdown := Growths;
      Injecting := True;
   end Set_Count_Limit;

   procedure Clear_Count_Limit is
   begin
      Injecting := False;
   end Clear_Count_Limit;

   function Process_ID return Interfaces.C.unsigned_long
     with Import, Convention => C,
          External_Name => "lua_ada_test_process_id";
   function Allocate
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;

   function Allocate
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
      pragma Unreferenced (Data);
      Result : System.Address;
      Old : constant Count := Count (Old_Size);
      New_Count : constant Count := Count (New_Size);
      Remaining : Count;
      Ceiling : constant Count := Count'Min (Host_Limit, Test_Limit);
   begin
      --  Owner-side limits can refuse before reaching this callback. Every
      --  later callback, including final releases, snapshots that real count
      --  while the owner is still alive. Provider refusal is also observed
      --  without changing its null-return contract or touching the old block.
      Refusals := Lua.Storage.Statistics (Memory.all).Refusals;
      --  Test controls belong to this actual shared provider. A newly
      --  constructed state has its own Storage.Owner but inherits this
      --  callback; limiting only the original owner would let it bypass both
      --  byte and growth-count refusal. The host ceiling stays independent.
      --  Refusal precedes the backing call and changes no live ownership.
      if Block /= System.Null_Address and then
        (Old > Live_Bytes or else Live_Blocks = 0)
      then
         Fault := True;
         return System.Null_Address;
      end if;
      Remaining := Live_Bytes -
        (if Block = System.Null_Address then 0 else Old);
      if New_Count > (if Block = System.Null_Address then 0 else Old) and then
        (Remaining > Ceiling or else New_Count > Ceiling - Remaining or else
         (Injecting and then Countdown = 0))
      then
         Provider_Refusals := Provider_Refusals + 1;
         return System.Null_Address;
      end if;
      Result := Provider (Provider_Data, Block, Old_Size, New_Size);
      if New_Size /= 0 and then Result = System.Null_Address then
         Provider_Refusals := Provider_Refusals + 1;
         return Result;
      end if;
      if Block /= System.Null_Address then
         if Old > Live_Bytes or else Live_Blocks = 0 then
            Fault := True;
         else
            Live_Bytes := Live_Bytes - Old;
            Live_Blocks := Live_Blocks - 1;
         end if;
      end if;
      if New_Size /= 0 then
         Live_Bytes := Live_Bytes + New_Count;
         Live_Blocks := Live_Blocks + 1;
         Peak_Bytes := Count'Max (Peak_Bytes, Live_Bytes);
         if Injecting and then
           New_Count > (if Block = System.Null_Address then 0 else Old)
         then
            Countdown := Countdown - 1;
         end if;
      end if;
      return Result;
   exception
      when others =>
         --  No Ada exception crosses the C-convention allocator boundary.
         --  A fault cannot become accepted evidence even if Lua catches the
         --  resulting allocation refusal; Finish fails the whole process.
         Fault := True;
         return System.Null_Address;
   end Allocate;

   procedure Attach (Memory : not null Lua.Storage.Owner_Access) is
      Initial : constant Lua.Storage.Allocation_Statistics :=
        Lua.Storage.Statistics (Memory.all);
   begin
      if Attached and then not Finished then
         raise Program_Error with "test allocator already attached";
      end if;
      Conformance_Allocator.Memory := Memory;
      Provider := Lua.Storage.Allocator (Memory.all);
      Provider_Data := Lua.Storage.Userdata (Memory.all);
      Live_Bytes := Initial.Raw_Bytes;
      Live_Blocks := Initial.Live_Blocks;
      Peak_Bytes := Initial.Peak_Raw_Bytes;
      Refusals := Initial.Refusals;
      Attached := True;
      Finished := False;
      Fault := False;
      Host_Limit := Lua.Storage.Conformance.Allocation_Ceiling (Memory.all);
      Test_Limit := Count'Last;
      Injecting := False;
      Provider_Refusals := 0;
      Lua.Storage.Set_Allocator (Memory.all, Allocate'Access);
   end Attach;

   procedure Finish is
      use Ada.Environment_Variables;
      use Ada.Text_IO;
      function Expected_Warnings return Interfaces.C.unsigned_long_long
        with Import, Convention => C,
             External_Name => "lua_ada_test_expected_finalizer_warnings";
   begin
      if not Attached or else Finished then return; end if;
      Finished := True;
      if Exists ("LUA_ADA_CONFORMANCE_TELEMETRY") then
         declare
            Run_ID : constant String :=
              Value ("LUA_ADA_CONFORMANCE_RUN_ID", "");
            PID : constant String := Ada.Strings.Fixed.Trim
              (Process_ID'Image, Ada.Strings.Both);
            Output : File_Type;
         begin
            if Run_ID'Length = 0 then
               raise Program_Error with "missing telemetry run ID";
            end if;
            for Byte of Run_ID loop
               if Byte not in '0' .. '9' | 'a' .. 'f' | '-' then
                  raise Program_Error with "invalid telemetry run ID";
               end if;
            end loop;
            Create (Output, Out_File,
                    Value ("LUA_ADA_CONFORMANCE_TELEMETRY") &
                    "." & PID & ".json");
            Put_Line (Output,
              "{""schema_version"":1,""run_id"":""" & Run_ID &
              """,""process_id"":" & PID &
              ",""configuration"":""" & Lua.Runtime_Configuration.Name &
              """,""allocator_limit_bytes"":" & Host_Limit'Image & "," &
              """managed_refusals"":" & Refusals'Image &
              ",""provider_refusals"":" & Provider_Refusals'Image &
              ",""outstanding_bytes"":" & Live_Bytes'Image &
              ",""outstanding_blocks"":" & Live_Blocks'Image &
              ",""peak_managed_bytes"":" & Peak_Bytes'Image &
              ",""expected_finalizer_warnings"":" &
              Expected_Warnings'Image &
              ",""shutdown_complete"":true,""accounting_fault"":" &
              (if Fault then "true" else "false") & "}");
            Close (Output);
         exception
            when others =>
               if Is_Open (Output) then Close (Output); end if;
               raise;
         end;
      end if;
      if Fault or else Live_Bytes /= 0 or else Live_Blocks /= 0 then
         raise Program_Error with "unbalanced test allocator at shutdown";
      end if;
   end Finish;
end Lua.Conformance_Allocator;
