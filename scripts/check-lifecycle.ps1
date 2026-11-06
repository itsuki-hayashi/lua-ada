param(
    [Parameter(Mandatory)]
    [string] $Interpreter,
    [string] $Oracle = '',
    [ValidateRange(1, 900)]
    [int] $TimeoutSeconds = 900,
    [long] $MemoryLimitBytes = 2147483648
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$suffix = if ($IsWindows) { '.exe' } else { '' }
$pin = '7579fc9d7ed90240487251dfb69168f8e64e9294'
$fixtures = @('goto.lua', 'coroutine.lua')
$primary = $fixtures
$utf8 = [Text.UTF8Encoding]::new($false)

function Invoke-Interpreter {
    param([string] $Executable, [string[]] $Arguments, [string] $Directory)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # Ambient Lua initialization must not add globals, handlers, or output
    # before the explicit test prelude. Each child receives a clean loader
    # environment; the user's actual process environment remains untouched.
    foreach ($name in @('LUA_INIT', 'LUA_INIT_5_5', 'LUA_PATH',
                       'LUA_PATH_5_5', 'LUA_CPATH', 'LUA_CPATH_5_5')) {
        [void]$start.Environment.Remove($name)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $outBuffer = [IO.MemoryStream]::new()
    $errBuffer = [IO.MemoryStream]::new()
    try {
        [void]$process.Start()
        # Capture byte streams before waiting so a full pipe cannot deadlock.
        # Decoding is deliberately reserved for failure diagnostics below.
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync($outBuffer)
        $stderr = $process.StandardError.BaseStream.CopyToAsync($errBuffer)
        # WorkingSet64 is sampled resident process memory, not Lua's
        # managed allocator accounting and not a promise about peak allocation.
        # Both pipes drain asynchronously while the watchdog polls the child.
        $clock = [Diagnostics.Stopwatch]::StartNew()
        [long] $peakSampledResident = 0
        while (-not $process.WaitForExit(50)) {
            $process.Refresh()
            $peakSampledResident = [Math]::Max(
                $peakSampledResident, $process.WorkingSet64)
            if ($peakSampledResident -gt $MemoryLimitBytes -or
                $clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                $process.Kill($true)
                $process.WaitForExit()
                $reason = if ($peakSampledResident -gt $MemoryLimitBytes) {
                    'PROCESS MEMORY WATCHDOG'
                } else { 'PROCESS TIMEOUT' }
                throw ($reason + ': ' + $Executable)
            }
        }
        [void]$stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        # PowerShell unwraps empty arrays produced by method expressions.
        # Typed locals retain a real zero-length byte[] for empty stderr.
        [byte[]] $capturedOut = $outBuffer.ToArray()
        [byte[]] $capturedErr = $errBuffer.ToArray()
        return @{
            Code = $process.ExitCode
            Out = $capturedOut
            Err = $capturedErr
            SampledResidentBytes = $peakSampledResident
        }
    }
    finally {
        $process.Dispose()
        $outBuffer.Dispose()
        $errBuffer.Dispose()
    }
}

function Require-Success {
    param([hashtable] $Result, [string] $Label, [string] $Marker)
    if ($Result.Code -ne 0 -or $Result.Err.Length -ne 0) {
        $message = $utf8.GetString($Result.Err)
        throw "$Label failed (exit $($Result.Code)): $message"
    }
    # The marker protects against an accidental successful early return.
    # Complete equality still compares every preceding byte independently.
    $tail = [Text.Encoding]::ASCII.GetBytes($Marker + [Environment]::NewLine)
    if ($Result.Out.Length -lt $tail.Length) { throw "$Label lacks success marker" }
    $offset = $Result.Out.Length - $tail.Length
    for ($index = 0; $index -lt $tail.Length; $index++) {
        if ($Result.Out[$offset + $index] -ne $tail[$index]) {
            throw "$Label lacks final $Marker marker"
        }
    }
}

try {
    Set-Location $projectRoot
    $revision = (& git -C references/lua rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $revision -ne $pin) {
        throw 'Upstream acceptance requires the pinned Lua 5.5.1 checkout'
    }
    & git -C references/lua diff --exit-code -- @($fixtures | ForEach-Object { "testes/$_" })
    if ($LASTEXITCODE -ne 0) { throw 'Selected upstream files have local changes' }
    $Interpreter = (Resolve-Path -LiteralPath $Interpreter).Path
    if ($Oracle -eq '') {
        & alr exec -- gprbuild -P experiments/abi/oracle.gpr
        if ($LASTEXITCODE -ne 0) { throw 'C reference interpreter build failed' }
        $Oracle = Join-Path $projectRoot "build/oracle/bin/lua$suffix"
    }
    $Oracle = (Resolve-Path -LiteralPath $Oracle).Path
    $runRoot = Join-Path $projectRoot ('reports/lifecycle/' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($runRoot) | Out-Null
    $records = [Collections.Generic.List[object]]::new()
    foreach ($name in $primary) {
        # Each file receives fresh processes and a disposable directory.
        # Neither interpreter executes from the reference tree.
        $directory = Join-Path $runRoot ([IO.Path]::GetFileNameWithoutExtension($name))
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        foreach ($fixture in $fixtures) {
            $source = Join-Path $projectRoot "references/lua/testes/$fixture"
            $destination = Join-Path $directory $fixture
            [IO.File]::Copy($source, $destination)
            if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
                throw "Fixture copy changed bytes: $fixture"
            }
        }
        $expected = Invoke-Interpreter -Executable $Oracle -Directory $directory -Arguments @(
            '-e', "assert(rawget(_G, 'T') == nil); package.path = './?.lua;./?/init.lua'", $name)
        $actual = Invoke-Interpreter -Executable $Interpreter -Directory $directory -Arguments @(
            '-e', "assert(rawget(_G, 'T') == nil); package.path = './?.lua;./?/init.lua'", $name)
        [IO.File]::WriteAllBytes((Join-Path $directory 'c.stdout'), $expected.Out)
        [IO.File]::WriteAllBytes((Join-Path $directory 'c.stderr'), $expected.Err)
        [IO.File]::WriteAllBytes((Join-Path $directory 'ada.stdout'), $actual.Out)
        [IO.File]::WriteAllBytes((Join-Path $directory 'ada.stderr'), $actual.Err)
        $marker = 'OK'
        Require-Success -Result $expected -Label "C $name" -Marker $marker
        Require-Success -Result $actual -Label "Ada $name" -Marker $marker
        if ([Convert]::ToBase64String($expected.Out) -cne
            [Convert]::ToBase64String($actual.Out)) {
            throw "RAW OUTPUT MISMATCH: $name (evidence retained in $directory)"
        }
        # Exactly two explicit upstream omission messages are expected.
        # New omission text must fail, never disappear through a skip filter.
        $text = $utf8.GetString($actual.Out)
        $omission = ' >>> testC not active: skipping coroutine API tests <<<'
        $count = ([regex]::Matches($text, [regex]::Escape($omission))).Count
        $expectedCount = if ($name -eq 'coroutine.lua') { 2 } else { 0 }
        if ($count -ne $expectedCount) {
            throw "Unexpected upstream omission count: $name ($count)"
        }
        $unexpected = @($text -split "
" | Where-Object {
            $_ -match '(?i)skip' -and $_.TrimEnd() -cne $omission
        })
        if ($unexpected.Count -ne 0) { throw 'Unexpected upstream skip output' }
        $records.Add(@{ File=$name; Revision=$pin; Policy='Lua_Compatible';
            MemoryLimitBytes=$MemoryLimitBytes;
            MemoryMeaning='50ms sampled WorkingSet64 resident process bytes';
            CResidentBytes=$expected.SampledResidentBytes;
            AdaResidentBytes=$actual.SampledResidentBytes;
            TimeoutSeconds=$TimeoutSeconds; Exit=$actual.Code; Mode='standalone';
            Flags=@(); T='absent'; Result='pass' })
        Write-Output "UPSTREAM PASS: $name (compatible policy; timeout=${TimeoutSeconds}s)"
    }
    [IO.File]::WriteAllText((Join-Path $runRoot 'results.json'),
        (ConvertTo-Json -InputObject @($records) -Depth 4), $utf8)
    Write-Output 'PASS: two unchanged files; coroutine default configuration with documented T-absent omissions'
}
finally { Set-Location $originalLocation }
exit 0
