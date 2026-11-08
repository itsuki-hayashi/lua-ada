with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Conformance_Adapter;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Lua.Opcodes;
with Lua.Prototypes;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Nextvar_Storage_Tests is
   use type Interfaces.C.size_t;
   use type Lua.Opcodes.Opcode;
   use type Lua.Prototypes.Prototype_Access;
   use type Lua.Storage.Byte_Count;
   use type System.Address;
   package VM renames Lua.Engine.Machine;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);
   procedure Library_Case;
   procedure Constructors_Case;
   procedure Open_Case;
   procedure Dense_Case;
   procedure Hash_Case;
   procedure Reverse_Case;
   procedure Sparse_Case;
   procedure Array_Churn_Case;
   procedure Hash_Churn_Case;
   procedure Vararg_Case;
   procedure Lifetime_Case;
   procedure Refused_Header;
   procedure Refused_Payload;
   procedure Refused_Partial;
   procedure Refused_Later;
   procedure Missing_Inspector;
   procedure Explicit_Mode;

   function Number_Image (Item : Positive) return String;
   function Number_Image (Item : Positive) return String is
     (Ada.Strings.Fixed.Trim (Item'Image, Ada.Strings.Both));

   procedure Check (Name : String; Mode : String := "ada-storage");
   procedure Check (Name : String; Mode : String := "ada-storage") is
      State : World;
   begin
      --  All 529 compiles and storage walks share this explicit instruction
      --  budget. The separate process campaign measures the 900 s / 2 GiB
      --  ceiling; this AUnit fixture does not claim that external protocol.
      Initialize (State, (Instructions => 100_000_000, others => <>));
      Conformance_Adapter.Install (State);
      Assert (Execute (State,
        "assert(loadfile('tests/lua/nextvar_storage_invariants.lua'))('" &
        Mode & "','" & Name & "')", "=nextvar-storage"),
        Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "nextvar storage fixture retains selected storage");
   exception
      when others => Finalize (State); raise;
   end Check;

   --  The following provider sits below managed allocation and emergency
   --  retry. It remains selected from initialization through finalization.
   --  A fault is armed only immediately before the actual NEWTABLE step;
   --  the first refused opcode proves construction, rather than compilation
   --  or an unrelated reservation, encountered the real provider failure.
   Armed : Boolean := False;
   Allowance, Refusals : Natural := 0;
   Raw_Live : Lua.Storage.Byte_Count := 0;
   Executing, First_Refused : Lua.Opcodes.Opcode := Lua.Opcodes.Op_NEWTABLE;
   function Provider
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   function Provider
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
      Result : System.Address;
   begin
      if Armed and then New_Size > Old_Size then
         if Allowance = 0 then
            if Refusals = 0 then First_Refused := Executing; end if;
            Refusals := Refusals + 1;
            return System.Null_Address;
         end if;
         Allowance := Allowance - 1;
      end if;
      Result := Lua.Storage.Default_Allocator
        (Data, Block, Old_Size, New_Size);
      if New_Size = 0 or else Result /= System.Null_Address then
         Raw_Live := Raw_Live - Lua.Storage.Byte_Count (Old_Size) +
           Lua.Storage.Byte_Count (New_Size);
      end if;
      return Result;
   end Provider;

   procedure Constructor_Fault (Permitted : Natural);
   procedure Constructor_Fault (Permitted : Natural) is
      State : World_Access := new World;
      Driver : VM.Driver;
      Source : Unbounded_String := To_Unbounded_String ("result={");
      Code : Prototype_Access;
      Activation : Frame_Access;
      Prior, Marker, Result_Key, Prior_Key, Result : Value;
      Rows, Live : Natural;
      Triggered, Rejected : Boolean := False;
   begin
      Armed := False;
      Refusals := 0;
      Raw_Live := 0;
      Allowance := Permitted;
      Lua.Storage.Set_Allocator (State.Memory, Provider'Access);
      Initialize (State.all, (others => <>));
      --  A previous successful canonical constructor is a genuine registry
      --  root. Its object key/value identity must survive a later constructor
      --  failure, emergency collection, frame retirement and a healthy retry.
      Assert (Execute (State.all,
        "prior={11,22,marker={payload=37}};result=false",
        "=constructor-prior"), Failure_Image (State.Current));
      Prior_Key := New_String (State.all, "prior");
      Result_Key := New_String (State.all, "result");
      Prior := Get (Global_Environment (State.all), Prior_Key);
      Marker := Get (Prior, New_String (State.all, "marker"));
      for Index in 1 .. 64 loop
         Append (Source, Integer'Image (Index) & ",");
      end loop;
      for Index in 1 .. 32 loop
         Append (Source, "k" & Number_Image (Index) & "=" &
                 Integer'Image (Index) & ",");
      end loop;
      Append (Source, "marker=prior.marker};return result");
      Code := Compiler.Compile
        (State.all, To_String (Source), "=constructor-provider-fault");
      State.Entry_Code := Code;
      VM.Start (Driver, State, Code);
      begin
         while not VM.Is_Complete (Driver) loop
            Assert (not State.Current.Stack.Is_Empty,
                    "constructor driver owns its real activation");
            Activation := State.Current.Stack.Last_Element;
            Assert (not Activation.Is_Native and then
                    Activation.Code.Canonical_Node /= null,
                    "constructor fault stays in its canonical body");
            Executing := Lua.Opcodes.Operation
              (Activation.Code.Canonical_Node.Code (Activation.PC));
            if not Triggered and then Executing = Lua.Opcodes.Op_NEWTABLE
            then
               Triggered := True;
               Armed := True;
            end if;
            VM.Step (Driver);
         end loop;
      exception
         when Language_Error => Rejected := True;
      end;
      Armed := False;
      Assert (Triggered and then Rejected and then Refusals > 0 and then
              State.Current.Failure_Class = Memory_Failure and then
              Failure_Image (State.Current) = "not enough memory",
              "actual constructor provider refusal must be a memory error");
      Assert (First_Refused in Lua.Opcodes.Op_NEWTABLE |
                Lua.Opcodes.Op_SETLIST | Lua.Opcodes.Op_SETFIELD |
                Lua.Opcodes.Op_SETI | Lua.Opcodes.Op_SETTABLE,
              "first refused growth belongs to actual construction");
      VM.Finish (Driver);
      VM.Clear_Frames (State.all);
      Conformance_Adapter.Verify_Table_Storage (State.all, Prior, Rows, Live);
      Assert (Rows >= Live and then Live = 3 and then
              Get (Global_Environment (State.all), Prior_Key) = Prior and then
              Get (Prior, New_String (State.all, "marker")) = Marker,
              "refused construction keeps the earlier real table and value");
      Assert (Get (Global_Environment (State.all), Result_Key) =
                Value'(Boolean_Kind, False),
              "failed construction never publishes the result binding");
      --  Reenter the normal execution boundary with the same source after
      --  restoring the provider. It owns error reset and recompilation; the
      --  test does not forge private failure flags to make a retry possible.
      Assert (Execute (State.all, To_String (Source), "=constructor-retry"),
              Failure_Image (State.Current));
      State.Entry_Code := null;
      Result := Get (Global_Environment (State.all), Result_Key);
      Conformance_Adapter.Verify_Table_Storage (State.all, Result, Rows, Live);
      Assert (Rows >= Live and then Live = 97 and then
              Table_Length (Result) = 64 and then
              Get (Result, New_String (State.all, "marker")) = Marker,
              "healthy retry publishes every constructor entry and alias");
      for Index in 1 .. 64 loop
         Assert (Get (Result, (Integer_Kind, Integer_Value (Index))) =
                   Value'(Integer_Kind, Integer_Value (Index)),
                 "retried constructor retains each dense value");
      end loop;
      for Index in 1 .. 32 loop
         Assert (Get (Result, New_String
           (State.all, "k" & Number_Image (Index))) =
             Value'(Integer_Kind, Integer_Value (Index)),
           "retried constructor retains each hash value");
      end loop;
      Finalize (State.all);
      Assert (Raw_Live = 0 and then
              Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "constructor refusal/retry releases actual selected storage");
      Free_World (State);
   exception
      when others =>
         Armed := False;
         VM.Cancel (Driver);
         Finalize (State.all);
         Free_World (State);
         raise;
   end Constructor_Fault;

   procedure Library_Case is
   begin
      Check ("Library");
   end Library_Case;
   procedure Constructors_Case is
   begin
      Check ("Constructors");
   end Constructors_Case;
   procedure Open_Case is
   begin
      Check ("Open_Constructor");
   end Open_Case;
   procedure Dense_Case is
   begin
      Check ("Dense");
   end Dense_Case;
   procedure Hash_Case is
   begin
      Check ("Hash");
   end Hash_Case;
   procedure Reverse_Case is
   begin
      Check ("Reverse");
   end Reverse_Case;
   procedure Sparse_Case is
   begin
      Check ("Sparse");
   end Sparse_Case;
   procedure Array_Churn_Case is
   begin
      Check ("Array_Churn");
   end Array_Churn_Case;
   procedure Hash_Churn_Case is
   begin
      Check ("Hash_Churn");
   end Hash_Churn_Case;
   procedure Vararg_Case is
   begin
      Check ("Vararg");
   end Vararg_Case;
   procedure Lifetime_Case is
   begin
      Check ("Object_Lifetime");
   end Lifetime_Case;
   procedure Refused_Header is
   begin
      Constructor_Fault (0);
   end Refused_Header;
   procedure Refused_Payload is
   begin
      Constructor_Fault (1);
   end Refused_Payload;
   procedure Refused_Partial is
   begin
      Constructor_Fault (3);
   end Refused_Partial;
   procedure Refused_Later is
   begin
      Constructor_Fault (6);
   end Refused_Later;

   procedure Missing_Inspector is
      State : World;
   begin
      --  A storage-mode run without the adapter must fail. A T-absent return
      --  is never accepted as execution of the private Ada ownership walk.
      Initialize (State, (others => <>));
      Assert (Execute (State,
        "assert(rawget(_G,'T')==nil);local f=assert(loadfile(" &
        "'tests/lua/nextvar_storage_invariants.lua'));" &
        "local ok,e=pcall(f,'ada-storage','Library');" &
        "assert(not ok and type(e)=='string')", "=storage-absent"),
        Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "missing-inspector control retains selected storage");
   exception
      when others => Finalize (State); raise;
   end Missing_Inspector;

   procedure Explicit_Mode is
      State : World;
   begin
      --  Typographical/omitted modes must not silently drop ownership checks.
      --  Unknown selected names must not report a successful empty workload.
      Initialize (State, (others => <>));
      Assert (Execute (State,
        "local f=assert(loadfile(" &
        "'tests/lua/nextvar_storage_invariants.lua'));" &
        "assert(not pcall(f));assert(not pcall(f,'ada'));" &
        "assert(not pcall(f,'public','Missing'))", "=storage-mode"),
        Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "explicit-mode control retains selected storage");
   exception
      when others => Finalize (State); raise;
   end Explicit_Mode;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "nextvar storage: library live entries",
                        Library_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: 529 real constructors",
                        Constructors_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: open constructor results",
                        Open_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: dynamic dense keys",
                        Dense_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: dynamic string keys",
                        Hash_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: reverse fill",
                        Reverse_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: sparse fill",
                        Sparse_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: bounded array churn",
                        Array_Churn_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: bounded hash churn",
                        Hash_Churn_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: collected key row reuse",
                        Lifetime_Case'Access);
      Test_Support.Add (Suite, "nextvar storage: vararg values and count",
                        Vararg_Case'Access);
      Test_Support.Add (Suite, "nextvar constructor: header provider refusal",
                        Refused_Header'Access);
      Test_Support.Add (Suite, "nextvar constructor: payload provider refusal",
                        Refused_Payload'Access);
      Test_Support.Add (Suite, "nextvar constructor: partial provider refusal",
                        Refused_Partial'Access);
      Test_Support.Add (Suite, "nextvar constructor: later provider refusal",
                        Refused_Later'Access);
      Test_Support.Add (Suite, "nextvar storage: mandatory actual inspector",
                        Missing_Inspector'Access);
      Test_Support.Add (Suite, "nextvar storage: explicit mode and case",
                        Explicit_Mode'Access);
   end Register;
end Lua.Nextvar_Storage_Tests;
