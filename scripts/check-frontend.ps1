param([string] $Probe, [string] $OpcodeProbe)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$suffix = if ($IsWindows) { '.exe' } else { '' }
$utf8 = [Text.UTF8Encoding]::new($false)
function Invoke-Checked {
    param([string] $Command, [string[]] $Arguments)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Command
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timeout = if ($Command -eq 'gprbuild') { 120000 } else { 30000 }
        if (-not $process.WaitForExit($timeout)) {
            $process.Kill($true)
            throw "PROCESS TIMEOUT: $Command"
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "PROCESS FAILURE: $Command exited $($process.ExitCode): $errors"
        }
        if ($output.Length -eq 0) { return @() }
        return $output.TrimEnd([char[]]([string][char]13 + [char]10)) -split '\r?\n'
    }
    finally { $process.Dispose() }
}
function Compare-Records {
    param([string[]] $Expected, [string[]] $Actual, [string] $Name)
    if ($Expected.Count -ne $Actual.Count) {
        throw "$Name record count: C=$($Expected.Count) Ada=$($Actual.Count)"
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Expected[$index] -cne $Actual[$index]) {
            throw "$Name record $index : C=$($Expected[$index]) Ada=$($Actual[$index])"
        }
    }
    Write-Output "PASS: $Name ($($Expected.Count) records)"
}
try {
    Set-Location $projectRoot
    $pin = (& git -C references/lua rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or
        $pin -ne '7579fc9d7ed90240487251dfb69168f8e64e9294') {
        throw 'Frontend oracle requires the pinned Lua 5.5.1 checkout'
    }
    if (-not $Probe) {
        $Probe = Join-Path $projectRoot "tests/bin/static/lexer_probe$suffix"
    }
    if (-not $OpcodeProbe) {
        $OpcodeProbe = Join-Path $projectRoot "tests/bin/static/lua-opcode_probe$suffix"
    }
    foreach ($project in @('frontend_oracle', 'opcode_oracle')) {
        Invoke-Checked gprbuild @('-P', "experiments/frontend/$project.gpr")
    }
    $oracle = Join-Path $projectRoot "build/frontend/frontend_oracle$suffix"
    $opcodeOracle = Join-Path $projectRoot "build/frontend/opcode_oracle$suffix"
    Compare-Records (Invoke-Checked $opcodeOracle @()) (Invoke-Checked $OpcodeProbe @()) '85 opcodes and 4096 words'

    # Arbitrary bytes are independent of grammar. Malformed literals and
    # unmatched bytes are expected cases, never process-level failures.
    $random = [Random]::new(551)
    $cases = [Collections.Generic.List[string]]::new()
    for ($trial = 0; $trial -lt 10000; $trial++) {
        $bytes = [byte[]]::new($trial % 65)
        $random.NextBytes($bytes)
        $cases.Add([Convert]::ToHexString($bytes))
    }
    $path = Join-Path $projectRoot 'reports/frontend-bytes.txt'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllLines($path, $cases, $utf8)
    Compare-Records (Invoke-Checked $oracle @('batch', $path)) (Invoke-Checked $Probe @('--batch', $path)) '10000 byte lexer cases'

    # Enough distinct interned names to trigger C collections before a
    # malformed string forces diagnostic construction. The source label must
    # remain rooted throughout, not just while its short string is cached.
    $gcSource = ((1..10000 | ForEach-Object { "name$_" }) -join ' ') + ' "\q"'
    $gcPath = Join-Path $projectRoot 'reports/frontend-lexer-gc.lua'
    [IO.File]::WriteAllText($gcPath, $gcSource, $utf8)
    Compare-Records (Invoke-Checked $oracle @('lex', $gcPath)) (Invoke-Checked $Probe @($gcPath)) 'lexer diagnostic after allocation pressure'

    # Each template protects distinct grammar/resolution machinery. Mutations
    # are classified by the C parser rather than assumed to be invalid.
    $templates = @(
        'local x = {0}; return x, -x^2',
        'local x<const> = {0}; return function(y) return x+y end',
        'local function f(n) if n == 0 then return {0} end return f(n-1) end',
        'for i=1,{0},2 do if i>3 then break end end',
        'for k,v in next,t do t[k]=v end',
        'repeat local x = {0} until x>0',
        'goto done; local x = {0}; ::done::; ::last::',
        'local x<close> = nil; return {0}',
        'global<const> value; return value, {0}',
        'local global = {0}; local t = {{global=global}}; return t.global',
        'return function(...args) args[1]={0}; return args, ... end',
        'do local x = {0}; local function f() return x end end'
    )
    $sources = [Collections.Generic.List[string]]::new()
    for ($trial = 0; $trial -lt 2000; $trial++) {
        $sources.Add(($templates[$trial % $templates.Count] -f ($trial + 1)))
    }
    $valid = $sources.ToArray()
    for ($trial = 0; $trial -lt 2000; $trial++) {
        $source = $valid[$trial]
        $at = $random.Next($source.Length)
        switch ($trial % 4) {
            0 { $source = $source.Remove($at, 1) }
            1 { $source = $source.Insert($at, '@') }
            2 { $source = $source.Insert($at, [string][char]10) }
            3 { $source = $source.Substring(0, $at) }
        }
        $sources.Add($source)
    }
    $encoded = @($sources | ForEach-Object {
        [Convert]::ToHexString($utf8.GetBytes($_))
    })
    $path = Join-Path $projectRoot 'reports/frontend-grammar.txt'
    [IO.File]::WriteAllLines($path, $encoded, $utf8)
    $expected = @(Invoke-Checked $oracle @('parse-batch', $path))
    $actual = @(Invoke-Checked $Probe @('--parse-batch', $path))
    for ($trial = 0; $trial -lt 2000; $trial++) {
        if ($expected[2 * $trial] -ne 'ACCEPT') {
            throw "Invalid generated grammar case $trial"
        }
    }
    Compare-Records $expected $actual '2000 grammar and 2000 mutations'
    $count = 0
    foreach ($file in Get-ChildItem references/lua/testes/*.lua) {
        Compare-Records (Invoke-Checked $oracle @('lex', $file.FullName)) (Invoke-Checked $Probe @($file.FullName)) "lex $($file.Name)"
        Compare-Records (Invoke-Checked $oracle @('parse', $file.FullName)) (Invoke-Checked $Probe @('--parse', $file.FullName)) "parse $($file.Name)"
        $count++
    }
    if ($count -ne 34) { throw "Expected 34 unchanged upstream files, found $count" }
    Write-Output 'PASS: pinned frontend/opcode campaign; no Lua source executed'
}
finally {
    Set-Location $originalLocation
}
