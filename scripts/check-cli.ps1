param(
    [Parameter(Mandatory)]
    [string] $Interpreter
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$executable = (Resolve-Path -LiteralPath $Interpreter).Path
$fixtureRoot = Join-Path $projectRoot 'reports/cli-fixtures'
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$newline = [Environment]::NewLine

# Every fixture is authored here rather than copied from upstream. File
# preamble handling is a loader behavior, distinct from source evaluation.
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'arguments.lua'),
    'print(arg[1],arg[2]); print(...)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot '-script.lua'), 'print(42)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'empty.lua'), '', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'shebang.lua'),
    "#!/usr/bin/env lua`nprint(42)", $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'bom.lua'),
    "#!/usr/bin/env lua`nprint(42)", [Text.UTF8Encoding]::new($true))

function Invoke-Case {
    param([hashtable] $Case)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executable
    $start.WorkingDirectory = $fixtureRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.StandardInputEncoding = $utf8
    foreach ($argument in $Case.Args) { $start.ArgumentList.Add($argument) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($Case.ContainsKey('Input')) { $process.StandardInput.Write($Case.Input) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw "CLI timed out: $($Case.Title)"
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        if ($Case.Fail) {
            if ($process.ExitCode -eq 0 -or
                -not $errorOutput.Contains($Case.Error)) {
                throw "Expected CLI failure: $($Case.Title): $errorOutput"
            }
        }
        elseif ($process.ExitCode -ne 0 -or $errorOutput -ne '') {
            throw "CLI failed: $($Case.Title): $errorOutput"
        }
        if ($Case.ContainsKey('Output') -and $output -cne $Case.Output) {
            throw "CLI output mismatch: $($Case.Title): <$output>"
        }
        if ($Case.ContainsKey('Contains') -and -not $output.Contains($Case.Contains)) {
            throw "Missing CLI output: $($Case.Title): <$output>"
        }
        Write-Output "CLI PASS: $($Case.Title)"
    }
    finally { $process.Dispose() }
}

$cases = @(
    # No input is deliberately batch usage, rather than an implicit REPL.
    @{ Title = 'no input displays usage'; Args = @(); Contains = 'Usage:' },
    @{ Title = 'explicit help'; Args = @('--help'); Contains = 'Usage:' },
    @{ Title = 'version'; Args = @('--version');
       Output = "Lua Ada 0.1.0-dev (target 5.5.1)$newline" },
    @{ Title = 'single snippet'; Args = @('-e', 'print(42)'); Output = "42$newline" },
    @{ Title = 'attached snippet'; Args = @('-eprint(42)'); Output = "42$newline" },
    # The second chunk observes the same session globals as the first.
    @{ Title = 'repeated snippets'; Args = @('-e', 'answer=40', '-e', 'print(answer+2)');
       Output = "42$newline" },
    @{ Title = 'explicit stdin'; Args = @('-'); Input = "print(42)`n";
       Output = "42$newline" },
    # Options appearing after the script name are ordinary script arguments.
    @{ Title = 'script arguments and varargs'; Args = @('arguments.lua', 'first', '-e');
       Output = "first`t-e${newline}first`t-e$newline" },
    @{ Title = 'snippets see negative argument indices';
       Args = @('-e', 'assert(arg[-2]=="-e")', 'arguments.lua', 'first', 'second');
       Output = "first`tsecond${newline}first`tsecond$newline" },
    @{ Title = 'option terminator'; Args = @('--', '-script.lua'); Output = "42$newline" },
    @{ Title = 'empty file'; Args = @('empty.lua'); Output = '' },
    @{ Title = 'file shebang'; Args = @('shebang.lua'); Output = "42$newline" },
    @{ Title = 'BOM and shebang'; Args = @('bom.lua'); Output = "42$newline" },
    # Error classes have process-level contracts as well as Ada API tests.
    @{ Title = 'syntax error'; Args = @('-e', 'local ='); Fail = $true;
       Error = 'expected'; Output = '' },
    @{ Title = 'runtime error'; Args = @('-e', "error('expected',0)"); Fail = $true;
       Error = 'expected'; Output = '' },
    @{ Title = 'output before runtime error'; Args = @('-e', "print(42); error('x',0)");
       Fail = $true; Error = 'x'; Output = "42$newline" },
    @{ Title = 'missing snippet argument'; Args = @('-e'); Fail = $true;
       Error = '-e requires'; Output = '' },
    @{ Title = 'unknown option'; Args = @('--invalid-option'); Fail = $true;
       Error = 'unrecognized option'; Output = '' },
    @{ Title = 'missing file'; Args = @('missing.lua'); Fail = $true;
       Error = 'lua_ada:'; Output = '' }
)
$cases += @(
    # Checking must accept deferred grammar and suppress every Lua side effect.
    @{ Title = 'check snippet suppresses output';
       Args = @('--check', '-e', 'print(42)'); Output = '' },
    @{ Title = 'check valid deferred syntax';
       Args = @('--check', '-e', 'local x<close>; goto done; ::done::'); Output = '' },
    @{ Title = 'check repeated independent snippets';
       Args = @('--check', '-e', 'global x', '-e', 'print(y)'); Output = '' },
    @{ Title = 'check explicit stdin'; Args = @('--check', '-');
       Input = 'print(42)'; Output = '' },
    @{ Title = 'check file ignores script arguments';
       Args = @('--check', 'arguments.lua', '--invalid-option'); Output = '' },
    @{ Title = 'check option terminator';
       Args = @('--check', '--', '-script.lua'); Output = '' },
    @{ Title = 'check file preamble';
       Args = @('--check', 'bom.lua'); Output = '' },
    @{ Title = 'check syntax failure'; Args = @('--check', '-e', 'local =');
       Fail = $true; Error = 'expected'; Output = '' },
    @{ Title = 'check stops before later input';
       Args = @('--check', '-e', 'local =', 'missing.lua');
       Fail = $true; Error = 'expected'; Output = '' },
    @{ Title = 'check no input'; Args = @('--check'); Contains = 'Usage:' },
    @{ Title = 'execute deferred syntax before effects';
       Args = @('-e', 'print(42); ::done::'); Fail = $true;
       Error = 'unsupported feature'; Output = '' }
)
foreach ($case in $cases) { Invoke-Case -Case $case }
exit 0
