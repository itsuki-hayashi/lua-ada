with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Concat_Tests is
   use type Interfaces.C.int;
   use type Lua.Storage.Byte_Count;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_concat";
   function Callback (Choice : Interfaces.C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_concat_budget";
   function Completed return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_concat_completed";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Check_Budget
     (Choice : Interfaces.C.int; Bounds : Limits; Source : String);
   procedure Primitive_Quota;
   procedure Extent_Quota;
   procedure Handler_Quota;
   procedure Caller_Mutation;
   procedure Weak_Operand_Lifetime;
   procedure Retained_Prefix;
   procedure Error_Location;
   procedure Current_Pair_Roots;
   procedure Primitive_Suffix;
   procedure Numeric_Primitives;
   procedure Empty_Result;
   procedure Singleton_Identity;
   procedure Empty_Right_Refusal;
   procedure Empty_Left_Refusal;
   procedure External_Empty_Copy;
   procedure Handler_Error_Identity;
   procedure Nonyieldable_Handler;
   procedure External_Empty_Left_Copy;
   procedure Empty_Handler_Result;
   procedure Number_Before_Handler;
   procedure Number_After_Handler;

   --  The C fixture documents setup/action/results and is independently
   --  run against pinned native default/T. Each named call creates and
   --  closes a fresh counted-provider state, checking actual public slots
   --  and post-close balance rather than a mock/private argument vector.
   procedure Caller_Mutation is
   begin
      Assert (Check (0) = 1, "caller operand mutation");
   end Caller_Mutation;

   procedure Weak_Operand_Lifetime is
   begin
      Assert (Check (1) = 1, "weak operand lifetime");
   end Weak_Operand_Lifetime;

   procedure Retained_Prefix is
   begin
      Assert (Check (2) = 1, "retained prefix and bounds");
   end Retained_Prefix;

   procedure Error_Location is
   begin
      Assert (Check (3) = 1, "native error location");
   end Error_Location;

   procedure Current_Pair_Roots is
   begin
      Assert (Check (4) = 1, "current pair roots retire");
   end Current_Pair_Roots;

   procedure Primitive_Suffix is
   begin
      Assert (Check (5) = 1, "primitive suffix actual slots");
   end Primitive_Suffix;

   procedure Numeric_Primitives is
   begin
      Assert (Check (6) = 1, "numeric primitive fold");
   end Numeric_Primitives;

   procedure Empty_Result is
   begin
      Assert (Check (7) = 1, "empty result preserves prefix");
   end Empty_Result;

   procedure Singleton_Identity is
   begin
      Assert (Check (8) = 1, "singleton keeps table identity");
   end Singleton_Identity;

   procedure Empty_Right_Refusal is
   begin
      Assert (Check (9) = 1, "empty right zero growth");
   end Empty_Right_Refusal;

   procedure Empty_Left_Refusal is
   begin
      Assert (Check (10) = 1, "empty left zero growth");
   end Empty_Left_Refusal;

   procedure External_Empty_Copy is
   begin
      Assert (Check (11) = 1, "external empty copies long string");
   end External_Empty_Copy;

   procedure Handler_Error_Identity is
   begin
      Assert (Check (12) = 1, "handler error identity and recovery");
   end Handler_Error_Identity;

   procedure Nonyieldable_Handler is
   begin
      Assert (Check (13) = 1, "live C boundary rejects yield");
   end Nonyieldable_Handler;

   procedure External_Empty_Left_Copy is
   begin
      Assert (Check (14) = 1, "external empty left copies long string");
   end External_Empty_Left_Copy;

   procedure Empty_Handler_Result is
   begin
      Assert (Check (15) = 1, "empty handler result becomes nil");
   end Empty_Handler_Result;

   procedure Number_Before_Handler is
   begin
      Assert (Check (16) = 1, "left numeric handler argument is unconverted");
   end Number_Before_Handler;

   procedure Number_After_Handler is
   begin
      Assert (Check (17) = 1, "right numeric handler argument is unconverted");
   end Number_After_Handler;

   procedure Check_Budget
     (Choice : Interfaces.C.int; Bounds : Limits; Source : String)
   is
      State : World;
      Item : Value;
   begin
      --  An actual C callback invokes the public operation. Its ordinary
      --  guard must abandon the C body when the same owning driver exhausts
      --  its host policy; Lua pcall cannot turn that abort into a value.
      Initialize (State, Bounds);
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (Choice));
      Set (State, Global_Environment (State), New_String (State, "concat"),
           Item);
      End_Operation (State);
      Assert (not Execute (State, Source, "C-concat-budget"),
              "C concat must share the original host policy");
      Assert (State.Current.Failure_Class = Host_Abort and then Completed = 0,
              "the real C body cannot continue after a host abort");
      Assert (Execute (State, "return 37", "C-concat-recovery"),
              "concat host abort must preserve the reusable session");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "all concat callback/continuation/scalar owners retire");
   exception
      when others => Finalize (State); raise;
   end Check_Budget;

   procedure Primitive_Quota is
   begin
      Check_Budget (0, (Instructions => 1_000, others => <>),
                    "pcall(concat);error('primitive quota was caught')");
   end Primitive_Quota;

   procedure Extent_Quota is
   begin
      Check_Budget (1, (String_Bytes => 200, others => <>),
                    "pcall(concat);error('extent quota was caught')");
   end Extent_Quota;

   procedure Handler_Quota is
   begin
      Check_Budget (2, (Instructions => 1_000, others => <>),
        "local t=setmetatable({},{__concat=function() " &
        "for i=1,100000 do end;return 37 end});" &
        "pcall(concat,t,t);error('handler quota was caught')");
   end Handler_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C concat: caller operand mutation",
                        Caller_Mutation'Access);
      Test_Support.Add (Suite, "C concat: weak operand lifetime",
                        Weak_Operand_Lifetime'Access);
      Test_Support.Add (Suite, "C concat: retained prefix and bounds",
                        Retained_Prefix'Access);
      Test_Support.Add (Suite, "C concat: native error location",
                        Error_Location'Access);
      Test_Support.Add (Suite, "C concat: current pair roots retire",
                        Current_Pair_Roots'Access);
      Test_Support.Add (Suite, "C concat: primitive suffix actual slots",
                        Primitive_Suffix'Access);
      Test_Support.Add (Suite, "C concat: numeric primitive fold",
                        Numeric_Primitives'Access);
      Test_Support.Add (Suite, "C concat: empty result preserves prefix",
                        Empty_Result'Access);
      Test_Support.Add (Suite, "C concat: singleton keeps table identity",
                        Singleton_Identity'Access);
      Test_Support.Add (Suite, "C concat: empty right zero growth",
                        Empty_Right_Refusal'Access);
      Test_Support.Add (Suite, "C concat: empty left zero growth",
                        Empty_Left_Refusal'Access);
      Test_Support.Add (Suite, "C concat: external empty copies long string",
                        External_Empty_Copy'Access);
      Test_Support.Add (Suite, "C concat: handler error identity and recovery",
                        Handler_Error_Identity'Access);
      Test_Support.Add (Suite, "C concat: live C boundary rejects yield",
                        Nonyieldable_Handler'Access);
      Test_Support.Add (Suite, "C concat: external empty left copies string",
                        External_Empty_Left_Copy'Access);
      Test_Support.Add (Suite, "C concat: empty handler result becomes nil",
                        Empty_Handler_Result'Access);
      Test_Support.Add (Suite, "C concat: left number reaches handler",
                        Number_Before_Handler'Access);
      Test_Support.Add (Suite, "C concat: right number reaches handler",
                        Number_After_Handler'Access);
      Test_Support.Add (Suite, "C concat: primitive fold host quota",
                        Primitive_Quota'Access);
      Test_Support.Add (Suite, "C concat: result extent host quota",
                        Extent_Quota'Access);
      Test_Support.Add (Suite, "C concat: handler shares host quota",
                        Handler_Quota'Access);
   end Register;
end Lua.C_Concat_Tests;
