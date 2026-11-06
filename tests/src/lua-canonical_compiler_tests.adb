with Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Canonical_Compiler; use Lua.Canonical_Compiler;
with Lua.Numbers;
with Lua.Opcodes; use Lua.Opcodes;
with Lua.Prototypes; use Lua.Prototypes;
with Lua.Storage;
with Lua.Syntax;
with Lua.Syntax_Trees;
with Test_Support;

package body Lua.Canonical_Compiler_Tests is
   use type Lua.Syntax.Check_Status;
   use type Lua.Storage.Byte_Count;
   use type Lua.Numbers.Integer_Value;
   use type Lua.Prototypes.Byte;
   use type Ada.Containers.Count_Type;

   function Lower
     (Source : String; Memory : in out Lua.Storage.Owner;
      Bounds : Lowering_Limits := (others => <>)) return Compilation_Result;
   function Lower
     (Source : String; Memory : in out Lua.Storage.Owner;
      Bounds : Lowering_Limits := (others => <>)) return Compilation_Result
   is
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      Lua.Syntax_Trees.Parse (Unit, Source, "=canonical-unit", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "invalid first-party compiler fixture: " &
              Lua.Syntax_Trees.Text (Unit, Unit.Result.Error.Message));
      return Compile
        (Unit, Lua.Storage.Reference (Memory), "=canonical-unit", Bounds);
   end Lower;

   function Has (Node : Prototype_Access; Op : Opcode) return Boolean;
   function Has (Node : Prototype_Access; Op : Opcode) return Boolean is
   begin
      for Instruction of Node.Code loop
         if Operation (Instruction) = Op then return True; end if;
      end loop;
      return False;
   end Has;

   procedure Main_Environment;
   procedure Captured_Mutation;
   procedure Folded_Const;
   procedure Register_Reuse;
   procedure Semantic_Locals;
   procedure Semantic_Upvalues;
   procedure Instruction_Quota;
   procedure Constant_Quota;
   procedure Prototype_Quota;
   procedure Nesting_Quota;
   procedure Open_Results;
   procedure Constructor_Results;
   procedure Numeric_Controls;
   procedure Generic_Controls;
   procedure Goto_Lifetimes;
   procedure Named_Varargs;
   procedure Debug_Metadata;
   procedure Method_Instruction;
   procedure Allocation_Transactions;

   procedure Main_Environment is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower ("return x", Memory);
      Node : constant Prototype_Access := Root (Result.Code);
   begin
      --  The frontend unit has already died inside Lower. Its canonical source
      --  and initial _ENV upvalue must still be owned by the resulting
      --  program.
      Assert (Result.Outcome = Succeeded and then
              Node.Upvalues.Length = 1 and then Node.Flags = 1,
              "main environment/vararg contract");
      Assert (Has (Node, Op_GETUPVAL) and then Has (Node, Op_GETTABLE),
              "global access did not use the resolved environment");
      Assert (String_Length (Result.Code, Node.Source) = 15,
              "source identity depends on the discarded frontend");
   end Main_Environment;

   procedure Captured_Mutation is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("local x=0;return function()x=x+1;return x end", Memory);
      Child : constant Prototype_Access :=
        Root (Result.Code).Children (1);
   begin
      --  A closure must capture its parent's actual slot and store through the
      --  same ordered upvalue. Merely copying the initial value loses
      --  mutation.
      Assert (Result.Outcome = Succeeded and then
              Child.Upvalues (1).In_Stack and then
              Child.Upvalues (1).Index = 0, "capture descriptor ownership");
      Assert (Has (Child, Op_GETUPVAL) and then Has (Child, Op_SETUPVAL),
              "captured read/write do not share a cell");
   end Captured_Mutation;

   procedure Folded_Const is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("local x <const> = 9223372036854775807+1;" &
         "return function()return x end", Memory);
      Child : constant Prototype_Access := Root (Result.Code).Children (1);
   begin
      --  Compile-time constants carry no stack cell or upvalue. Integer
      --  folding
      --  must preserve Lua wrapping instead of raising an Ada overflow check.
      Assert (Child.Upvalues.Is_Empty, "folded constant acquired an upvalue");
      Assert (Child.Constants (1).Integer_Data =
                Lua.Numbers.Integer_Value'First, "constant integer wrapping");
   end Folded_Const;

   procedure Register_Reuse is
      Memory : Lua.Storage.Owner;
      Source : Unbounded_String := To_Unbounded_String ("local x=0;");
   begin
      --  Thousands of flat statements use a bounded live register footprint.
      --  Temporaries must be recycled after each source statement, not counted
      --  as permanently live locals until the function ends.
      for Index in 1 .. 2_000 loop Append (Source, "x=x+1;"); end loop;
      declare
         Result : constant Compilation_Result := Lower
           (To_String (Source), Memory);
      begin
         Assert (Result.Outcome = Succeeded and then
                 Root (Result.Code).Max_Stack < 10,
                 "flat chunk accumulated temporary registers");
      end;
   end Register_Reuse;

   procedure Semantic_Locals is
      Memory : Lua.Storage.Owner;
      Source : Unbounded_String;
   begin
      --  Shared parsing deliberately does not imitate compiler register
      --  limits.
      --  Lowering 201 simultaneously live nonconstant locals must instead give
      --  the canonical compiler limit, distinct from a host resource refusal.
      for Index in 1 .. 201 loop
         declare
            Image : constant String := Positive'Image (Index);
         begin
            Append (Source, "local x" & Image (2 .. Image'Last) & "=1;");
         end;
      end loop;
      declare
         Result : constant Compilation_Result := Lower
           (To_String (Source), Memory);
      begin
         Assert (Result.Outcome = Compiler_Limit and then
                 Result.Error = Local_Limit, "semantic local limit class");
      end;
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
              "local limit retained partial canonical code");
   end Semantic_Locals;

   procedure Semantic_Upvalues is
      Memory : Lua.Storage.Owner;
      Source : Unbounded_String;
      function Name (Prefix : Character; Index : Positive) return String;
      function Name (Prefix : Character; Index : Positive) return String is
         Image : constant String := Positive'Image (Index);
      begin
         return Prefix & Image (Image'First + 1 .. Image'Last);
      end Name;
   begin
      --  Two valid parent scopes contribute 150 cells each. The innermost
      --  function needs 300 captures before its return expression is emitted,
      --  isolating the 255-upvalue limit from the 200-local/register limits.
      for Index in 1 .. 150 loop
         Append (Source, "local " & Name ('a', Index) & "=1;");
      end loop;
      Append (Source, "return function()");
      for Index in 1 .. 150 loop
         Append (Source, "local " & Name ('b', Index) & "=1;");
      end loop;
      Append (Source, "return function()return ");
      for Index in 1 .. 300 loop
         if Index /= 1 then Append (Source, ','); end if;
         Append (Source, Name
           ((if Index <= 150 then 'a' else 'b'), (Index - 1) mod 150 + 1));
      end loop;
      Append (Source, " end end");
      declare
         Result : constant Compilation_Result := Lower
           (To_String (Source), Memory);
      begin
         Assert (Result.Outcome = Compiler_Limit and then
                 Result.Error = Upvalue_Limit,
                 "upvalue encoding limit became a host resource failure");
      end;
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
              "failed upvalue lowering retained its partial graph");
   end Semantic_Upvalues;

   procedure Instruction_Quota is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return 42", Memory, (Instructions => 1, others => <>));
   begin
      --  The first vararg-preparation word fits; the value word exceeds only
      --  the explicitly configured lowering budget, so syntax stays valid.
      Assert (Result.Outcome = Resource_Limit and then
              Result.Error = Instruction_Budget, "instruction quota class");
   end Instruction_Quota;

   procedure Constant_Quota is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return 'one','two'", Memory, (Constants => 1, others => <>));
   begin
      --  Two retained byte constants exceed the host's one-constant budget.
      --  No partially owned source/prototype storage may escape that result.
      Assert (Result.Outcome = Resource_Limit and then
              Result.Error = Constant_Budget and then
              Prototype_Count (Result.Code) = 0, "constant quota cleanup");
   end Constant_Quota;

   procedure Prototype_Quota is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return function()end", Memory, (Prototypes => 1, others => <>));
   begin
      --  Root allocation succeeds; the nested function fails before its node
      --  is published. Both paths must release the already owned root.
      Assert (Result.Outcome = Resource_Limit and then
              Result.Error = Prototype_Budget and then
              Prototype_Count (Result.Code) = 0, "prototype quota cleanup");
   end Prototype_Quota;

   procedure Nesting_Quota is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return function()end", Memory, (Nesting => 1, others => <>));
   begin
      --  A valid nested function exceeds a smaller lowering policy, not a
      --  grammar restriction or the representable C instruction format.
      Assert (Result.Outcome = Resource_Limit and then
              Result.Error = Nesting_Budget, "nesting quota class");
   end Nesting_Quota;

   procedure Open_Results is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower ("return 1,f()", Memory);
      Node : constant Prototype_Access := Root (Result.Code);
      Found : Boolean := False;
   begin
      --  The final call supplies every remaining return value. Its open top
      --  must feed the immediately following open RETURN without adjustment.
      for Index in Node.Code.First_Index .. Node.Code.Last_Index - 1 loop
         if Operation (Node.Code (Index)) = Op_CALL then
            Found := Get (Node.Code (Index), C).Value = 0 and then
              Operation (Node.Code (Index + 1)) = Op_RETURN and then
              Get (Node.Code (Index + 1), B).Value = 0;
         end if;
      end loop;
      Assert (Found, "open call/return result contract");
   end Open_Results;

   procedure Constructor_Results is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower ("return {1,f()}", Memory);
      Node : constant Prototype_Access := Root (Result.Code);
      Found : Boolean := False;
   begin
      --  An expanding final sequence field uses top-aware SETLIST. A fixed
      --  count would either discard results or expose uninitialized registers.
      for Instruction of Node.Code loop
         if Operation (Instruction) = Op_SETLIST then
            Found := Get (Instruction, VB).Value = 0 and then
              Get (Instruction, VC).Value = 1;
         end if;
      end loop;
      Assert (Found, "constructor lost final multiple-result expansion");
   end Constructor_Results;

   procedure Numeric_Controls is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("for i=1,3 do end", Memory);
   begin
      --  Pinned Lua 5.5 numeric loops have three controls, not the historical
      --  four-slot layout. An empty body should need exactly those slots.
      Assert (Root (Result.Code).Max_Stack = 3 and then
              Has (Root (Result.Code), Op_FORPREP) and then
              Has (Root (Result.Code), Op_FORLOOP), "numeric control layout");
   end Numeric_Controls;

   procedure Generic_Controls is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("for x in f,nil,nil,nil do end", Memory);
      Node : constant Prototype_Access := Root (Result.Code);
   begin
      --  Generic controls include a closing value and iterator scratch. PREP
      --  must lead to CALL/LOOP rather than a hand-written ordinary while
      --  loop.
      Assert (Node.Max_Stack >= 6 and then Has (Node, Op_TFORPREP) and then
              Has (Node, Op_TFORCALL) and then Has (Node, Op_TFORLOOP),
              "generic closing/control layout");
   end Generic_Controls;

   procedure Goto_Lifetimes is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("::again::local x=1;local f=function()return x end;goto again",
         Memory);
      Node : constant Prototype_Access := Root (Result.Code);
      Found : Boolean := False;
   begin
      --  A backward jump leaves both declarations. Closing before its jump
      --  detaches captured x so a later declaration can create a fresh cell.
      for Index in Node.Code.First_Index .. Node.Code.Last_Index - 1 loop
         if Operation (Node.Code (Index)) = Op_CLOSE and then
           Operation (Node.Code (Index + 1)) = Op_JMP
         then
            Found := Get (Node.Code (Index + 1), SJ).Value < 0;
         end if;
      end loop;
      Assert (Found, "backward declaration jump omitted capture cleanup");
   end Goto_Lifetimes;

   procedure Named_Varargs is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("return function(a,...v)return v,... end", Memory);
      Child : constant Prototype_Access := Root (Result.Code).Children (1);
      Found : Boolean := False;
   begin
      --  Escaping a named vararg parameter requires its real table. VARARG
      --  reads that table with k=1/B=numparams instead of hidden arguments.
      for Instruction of Child.Code loop
         if Operation (Instruction) = Op_VARARG then
            Found := Get (Instruction, K).Value = 1 and then
              Get (Instruction, B).Value = 1;
         end if;
      end loop;
      Assert (Child.Flags = 2 and then Child.Parameters = 1 and then Found,
              "named vararg table contract");
   end Named_Varargs;

   procedure Debug_Metadata is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower
        ("local function f(x)" & ASCII.LF & "local y=x" & ASCII.LF &
         "return y end" & ASCII.LF & "return f", Memory);
      Child : constant Prototype_Access := Root (Result.Code).Children (1);
   begin
      --  Source ranges and local lifetimes belong to the canonical graph and
      --  survive the frontend. Every word gets a delta/absolute line record.
      Assert (Child.First_Line = 1 and then Child.Last_Line = 3 and then
              Child.Lines.Length = Child.Code.Length,
              "canonical source/line metadata");
      Assert (Child.Locals.Length = 2 and then
              Child.Locals (2).Start_PC < Child.Locals (2).End_PC,
              "active local debug lifetime");
   end Debug_Metadata;

   procedure Method_Instruction is
      Memory : Lua.Storage.Owner;
      Result : constant Compilation_Result := Lower ("return t:f()", Memory);
      Node : constant Prototype_Access := Root (Result.Code);
   begin
      --  Short method names with a small constant index carry the pinned SELF
      --  instruction. Runtime debug lookup can derive namewhat="method" from
      --  real code, while SELF itself preserves the implicit receiver value.
      Assert (Has (Node, Op_SELF), "method call lost its SELF instruction");
   end Method_Instruction;

   procedure Allocation_Transactions is
      Memory : Lua.Storage.Owner;
      Completed : Boolean := False;
      Refused : Natural := 0;
   begin
      --  Sweep every allocation boundary through lexical maps, constants,
      --  child nodes and debug vectors. After each failed or successful result
      --  finalizes, its owner must contain no abandoned compilation storage.
      for Countdown in 0 .. 250 loop
         Lua.Storage.Set_Failure_Countdown
           (Memory, Lua.Storage.Byte_Count (Countdown));
         declare
            Result : constant Compilation_Result := Lower
              ("local x=1;return function(a)local y=x+a;return y end", Memory);
         begin
            Completed := Result.Outcome = Succeeded;
            Assert (Completed or else Result.Outcome = Memory_Failure,
                    "allocation refusal became a compiler error");
            if not Completed then Refused := Refused + 1; end if;
         end;
         Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
                 "canonical lowering leaked partial owned storage");
         Lua.Storage.Clear_Failures (Memory);
         exit when Completed;
      end loop;
      Assert (Completed and then Refused > 20,
              "allocation sweep did not reach successful compilation");
   end Allocation_Transactions;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "canonical compiler: main environment",
        Main_Environment'Access);
      Test_Support.Add (Suite, "canonical compiler: captured mutation",
        Captured_Mutation'Access);
      Test_Support.Add (Suite, "canonical compiler: folded constant cells",
        Folded_Const'Access);
      Test_Support.Add (Suite, "canonical compiler: flat register reuse",
        Register_Reuse'Access);
      Test_Support.Add (Suite, "canonical compiler: semantic locals",
        Semantic_Locals'Access);
      Test_Support.Add (Suite, "canonical compiler: semantic upvalues",
        Semantic_Upvalues'Access);
      Test_Support.Add (Suite, "canonical compiler: instruction quota",
        Instruction_Quota'Access);
      Test_Support.Add (Suite, "canonical compiler: constant quota",
        Constant_Quota'Access);
      Test_Support.Add (Suite, "canonical compiler: prototype quota",
        Prototype_Quota'Access);
      Test_Support.Add (Suite, "canonical compiler: nesting quota",
        Nesting_Quota'Access);
      Test_Support.Add (Suite, "canonical compiler: open call results",
        Open_Results'Access);
      Test_Support.Add (Suite, "canonical compiler: constructor results",
        Constructor_Results'Access);
      Test_Support.Add (Suite, "canonical compiler: numeric controls",
        Numeric_Controls'Access);
      Test_Support.Add (Suite, "canonical compiler: generic controls",
        Generic_Controls'Access);
      Test_Support.Add (Suite, "canonical compiler: goto lifetimes",
        Goto_Lifetimes'Access);
      Test_Support.Add (Suite, "canonical compiler: named varargs",
        Named_Varargs'Access);
      Test_Support.Add (Suite, "canonical compiler: debug metadata",
        Debug_Metadata'Access);
      Test_Support.Add (Suite, "canonical compiler: method instruction",
        Method_Instruction'Access);
      Test_Support.Add (Suite, "canonical compiler: allocation transactions",
        Allocation_Transactions'Access);
   end Register;
end Lua.Canonical_Compiler_Tests;
