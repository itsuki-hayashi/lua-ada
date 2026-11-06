with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Binary_Runtime_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      State : Session;
      Result : constant Execution_Result := Execute
        (State, Source, "=binary-regression");
   begin
      Assert (Result.Status = Succeeded,
              To_String (Result.Error.Message));
   end Check;

   procedure Simple_Roundtrip;
   procedure Nested_Subtree;
   procedure Initial_Upvalues;
   procedure Explicit_Nil_Environment;
   procedure Stripped_Metadata;
   procedure Retained_Metadata;
   procedure Fragmented_Reader;
   procedure Mode_Selection;
   procedure Version_Failure;
   procedure Truncation_Failure;
   procedure Native_Dump_Rejected;
   procedure Dump_Type_Checked;
   procedure Collection_Roundtrips;
   procedure Shifted_Binary_Arguments;
   procedure Malformed_Execution_Recovery;
   procedure Nested_Register_Quota;

   procedure Simple_Roundtrip is
      --  Dump a real closure and execute the resulting native bytes. The
      --  signature
      --  and return value protect the normal Lua-facing dump/load path.
   begin
      Check
        ("local b=string.dump(function()return 42 end);" &
         "assert(b:sub(1,4)=='\27Lua');" &
         "assert(assert(load(b,'binary','b'))()==42)");
   end Simple_Roundtrip;

   procedure Nested_Subtree is
      --  Select an inner prototype rather than its owning compilation root.
      --  Loading
      --  the outer chunk instead would return a function or no useful result.
   begin
      Check
        ("local function outer()return function(a,b)return a+b end end;" &
         "local b=string.dump(outer());local f=assert(load(b));" &
         "assert(f(17,25)==42)");
   end Nested_Subtree;

   procedure Initial_Upvalues is
      --  Binary chunks serialize capture descriptors, not captured runtime
      --  values.
      --  The first fresh cell receives the explicit environment; others nil.
   begin
      Check
        ("local x,y=17,19;local f=function()return x,y end;" &
         "local env={marker=23};" &
         "local g=assert(load(string.dump(f),nil,'b',env));local a,b=g();" &
         "assert(a==env and b==nil)");
   end Initial_Upvalues;

   procedure Explicit_Nil_Environment is
      --  An explicit nil environment must remain nil after binary loading.
      --  Omitted
      --  environments instead receive the session globals through their cell.
   begin
      Check
        ("local f=function()return missing end;" &
         "local g=assert(load(string.dump(f),nil,'b',nil));" &
         "assert(select(2,debug.getupvalue(g,1))==nil);" &
         "assert(not pcall(g))");
   end Explicit_Nil_Environment;

   procedure Stripped_Metadata is
      --  Strip source/local names while retaining executable parameters and
      --  source
      --  ranges. A dumped nested function remains Lua, not a main chunk.
   begin
      Check
        ("local f=assert(load('return function(value)return value " &
         "end','=original'))();local g=assert(load(string.dump(f,true)));" &
         "local i=debug.getinfo(g,'S');" &
         "assert(i.what=='Lua' and i.source=='=?' and g(9)==9)");
   end Stripped_Metadata;

   procedure Retained_Metadata is
      --  An unstripped binary retains its embedded source identity and
      --  parameters.
      --  The loader label must not replace the source stored in that graph.
   begin
      Check
        ("local f=assert(load('return function(a,b)return a+b " &
         "end','=original'))();" &
         "local g=assert(load(string.dump(f,false),'replacement'));" &
         "local i=debug.getinfo(g,'Su');" &
         "assert(i.source=='=original' and i.what=='Lua' and " &
         "i.nparams==2)");
   end Retained_Metadata;

   procedure Fragmented_Reader is
      --  Return small binary fragments through a Lua reader callback.
      --  Embedded NUL
      --  and header boundaries must survive native continuation assembly.
   begin
      Check
        ("local b=string.dump(function()return 'a\0b' end);local i=1;" &
         "local f=assert(load(function()if i>#b then return nil end;" &
         "local s=b:sub(i,i+6);i=i+7;return s end,nil,'b'));" &
         "assert(f()=='a\0b')");
   end Fragmented_Reader;

   procedure Mode_Selection is
      --  Apply the signature-selected mode check before decoding. Both
      --  disallowed
      --  directions fail, while a combined mode accepts the binary chunk.
   begin
      Check
        ("local b=string.dump(function()end);local f,e=load(b,nil,'t');" &
         "assert(not f and e:find('binary'));" &
         "f,e=load('return 1',nil,'b');assert(not f and e:find('text'));" &
         "assert(load(b,nil,'bt'))");
   end Mode_Selection;

   procedure Version_Failure is
      --  Change only the native header version. The load must return
      --  nil/message,
      --  preserving a catchable syntax failure rather than running any bytes.
   begin
      Check
        ("local b=string.dump(function()return 1 end);" &
         "b=b:sub(1,4)..string.char(0)..b:sub(6);" &
         "local f,e=load(b,nil,'b');assert(not f and e:find('version'))");
   end Version_Failure;

   procedure Truncation_Failure is
      --  Remove the final required metadata byte from a valid emitted
      --  chunk. The
      --  partial graph must be discarded and the session stay usable.
   begin
      Check
        ("local b=string.dump(function()return 1 end);" &
         "local f,e=load(b:sub(1,#b-1),nil,'b');" &
         "assert(not f and type(e)=='string')");
   end Truncation_Failure;

   procedure Native_Dump_Rejected is
      --  A native function has no serializable Lua prototype. Reject it
      --  explicitly
      --  instead of producing a fabricated empty chunk or function handle.
   begin
      Check
        ("local ok,e=pcall(string.dump,print);" &
         "assert(not ok and e:find('unable to dump'))");
   end Native_Dump_Rejected;

   procedure Dump_Type_Checked is
      --  Validate the source function type independently from native-function
      --  rejection, preserving the Lua argument-error boundary.
   begin
      Check
        ("local ok,e=pcall(string.dump,{});" &
         "assert(not ok and e:find('function expected'))");
   end Dump_Type_Checked;

   procedure Collection_Roundtrips is
      --  Collect between repeated dump/load calls while each loaded closure is
      --  live. Its owned code/constants survive and previous graphs expire.
   begin
      Check
        ("for i=1,40 do local b=string.dump(function(x)return x+1 end);" &
         "local g=assert(load(b));assert(g(i)==i+1);collectgarbage()end");
   end Collection_Roundtrips;

   procedure Shifted_Binary_Arguments is
      State : Session;
      Prepared : constant Execution_Result := Execute
        (State, "print(string.dump(function(...)print(...)end))");
      Bytes : constant String := To_String (Prepared.Output);
      Source : String (17 .. 17 + Bytes'Length - 2);
      Result : Execution_Result;
   begin
      --  Capture emitted bytes through the existing byte-preserving output
      --  API, remove print's LF, and pass an unusual String lower bound.
      --  Real chunk arguments must reach the loaded function's vararg slots.
      Assert (Prepared.Status = Succeeded, "binary fixture did not dump");
      Source := Bytes (Bytes'First .. Bytes'Last - 1);
      Result := Execute (State, Source, "shifted-binary",
        Arguments => [1 => To_Unbounded_String ("first"),
                      2 => To_Unbounded_String ("second")]);
      Assert (Result.Status = Succeeded and then
                To_String (Result.Output) = "first" &
                  Ada.Characters.Latin_1.HT & "second" &
                  Ada.Characters.Latin_1.LF, "shifted binary arguments");
   end Shifted_Binary_Arguments;

   procedure Malformed_Execution_Recovery is
      State : Session;
      Result : Execution_Result;
   begin
      --  Raw embedding also recognizes a native signature. Truncated input
      --  is a structured syntax failure; another chunk can still execute.
      Result := Execute (State, Character'Val (27) & "Lua", "bad-binary");
      Assert (Result.Status = Syntax_Error, "bad binary status");
      Result := Execute (State, "print(42)", "binary-recovery");
      Assert (Result.Status = Succeeded and then
                To_String (Result.Output) = "42" &
                  Ada.Characters.Latin_1.LF, "binary damaged session");
   end Malformed_Execution_Recovery;

   procedure Nested_Register_Quota is
      State : Session;
      Result : Execution_Result;
   begin
      --  A low host register quota applies to every adopted prototype, even
      --  an uncalled child. Validate all code before a chunk can run effects.
      Set_Limits (State, (Registers => 3, others => <>));
      Result := Execute (State,
        "local f=function()local a,b,c,d=1,2,3,4;return a+b+c+d end",
        "nested-register-quota");
      Assert (Result.Status = Resource_Error, "nested register quota bypass");
   end Nested_Register_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "binary runtime: simple roundtrip",
                        Simple_Roundtrip'Access);
      Test_Support.Add (Suite, "binary runtime: selected nested subtree",
                        Nested_Subtree'Access);
      Test_Support.Add (Suite, "binary runtime: initial capture cells",
                        Initial_Upvalues'Access);
      Test_Support.Add (Suite, "binary runtime: explicit nil environment",
                        Explicit_Nil_Environment'Access);
      Test_Support.Add (Suite, "binary runtime: stripped debug metadata",
                        Stripped_Metadata'Access);
      Test_Support.Add (Suite, "binary runtime: retained source identity",
                        Retained_Metadata'Access);
      Test_Support.Add (Suite, "binary runtime: fragmented binary reader",
                        Fragmented_Reader'Access);
      Test_Support.Add (Suite, "binary runtime: binary mode filtering",
                        Mode_Selection'Access);
      Test_Support.Add (Suite, "binary runtime: invalid native version",
                        Version_Failure'Access);
      Test_Support.Add (Suite, "binary runtime: truncated native chunk",
                        Truncation_Failure'Access);
      Test_Support.Add (Suite, "binary runtime: native function rejection",
                        Native_Dump_Rejected'Access);
      Test_Support.Add (Suite, "binary runtime: dump argument type",
                        Dump_Type_Checked'Access);
      Test_Support.Add (Suite, "binary runtime: collection during roundtrips",
                        Collection_Roundtrips'Access);
      Test_Support.Add (Suite, "binary runtime: shifted arguments",
                        Shifted_Binary_Arguments'Access);
      Test_Support.Add (Suite, "binary runtime: malformed recovery",
                        Malformed_Execution_Recovery'Access);
      Test_Support.Add (Suite, "binary runtime: nested register quota",
                        Nested_Register_Quota'Access);
   end Register;
end Binary_Runtime_Tests;
