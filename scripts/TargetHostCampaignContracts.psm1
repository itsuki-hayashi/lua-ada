Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# These closed source contracts define actual inputs once for producer and
# replay. They do not certify execution or broaden any source exception.
function Get-TargetHostCampaignCases {
    param([ValidateSet('console-lua','console-c','readline')][string]$Kind,
        [ValidateSet('windows','linux','macos')][string]$Platform)
    if($Kind -ceq 'console-c'){
        return @('host','host-close','callback-close','callback-error'|ForEach-Object{@{name=$_}})
    }
    if($Kind -ceq 'console-lua'){
$ordinary="require('debug').debug();print('AFTER')"
$cases=@(
    @{name='write-and-continue';setup=$ordinary;input="io.stderr:write(1000)`ncont`n"},
    @{name='discard-results';setup=$ordinary;input="return 123,'discard'`ncont`n"},
    @{name='syntax-error-recovery';setup=$ordinary;input="local =`nio.stderr:write('RECOVERED')`ncont`n"},
    @{name='error-object-conversion';setup=$ordinary;input="error(setmetatable({},{__tostring=function()return 'OBJECT ERROR'end}))`nio.stderr:write('RECOVERED')`ncont`n"},
    @{name='command-environment';setup="local console_local=99;_G.console_global=17;require('debug').debug();assert(console_global==18);print('AFTER')";input="assert(console_local==nil);console_global=console_global+1`ncont`n"},
    @{name='eof';setup=$ordinary;input=''},
    @{name='partial-final-command';setup=$ordinary;input="io.stderr:write('E')"},
    @{name='embedded-nul';setup=$ordinary;input="io.stderr:write('N')`0ignored`ncont`n"},
    @{name='fixed-buffer-boundary';setup=$ordinary;input=(('--'+('x'*247))*3)+"`nio.stderr:write('B')`ncont`n"},
    @{name='numeric-error-conversion';setup=$ordinary;input="error(setmetatable({},{__tostring=function()return 17 end}))`ncont`n"},
    @{name='conversion-error-escapes';setup="local ok,e=pcall(require('debug').debug);assert(not ok and e=='CONVERT');print('AFTER')";input="error(setmetatable({},{__tostring=function()error('CONVERT',0)end}))`n"},
    @{name='command-cannot-yield';setup="local c=coroutine.create(require('debug').debug);assert(coroutine.resume(c));assert(coroutine.status(c)=='dead');print('AFTER')";input="coroutine.yield('escape')`ncont`n"},
    @{name='initial-argument-release';setup="_G.watch=setmetatable({},{__mode='v'});require('debug').debug((function()local t={}watch[1]=t;return t end)());assert(watch[1]==nil);print('AFTER')";input="collectgarbage();assert(watch[1]~=nil)`ncollectgarbage();assert(watch[1]==nil)`ncont`n"},
    @{name='binary-error-bytes';setup=$ordinary;input="error(string.char(255,254),0)`ncont`n"}
)
if(($Platform -ceq 'windows')){
    $cases+=@(
        @{name='native-text-crlf';setup=$ordinary;input="io.stderr:write('R')`r`ncont`r`n"},
        @{name='native-text-ctrl-z';setup=$ordinary;input="`u{001a}ignored`n"}
    )
}
        return $cases
    }
$cases=@(
    @{name='basic';input="print(17)`n"},
    @{name='empty-eof';input=''},
    @{name='unterminated-final-line';input='print(19)'},
    @{name='empty-line';input="`nprint(23)`n"},
    @{name='fixed-buffer-boundary';input=('--'+(' '*1100))+"`nprint(29)`n"},
    @{name='embedded-nul';input="print(31)`0print(37)`nprint(41)`n"},
    @{name='multiline';input="function f()`nreturn 43`nend`nprint(f())`n"},
    @{name='dynamic-prompt';input="_PROMPT='Q'`nprint(47)`n"},
    @{name='crlf';input="print(53)`r`nprint(59)`r`n"},
    @{name='invalid-utf8-comment';bytes=([byte[]]@(45,45,255,254,10)+[Text.Encoding]::ASCII.GetBytes("print(61)`n"))},
    @{name='missing-library-warnings-off';input="print(67)`n";library='missing-readline-library-that-does-not-exist'},
    @{name='missing-library-warnings-on';input="print(71)`n";library='missing-readline-library-that-does-not-exist';warnings=$true},
    @{name='ignored-library-override';input="print(73)`n";library='missing-readline-library-that-does-not-exist';ignore=$true;warnings=$true}
)
if(($Platform -ceq 'windows')){$cases+=@{name='native-text-ctrl-z';input="`u{001a}print(79)`n"}}
    return $cases
}

function Get-TargetHostCampaignArguments {
    param([ValidateSet('console-lua','console-c','readline')][string]$Kind,
        [Collections.IDictionary]$Case)
    if($Kind -ceq 'console-lua'){return @('-e',$Case.setup)}
    if($Kind -ceq 'console-c'){return @('--debug-console-'+$Case.name)}
    $arguments=@('-i')
    if($Case.Contains('warnings')){$arguments+='-W'}
    if($Case.Contains('ignore')){$arguments+='-E'}
    return $arguments+@('-e',"_PROMPT='P';_PROMPT2='C'")
}

function Get-TargetHostCampaignInputBytes {
    param([ValidateSet('console-lua','console-c','readline')][string]$Kind,
        [Collections.IDictionary]$Case)
    if($Kind -ceq 'console-c'){
        return ,([Text.Encoding]::UTF8.GetBytes("collectgarbage();assert(watch[1]~=nil)`ncollectgarbage();assert(watch[1]==nil)`ncont`n"))
    }
    if($Case.Contains('bytes')){return ,([byte[]]$Case.bytes)}
    return ,([Text.Encoding]::UTF8.GetBytes($Case.input))
}

function Get-TargetHostCampaignSourcePaths {
    param([ValidateSet('console-lua','console-c','readline')][string]$Kind)
    $scriptName=switch($Kind){'console-lua'{'check-debug-console.ps1'}'console-c'{'check-debug-console-c.ps1'}'readline'{'check-cli-readline.ps1'}}
    return @('scripts/TargetHostCampaignContracts.psm1','scripts/ConformanceRunner.psm1',('scripts/'+$scriptName))
}

function Get-TargetHostConsoleCompileArguments {
    param([ValidateSet('default','upstream-test')][string]$Configuration,
        [ValidateSet('windows','linux','macos')][string]$Platform,
        [string]$SourceRoot,[string]$NativeImage,[string]$NativeExecutable)
    $arguments=@('-std=c99','-Wall','-Wextra','-Werror','-pedantic')
    # The actual T constructor macro selects debug_realloc/l_memcontrol in
    # the separately linked native oracle. Ada keeps its public SDK consumer;
    # no C interpreter header or allocator enters the Ada implementation.
    if($Configuration -ceq 'upstream-test'){$arguments+='-DLUA_USER_H=<ltests.h>'}
    if($Platform -ceq 'windows'){$arguments+='-DLUA_BUILD_AS_DLL'}
    elseif($Platform -ceq 'macos'){$arguments+='-DLUA_USE_MACOSX'}
    else{$arguments+='-DLUA_USE_LINUX'}
    # PIC resolves the shared oracle's actual l_memcontrol address through the
    # GOT instead of a Linux executable data copy relocation.
    if($Platform -cne 'windows'){$arguments+='-fPIC'}
    # Explicit slash spelling also lets another host replay the recorded
    # arguments without interpreting a foreign drive as a local filesystem.
    $source=$SourceRoot.Replace('\','/').TrimEnd('/')
    return $arguments+@(('-I'+$source+'/references/lua'),
        ($source+'/c_api/tests/builtin_api_contract.c'),
        ('-L'+$NativeImage.Replace('\','/')),'-lconformance_lua','-lm','-o',$NativeExecutable.Replace('\','/'))
}

Export-ModuleMember -Function Get-TargetHostCampaignCases,Get-TargetHostCampaignArguments,
    Get-TargetHostCampaignInputBytes,Get-TargetHostCampaignSourcePaths,
    Get-TargetHostConsoleCompileArguments
