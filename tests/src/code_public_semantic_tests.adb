with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Code_Public_Semantic_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure F_Zero;
   procedure F_Zero is
   begin
      --  checkF zero retains float kind.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return 0.0 end,0.0,'floa" &
         "t')" & ASCII.LF &
         "end");
   end F_Zero;

   procedure I_Captured_Zero;
   procedure I_Captured_Zero is
   begin
      --  checkI propagated zero retains integer kind.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return k0 end,0,'integer" &
         "')" & ASCII.LF &
         "end");
   end I_Captured_Zero;

   procedure I_Zero_Floor;
   procedure I_Zero_Floor is
   begin
      --  checkI unary zero and floor division.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return -k0//1 end,0,'int" &
         "eger')" & ASCII.LF &
         "end");
   end I_Zero_Floor;

   procedure K_Reciprocal;
   procedure K_Reciprocal is
   begin
      --  checkK reciprocal retains float kind.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return 3^-1 end,1/3,'flo" &
         "at')" & ASCII.LF &
         "end");
   end K_Reciprocal;

   procedure K_Power;
   procedure K_Power is
   begin
      --  checkK folded power keeps its exact value.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return (1 + 1)^(50 + 50)" &
         " end,2^100,'float')" & ASCII.LF &
         "end");
   end K_Power;

   procedure K_Negative_Power;
   procedure K_Negative_Power is
   begin
      --  checkK negative integer base produces float.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return (-2)^(31 - 2) end" &
         ",-0x20000000 + 0.0,'float')" & ASCII.LF &
         "end");
   end K_Negative_Power;

   procedure F_Floor;
   procedure F_Floor is
   begin
      --  checkF propagated power and float floor division.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return (-k3^0 + 5) // 3." &
         "0 end,1.0,'float')" & ASCII.LF &
         "end");
   end F_Floor;

   procedure I_Modulo;
   procedure I_Modulo is
   begin
      --  checkI negative integer modulo.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return -k3 % 5 end,2,'in" &
         "teger')" & ASCII.LF &
         "end");
   end I_Modulo;

   procedure F_Division;
   procedure F_Division is
   begin
      --  checkF nested power modulo and true division.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return -((2.0^8 + -(-1))" &
         " % 8)/2 * 4 - 3 end,-5.0,'float')" & ASCII.LF &
         "end");
   end F_Division;

   procedure F_Floor_Modulo;
   procedure F_Floor_Modulo is
   begin
      --  checkF power result preserves float floor kind.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return -((2^8 + -(-1)) %" &
         " 8)//2 * 4 - 3 end,-7.0,'float')" & ASCII.LF &
         "end");
   end F_Floor_Modulo;

   procedure I_Bitwise_Mixed;
   procedure I_Bitwise_Mixed is
   begin
      --  checkI mixed float operands become integer bits.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return 0xF0.0 | 0xCC.0 ~" &
         " 0xAA & 0xFD end,0xF4,'integer')" & ASCII.LF &
         "end");
   end I_Bitwise_Mixed;

   procedure I_Bitwise_Not;
   procedure I_Bitwise_Not is
   begin
      --  checkI propagated bitwise constants.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return ~(~kFF0 | kFF0) e" &
         "nd,0,'integer')" & ASCII.LF &
         "end");
   end I_Bitwise_Not;

   procedure I_Bitwise_Float;
   procedure I_Bitwise_Float is
   begin
      --  checkI integral float double complement.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return ~~-1024.0 end,-10" &
         "24,'integer')" & ASCII.LF &
         "end");
   end I_Bitwise_Float;

   procedure I_Shifts;
   procedure I_Shifts is
   begin
      --  checkI constant shifts with a negative displacement.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  one(function()return ((100 << k6) << -" &
         "4) >> 2 end,100,'integer')" & ASCII.LF &
         "end");
   end I_Shifts;

   procedure Integer_Borders;
   procedure Integer_Borders is
   begin
      --  Every integer immediate boundary keeps one integer result.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local a=17;local sbx=((1 << a)-1) >> 1" & ASCII.LF &
         "  local border <const> = 65535" & ASCII.LF &
         "  one(function()return border end,sbx,'i" &
         "nteger')" & ASCII.LF &
         "  one(function()return -border end,-sbx," &
         "'integer')" & ASCII.LF &
         "  one(function()return border+1 end,sbx+" &
         "1,'integer')" & ASCII.LF &
         "  one(function()return border+2 end,sbx+" &
         "2,'integer')" & ASCII.LF &
         "  one(function()return -(border+1)end,-(" &
         "sbx+1),'integer')" & ASCII.LF &
         "end");
   end Integer_Borders;

   procedure Float_Borders;
   procedure Float_Borders is
   begin
      --  Integral float immediates keep their float result kind.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local a=17;local sbx=((1 << a)-1) >> 1" & ASCII.LF &
         "  local border <const> = 65535.0" & ASCII.LF &
         "  one(function()return border end,sbx+0." &
         "0,'float')" & ASCII.LF &
         "  one(function()return -border end,-sbx+" &
         "0.0,'float')" & ASCII.LF &
         "  one(function()return border+1 end,sbx+" &
         "1.0,'float')" & ASCII.LF &
         "  one(function()return border+2 end,sbx+" &
         "2.0,'float')" & ASCII.LF &
         "  one(function()return -(border+1)end,-(" &
         "sbx+1.0),'float')" & ASCII.LF &
         "end");
   end Float_Borders;

   procedure Maximum_Integer;
   procedure Maximum_Integer is
   begin
      --  Generated hexadecimal return survives a binary round trip.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local n=math.maxinteger" & ASCII.LF &
         "  local source=string.format(" & ASCII.LF &
         "    ""local a = {[true] = 0X%x}; return a" &
         "[true]"",n)" & ASCII.LF &
         "  local f=assert(load(source))" & ASCII.LF &
         "  one(f,n,'integer')" & ASCII.LF &
         "  f=assert(load(string.dump(f)))" & ASCII.LF &
         "  one(f,n,'integer')" & ASCII.LF &
         "end");
   end Maximum_Integer;

   procedure Minimum_Integer;
   procedure Minimum_Integer is
   begin
      --  Generated hexadecimal return survives a binary round trip.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local n=math.mininteger" & ASCII.LF &
         "  local source=string.format(" & ASCII.LF &
         "    ""local a = {[true] = 0X%x}; return a" &
         "[true]"",n)" & ASCII.LF &
         "  local f=assert(load(source))" & ASCII.LF &
         "  one(f,n,'integer')" & ASCII.LF &
         "  f=assert(load(string.dump(f)))" & ASCII.LF &
         "  one(f,n,'integer')" & ASCII.LF &
         "end");
   end Minimum_Integer;

   procedure Negative_Hex;
   procedure Negative_Hex is
   begin
      --  Generated hexadecimal return survives a binary round trip.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local n=-1" & ASCII.LF &
         "  local source=string.format(" & ASCII.LF &
         "    ""local a = {[true] = 0X%x}; return a" &
         "[true]"",n)" & ASCII.LF &
         "  local f=assert(load(source))" & ASCII.LF &
         "  one(f,n,'integer')" & ASCII.LF &
         "  f=assert(load(string.dump(f)))" & ASCII.LF &
         "  one(f,n,'integer')" & ASCII.LF &
         "end");
   end Negative_Hex;

   procedure Nested_Constants;
   procedure Nested_Constants is
   begin
      --  Nested constant functions retain values and return arity.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local k0 <const> = ""000000000000000000" &
         "00000000000000000000000000000000""" & ASCII.LF &
         "  local function f1()" & ASCII.LF &
         "    local k <const> = k0" & ASCII.LF &
         "    return function()" & ASCII.LF &
         "      return function()return k end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local result=table.pack(f1())" & ASCII.LF &
         "  assert(result.n==1 and type(result[1])" &
         "=='function')" & ASCII.LF &
         "  local f2=result[1]" & ASCII.LF &
         "  result=table.pack(f2())" & ASCII.LF &
         "  assert(result.n==1 and type(result[1])" &
         "=='function')" & ASCII.LF &
         "  local f3=result[1]" & ASCII.LF &
         "  one(f3,k0,nil)" & ASCII.LF &
         "  for _,f in ipairs({f1,f2,f3})do" & ASCII.LF &
         "    for _,strip in ipairs({false,true})d" &
         "o" & ASCII.LF &
         "      local loaded=assert(load(string.du" &
         "mp(f,strip)))" & ASCII.LF &
         "      local returned=table.pack(loaded()" &
         ")" & ASCII.LF &
         "      assert(returned.n==1)" & ASCII.LF &
         "      if f==f1 then" & ASCII.LF &
         "        returned=table.pack(returned[1](" &
         "))" & ASCII.LF &
         "        assert(returned.n==1 and type(re" &
         "turned[1])=='function')" & ASCII.LF &
         "        one(returned[1],k0,nil)" & ASCII.LF &
         "      elseif f==f2 then" & ASCII.LF &
         "        assert(type(returned[1])=='funct" &
         "ion')" & ASCII.LF &
         "        one(returned[1],k0,nil)" & ASCII.LF &
         "      else assert(returned[1]==k0 and ty" &
         "pe(returned[1])=='string')end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "end");
   end Nested_Constants;

   procedure Callback_Sequence;
   procedure Callback_Sequence is
   begin
      --  The original eight callback arguments retain value and kind.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local foo = function(f,a)" & ASCII.LF &
         "    f(100 * 1000)" & ASCII.LF &
         "    f(100.0 * 1000)" & ASCII.LF &
         "    f(-100 * 1000)" & ASCII.LF &
         "    f(-100 * 1000.0)" & ASCII.LF &
         "    f(100000)" & ASCII.LF &
         "    f(100000.0)" & ASCII.LF &
         "    f(-100000)" & ASCII.LF &
         "    f(-100000.0)" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local seen={}" & ASCII.LF &
         "  local result=table.pack(foo(function(." &
         "..)" & ASCII.LF &
         "    local arguments=table.pack(...)" & ASCII.LF &
         "    assert(arguments.n==1)" & ASCII.LF &
         "    seen[#seen+1]={arguments[1],math.typ" &
         "e(arguments[1])}" & ASCII.LF &
         "  end))" & ASCII.LF &
         "  assert(result.n==0 and #seen==8)" & ASCII.LF &
         "  local values={100000,100000,-100000,-1" &
         "00000,100000,100000,-100000,-100000}" & ASCII.LF &
         "  for i=1,8 do" & ASCII.LF &
         "    assert(seen[i][1]==values[i])" & ASCII.LF &
         "    assert(seen[i][2]==(i%2==1 and 'inte" &
         "ger'or'float'))" & ASCII.LF &
         "  end" & ASCII.LF &
         "end");
   end Callback_Sequence;

   procedure Assignment_Sequence;
   procedure Assignment_Sequence is
   begin
      --  Every repeated absent-key assignment reaches its recorder.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local foo = function(t,a)" & ASCII.LF &
         "    t[a] = 1; t[a] = 1.0" & ASCII.LF &
         "    t[a] = 1; t[a] = 1.0" & ASCII.LF &
         "    t[a] = 2; t[a] = 2.0" & ASCII.LF &
         "    t[a] = 0; t[a] = 0.0" & ASCII.LF &
         "    t[a] = 1; t[a] = 1.0" & ASCII.LF &
         "    t[a] = 2; t[a] = 2.0" & ASCII.LF &
         "    t[a] = 0; t[a] = 0.0" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local seen={};local key={};local proxy" & ASCII.LF &
         "  proxy=setmetatable({},{__newindex=func" &
         "tion(...)" & ASCII.LF &
         "    local args=table.pack(...)" & ASCII.LF &
         "    assert(args.n==3 and args[1]==proxy " &
         "and args[2]==key)" & ASCII.LF &
         "    seen[#seen+1]={args[3],math.type(arg" &
         "s[3])}" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  assert(select('#',foo(proxy,key))==0 a" &
         "nd #seen==14 and next(proxy)==nil)" & ASCII.LF &
         "  local values={1,1,1,1,2,2,0,0,1,1,2,2," &
         "0,0}" & ASCII.LF &
         "  for i=1,14 do" & ASCII.LF &
         "    assert(seen[i][1]==values[i])" & ASCII.LF &
         "    assert(seen[i][2]==(i%2==1 and 'inte" &
         "ger'or'float'))" & ASCII.LF &
         "  end" & ASCII.LF &
         "end");
   end Assignment_Sequence;

   procedure Constructor_49;
   procedure Constructor_49 is
   begin
      --  Constructor boundary values and final vararg expansion.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local n=49" & ASCII.LF &
         "  local ordinary=""local a; return {""..st" &
         "ring.rep(""a, "",n)..""}""" & ASCII.LF &
         "  local empty=table.pack(assert(load(ord" &
         "inary))())" & ASCII.LF &
         "  assert(empty.n==1 and type(empty[1])==" &
         "'table'and next(empty[1])==nil)" & ASCII.LF &
         "  local source=""return function(...) ret" &
         "urn {""..string.rep(""11,"",n-1)..""...} end" &
         """" & ASCII.LF &
         "  local f=assert(load(source))()" & ASCII.LF &
         "  for _,args in ipairs({table.pack(),tab" &
         "le.pack(23),table.pack(23,nil,41.0)})do" & ASCII.LF &
         "    local returned=table.pack(f(table.un" &
         "pack(args,1,args.n)))" & ASCII.LF &
         "    assert(returned.n==1 and type(return" &
         "ed[1])=='table')" & ASCII.LF &
         "    local t=returned[1];local count=0" & ASCII.LF &
         "    for i=1,n-1 do assert(t[i]==11 and m" &
         "ath.type(t[i])=='integer')end" & ASCII.LF &
         "    if args.n==0 then assert(t[n]==nil a" &
         "nd t[n+2]==nil)" & ASCII.LF &
         "    elseif args.n==1 then" & ASCII.LF &
         "      assert(t[n]==23 and math.type(t[n]" &
         ")=='integer'and t[n+2]==nil)" & ASCII.LF &
         "    else" & ASCII.LF &
         "      assert(t[n]==23 and math.type(t[n]" &
         ")=='integer')" & ASCII.LF &
         "      assert(t[n+2]==41 and math.type(t[" &
         "n+2])=='float')" & ASCII.LF &
         "    end" & ASCII.LF &
         "    for k,v in pairs(t)do" & ASCII.LF &
         "      count=count+1;assert(math.type(k)=" &
         "='integer'and k>=1)" & ASCII.LF &
         "      if k<n then assert(v==11 and math." &
         "type(v)=='integer')" & ASCII.LF &
         "      elseif k==n then assert(v==23 and " &
         "math.type(v)=='integer')" & ASCII.LF &
         "      else assert(k==n+2 and v==41 and m" &
         "ath.type(v)=='float')end" & ASCII.LF &
         "    end" & ASCII.LF &
         "    assert(count==n-1+(args.n==3 and 2 o" &
         "r args.n))" & ASCII.LF &
         "    assert(t[n+1]==nil and t[n+3]==nil)" & ASCII.LF &
         "  end" & ASCII.LF &
         "end");
   end Constructor_49;

   procedure Constructor_50;
   procedure Constructor_50 is
   begin
      --  Constructor boundary values and final vararg expansion.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local n=50" & ASCII.LF &
         "  local ordinary=""local a; return {""..st" &
         "ring.rep(""a, "",n)..""}""" & ASCII.LF &
         "  local empty=table.pack(assert(load(ord" &
         "inary))())" & ASCII.LF &
         "  assert(empty.n==1 and type(empty[1])==" &
         "'table'and next(empty[1])==nil)" & ASCII.LF &
         "  local source=""return function(...) ret" &
         "urn {""..string.rep(""11,"",n-1)..""...} end" &
         """" & ASCII.LF &
         "  local f=assert(load(source))()" & ASCII.LF &
         "  for _,args in ipairs({table.pack(),tab" &
         "le.pack(23),table.pack(23,nil,41.0)})do" & ASCII.LF &
         "    local returned=table.pack(f(table.un" &
         "pack(args,1,args.n)))" & ASCII.LF &
         "    assert(returned.n==1 and type(return" &
         "ed[1])=='table')" & ASCII.LF &
         "    local t=returned[1];local count=0" & ASCII.LF &
         "    for i=1,n-1 do assert(t[i]==11 and m" &
         "ath.type(t[i])=='integer')end" & ASCII.LF &
         "    if args.n==0 then assert(t[n]==nil a" &
         "nd t[n+2]==nil)" & ASCII.LF &
         "    elseif args.n==1 then" & ASCII.LF &
         "      assert(t[n]==23 and math.type(t[n]" &
         ")=='integer'and t[n+2]==nil)" & ASCII.LF &
         "    else" & ASCII.LF &
         "      assert(t[n]==23 and math.type(t[n]" &
         ")=='integer')" & ASCII.LF &
         "      assert(t[n+2]==41 and math.type(t[" &
         "n+2])=='float')" & ASCII.LF &
         "    end" & ASCII.LF &
         "    for k,v in pairs(t)do" & ASCII.LF &
         "      count=count+1;assert(math.type(k)=" &
         "='integer'and k>=1)" & ASCII.LF &
         "      if k<n then assert(v==11 and math." &
         "type(v)=='integer')" & ASCII.LF &
         "      elseif k==n then assert(v==23 and " &
         "math.type(v)=='integer')" & ASCII.LF &
         "      else assert(k==n+2 and v==41 and m" &
         "ath.type(v)=='float')end" & ASCII.LF &
         "    end" & ASCII.LF &
         "    assert(count==n-1+(args.n==3 and 2 o" &
         "r args.n))" & ASCII.LF &
         "    assert(t[n+1]==nil and t[n+3]==nil)" & ASCII.LF &
         "  end" & ASCII.LF &
         "end");
   end Constructor_50;

   procedure Constructor_51;
   procedure Constructor_51 is
   begin
      --  Constructor boundary values and final vararg expansion.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local n=51" & ASCII.LF &
         "  local ordinary=""local a; return {""..st" &
         "ring.rep(""a, "",n)..""}""" & ASCII.LF &
         "  local empty=table.pack(assert(load(ord" &
         "inary))())" & ASCII.LF &
         "  assert(empty.n==1 and type(empty[1])==" &
         "'table'and next(empty[1])==nil)" & ASCII.LF &
         "  local source=""return function(...) ret" &
         "urn {""..string.rep(""11,"",n-1)..""...} end" &
         """" & ASCII.LF &
         "  local f=assert(load(source))()" & ASCII.LF &
         "  for _,args in ipairs({table.pack(),tab" &
         "le.pack(23),table.pack(23,nil,41.0)})do" & ASCII.LF &
         "    local returned=table.pack(f(table.un" &
         "pack(args,1,args.n)))" & ASCII.LF &
         "    assert(returned.n==1 and type(return" &
         "ed[1])=='table')" & ASCII.LF &
         "    local t=returned[1];local count=0" & ASCII.LF &
         "    for i=1,n-1 do assert(t[i]==11 and m" &
         "ath.type(t[i])=='integer')end" & ASCII.LF &
         "    if args.n==0 then assert(t[n]==nil a" &
         "nd t[n+2]==nil)" & ASCII.LF &
         "    elseif args.n==1 then" & ASCII.LF &
         "      assert(t[n]==23 and math.type(t[n]" &
         ")=='integer'and t[n+2]==nil)" & ASCII.LF &
         "    else" & ASCII.LF &
         "      assert(t[n]==23 and math.type(t[n]" &
         ")=='integer')" & ASCII.LF &
         "      assert(t[n+2]==41 and math.type(t[" &
         "n+2])=='float')" & ASCII.LF &
         "    end" & ASCII.LF &
         "    for k,v in pairs(t)do" & ASCII.LF &
         "      count=count+1;assert(math.type(k)=" &
         "='integer'and k>=1)" & ASCII.LF &
         "      if k<n then assert(v==11 and math." &
         "type(v)=='integer')" & ASCII.LF &
         "      elseif k==n then assert(v==23 and " &
         "math.type(v)=='integer')" & ASCII.LF &
         "      else assert(k==n+2 and v==41 and m" &
         "ath.type(v)=='float')end" & ASCII.LF &
         "    end" & ASCII.LF &
         "    assert(count==n-1+(args.n==3 and 2 o" &
         "r args.n))" & ASCII.LF &
         "    assert(t[n+1]==nil and t[n+3]==nil)" & ASCII.LF &
         "  end" & ASCII.LF &
         "end");
   end Constructor_51;

   procedure Return_Zero;
   procedure Return_Zero is
   begin
      --  A function with no explicit results returns zero values.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local function f()local a=37 end" & ASCII.LF &
         "  assert(table.pack(f()).n==0)" & ASCII.LF &
         "  assert(table.pack(assert(load(string.d" &
         "ump(f)))()).n==0)" & ASCII.LF &
         "end");
   end Return_Zero;

   procedure Return_One_Nil;
   procedure Return_One_Nil is
   begin
      --  One nil result remains distinct from no result after dump/load.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local function f(a,b,c)return a end" & ASCII.LF &
         "  local result=table.pack(f(nil,37,41.0)" &
         ")" & ASCII.LF &
         "  assert(result.n==1 and result[1]==nil)" & ASCII.LF &
         "  result=table.pack(assert(load(string.d" &
         "ump(f)))(nil,37,41.0))" & ASCII.LF &
         "  assert(result.n==1 and result[1]==nil)" & ASCII.LF &
         "end");
   end Return_One_Nil;

   procedure Return_Multiple;
   procedure Return_Multiple is
   begin
      --  A final nil and float preserve exact result count and kinds.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local function f()return 37,nil,41.0,n" &
         "il end" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==4 and result[1]==37 a" &
         "nd result[2]==nil)" & ASCII.LF &
         "  assert(math.type(result[1])=='integer'" &
         "and result[3]==41)" & ASCII.LF &
         "  assert(math.type(result[3])=='float'an" &
         "d result[4]==nil)" & ASCII.LF &
         "  local loaded=table.pack(assert(load(st" &
         "ring.dump(f)))())" & ASCII.LF &
         "  assert(loaded.n==4 and loaded[1]==37 a" &
         "nd loaded[2]==nil)" & ASCII.LF &
         "  assert(math.type(loaded[1])=='integer'" &
         "and loaded[3]==41)" & ASCII.LF &
         "  assert(math.type(loaded[3])=='float'an" &
         "d loaded[4]==nil)" & ASCII.LF &
         "end");
   end Return_Multiple;

   procedure Register_Load;
   procedure Register_Load is
   begin
      --  Preserve valid and oversized load boundaries without invocation.
      Check
        ("-- Source-linked public semantics; priva" &
         "te optimizer layouts stay separate." & ASCII.LF &
         "local k0aux <const> = 0" & ASCII.LF &
         "local k0 <const> = k0aux" & ASCII.LF &
         "local k3 <const> = 3" & ASCII.LF &
         "local k6 <const> = k3 + (k3 << k0)" & ASCII.LF &
         "local kFF0 <const> = 0xFF0" & ASCII.LF &
         "local function one(f,wanted,kind)" & ASCII.LF &
         "  local result=table.pack(f())" & ASCII.LF &
         "  assert(result.n==1 and result[1]==want" &
         "ed)" & ASCII.LF &
         "  assert(math.type(result[1])==kind)" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local source=""local a; return a(""..str" &
         "ing.rep(""a, "",252)..""a)""" & ASCII.LF &
         "  assert(type(assert(load(source)))=='fu" &
         "nction')" & ASCII.LF &
         "  source=""local a; return a(""..string.re" &
         "p(""a, "",253)..""a)""" & ASCII.LF &
         "  local f,msg=load(source)" & ASCII.LF &
         "  assert(f==nil and string.find(msg,""too" &
         " many registers""))" & ASCII.LF &
         "end");
   end Register_Load;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "code public semantics: f zero",
         F_Zero'Access);
      Test_Support.Add
        (Suite, "code public semantics: i captured zero",
         I_Captured_Zero'Access);
      Test_Support.Add
        (Suite, "code public semantics: i zero floor",
         I_Zero_Floor'Access);
      Test_Support.Add
        (Suite, "code public semantics: k reciprocal",
         K_Reciprocal'Access);
      Test_Support.Add
        (Suite, "code public semantics: k power",
         K_Power'Access);
      Test_Support.Add
        (Suite, "code public semantics: k negative power",
         K_Negative_Power'Access);
      Test_Support.Add
        (Suite, "code public semantics: f floor",
         F_Floor'Access);
      Test_Support.Add
        (Suite, "code public semantics: i modulo",
         I_Modulo'Access);
      Test_Support.Add
        (Suite, "code public semantics: f division",
         F_Division'Access);
      Test_Support.Add
        (Suite, "code public semantics: f floor modulo",
         F_Floor_Modulo'Access);
      Test_Support.Add
        (Suite, "code public semantics: i bitwise mixed",
         I_Bitwise_Mixed'Access);
      Test_Support.Add
        (Suite, "code public semantics: i bitwise not",
         I_Bitwise_Not'Access);
      Test_Support.Add
        (Suite, "code public semantics: i bitwise float",
         I_Bitwise_Float'Access);
      Test_Support.Add
        (Suite, "code public semantics: i shifts",
         I_Shifts'Access);
      Test_Support.Add
        (Suite, "code public semantics: integer borders",
         Integer_Borders'Access);
      Test_Support.Add
        (Suite, "code public semantics: float borders",
         Float_Borders'Access);
      Test_Support.Add
        (Suite, "code public semantics: maximum integer",
         Maximum_Integer'Access);
      Test_Support.Add
        (Suite, "code public semantics: minimum integer",
         Minimum_Integer'Access);
      Test_Support.Add
        (Suite, "code public semantics: negative hex",
         Negative_Hex'Access);
      Test_Support.Add
        (Suite, "code public semantics: nested constants",
         Nested_Constants'Access);
      Test_Support.Add
        (Suite, "code public semantics: callback sequence",
         Callback_Sequence'Access);
      Test_Support.Add
        (Suite, "code public semantics: assignment sequence",
         Assignment_Sequence'Access);
      Test_Support.Add
        (Suite, "code public semantics: constructor 49",
         Constructor_49'Access);
      Test_Support.Add
        (Suite, "code public semantics: constructor 50",
         Constructor_50'Access);
      Test_Support.Add
        (Suite, "code public semantics: constructor 51",
         Constructor_51'Access);
      Test_Support.Add
        (Suite, "code public semantics: return zero",
         Return_Zero'Access);
      Test_Support.Add
        (Suite, "code public semantics: return one nil",
         Return_One_Nil'Access);
      Test_Support.Add
        (Suite, "code public semantics: return multiple",
         Return_Multiple'Access);
      Test_Support.Add
        (Suite, "code public semantics: register load",
         Register_Load'Access);
   end Register;
end Code_Public_Semantic_Tests;
