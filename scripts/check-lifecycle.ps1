param(
    [Parameter(Mandatory)]
    [string] $Interpreter,
    [string] $Oracle = '',
    [ValidateSet('default','upstream-test')]
    [string] $Configuration = 'default',
    [string] $ReferenceLibraryDirectory = '',
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
    param([string] $Executable, [string[]] $Arguments, [string] $Directory,
          [string] $OutputPrefix)
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
    if ($Configuration -ceq 'upstream-test') {
        $start.Environment['MEMLIMIT'] = [string]$MemoryLimitBytes
        $start.Environment['LUA_ADA_CONFORMANCE_ALLOCATOR'] = [string]$MemoryLimitBytes
    }
    if ($ReferenceLibraryDirectory -ne '') {
        foreach ($name in @('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH')) {
            $start.Environment[$name] = $ReferenceLibraryDirectory +
                [IO.Path]::PathSeparator + $start.Environment[$name]
        }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    # Preserve bytes while the child runs. A killed process must retain its
    # actual operation, streams and measurements; a watchdog exception cannot
    # discard the only evidence of the original failing workload.
    $outPath=$OutputPrefix+'.stdout';$errPath=$OutputPrefix+'.stderr'
    $outBuffer = [IO.File]::Create($outPath)
    $errBuffer = [IO.File]::Create($errPath)
    $reason=$null
    $record=@{schema_version=1;kind='lifecycle-process-observation';
        runtime_acceptance=$false;coverage_authority=$false;
        executable=$Executable;executable_sha256=(Get-FileHash $Executable).Hash.ToLowerInvariant();
        arguments=$Arguments;working_directory=$Directory;
        timeout_seconds=$TimeoutSeconds;sampled_resident_limit_bytes=$MemoryLimitBytes;
        started_utc=[DateTime]::UtcNow.ToString('o')}
    try {
        [void]$process.Start()
        $record.process_id=$process.Id
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
                break
            }
        }
        [void]$stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        $outBuffer.Flush();$errBuffer.Flush()
        $outBuffer.Dispose();$errBuffer.Dispose()
        $record.exit_code=$process.ExitCode
        $record.elapsed_milliseconds=$clock.ElapsedMilliseconds
        $record.peak_sampled_resident_bytes=$peakSampledResident
        $record.watchdog_failure=$reason
        foreach($stream in @('stdout','stderr')){
            $path=if($stream -ceq 'stdout'){$outPath}else{$errPath}
            $record[$stream]=@{path=$path;bytes=(Get-Item $path).Length;
                sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
        }
        [IO.File]::WriteAllText($OutputPrefix+'.process.json',
            ($record|ConvertTo-Json -Depth 8).Replace("`r`n","`n")+"`n",$utf8)
        if($null -ne $reason){
            throw ($reason+': '+($Arguments -join ' ')+
                '; sampled resident bytes='+$peakSampledResident+
                '; evidence='+$OutputPrefix+'.process.json')
        }
        # Read only completed captures; empty streams remain real byte arrays.
        [byte[]] $capturedOut = [IO.File]::ReadAllBytes($outPath)
        [byte[]] $capturedErr = [IO.File]::ReadAllBytes($errPath)
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
    & git -C references/lua diff HEAD --exit-code -- @($fixtures | ForEach-Object { "testes/$_" })
    if ($LASTEXITCODE -ne 0) { throw 'Selected upstream files have local changes' }
    $inventory = Get-Content -LiteralPath (
        Join-Path $projectRoot 'tests/conformance/suite.json') -Raw |
        ConvertFrom-Json
    if ($inventory.reference_revision -ne $pin) {
        throw 'Fixture hash inventory revision does not match the oracle'
    }
    $Interpreter = (Resolve-Path -LiteralPath $Interpreter).Path
    if ($Oracle -eq '') {
        if ($Configuration -ceq 'upstream-test') {
            throw 'Instrumented lifecycle requires an explicit matching C oracle'
        }
        & alr exec -- gprbuild -P experiments/abi/oracle.gpr
        if ($LASTEXITCODE -ne 0) { throw 'C reference interpreter build failed' }
        $Oracle = Join-Path $projectRoot "build/oracle/bin/lua$suffix"
    }
    $Oracle = (Resolve-Path -LiteralPath $Oracle).Path
    $runRoot = Join-Path $projectRoot ('reports/lifecycle/' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($runRoot) | Out-Null
    if ($Configuration -ceq 'upstream-test') {
        # Product CLI states intentionally omit the private adapter. These
        # unchanged upstream paths need the real instrumented launchers in
        # both roles, with matching grammar and allocator configuration.
        Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
        foreach ($role in @('ReferenceC','Ada')) {
            $exe = if ($role -ceq 'ReferenceC') { $Oracle } else { $Interpreter }
            $probe = Invoke-Interpreter -Executable $exe -Arguments @('--conformance-config') `
                -Directory $runRoot -OutputPrefix (Join-Path $runRoot ($role+'-configuration'))
            if ($probe.Code -ne 0 -or $probe.Err.Length -ne 0) {
                throw "Instrumented lifecycle configuration probe failed: $role"
            }
            $observed = $utf8.GetString($probe.Out) | ConvertFrom-Json -AsHashtable
            [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration `
                -Target $role -AllocatorLimitBytes $MemoryLimitBytes)
        }
    }
    $records = [Collections.Generic.List[object]]::new()
    foreach ($name in $primary) {
        # Each file receives fresh processes and a disposable directory.
        # Neither interpreter executes from the reference tree.
        $directory = Join-Path $runRoot ([IO.Path]::GetFileNameWithoutExtension($name))
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        foreach ($fixture in $fixtures) {
            $source = Join-Path $projectRoot "references/lua/testes/$fixture"
            $destination = Join-Path $directory $fixture
            $entry = @($inventory.files | Where-Object { $_.path -ceq $fixture })
            if ($entry.Count -ne 1 -or
                (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                $entry[0].sha256) {
                throw "Fixture does not match its pinned source hash: $fixture"
            }
            [IO.File]::Copy($source, $destination)
            if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
                throw "Fixture copy changed bytes: $fixture"
            }
        }
        $setup = if ($Configuration -ceq 'upstream-test') {
            "assert(type(T)=='table' and type(T.testC)=='function'); package.path='./?.lua;./?/init.lua'"
        } else { "assert(rawget(_G, 'T') == nil); package.path = './?.lua;./?/init.lua'" }
        $expected = Invoke-Interpreter -Executable $Oracle -Directory $directory -OutputPrefix (Join-Path $directory 'c') -Arguments @('-e', $setup, $name)
        $actual = Invoke-Interpreter -Executable $Interpreter -Directory $directory -OutputPrefix (Join-Path $directory 'ada') -Arguments @('-e', $setup, $name)
        $marker = 'OK'
        Require-Success -Result $expected -Label "C $name" -Marker $marker
        Require-Success -Result $actual -Label "Ada $name" -Marker $marker
        if ([Convert]::ToBase64String($expected.Out) -cne
            [Convert]::ToBase64String($actual.Out)) {
            throw "RAW OUTPUT MISMATCH: $name (evidence retained in $directory)"
        }
        # Only default coroutine execution permits the two explicit upstream
        # omissions. Instrumented execution permits none; new omission text
        # must fail, never disappear through a skip filter.
        $text = $utf8.GetString($actual.Out)
        $omission = ' >>> testC not active: skipping coroutine API tests <<<'
        $count = ([regex]::Matches($text, [regex]::Escape($omission))).Count
        $expectedCount = if ($Configuration -ceq 'default' -and $name -eq 'coroutine.lua') { 2 } else { 0 }
        if ($count -ne $expectedCount) {
            throw "Unexpected upstream omission count: $name ($count)"
        }
        $unexpected = @($text -split "
" | Where-Object {
            $_ -match '(?i)skip' -and $_.TrimEnd() -cne $omission
        })
        if ($unexpected.Count -ne 0) { throw 'Unexpected upstream skip output' }
        if ($Configuration -ceq 'upstream-test' -and $name -ceq 'coroutine.lua') {
            if ([regex]::Matches($text,'(?m)^testing coroutine API\r?$').Count -ne 2 -or
                [regex]::Matches($text,'(?m)^testing yields inside hooks\r?$').Count -ne 1) {
                throw 'Instrumented coroutine API/hook witnesses are incomplete'
            }
        }
        $records.Add(@{ File=$name; Revision=$pin; Policy='Lua_Compatible';
            MemoryLimitBytes=$MemoryLimitBytes;
            MemoryMeaning='50ms sampled WorkingSet64 resident process bytes';
            CResidentBytes=$expected.SampledResidentBytes;
            AdaResidentBytes=$actual.SampledResidentBytes;
            TimeoutSeconds=$TimeoutSeconds; Exit=$actual.Code; Mode='standalone';
            Flags=@(); Configuration=$Configuration;
            T=$(if($Configuration -ceq 'upstream-test'){'present'}else{'absent'}); Result='pass' })
        Write-Output "UPSTREAM PASS: $name (compatible policy; timeout=${TimeoutSeconds}s)"
    }
    [IO.File]::WriteAllText((Join-Path $runRoot 'results.json'),
        (ConvertTo-Json -InputObject @($records) -Depth 4), $utf8)
    Write-Output "PASS: two unchanged lifecycle files; configuration=$Configuration; instrumented paths require T and zero omissions"
}
finally { Set-Location $originalLocation }
exit 0
