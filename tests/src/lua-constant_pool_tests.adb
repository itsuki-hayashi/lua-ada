with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Canonical_Compiler; use Lua.Canonical_Compiler;
with Lua.Storage;
with Lua.Syntax;
with Lua.Syntax_Trees;
with Test_Support;

package body Lua.Constant_Pool_Tests is
   use type Lua.Syntax.Check_Status;
   use type Lua.Storage.Byte_Count;

   function Lower
     (Source : String; Memory : in out Lua.Storage.Owner;
      Constants : Positive) return Compilation_Result;
   function Lower
     (Source : String; Memory : in out Lua.Storage.Owner;
      Constants : Positive) return Compilation_Result
   is
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      Lua.Syntax_Trees.Parse
        (Unit, Source, "=constant-cache", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "invalid constant-cache fixture");
      return Compile
        (Unit, Lua.Storage.Reference (Memory), "=constant-cache",
         (Constants => Constants, others => <>));
   end Lower;

   procedure Repeated_Key_Budget;
   procedure Repeated_Key_Budget is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return 'same','same','same'", Memory, Constants => 1);
   begin
      --  Repeated uses retain one string constant under an explicit host
      --  lowering quota. Their number of source occurrences is not storage.
      Assert (Result.Outcome = Succeeded,
              "repeated string uses exhausted the retained-constant quota");
   end Repeated_Key_Budget;

   procedure Exact_Byte_Budget;
   procedure Exact_Byte_Budget is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return 'key','Key','key\0x','key\0y','key','Key'",
         Memory, Constants => 4);
      Too_Small : constant Compilation_Result := Lower
        ("return 'key','Key','key\0x','key\0y'", Memory, Constants => 3);
   begin
      --  Reuse is byte-exact, including case and bytes after an embedded NUL.
      --  The same source fits four retained keys, while three cannot hold it.
      Assert (Result.Outcome = Succeeded and then
              Too_Small.Outcome = Resource_Limit and then
              Too_Small.Error = Constant_Budget,
              "case/NUL keys collapsed or duplicate uses were retained");
   end Exact_Byte_Budget;

   procedure Independent_Function_Budgets;
   procedure Independent_Function_Budgets is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return 'root',function()return 'left','right' end," &
         "function()return 'right','left' end", Memory, Constants => 5);
      Too_Small : constant Compilation_Result := Lower
        ("return 'root',function()return 'left','right' end," &
         "function()return 'right','left' end", Memory, Constants => 4);
   begin
      --  Children own different constant indexes even when their byte strings
      --  share the immutable program interner. The aggregate quota counts
      --  each child's retained constants, never a parent's cached pool slot.
      Assert (Result.Outcome = Succeeded and then
              Too_Small.Outcome = Resource_Limit and then
              Too_Small.Error = Constant_Budget,
              "a child borrowed another function's retained constant slot");
   end Independent_Function_Budgets;

   procedure Growth_Refusal_Transactions;
   procedure Growth_Refusal_Transactions is
      Source : Unbounded_String;
      Unit : Lua.Syntax_Trees.Compilation_Unit;
      Memory : Lua.Storage.Owner;
      Completed : Boolean := False;
      Refused : Natural := 0;
   begin
      --  Sixty-four unique keys and repeated uses force several dense table
      --  growths. Sweep real allocation refusal through every compiler phase;
      --  partial keys, bucket links, model bytes and nested functions must
      --  finalize before the same owner is retried without failure injection.
      for Index in 1 .. 64 loop
         Append (Source, "sink('key" & Ada.Strings.Fixed.Trim
           (Index'Image, Both) & "');");
      end loop;
      Append (Source, "return function()return 'key1','key64','key1' end");
      Lua.Syntax_Trees.Parse
        (Unit, To_String (Source), "=constant-cache", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "invalid constant growth fixture");
      for Countdown in 0 .. 1_200 loop
         Lua.Storage.Set_Failure_Countdown
           (Memory, Lua.Storage.Byte_Count (Countdown));
         declare
            Result : constant Compilation_Result := Compile
              (Unit, Lua.Storage.Reference (Memory), "=constant-cache");
         begin
            Completed := Result.Outcome = Succeeded;
            Assert (Completed or else Result.Outcome = Memory_Failure,
                    "string-key refusal changed compiler failure class");
            if not Completed then Refused := Refused + 1; end if;
         end;
         Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
                 "partial string-constant growth retained compiler storage");
         Lua.Storage.Clear_Failures (Memory);
         exit when Completed;
      end loop;
      Assert (Completed and then Refused > 20,
              "string-key refusal sweep never reached a verified success");
   end Growth_Refusal_Transactions;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "constant pool: repeated key quota",
         Repeated_Key_Budget'Access);
      Test_Support.Add
        (Suite, "constant pool: exact case and NUL", Exact_Byte_Budget'Access);
      Test_Support.Add
        (Suite, "constant pool: independent function quotas",
         Independent_Function_Budgets'Access);
      Test_Support.Add
        (Suite, "constant pool: growth refusal transactions",
         Growth_Refusal_Transactions'Access);
   end Register;
end Lua.Constant_Pool_Tests;
