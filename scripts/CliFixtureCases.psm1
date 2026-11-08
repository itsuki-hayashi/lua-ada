Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-CliCaseDefinitions {
    param([Parameter(Mandatory)][string]$DefaultPackagePath,
          [Parameter(Mandatory)][string]$DefaultPackageCPath,
          [ValidateSet('windows','linux','macos')][string]$Platform,
          [ValidateSet('full','native','prompt')][string]$Mode='full')
    $newline=if($Platform -ceq 'windows'){"`r`n"}else{"`n"}
    $banner='Lua 5.5.1  Copyright (C) 1994-2026 Lua.org, PUC-Rio'
    # These are the original CLI operation contracts, shared by observation
    # and replay. Host setup is never evaluated as an unselected Lua script.
    $cases = @(
        # Lua narrows lua_Integer to the native C int before process exit.
        # Windows exposes the signed status; POSIX reports its lowest byte.
        @{ Title = 'negative process exit retains native status';
           ExitCode = $(if (($Platform -ceq 'windows')) { -1 } else { 255 });
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
           Output = ('./cli_env/?.lua;'+$DefaultPackagePath) },
        @{ Title = 'LUA_PATH only separators selects the complete default';
           Env = @{ LUA_PATH = ';;' };Args = @('-e','io.write(package.path)');
           Output = $DefaultPackagePath },
        @{ Title = 'LUA_PATH expands only the first double separator';
           Env = @{ LUA_PATH = 'before;;after;;literal' };Args = @('-e','io.write(package.path)');
           Output = ('before;'+$DefaultPackagePath+';after;;literal') },
        @{ Title = 'LUA_PATH leading separator preserves the remaining suffix';
           Env = @{ LUA_PATH = ';;after;;literal' };Args = @('-e','io.write(package.path)');
           Output = ($DefaultPackagePath+';after;;literal') },
        @{ Title = 'LUA_CPATH only separators selects the complete default';
           Env = @{ LUA_CPATH = ';;' };Args = @('-e','io.write(package.cpath)');
           Output = $DefaultPackageCPath },
        @{ Title = 'LUA_CPATH expands only the first double separator';
           Env = @{ LUA_CPATH = 'before;;after;;literal' };Args = @('-e','io.write(package.cpath)');
           Output = ('before;'+$DefaultPackageCPath+';after;;literal') },
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
    $promptInput=" --`na = 2`n"
    $promptSetup="assert(loadfile('prompt-controls.lua'))"
    $promptCases=@(
        @{Title='REPL resolves a custom primary prompt';Args=@("-e_PROMPT='alo'",'-i');
          Input=$promptInput;Output=($banner+$newline+'aloaloalo'+$newline)},
        @{Title='REPL resolves a custom continuation prompt';
          Args=@("-e_PROMPT='P:';_PROMPT2='C:'",'-i');Input="x={`n1}`n#x`n";
          Output=($banner+$newline+'P:C:P:1'+$newline+'P:'+$newline)},
        @{Title='REPL accepts empty primary and continuation prompts';
          Args=@("-e_PROMPT='' _PROMPT2=''",'-i');
          Input="(6*2-6) -- ===`na =`n10`nprint(a)`na";
          Output=($banner+$newline+'6'+$newline+'10'+$newline+'10'+$newline+$newline)},
        @{Title='REPL converts numeric prompt values';Args=@('-e',"$promptSetup('number')",'-i');
          Input=$promptInput;Output=($banner+$newline+'17.017.017.0'+$newline)},
        @{Title='REPL converts boolean prompt values';Args=@('-e',"$promptSetup('boolean')",'-i');
          Input=$promptInput;Output=($banner+$newline+'falsefalsefalse'+$newline)},
        @{Title='REPL truncates rendered prompt at NUL';Args=@('-e',"$promptSetup('embedded-nul')",'-i');
          Input=$promptInput;Output=($banner+$newline+'PPP'+$newline)},
        @{Title='REPL ignores replaced global tostring';Args=@('-e',"$promptSetup('global-tostring')",'-i');
          Input=$promptInput;Output=($banner+$newline+'373737'+$newline)},
        @{Title='REPL resolves dynamic tostring on every prompt';Args=@('-e',"$promptSetup('dynamic-tostring')",'-i');
          Input=$promptInput;Output=($banner+$newline+'XXXXXXXXX'+$newline)},
        @{Title='REPL tostring sees the actual anonymous C frame';Args=@('-e',"$promptSetup('tostring-frame')",'-i');
          Input=$promptInput;Output=($banner+$newline+'frameframeframe'+$newline)},
        @{Title='REPL global handler sees the actual anonymous C frame';Args=@('-e',"$promptSetup('index-frame')",'-i');
          Input=$promptInput;Output=($banner+$newline+'frameframeframe'+$newline)},
        @{Title='REPL invalid tostring terminates without reading input';
          Args=@('-e',"$promptSetup('bad-tostring')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=("'__tostring' must return a string"+$newline);
          Output=($banner+$newline)},
        @{Title='REPL prompt error terminates with raw message';
          Args=@('-e',"$promptSetup('error-tostring')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=('prompt-broken'+$newline);Output=($banner+$newline)},
        @{Title='REPL prompt table error uses raw report fallback';
          Args=@('-e',"$promptSetup('error-table')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=('(error message not a string)'+$newline);
          Output=($banner+$newline)},
        @{Title='REPL prompt boolean error uses raw report fallback';
          Args=@('-e',"$promptSetup('error-boolean')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=('(error message not a string)'+$newline);
          Output=($banner+$newline)},
        @{Title='REPL prompt NUL error displays only its C prefix';
          Args=@('-e',"$promptSetup('error-nul')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=('prefix'+$newline);Output=($banner+$newline)},
        @{Title='REPL global lookup error terminates with raw message';
          Args=@('-e',"$promptSetup('index-error')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=('index-broken'+$newline);Output=($banner+$newline)},
        @{Title='REPL prompt yield is rejected';
          Args=@('-e',"$promptSetup('yield-tostring')",'-i');Input="error('input ran')`n";
          ExitCode=1;StderrExact=('attempt to yield from outside a coroutine'+$newline);
          Output=($banner+$newline)},
        @{Title='REPL prompt typed exit without close retains status';
          Args=@('-e',"$promptSetup('exit-no-close')",'-i');Input="error('input ran')`n";
          ExitCode=37;Output=($banner+$newline)},
        @{Title='REPL prompt typed exit with close retains status';
          Args=@('-e',"$promptSetup('exit-close')",'-i');Input="error('input ran')`n";
          ExitCode=37;Output=($banner+$newline)}
    )
    $cases+=@($promptCases)
    $nativeTitles+=@($promptCases.Title)
    # These exact prompt callbacks terminate before the REPL reads its poison
    # input. Preserve attempted delivery and any early pipe close separately;
    # the output/exit/error contract still proves that the input never ran.
    foreach($case in $promptCases){
        if($case.ContainsKey('ExitCode')){$case['InputMayCloseEarly']=$true}
    }
    
    $selected=@($cases|Where-Object{
        $Mode -ceq 'full' -or ($Mode -ceq 'native' -and $_.Title -cin $nativeTitles) -or
        ($Mode -ceq 'prompt' -and $_.Title -cin $promptCases.Title)
    })
    return @{cases=$selected;prompt_titles=@($promptCases.Title)}
}

Export-ModuleMember -Function Get-CliCaseDefinitions
