param(
    [Parameter(Mandatory)][string] $Probe,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [string] $RuntimeDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path $root ('reports/chunk-codec/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$Probe = (Resolve-Path -LiteralPath $Probe).Path
$ReferenceInterpreter = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
$library = Join-Path (Split-Path -Parent (Split-Path -Parent $ReferenceInterpreter)) 'lib'
$prefix = @($library)
if ($RuntimeDirectory -ne '') { $prefix += (Resolve-Path -LiteralPath $RuntimeDirectory).Path }
$environment = @{
    PATH=($prefix -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
    LD_LIBRARY_PATH=($prefix -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    DYLD_LIBRARY_PATH=($prefix -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
$encoding = [Text.UTF8Encoding]::new($false)
$observations = [Collections.Generic.List[object]]::new()
$observedConfiguration = $null
$referenceVerified = $false
$sourceRecords = @()

function Invoke-Fixture {
    param([string] $Executable, [string[]] $Arguments, [string] $Name)
    $result = Invoke-ConformanceProcess -Executable $Executable -Arguments $Arguments `
        -Directory $temporary -OutputPrefix (Join-Path $temporary $Name) `
        -Environment $environment -TimeoutSeconds 60
    $observations.Add($result)
    if ($result.exit_code -ne 0 -or $result.timed_out -or $result.abnormal_exit_kind -or
        $result.stderr_bytes -ne 0 -or $result.capture_exceeded -or $result.pipe_drain_failed -or
        $result.process_tree_kill_error) {
        throw "Chunk fixture failed: $Name; see $($result.stderr_path)"
    }
    return $result
}

$generator = @'
global <const> *
local sources = {
  'return 42',
  'local x=5;return function(y,...) return x+y,select("#",...) end',
  'local t={1,2,3};local s=0;for i,v in pairs(t) do s=s+i*v end;'..
    'for i=1,3 do s=s+i end;return s',
  'local s=0;do local r <close> = setmetatable({},'..
    '{__close=function()s=s+1 end});goto out end ::out:: return s',
  'local function f(...v) return #v,v[2],select("#",...) end;return f(2,3,4)',
  'local function f()'..string.rep('\n',350)..'return 7 end;return f()',
  'return math.mininteger,math.maxinteger,-0.0,0x1p-1074,"a\\0b","'..
    string.rep('long',80)..'"',
  'local a,b=...;a=a or 7;b=b or 3;local t={x=a};t[3]=b;'..
    'return (a+b)*(a-b),a//b,a%b,a<<b,a~b,t.x..t[3]',
}
local list=assert(io.open('manifest.txt','wb'))
for index,source in ipairs(sources) do
  local f=assert(load('global <const> *;'..source,'@codec-'..index))
  for _,strip in ipairs({false,true}) do
    local name=string.format('case-%02d-%s.luac',index,strip and 'strip' or 'full')
    local file=assert(io.open(name,'wb'));file:write(string.dump(f,strip));file:close()
    list:write(name,'\n')
  end
end
list:close()
print('CHUNK FIXTURES OK')
'@
$verifier = @'
global <const> *
local function observe(f)
  local r=table.pack(f(7,3))
  if type(r[1])=='function' then r=table.pack(r[1](9,4,5)) end
  local out={tostring(r.n)}
  for i=1,r.n do
    local x=r[i];local kind=type(x)
    if kind=='number' then
      x=math.type(x)=='integer' and string.pack('j',x) or string.pack('d',x)
    elseif kind=='string' then x=x
    else x=tostring(x) end
    out[#out+1]=kind..':'..#x..':'..x
  end
  return table.concat(out,'|')
end
local first=assert(loadfile(arg[1],'b'))
if arg[2] then
  assert(observe(first)==observe(assert(loadfile(arg[2],'b'))))
else assert(first()==42) end
print('CHUNK CROSSLOAD OK')
'@
[IO.File]::WriteAllText((Join-Path $temporary 'generate.lua'),$generator,$encoding)
[IO.File]::WriteAllText((Join-Path $temporary 'verify.lua'),$verifier,$encoding)
$records = [Collections.Generic.List[object]]::new()
try {
    # The same native binary can have materially different compile-time
    # behavior. Verify its measured profile and the complete immutable source
    # tree rather than labeling an arbitrary installed Lua as the pinned oracle.
    Test-ConformanceReferenceTree -Root $root
    $referenceVerified = $true
    foreach ($name in @('ldump.c','lundump.c','lundump.h','lopcodes.h','lobject.h')) {
        $path = Join-Path $root "references/lua/$name"
        $sourceRecords += [ordered]@{path=$name;
            sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    }
    $configurationProcess = Invoke-Fixture $ReferenceInterpreter @('--conformance-config') 'configuration'
    $observedConfiguration = Get-Content -LiteralPath $configurationProcess.stdout_path -Raw |
        ConvertFrom-Json -AsHashtable
    [void](Test-ConformanceConfiguration -Observed $observedConfiguration `
        -Configuration $Configuration -Target ReferenceC `
        -AllocatorLimitBytes 2147483648L)
    if ($observedConfiguration.implementation -cne 'C Lua' -or
        $observedConfiguration.test_adapter -cne ($Configuration -eq 'upstream-test')) {
        throw 'The codec reference must be the actual configured C oracle'
    }
    [void](Invoke-Fixture $ReferenceInterpreter @('generate.lua') 'generate')
    $cases = @(Get-Content -LiteralPath (Join-Path $temporary 'manifest.txt'))
    if ($cases.Count -ne 16) { throw 'Expected sixteen C-produced chunk fixtures' }
    foreach ($name in $cases) {
        $copy = $name + '.ada'
        [void](Invoke-Fixture $Probe @('roundtrip',$name,$copy) ($name + '-roundtrip'))
        [void](Invoke-Fixture $ReferenceInterpreter @('verify.lua',$name,$copy) ($name + '-crossload'))
        $originalHash = (Get-FileHash -LiteralPath (Join-Path $temporary $name) -Algorithm SHA256).Hash
        $copyHash = (Get-FileHash -LiteralPath (Join-Path $temporary $copy) -Algorithm SHA256).Hash
        if ($originalHash -cne $copyHash) { throw "Canonical bytes changed on roundtrip: $name" }
        $records.Add([ordered]@{source=$name;source_sha256=$originalHash;copy=$copy;
            copy_sha256=$copyHash;mode='preserved';result='passed'})
        if ($name.EndsWith('-full.luac')) {
            $stripped = $name + '.ada-stripped'
            [void](Invoke-Fixture $Probe @('roundtrip',$name,$stripped,'strip') ($name + '-strip'))
            [void](Invoke-Fixture $ReferenceInterpreter @('verify.lua',$name,$stripped) ($name + '-strip-crossload'))
            $records.Add([ordered]@{source=$name;source_sha256=$originalHash;copy=$stripped;
                copy_sha256=(Get-FileHash -LiteralPath (Join-Path $temporary $stripped) -Algorithm SHA256).Hash;
                mode='stripped';result='passed'})
        }
    }
    [void](Invoke-Fixture $Probe @('emit','ada-built.luac') 'emit')
    [void](Invoke-Fixture $ReferenceInterpreter @('verify.lua','ada-built.luac') 'emit-crossload')
    Write-Output 'PASS: chunk codec; 16 exact roundtrips, 8 stripped crossloads, Ada-built C execution'
}
finally {
    $report=[ordered]@{schema_version=1;reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        scope='standalone-codec-only; not Ada canonical VM execution';
        configuration=$Configuration;observed_configuration=$observedConfiguration;
        reference_tree_verified=$referenceVerified;source_records=$sourceRecords;
        host=[Runtime.InteropServices.RuntimeInformation]::OSDescription;
        probe=$Probe;reference=$ReferenceInterpreter;
        probe_sha256=(Get-FileHash -LiteralPath $Probe -Algorithm SHA256).Hash;
        reference_sha256=(Get-FileHash -LiteralPath $ReferenceInterpreter -Algorithm SHA256).Hash;
        cases=$records.ToArray();processes=$observations.ToArray()}
    [IO.File]::WriteAllText((Join-Path $temporary 'report.json'),
        (ConvertTo-Json -InputObject $report -Depth 12)+"`n",$encoding)
}
