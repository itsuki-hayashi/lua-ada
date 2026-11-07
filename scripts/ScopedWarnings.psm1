Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-ScopedWarningCases {
    param([ValidateSet('default','upstream-test')][string] $Configuration)
    $setup=if($Configuration -ceq 'upstream-test'){"assert(type(T)=='table'); "}else{'assert(T==nil); '}
    $cases=@(
        @{name='normal-warning';reject=$true;source="warn('@on'); warn('scoped unexpected warning'); print('OK')"},
        @{name='shutdown-warning';reject=$true;source="warn('@on'); _retained=setmetatable({}, {__gc=function() assert(false,'scoped shutdown assertion') end}); print('OK')"},
        @{name='explicit-warning-off';reject=$false;source="warn('@on'); warn('@off'); warn('explicitly suppressed'); print('OK')"}
    )
    if($Configuration -ceq 'upstream-test') {
        $cases+=@{name='stored-warning-consumed';reject=$false;source="warn('@on'); warn('@store'); warn('expected',' fragments'); assert(_WARN=='expected fragments'); _WARN=false; warn('@normal'); print('OK')"}
    }
    foreach($case in $cases) { $case.source=$setup+$case.source }
    return $cases
}

function Get-ScopedWarningSources {
    return @('scripts/test-scoped-warnings.ps1','scripts/ScopedWarnings.psm1',
        'scripts/check-gc-events.ps1','scripts/run-conformance.ps1',
        'scripts/ConformanceRunner.psm1','tests/c/conformance_adapter.c','references/lua/ltests.c')
}

function Assert-ScopedWarningProcess {
    param([Collections.IDictionary] $Process,[Collections.IDictionary] $Case,
          [ValidateSet('ReferenceC','Ada')][string] $Target,
          [ValidateSet('default','upstream-test')][string] $Configuration,
          [ValidateSet('windows','linux','macos')][string] $Platform)
    if($Process.timed_out -or $Process.capture_exceeded -or $Process.pipe_drain_failed -or
        $Process.process_tree_kill_error -or $Process.timeout_seconds -ne 30 -or
        @($Process.arguments).Count -ne 2 -or $Process.arguments[0] -cne '-e' -or
        $Process.arguments[1] -cne $Case.source) { throw 'Warning process setup or completion differs' }
    $stdout=[IO.File]::ReadAllText($Process.stdout_path)
    $stderr=[IO.File]::ReadAllText($Process.stderr_path)
    $newline=if($Platform -ceq 'windows'){"`r`n"}else{"`n"}
    $expectedOutput=if($Configuration -ceq 'upstream-test' -and $Case.name -ceq 'normal-warning'){''}else{"OK$newline"}
    if($stdout -cne $expectedOutput) { throw 'Warning process completion phase differs' }
    if(-not $Case.reject) {
        if($Process.exit_code -ne 0 -or $stderr -cne '') { throw 'Warning control did not complete with empty stderr' }
        return
    }
    # Native -e names its chunk =(command line). The first-party runner uses
    # the literal name (command line); Short_Source therefore quotes it. Keep
    # both actual identities rather than normalizing the captured warning.
    $payload=if($Case.name -ceq 'normal-warning'){'scoped unexpected warning'}else{
        $location=if($Target -ceq 'Ada'){'[string "(command line)"]'}else{'(command line)'}
        "error in __gc ($($location):1: scoped shutdown assertion)"
    }
    if($Configuration -ceq 'default') {
        if($Process.exit_code -ne 0 -or $stderr -cne "Lua warning: $payload$newline") {
            throw 'Default warning payload or normal return differs'
        }
        return
    }
    if($Target -ceq 'ReferenceC') {
        if($Process.exit_code -ne 1 -or
            $stderr -cne "Unexpected warning in test mode: $payload$($newline)aborting...$newline") {
            throw 'Native T warning payload or abort transport differs'
        }
        return
    }
    $prefix="T warning failure: unexpected warning: $payload$newline"
    if(-not $stderr.StartsWith($prefix,[StringComparison]::Ordinal)) {
        throw 'Ada T warning payload differs'
    }
    $transport=$stderr.Substring($prefix.Length)
    if($Platform -ceq 'windows') {
        if($Process.exit_code -ne 3 -or $transport -cne '') { throw 'Windows T abort transport differs' }
    } elseif($Process.exit_code -eq 134) {
        if($transport -cne '') { throw 'POSIX T abort has unrelated diagnostics' }
    } elseif($Platform -ceq 'macos') {
        # GNAT's last-chance handler reports machine addresses. Permit only
        # its exact structural transport, with the measured executable path;
        # retain every original byte and hash in the evidence bundle.
        $pattern='\A\nExecution of '+[regex]::Escape($Process.executable)+
            ' terminated by unhandled exception\nraised PROGRAM_ERROR : unhandled signal\n'+
            '(?:Load address: 0x[0-9a-fA-F]+\n)?Call stack traceback locations:\n'+
            '0x[0-9a-fA-F]+(?: 0x[0-9a-fA-F]+)*\n\z'
        if($Process.exit_code -ne 1 -or $transport -cnotmatch $pattern) { throw 'Darwin T signal transport differs' }
    } else {
        $expected=if($Case.name -ceq 'shutdown-warning'){"lua_ada: unhandled signal`n"}else{
            "(command line):1: internal Ada check: unhandled signal`n"
        }
        if($Process.exit_code -ne 1 -or $transport -cne $expected) { throw 'Linux T signal transport differs' }
    }
}

Export-ModuleMember -Function Get-ScopedWarningCases,Get-ScopedWarningSources,Assert-ScopedWarningProcess
