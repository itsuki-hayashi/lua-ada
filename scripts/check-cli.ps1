param(
    [Parameter(Mandatory)]
    [string] $Interpreter,
    [switch] $NativeProtocol
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$executable = (Resolve-Path -LiteralPath $Interpreter).Path
$fixtureRoot = Join-Path $projectRoot ('reports/cli-fixtures/'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$newline = [Environment]::NewLine

# Every fixture is authored here rather than copied from upstream. File
# preamble handling is a loader behavior, distinct from source evaluation.
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'arguments.lua'),
    'print(arg[1],arg[2]); print(...)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot '-script.lua'), 'print(42)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'empty.lua'), '', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'source-name.lua'),
    'local d=debug.getinfo(1,"S"); print(d.source,d.short_src)', $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'shebang.lua'),
    "#!/usr/bin/env lua`nprint(42)", $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'bom.lua'),
    "#!/usr/bin/env lua`nprint(42)", [Text.UTF8Encoding]::new($true))

[IO.File]::WriteAllText((Join-Path $fixtureRoot 'cli_lib.lua'),
    "return { tag = 'lib' }", $utf8)
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'cli_init.lua'),
    "init_ran = 'file'", $utf8)
$banner = 'Lua 5.5.1  Copyright (C) 1994-2026 Lua.org, PUC-Rio'

[IO.File]::WriteAllText((Join-Path $fixtureRoot 'large-source.lua'),
    ('--[[' + ('a' * 1000001) + ']] print(42)'), $utf8)

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
    # Start from a clean Lua environment so the host's own variables never
    # leak into a case; each case then sets exactly what it exercises.
    foreach ($name in 'LUA_INIT', 'LUA_INIT_5_5', 'LUA_PATH', 'LUA_PATH_5_5',
             'LUA_CPATH', 'LUA_CPATH_5_5') {
        [void]$start.Environment.Remove($name)
    }
    if ($Case.ContainsKey('Env')) {
        foreach ($name in $Case.Env.Keys) {
            $start.Environment[$name] = $Case.Env[$name]
        }
    }

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
        if ($Case.ContainsKey('ExitCode')) {
            if ($process.ExitCode -ne $Case.ExitCode -or $errorOutput -ne '') {
                throw "CLI typed exit mismatch: $($Case.Title): $errorOutput"
            }
        }
        elseif ($Case.ContainsKey('StderrExact')) {
            if ($process.ExitCode -ne 0 -or $errorOutput -cne $Case.StderrExact) {
                throw "CLI stderr differs: $($Case.Title): <$errorOutput>"
            }
        }
        elseif ($Case.ContainsKey('Stderr')) {
            # Interactive errors are reported but do not fail the process.
            if ($process.ExitCode -ne 0 -or
                -not $errorOutput.Contains($Case.Stderr)) {
                throw "Expected CLI stderr with success: $($Case.Title): $errorOutput"
            }
        }
        elseif ($Case.Fail) {
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
        if ($Case.ContainsKey('CaptureOutput')) { & $Case.CaptureOutput $output }
        Write-Output "CLI PASS: $($Case.Title)"
    }
    finally { $process.Dispose() }
}

# The expansion operation inserts the selected executable's actual clean
# default. Its platform/executable directories come from pinned luaconf.h;
# the old minimal './?.lua' path is no longer its first template. Capture
# defaults in separate -E children, retaining every byte for the environment
# cases below. NativeProtocol executes these same expansion regressions.
Invoke-Case @{Title='capture clean package.path default';Args=@('-E','-e','io.write(package.path)');
    CaptureOutput={param($text) if([string]::IsNullOrEmpty($text)){throw 'Empty clean package.path'};$script:DefaultPackagePath=$text}}
Invoke-Case @{Title='capture clean package.cpath default';Args=@('-E','-e','io.write(package.cpath)');
    CaptureOutput={param($text) if([string]::IsNullOrEmpty($text)){throw 'Empty clean package.cpath'};$script:DefaultPackageCPath=$text}}

$cases = @(
    # Lua narrows lua_Integer to the native C int before process exit.
    # Windows exposes the signed status; POSIX reports its lowest byte.
    @{ Title = 'negative process exit retains native status';
       ExitCode = $(if ($IsWindows) { -1 } else { 255 });
       Args = @('-e', 'os.exit(-1,false)'); Output = '' },
    @{ Title = 'oversized process exit retains low C int bits'; ExitCode = 0;
       Args = @('-e', 'os.exit(4294967296,false); error("unreachable")'); Output = '' },
    # The native unbuffered call ignores buffer capacity. A checked Ada
    # range conversion must not reject the otherwise valid Lua integer.
    @{ Title = 'unbuffered file accepts negative size_t input';
       Args = @('-e', 'local f=assert(io.open("negative-size.tmp","w")); assert(f:setvbuf("no",-1)); assert(f:write("ok")); assert(f:close()); assert(os.remove("negative-size.tmp"))');
       Output = '' },
    @{ Title = 'typed exit without Lua close handlers'; ExitCode = 42;
       Args = @('-e', 'saved=setmetatable({}, {__gc=function() print("finalized") end}); local x <close> = setmetatable({}, {__close=function() print("closed") end}); os.exit(42,false)', '-e', 'error("unreachable")');
       Output = '' },
    @{ Title = 'typed exit completes Lua close handlers'; ExitCode = 43;
       Args = @('-e', 'saved=setmetatable({}, {__gc=function() print("finalized") end}); local x <close> = setmetatable({}, {__close=function() print("closed") end}); os.exit(43,true)', '-e', 'error("unreachable")');
       Output = "closed${newline}finalized$newline" },
    # A reachable finalizable object must run at explicit CLI state closure,
    # after the chunk marker; physical Ada disposal alone cannot satisfy it.
    @{ Title = 'state close finalizes reachable objects';
       Args = @('-e', 'saved=setmetatable({}, {__gc=function() print("closed") end}); print("done")');
       Output = "done${newline}closed$newline" },
    @{ Title = 'failed snippet closes reachable objects';
       Args = @('-e', 'saved=setmetatable({}, {__gc=function() print("closed") end}); error("expected")');
       Fail = $true; Error = 'expected'; Output = "closed$newline" },
    # Like lua.c, no script and no -e/-v/-i executes redirected stdin; the
    # harness always redirects, so an empty stdin is an empty program.
    @{ Title = 'no input executes empty redirected stdin'; Args = @();
       Output = '' },
    @{ Title = 'implicit redirected stdin'; Args = @();
       Input = "print(42)`n"; Output = "42$newline" },
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
    # Prototype source markers distinguish files/named chunks from snippets.
    # The human-facing short name omits the marker in both file loaders.
    @{ Title = 'file debug source identity'; Args = @('source-name.lua');
       Output = "@source-name.lua`tsource-name.lua$newline" },
    @{ Title = 'dofile debug source identity';
       Args = @('-e', 'dofile("source-name.lua")');
       Output = "@source-name.lua`tsource-name.lua$newline" },
    @{ Title = 'loadfile debug source identity';
       Args = @('-e', 'assert(loadfile("source-name.lua"))()');
       Output = "@source-name.lua`tsource-name.lua$newline" },
    @{ Title = 'command-line debug source identity';
       Args = @('-e', 'local d=debug.getinfo(1,"S"); print(d.source,d.short_src)');
       Output = "=(command line)`t(command line)$newline" },
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
       Error = "'-e' needs argument"; Output = '' },
    @{ Title = 'snippet argument must not be an option';
       Args = @('-e', '-v'); Fail = $true;
       Error = "'-e' needs argument"; Output = '' },
    @{ Title = 'library option needs argument'; Args = @('-l'); Fail = $true;
       Error = "'-l' needs argument"; Output = '' },
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
    @{ Title = 'execute resolved label';
       Args = @('-e', 'print(42); ::done::'); Output = "42$newline" },
    @{ Title = 'compatible instruction policy';
       Args = @('-e', 'local n=0; for i=1,150000 do n=n+1 end; print(n)');
       Output = "150000$newline" },
    @{ Title = 'compatible file source policy';
       Args = @('large-source.lua'); Output = "42$newline" },
    @{ Title = 'compatible stdin source policy'; Args = @('-');
       Input = ('--[[' + ('a' * 1000001) + ']] print(42)');
       Output = "42$newline" },
    @{ Title = 'compatible check source policy';
       Args = @('--check', 'large-source.lua'); Output = '' },
    @{ Title = 'compatible runtime load source policy';
       Args = @('-e', "assert(load('--[['..string.rep('a',1000001)..']] return 42'))(); print(42)");
       Output = "42$newline" }
)
# lua.c option, environment, stdin and REPL behaviors. Each case isolates
# one behavior; the harness clears every LUA_* variable before the case.
$cases += @(
    @{ Title = '-v prints the native banner only'; Args = @('-v');
       Output = "$banner$newline" },
    @{ Title = '--version keeps the project banner'; Args = @('--version');
       Output = "Lua Ada 0.1.0-dev (target 5.5.1)$newline" },
    @{ Title = '-l requires into the module-named global';
       Args = @('-l', 'cli_lib', '-e', 'print(cli_lib.tag)');
       Output = "lib$newline" },
    @{ Title = '-l g=mod requires into an explicit global';
       Args = @('-l', 'alias=cli_lib', '-e', 'print(alias.tag)');
       Output = "lib$newline" },
    @{ Title = '-e and -l run in command-line order';
       Args = @('-e', 'x=1', '-l', 'cli_lib', '-e', 'print(x, cli_lib.tag)');
       Output = "1`tlib$newline" },
    @{ Title = '-l failure stops later actions'; Fail = $true;
       Args = @('-l', 'cli_missing_module', '-e', 'print(1)');
       Error = "module 'cli_missing_module' not found"; Output = '' },
    @{ Title = '-l uses the current global require';
       Args = @('-e', 'require = function(n) return n .. "!" end',
                '-l', 'tag=anything', '-e', 'print(tag)');
       Output = "anything!$newline" },
    @{ Title = '-W is accepted before a snippet';
       Args = @('-W', '-e', 'print(1)'); Output = "1$newline" },
    @{ Title = '-W bypasses overwritten warn';
       Args = @('-e', 'savedwarn=warn; warn=function() error("wrong warn") end',
                '-W', '-e', 'savedwarn("visible")'); Output = '';
       StderrExact = "Lua warning: visible$newline" },
    @{ Title = 'warning initialization bypasses removed warn';
       Env = @{ LUA_INIT = 'savedwarn=warn; warn=nil' };
       Args = @('-W', '-e', 'savedwarn("init override")'); Output = '';
       StderrExact = "Lua warning: init override$newline" },
    @{ Title = 'warning controls preserve action order';
       Args = @('-e', 'warn("@on")', '-W', '-e',
                'warn("visible"); warn("@off"); warn("hidden")'); Output = '';
       StderrExact = "Lua warning: visible$newline" },
    @{ Title = 'warnings default off';
       Args = @('-e', 'warn("hidden"); print(1)'); Output = "1$newline" },
    @{ Title = 'LUA_INIT runs before snippets';
       Env = @{ LUA_INIT = 'init_ran = 1' };
       Args = @('-e', 'print(init_ran)'); Output = "1$newline" },
    @{ Title = 'LUA_INIT warning control resets before actions';
       Env = @{ LUA_INIT = 'warn("@on")' };
       Args = @('-e', 'warn("init-enabled")'); Output = '';
       StderrExact = '' },
    @{ Title = 'LUA_INIT warning uses initial enabled handler';
       Env = @{ LUA_INIT = 'warn("during-init")' };
       Args = @('-e', 'warn("after-init")'); Output = '';
       StderrExact = "Lua warning: during-init$newline" },
    @{ Title = 'LUA_INIT_5_5 takes precedence over LUA_INIT';
       Env = @{ LUA_INIT = 'which = "plain"'; LUA_INIT_5_5 = 'which = "versioned"' };
       Args = @('-e', 'print(which)'); Output = "versioned$newline" },
    @{ Title = 'LUA_INIT @file loads a file';
       Env = @{ LUA_INIT = '@cli_init.lua' };
       Args = @('-e', 'print(init_ran)'); Output = "file$newline" },
    @{ Title = 'LUA_INIT failure is reported'; Fail = $true;
       Env = @{ LUA_INIT = 'error("boom", 0)' };
       Args = @('-e', 'print(1)'); Error = 'boom'; Output = '' },
    @{ Title = '-E ignores LUA_INIT';
       Env = @{ LUA_INIT = 'init_ran = 1' };
       Args = @('-E', '-e', 'print(init_ran)'); Output = "nil$newline" },
    @{ Title = 'LUA_PATH ;; expands to the default path';
       Env = @{ LUA_PATH = './cli_env/?.lua;;' };
       Args = @('-e', 'io.write(package.path)');
       Output = ('./cli_env/?.lua;'+$script:DefaultPackagePath) },
    @{ Title = 'LUA_PATH only separators selects the complete default';
       Env = @{ LUA_PATH = ';;' };Args = @('-e','io.write(package.path)');
       Output = $script:DefaultPackagePath },
    @{ Title = 'LUA_PATH expands only the first double separator';
       Env = @{ LUA_PATH = 'before;;after;;literal' };Args = @('-e','io.write(package.path)');
       Output = ('before;'+$script:DefaultPackagePath+';after;;literal') },
    @{ Title = 'LUA_PATH leading separator preserves the remaining suffix';
       Env = @{ LUA_PATH = ';;after;;literal' };Args = @('-e','io.write(package.path)');
       Output = ($script:DefaultPackagePath+';after;;literal') },
    @{ Title = 'LUA_CPATH only separators selects the complete default';
       Env = @{ LUA_CPATH = ';;' };Args = @('-e','io.write(package.cpath)');
       Output = $script:DefaultPackageCPath },
    @{ Title = 'LUA_CPATH expands only the first double separator';
       Env = @{ LUA_CPATH = 'before;;after;;literal' };Args = @('-e','io.write(package.cpath)');
       Output = ('before;'+$script:DefaultPackageCPath+';after;;literal') },
    @{ Title = 'LUA_PATH_5_5 takes precedence over LUA_PATH';
       Env = @{ LUA_PATH = 'plain'; LUA_PATH_5_5 = 'versioned' };
       Args = @('-e', 'print(package.path)'); Output = "versioned$newline" },
    @{ Title = '-E ignores LUA_PATH';
       Env = @{ LUA_PATH = 'ignored_path' };
       Args = @('-E', '-e', 'print(package.path:find("ignored_path", 1, true))');
       Output = "nil$newline" },
    @{ Title = 'file named - after -- is not stdin'; Fail = $true;
       Args = @('--', '-'); Input = 'print(1)'; Error = 'lua_ada:';
       Output = '' },
    # A raw Ctrl-Z byte in a comment must not truncate redirected stdin.
    @{ Title = 'stdin preserves Ctrl-Z and NUL bytes';
       Args = @('-'); Input = "--$([char]26)$([char]0)`nprint(7)`n";
       Output = "7$newline" },
    @{ Title = 'implicit stdin preserves Ctrl-Z byte'; Args = @();
       Input = "--$([char]26)`nprint(8)`n"; Output = "8$newline" },
    @{ Title = '-i prints banner, prompts and expression results';
       Args = @('-i'); Input = "1+1`nprint('x')`nx=5`nx`n";
       Output = "$banner$newline> 2$newline> x$newline> > 5$newline> $newline" },
    @{ Title = 'REPL prints every result through print';
       Args = @('-i'); Input = "1,2`n";
       Output = "$banner$newline> 1`t2$newline> $newline" },
    @{ Title = 'REPL multiline statement uses continuation prompt';
       Args = @('-i'); Input = "x = {`n1,`n2}`n#x`n";
       Output = "$banner$newline> >> >> > 2$newline> $newline" },
    @{ Title = 'REPL error is reported and the loop continues';
       Args = @('-i'); Input = "error('bad', 0)`nprint('after')`n";
       Stderr = 'bad';
       Output = "$banner$newline> > after$newline> $newline" },
    @{ Title = 'REPL syntax error is reported and the loop continues';
       Args = @('-i'); Input = "x = = 1`nprint('after')`n";
       Stderr = 'stdin:1:';
       Output = "$banner$newline> > after$newline> $newline" },
    @{ Title = 'REPL calls the overwritten global print';
       Args = @('-i');
       Input = "print = function(...) io.write('P:', ..., '\n') end`n1`n";
       Output = "$banner$newline> > P:1$newline> $newline" },
    @{ Title = 'REPL resolves print through the environment handler';
       Args = @('-i');
       Input = "local p=print; print=nil; setmetatable(_G,{__index=function(_,k) if k=='print' then return p end end})`n42`n";
       Stderr = 'warning: locals do not survive';
       Output = "$banner$newline> > 42$newline> $newline" },
    @{ Title = 'REPL semantic EOF error does not consume next command';
       Args = @('-i'); Input = "goto absent`nprint('after')`n";
       Stderr = "no visible label";
       Output = "$banner$newline> > after$newline> $newline" },
    @{ Title = 'REPL print failure is wrapped and not fatal';
       Args = @('-i');
       Input = "print = function() error('pe', 0) end`n1`nio.write('ok\n')`n";
       Stderr = "error calling 'print' (pe)";
       Output = "$banner$newline> > > ok$newline> $newline" },
    @{ Title = 'REPL with print removed reports and continues';
       Args = @('-i'); Input = "print = nil`n1`n";
       Stderr = "error calling 'print'";
       Output = "$banner$newline> > > $newline" },
    @{ Title = 'REPL typed exit skips later input'; ExitCode = 7;
       Args = @('-i'); Input = "os.exit(7)`nprint('no')`n";
       Output = "$banner$newline> " },
    @{ Title = '-i runs snippets before the loop';
       Args = @('-i', '-e', 'print(1)'); Input = '';
       Output = "$banner${newline}1$newline> $newline" }
)
# The same expected process protocol can be checked against the pinned C
# executable. Project-only switches, project default paths and diagnostic
# prefixes are deliberately outside this focused cross-runtime selection.
$nativeTitles = @(
    '-v prints the native banner only',
    '-l requires into the module-named global',
    '-l g=mod requires into an explicit global',
    '-e and -l run in command-line order',
    '-l failure stops later actions',
    '-l uses the current global require',
    '-W is accepted before a snippet',
    '-W bypasses overwritten warn',
    'warning initialization bypasses removed warn',
    'warning controls preserve action order',
    'warnings default off',
    'LUA_INIT runs before snippets',
    'LUA_INIT warning control resets before actions',
    'LUA_INIT warning uses initial enabled handler',
    'LUA_INIT_5_5 takes precedence over LUA_INIT',
    'LUA_INIT @file loads a file',
    'LUA_INIT failure is reported',
    '-E ignores LUA_INIT',
    'LUA_PATH ;; expands to the default path',
    'LUA_PATH only separators selects the complete default',
    'LUA_PATH expands only the first double separator',
    'LUA_PATH leading separator preserves the remaining suffix',
    'LUA_CPATH only separators selects the complete default',
    'LUA_CPATH expands only the first double separator',
    'LUA_PATH_5_5 takes precedence over LUA_PATH',
    '-E ignores LUA_PATH',
    '-i prints banner, prompts and expression results',
    'REPL prints every result through print',
    'REPL multiline statement uses continuation prompt',
    'REPL error is reported and the loop continues',
    'REPL syntax error is reported and the loop continues',
    'REPL calls the overwritten global print',
    'REPL resolves print through the environment handler',
    'REPL semantic EOF error does not consume next command',
    'REPL print failure is wrapped and not fatal',
    'REPL with print removed reports and continues',
    'REPL typed exit skips later input',
    '-i runs snippets before the loop'
)
foreach ($case in $cases) {
    if (-not $NativeProtocol -or $case.Title -cin $nativeTitles) {
        Invoke-Case -Case $case
    }
}
exit 0
