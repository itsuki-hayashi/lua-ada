param(
    [Parameter(Mandatory)][string] $Probe,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [string] $RuntimeProbe = '',
    [string] $RuntimeDirectory = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/canonical-compiler/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$Probe = (Resolve-Path -LiteralPath $Probe).Path
$ReferenceInterpreter = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
if ($RuntimeProbe -ne '') { $RuntimeProbe = (Resolve-Path -LiteralPath $RuntimeProbe).Path }
$library = Join-Path (Split-Path -Parent (Split-Path -Parent $ReferenceInterpreter)) 'lib'
$paths = @($library)
if ($RuntimeDirectory -ne '') { $paths += (Resolve-Path -LiteralPath $RuntimeDirectory).Path }
$environment = @{
    PATH=($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
    LD_LIBRARY_PATH=($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    DYLD_LIBRARY_PATH=($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
$encoding = [Text.UTF8Encoding]::new($false)
$observations = [Collections.Generic.List[object]]::new()
$records = [Collections.Generic.List[object]]::new()
$configurationObserved = $null
function Invoke-Fixture {
    param([string] $Executable, [string[]] $Arguments, [string] $Name)
    $result = Invoke-ConformanceProcess -Executable $Executable -Arguments $Arguments `
        -Directory $directory -OutputPrefix (Join-Path $directory $Name) `
        -Environment $environment -TimeoutSeconds 60
    $observations.Add($result)
    if ($result.exit_code -ne 0 -or $result.timed_out -or $result.abnormal_exit_kind -or
        $result.stderr_bytes -ne 0 -or $result.capture_exceeded -or $result.pipe_drain_failed -or
        $result.process_tree_kill_error) {
        throw "Canonical compiler fixture failed: $Name; see $($result.stderr_path)"
    }
    return $result
}
# Each fixture has one named semantic purpose. Both observed executions use
# the same isolated C VM: this tests Ada code generation, not Ada VM parity.
$cases = [ordered]@{
    primitives = 'print(1+2,9-4,3*7,7/2,7//2,7%2,2^3,5&3,5|2,5~2,5<<2,20>>2,-7,~7,not nil,#"abc","a".."b",1==1,1~=2,1<2,1<=1,2>1,2>=2)'
    short_circuit = 'local n=0;local function f() n=n+1;return n end;print(false and f(),true or f(),nil or f(),n,(false or 3) and 4)'
    closure_mutation = 'local function make()local n=0;return function(x)n=n+x;return n end end;local a,b=make(),make();print(a(2),a(3),b(9),a(1))'
    recursion_tail = 'local function f(n,a)if n==0 then return a end;return f(n-1,a+n)end;print(f(2000,0))'
    methods = 'local t={x=9};function t:f(a,...)return self.x+a,select("#",...),... end;print(t:f(3,7,8))'
    multiple_results = 'local function f()return 2,3,4 end;local a,b,c,d=1,f();print(a,b,c,d);a,b,c=f(),f();print(a,b,c);print((f()),f())'
    zero_results = 'local function f()end;local a,b=f();print(a,b,select("#",f()),select("#",(f())))'
    parallel_assignment = 'local a,i,t=1,1,{10,20};i,t[i],a=2,99,i;print(i,t[1],t[2],a);local x,y=3,4;x,y=y,x;print(x,y)'
    environments = 'local original=_ENV;local x=7;local _ENV=setmetatable({x=11},{__index=original});local function f()return x,math.type(1),_ENV.x end;print(f())'
    constructors = 'local function f()return 7,8,9 end;local n=0;local function key()n=n+1;return "k" end;local t={[key()]=2,3,4,f()};print(n,t.k,#t,t[1],t[2],t[3],t[4],t[5])'
    while_repeat = 'local i,s=0,0;while i<8 do i=i+1;if i==6 then break end;s=s+i end;repeat local x=i;i=i-1 until x==3;print(i,s)'
    numeric_loops = 'local f={};for i=1,3 do f[i]=function()return i end end;for i=1,3 do end;local s=0;for i=5,1,-2 do s=s+i end;print(f[1](),f[2](),f[3](),s)'
    generic_loops = 'local s=0;for i,v in ipairs({3,4,5})do s=s+i*v end;local f={};for k,v in pairs({a=1,b=2})do f[k]=function()return k,v end end;print(s,f.a(),f.b())'
    iterator_closing = 'local n=0;local r=setmetatable({},{__close=function()n=n+1 end});local function f(_,i)if i<3 then return i+1,i+10 end end;local s=0;for i,v in f,nil,0,r do s=s+v;if i==2 then break end end;print(s,n)'
    backward_goto = 'local t={};local i=0;::again:: local x=i;t[#t+1]=function()return x end;i=i+1;if i<3 then goto again end;print(t[1](),t[2](),t[3]())'
    goto_close = 'local s="";local function resource(x)return setmetatable({},{__close=function()s=s..x end})end;do local a <close> = resource("a");do local b <close> = resource("b");goto done end end;::done::print(s)'
    protected_close = 'local s="";local function f()local x <close> = setmetatable({},{__close=function(_,e)s=type(e)end});error({})end;local ok,e=pcall(f);print(ok,type(e),s)'
    named_varargs = 'local function f(a,...v)local g=function()return v[2],v.n end;v[1]=a;return g(),v[1],... end;print(f(8,2,3,4))'
    const_captures = 'local a <const> = 1+2;local b,c <const> = 4,"bytes";local function f()return a,b,c end;print(f());print(debug.getupvalue(f,1))'
    coroutine_frames = 'local co=coroutine.create(function(a)local b=coroutine.yield(a+1,a+2);return b*2 end);print(coroutine.resume(co,3));print(coroutine.resume(co,9));print(coroutine.status(co))'
    metamethods = 'local m={__add=function(a,b)return a.n+b.n end,__index=function(_,k)return k end,__call=function(_,x)return x+1 end};local a,b=setmetatable({n=2},m),setmetatable({n=5},m);print(a+b,a.foo,a(7))'
    globals = 'global fresh_value = 3;global function fresh_function(x)return fresh_value+x end;print(fresh_function(4))'
    false_closing_binding = 'local n=0;do local r <close> = false;local f=function()return r end;debug.setupvalue(f,1,setmetatable({},{__close=function()n=n+1 end}))end;print(n)'
    weak_dead_temporaries = 'local w=setmetatable({},{__mode="v"});do local x={};w[1]=x end;collectgarbage();print(w[1])'
    goto_inside_iterator = 'local n=0;local r=setmetatable({},{__close=function()n=n+1 end});local function f(_,i)if i<3 then return i+1 end end;local s=0;for i in f,nil,0,r do if i==2 then goto skip end;s=s+i;::skip::end;print(s,n)'
    repeat_closing = 'local s="";local i=0;repeat local r <close> = setmetatable({},{__close=function()s=s..i end});i=i+1 until i==3;print(s)'
    closing_error_replacement = 'local function f()local x <close> = setmetatable({},{__close=function()error(37)end});error(19)end;local ok,e=pcall(f);print(ok,e)'
    concat_association = 'local s="";local m={__concat=function(a,b)s=s..a.n..b.n;return setmetatable({n=a.n..b.n},getmetatable(a))end};local a,b,c=setmetatable({n="a"},m),setmetatable({n="b"},m),setmetatable({n="c"},m);print((a..b..c).n,s)'
    numeric_integer_limits = 'local n=0;for i=math.maxinteger-1,math.maxinteger do n=n+1 end;for i=math.mininteger+1,math.mininteger,-1 do n=n+1 end;print(n)'
    fixed_vararg_large_n = 'local function f(...v)v.n=1000001;local x=...;return x end;print(f(7))'
    parallel_environment = 'global result;local old=_ENV;local replacement={};_ENV,result=replacement,41;old.print(old.result,replacement.result);_ENV=old'
    binary_string_constants = 'local s="a\0\255b";print(#s,string.byte(s,1,-1),s=="a\0\255b")'
    global_redefinition = 'global only_once=1;local ok,e=pcall(function()global only_once=2 end);print(ok,type(e),only_once)'
    random_defaults = 'math.randomseed(17,-9);print(math.random(),math.random(0));local a,b=math.randomseed();print(math.type(a),math.type(b),math.type(math.random(0)))'
    loaded_environment = 'local env={x=17};local f=assert(load("return x",nil,"t",env));print(f());local g=assert(load("return _ENV",nil,"t",nil));print(g())'
    extended_constructor = ('local function f()return 8,9 end;local t={' + ((1..1025 | ForEach-Object { '1' }) -join ',') + ',f()};print(#t,t[1025],t[1026],t[1027])')
}
$dump = @'
global <const> *
local output=assert(io.open(arg[2],'wb'))
output:write(string.dump(assert(loadfile(arg[1]))))
output:close()
'@
[IO.File]::WriteAllText((Join-Path $directory 'dump.lua'),$dump,$encoding)
try {
    Test-ConformanceReferenceTree -Root $root
    $measured = Invoke-Fixture $ReferenceInterpreter @('--conformance-config') 'configuration'
    $configurationObserved = Get-Content -LiteralPath $measured.stdout_path -Raw | ConvertFrom-Json -AsHashtable
    [void](Test-ConformanceConfiguration -Observed $configurationObserved -Target ReferenceC `
        -Configuration $Configuration -AllocatorLimitBytes 2147483648L)
    if ($configurationObserved.implementation -cne 'C Lua') { throw 'An actual C oracle is required' }
    foreach ($entry in $cases.GetEnumerator()) {
        $name = $entry.Key + '.lua'
        $source = 'global <const> *;' + $entry.Value + "`n"
        [IO.File]::WriteAllText((Join-Path $directory $name),$source,$encoding)
        $compiled = $name + '.luac'
        [void](Invoke-Fixture $Probe @($name,$compiled) ($entry.Key + '-compile'))
        $original = Invoke-Fixture $ReferenceInterpreter @($name) ($entry.Key + '-source')
        $canonical = Invoke-Fixture $ReferenceInterpreter @($compiled) ($entry.Key + '-chunk')
        $expected = [Convert]::ToBase64String([IO.File]::ReadAllBytes($original.stdout_path))
        $actual = [Convert]::ToBase64String([IO.File]::ReadAllBytes($canonical.stdout_path))
        if ($expected -cne $actual) { throw "Canonical compiler output mismatch: $($entry.Key)" }
        if ($RuntimeProbe -ne '') {
            $cChunk = $name + '.c.luac'
            [void](Invoke-Fixture $ReferenceInterpreter @('dump.lua',$name,$cChunk) ($entry.Key + '-c-dump'))
            foreach ($inputChunk in @($compiled,$cChunk)) {
                $ada = Invoke-Fixture $RuntimeProbe @($inputChunk) ($entry.Key + '-ada-' + $inputChunk)
                $observed = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ada.stdout_path))
                if ($expected -cne $observed) {
                    throw "Canonical Ada runtime mismatch: $($entry.Key)/$inputChunk"
                }
            }
        }
        $records.Add([ordered]@{name=$entry.Key;result='passed';
            source_sha256=(Get-FileHash -LiteralPath (Join-Path $directory $name) -Algorithm SHA256).Hash;
            chunk_sha256=(Get-FileHash -LiteralPath (Join-Path $directory $compiled) -Algorithm SHA256).Hash})
    }
    if ($RuntimeProbe -ne '') {
        Write-Output "PASS: $($records.Count) four-way canonical C/Ada compiler/runtime cases"
    } else {
        Write-Output "PASS: $($records.Count) canonical compiler cases executed by C (Ada VM checked separately)"
    }
}
finally {
    $report=[ordered]@{schema_version=1;configuration=$Configuration;
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        observed_configuration=$configurationObserved;scope='Ada compiler; separate C VM execution';
        runtime_probe=$RuntimeProbe;four_way=($RuntimeProbe -ne '');
        compiler_probe_sha256=(Get-FileHash -LiteralPath $Probe -Algorithm SHA256).Hash;
        reference_sha256=(Get-FileHash -LiteralPath $ReferenceInterpreter -Algorithm SHA256).Hash;
        cases=$records.ToArray();processes=$observations.ToArray()}
    [IO.File]::WriteAllText((Join-Path $directory 'report.json'),
        (ConvertTo-Json -InputObject $report -Depth 12)+"`n",$encoding)
}
