param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [string] $RuntimeDirectory = '',
    [ValidateSet('default','upstream-test')][string] $Configuration='default'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/binary-cli/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$Interpreter = (Resolve-Path -LiteralPath $Interpreter).Path
$ReferenceInterpreter = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
$library = Join-Path (Split-Path -Parent (Split-Path -Parent $ReferenceInterpreter)) 'lib'
$paths = @($library)
if ($RuntimeDirectory -ne '') { $paths += (Resolve-Path -LiteralPath $RuntimeDirectory).Path }
$environment = @{
    PATH=($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
    LD_LIBRARY_PATH=($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    DYLD_LIBRARY_PATH=($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
$encoding = [Text.UTF8Encoding]::new($false)
$processes = [Collections.Generic.List[object]]::new()
$cases = [Collections.Generic.List[object]]::new()
function Invoke-Fixture {
    param([string] $Executable, [string[]] $Arguments, [string] $Name)
    $result = Invoke-ConformanceProcess -Executable $Executable -Arguments $Arguments `
        -Directory $directory -OutputPrefix (Join-Path $directory $Name) `
        -Environment $environment -TimeoutSeconds 60
    $processes.Add($result)
    if ($result.exit_code -ne 0 -or $result.timed_out -or $result.abnormal_exit_kind -or
        $result.stderr_bytes -ne 0 -or $result.capture_exceeded -or $result.pipe_drain_failed -or
        $result.process_tree_kill_error) { throw "Binary CLI fixture failed: $Name; see $($result.stderr_path)" }
    return $result
}
function Compare-Output {
    param([object] $Expected, [object] $Actual, [string] $Name)
    $left = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Expected.stdout_path))
    $right = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Actual.stdout_path))
    if ($left -cne $right) { throw "Binary CLI byte output mismatch: $Name" }
    $cases.Add([ordered]@{name=$Name;result='passed';stdout_base64=$left})
}
$generate = @'
global <const> *
local function write(name,data)
  local f=assert(io.open(name,'wb'));f:write(data);f:close()
end
local main=assert(load('global <const> *;print("C_BINARY",7)', '@c-main'))
local bytes=string.dump(main)
write('plain.luac',bytes)
write('bom.luac','\239\187\191'..bytes)
write('shebang.luac','#!/usr/bin/env lua\n'..bytes)
write('bom-shebang.luac','\239\187\191#!/usr/bin/env lua\n'..bytes)
local function named(a,...v) print(tonumber(a)+v.n,v[1],v.n) end
write('named.luac',string.dump(named))
local captured={}
local function nonenv() return captured end
write('nonenv.luac',string.dump(nonenv))
print('BINARY CLI FIXTURES OK')
'@
$environments = @'
global <const> *
local f=assert(loadfile('nonenv.luac','b'))
print(type(f()),f()==_G)
local data
-- read bytes without io: string.dump returns the actual just-loaded closure.
data=string.dump(f)
local g=assert(load(data,'=explicit nil','b',nil))
print(g()==nil,debug.getinfo(g,'S').what)
'@
$dump = @'
global <const> *
local function f() print('ADA_BINARY',17) end
local data=string.dump(f,ARG_STRIP)
local hex={}
for index=1,#data do hex[index]=string.format('%02x',string.byte(data,index)) end
print(table.concat(hex))
'@
try {
    Test-ConformanceReferenceTree -Root $root
    $configurationProcess = Invoke-Fixture $ReferenceInterpreter @('--conformance-config') 'configuration'
    $observed = Get-Content -LiteralPath $configurationProcess.stdout_path -Raw | ConvertFrom-Json -AsHashtable
    [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration `
        -Target ReferenceC -AllocatorLimitBytes 2147483648L)
    [IO.File]::WriteAllText((Join-Path $directory 'generate.lua'),$generate,$encoding)
    [void](Invoke-Fixture $ReferenceInterpreter @('generate.lua') 'generate')
    foreach ($name in @('plain.luac','bom.luac','shebang.luac','bom-shebang.luac','named.luac')) {
        $arguments = @($name)
        if ($name -eq 'named.luac') { $arguments += @('4','x','y') }
        $c = Invoke-Fixture $ReferenceInterpreter $arguments ($name + '-c')
        $ada = Invoke-Fixture $Interpreter $arguments ($name + '-ada')
        Compare-Output $c $ada $name
    }
    [IO.File]::WriteAllText((Join-Path $directory 'environments.lua'),$environments,$encoding)
    $c = Invoke-Fixture $ReferenceInterpreter @('environments.lua') 'environment-c'
    $ada = Invoke-Fixture $Interpreter @('environments.lua') 'environment-ada'
    Compare-Output $c $ada 'first-upvalue environments'
    foreach ($strip in @($false,$true)) {
        $name = 'ada-dump-' + $strip.ToString().ToLowerInvariant()
        $source = $dump.Replace('ARG_STRIP',$strip.ToString().ToLowerInvariant())
        [IO.File]::WriteAllText((Join-Path $directory ($name + '.lua')),$source,$encoding)
        $encoded = Invoke-Fixture $Interpreter @($name + '.lua') $name
        $hex = [IO.File]::ReadAllText($encoded.stdout_path).Trim()
        if ($hex -cnotmatch '^[0-9a-f]+$' -or $hex.Length -lt 80 -or
            $hex.Length % 2 -ne 0 -or -not $hex.StartsWith('1b4c75615500')) {
            throw "Ada string.dump did not return one native chunk hex line: $name"
        }
        [IO.File]::WriteAllBytes((Join-Path $directory ($name + '.luac')),
            [Convert]::FromHexString($hex))
        [IO.File]::WriteAllText((Join-Path $directory 'expected.lua'),
            'global <const> *;print("ADA_BINARY",17)',$encoding)
        $expected = Invoke-Fixture $ReferenceInterpreter @('expected.lua') ($name + '-expected')
        $c = Invoke-Fixture $ReferenceInterpreter @($name + '.luac') ($name + '-c-load')
        Compare-Output $expected $c ($name + ' C load')
        $ada = Invoke-Fixture $Interpreter @($name + '.luac') ($name + '-ada-load')
        Compare-Output $expected $ada ($name + ' Ada load')
    }
    Write-Output "PASS: $($cases.Count) binary CLI C/Ada file/dump/environment comparisons"
}
finally {
    $report=[ordered]@{schema_version=1;reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';
        configuration=$Configuration;interpreter=$Interpreter;reference=$ReferenceInterpreter;
        cases=$cases.ToArray();processes=$processes.ToArray()}
    [IO.File]::WriteAllText((Join-Path $directory 'report.json'),
        (ConvertTo-Json -InputObject $report -Depth 12)+"`n",$encoding)
}
