with Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Canonical_Compiler;
with Lua.Chunks;
with Lua.Prototypes; use Lua.Prototypes;
with Lua.Runtime_Configuration;
with Lua.Storage;
with Lua.Storage.Buffers;
with Lua.Syntax;
with Lua.Syntax_Trees;
with Test_Support;

package body Lua.Line_Baseline_Tests is
   use type Ada.Containers.Count_Type;
   use type Interfaces.Integer_8;
   use type Lua.Canonical_Compiler.Status;
   use type Lua.Chunks.Status;
   use type Lua.Syntax.Check_Status;

   function Lower
     (Source : String; Memory : in out Lua.Storage.Owner)
      return Lua.Canonical_Compiler.Compilation_Result;
   procedure Check_Reader (Node : not null Prototype_Access);
   procedure Check_Program (Code : Program);
   function Long_Line (Count : Positive := 400) return String;

   function Lower
     (Source : String; Memory : in out Lua.Storage.Owner)
      return Lua.Canonical_Compiler.Compilation_Result
   is
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      Lua.Syntax_Trees.Parse
        (Unit, Source, "=line-baseline", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "line baseline fixture failed its shared parser");
      return Lua.Canonical_Compiler.Compile
        (Unit, Lua.Storage.Reference (Memory), "=line-baseline");
   end Lower;

   procedure Check_Reader (Node : not null Prototype_Access) is
      Interval : constant Positive :=
        Lua.Runtime_Configuration.Absolute_Line_Interval;
      Estimate : Integer;
      Base_PC, Reconstructed, Line : Integer;
      Absolute : Natural;
   begin
      Assert (Node.Code.Length = Node.Lines.Length,
              "every word must retain a line entry before stripping");
      --  Exercise every PC, including immediately before, at and after each
      --  reader interval. This is the actual C reader's lower-bound rule,
      --  not an expectation for the compiler's private marker positions.
      for PC in 0 .. Natural (Node.Code.Length) - 1 loop
         if Node.Absolute_Lines.Is_Empty or else
           PC < Node.Absolute_Lines.First_Element.PC
         then
            Base_PC := -1;
            Line := Node.First_Line;
         else
            Estimate := Integer (PC / Interval) - 1;
            Assert
              (Estimate < 0 or else
               (Estimate < Natural (Node.Absolute_Lines.Length) and then
                Node.Absolute_Lines (Estimate + 1).PC <= PC),
               "native absolute-line estimate is not a lower bound");
            Absolute := Natural (Estimate + 1);
            while Absolute < Natural (Node.Absolute_Lines.Length) and then
              Node.Absolute_Lines (Absolute + 1).PC <= PC
            loop
               Absolute := Absolute + 1;
            end loop;
            Assert (Absolute > 0, "reader failed to locate its first base");
            Base_PC := Node.Absolute_Lines (Absolute).PC;
            Line := Node.Absolute_Lines (Absolute).Line;
         end if;
         --  Once the chosen absolute base is correct, its following deltas
         --  contain no skipped marker. A simple independent scan supplies the
         --  expected line, including large nonperiodic source-line jumps.
         for Offset in Base_PC + 1 .. PC loop
            Assert (Node.Lines (Offset + 1) /= -128,
                    "native reader crossed an unselected absolute marker");
            Line := Line + Integer (Node.Lines (Offset + 1));
         end loop;
         Reconstructed := Node.First_Line;
         Absolute := 1;
         for Offset in 0 .. PC loop
            if Node.Lines (Offset + 1) = -128 then
               Assert
                 (Absolute <= Natural (Node.Absolute_Lines.Length) and then
                  Node.Absolute_Lines (Absolute).PC = Offset,
                  "marker has no corresponding actual absolute record");
               Reconstructed := Node.Absolute_Lines (Absolute).Line;
               Absolute := Absolute + 1;
            else
               Reconstructed := Reconstructed +
                 Integer (Node.Lines (Offset + 1));
            end if;
         end loop;
         Assert (Line = Reconstructed,
                 "native base lookup changed the actual source line");
      end loop;
   end Check_Reader;

   procedure Check_Program (Code : Program) is
   begin
      for Index in 1 .. Prototype_Count (Code) loop
         Check_Reader (Prototype_At (Code, Index));
      end loop;
   end Check_Program;

   function Long_Line (Count : Positive := 400) return String is
      Source : Unbounded_String := To_Unbounded_String ("local x=0;");
   begin
      for Index in 1 .. Count loop
         Append (Source, "x=x+1;");
      end loop;
      return To_String (Source) & "return x";
   end Long_Line;

   procedure Empty_Root;
   procedure Empty_Root is
      Memory : Lua.Storage.Owner;
      Result : constant Lua.Canonical_Compiler.Compilation_Result :=
        Lower ("", Memory);
   begin
      --  An empty root still has its real implicit return and line entry.
      Assert (Result.Outcome = Lua.Canonical_Compiler.Succeeded,
              "empty root compilation failed");
      Check_Program (Result.Code);
   end Empty_Root;

   procedure Interval_Boundaries;
   procedure Interval_Boundaries is
      Memory : Lua.Storage.Owner;
      Result : constant Lua.Canonical_Compiler.Compilation_Result :=
        Lower (Long_Line, Memory);
   begin
      --  One physical source line emits enough actual words to cross several
      --  ordinary and tiny T reader intervals without any large line jump.
      Assert (Result.Outcome = Lua.Canonical_Compiler.Succeeded and then
              Root (Result.Code).Code.Length > 3 *
                Ada.Containers.Count_Type
                  (Lua.Runtime_Configuration.Absolute_Line_Interval),
              "long single line failed to cross reader intervals");
      Check_Program (Result.Code);
   end Interval_Boundaries;

   procedure Line_Jumps;
   procedure Line_Jumps is
      Memory : Lua.Storage.Owner;
      Gap : constant String (1 .. 300) := [others => ASCII.LF];
      Result : constant Lua.Canonical_Compiler.Compilation_Result :=
        Lower ("local x=1" & Gap & "x=x+1" & Gap & "return x", Memory);
   begin
      --  Large blank/comment gaps add nonperiodic bases. The estimate must
      --  still be a lower bound when these records shift every later index.
      Assert (Result.Outcome = Lua.Canonical_Compiler.Succeeded and then
              Root (Result.Code).Absolute_Lines.Length >= 3,
              "distant lines did not preserve their absolute records");
      Check_Program (Result.Code);
   end Line_Jumps;

   procedure Child_Prototypes;
   procedure Child_Prototypes is
      Memory : Lua.Storage.Owner;
      Result : constant Lua.Canonical_Compiler.Compilation_Result := Lower
        ("local function f()" & Long_Line & " end;" &
         "return function()return f()end", Memory);
   begin
      --  Each child has its own PC and absolute-index origin. A root's dense
      --  table cannot repair a nested prototype written with a wider gap.
      Assert (Result.Outcome = Lua.Canonical_Compiler.Succeeded and then
              Prototype_Count (Result.Code) = 3,
              "nested interval fixture lost an actual child");
      Check_Program (Result.Code);
   end Child_Prototypes;

   procedure Encoded_Bases;
   procedure Encoded_Bases is
      Memory : Lua.Storage.Owner;
      Result : Lua.Canonical_Compiler.Compilation_Result :=
        Lower (Long_Line, Memory);
   begin
      --  Check the actual encoded/decoded graph too; in-memory correctness
      --  must survive the binary layout consumed by the separate C oracle.
      Assert (Result.Outcome = Lua.Canonical_Compiler.Succeeded,
              "line roundtrip fixture failed");
      declare
         Bytes : constant Lua.Storage.Buffers.Buffer :=
           Lua.Chunks.Encode (Result.Code);
         Decoded : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
           (Lua.Storage.Buffers.To_String (Bytes),
            Lua.Storage.Reference (Memory));
      begin
         Assert (Decoded.Outcome = Lua.Chunks.Succeeded,
                 "actual line graph did not survive encoding");
         Check_Program (Decoded.Code);
      end;
   end Encoded_Bases;

   procedure Stripped_Bases;
   procedure Stripped_Bases is
      Memory : Lua.Storage.Owner;
      Result : Lua.Canonical_Compiler.Compilation_Result := Lower
        ("return function()" & Long_Line & " end", Memory);
   begin
      --  Stripping removes both halves of every line table. It must not leave
      --  markers that a native reader interprets without an absolute record.
      Assert (Result.Outcome = Lua.Canonical_Compiler.Succeeded,
              "stripped interval fixture failed");
      declare
         Bytes : constant Lua.Storage.Buffers.Buffer :=
           Lua.Chunks.Encode (Result.Code, Strip => True);
         Decoded : constant Lua.Chunks.Decode_Result := Lua.Chunks.Decode
           (Lua.Storage.Buffers.To_String (Bytes),
            Lua.Storage.Reference (Memory));
      begin
         Assert (Decoded.Outcome = Lua.Chunks.Succeeded,
                 "stripped line graph did not survive encoding");
         for Index in 1 .. Prototype_Count (Decoded.Code) loop
            Assert
              (Prototype_At (Decoded.Code, Index).Lines.Is_Empty and then
               Prototype_At (Decoded.Code, Index).Absolute_Lines.Is_Empty,
               "stripping retained one half of the line lookup tables");
         end loop;
      end;
   end Stripped_Bases;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "line baseline: empty root", Empty_Root'Access);
      Test_Support.Add (Suite, "line baseline: interval boundaries",
                        Interval_Boundaries'Access);
      Test_Support.Add (Suite, "line baseline: source jumps",
                        Line_Jumps'Access);
      Test_Support.Add (Suite, "line baseline: children",
                        Child_Prototypes'Access);
      Test_Support.Add (Suite, "line baseline: actual binary",
                        Encoded_Bases'Access);
      Test_Support.Add (Suite, "line baseline: stripped binary",
                        Stripped_Bases'Access);
   end Register;
end Lua.Line_Baseline_Tests;
