Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-SdkMacroCaseNames {
    param([Parameter(Mandatory)][ValidateSet('ordinary','client-opt-ins')][string] $Role,
          [Parameter(Mandatory)][bool] $C89)
    $names=@('register-cfunction','islightuserdata','isboolean','isnone','insert-suffix','replace-pop',
        'newuserdata-one-uservalue','getuservalue-alias','setuservalue-alias','newlibtable-empty','newlib-calls',
        'argcheck-short-circuit','argcheck-protected-error','argexpected-short-circuit','argexpected-protected-error',
        'checkstring-binary','checkstring-number','checkstring-protected-error','optstring-default','optstring-present',
        'typename-alias','dofile-results','dofile-syntax','dofile-runtime','dostring-results','dostring-syntax','dostring-runtime',
        'getmetatable-registry','opt-short-circuit','loadbuffer-extent','intop-wrap','pushfail-selected','legacy-strlen',
        'legacy-objlen','legacy-equal-metamethod','legacy-lessthan-metamethod','floor-helper','float-attribute','math-helper',
        'decimal-helper','integer-format','sprintf-helper')
    if(-not $C89){$names+=@('hex-parse','hex-format')}
    $names+=@('pointer-format','locale-decimal','branch-hints','stringify-raw-bytes','stringify-expanded-bytes')
    if($Role -ceq 'client-opt-ins'){$names+=@('compat-checkunsigned','compat-optunsigned','compat-checkint','compat-optint','compat-checklong','compat-optlong')}
    return $names
}

function Test-SdkMacroProtocol {
    param([Parameter(Mandatory)][string] $Text,[Parameter(Mandatory)][ValidateSet('ordinary','client-opt-ins')][string] $Role,
          [Parameter(Mandatory)][ValidateSet('windows','linux','macos')][string] $Platform,
          [Parameter(Mandatory)][object] $ReportedCases)
    # This models the pinned ordinary SDK receiver, not the runtime's private
    # implementation CPP state. luaconf.h itself enables LUA_USE_C89 on regular
    # Windows, even with -std=c99. POSIX selection forbids that combination.
    # Real opt-in aliases use a separate wrapper compiled into a separate main.
    $c89=$Platform -ceq 'windows';$opt=[int]($Role -ceq 'client-opt-ins')
    $names=Get-SdkMacroCaseNames -Role $Role -C89 $c89
    $lines=@("MACRO-CONFIG: APIINTCASTS=$opt FAILISFALSE=$opt C89=$([int]$c89)")
    foreach($name in $names){
        # These bytes come from actual preprocessor expansions in the client.
        # A passing registration or declaration count cannot replace them.
        if($name -ceq 'stringify-raw-bytes'){$lines+='MACRO-TOKEN-RAW: MACRO_CONTRACT_TOKEN'}
        if($name -ceq 'stringify-expanded-bytes'){$lines+='MACRO-TOKEN-EXPANDED: 41'}
        $lines+='PASS: macro-'+$name
    }
    $lines+='PASS: public SDK macro contract'
    if(($ReportedCases -isnot [int] -and $ReportedCases -isnot [long]) -or $ReportedCases -ne $names.Count -or
        $Text.Replace("`r`n","`n") -cne (($lines -join "`n")+"`n")){
        throw 'SDK macro receiver configuration actual ordered operations or expanded bytes differ'
    }
    return @{observed_cases=$names;receiver_role=$Role;runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Get-SdkMacroCaseNames, Test-SdkMacroProtocol
