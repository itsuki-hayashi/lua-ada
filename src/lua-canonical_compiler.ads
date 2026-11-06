with Lua.Lexers;
with Lua.Prototypes;
with Lua.Storage;
with Lua.Syntax_Trees;

private package Lua.Canonical_Compiler is
   type Status is
     (Succeeded, Compiler_Limit, Resource_Limit, Memory_Failure);
   type Error_Kind is
     (No_Error, Register_Limit, Local_Limit, Upvalue_Limit, Jump_Limit,
      Constant_Encoding_Limit, Instruction_Budget, Constant_Budget,
      Prototype_Budget, Nesting_Budget, Allocation_Refused);
   type Lowering_Limits is record
      Instructions : Positive := Positive'Last;
      Constants : Positive := Positive'Last;
      Prototypes : Positive := Positive'Last;
      Nesting : Positive := 200;
   end record;
   type Compilation_Result is limited record
      Outcome : Status := Compiler_Limit;
      Error : Error_Kind := No_Error;
      Location : Lua.Lexers.Source_Location;
      Code : Lua.Prototypes.Program;
   end record;
   function Compile
     (Unit : in out Lua.Syntax_Trees.Compilation_Unit;
      Memory : not null Lua.Storage.Owner_Access;
      Source_Name : String;
      Bounds : Lowering_Limits := (others => <>)) return Compilation_Result;
   --  Lower an already successful resolved unit into owned canonical code.
   --  The frontend remains the only grammar and static resolver. Semantic
   --  encoding limits remain distinct from explicit host work budgets.
   --  Every retained byte/vector and temporary work list uses Memory, which
   --  must outlive the result. No engine values or runtime heap are touched.
   --  @exception Program_Error Unit has not passed shared frontend checking.
   function Message (Error : Error_Kind) return String;
end Lua.Canonical_Compiler;
