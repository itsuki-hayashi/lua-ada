param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $RuntimeDirectory,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [ValidateSet('gc-io-events','expanded-t-conformance')][string] $Scope = 'gc-io-events',
    [ValidateSet('development','validation','release')][string] $Profile = 'validation',
    [ValidateSet('static','static-pic','relocatable')][string] $LibraryType = 'static',
    [Parameter(Mandatory)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ScopedWarnings.psm1') -Force
# These retained legacy fixtures protect the previously reviewed termination
# mapping. Actual runs and matrix replay use ScopedWarnings.psm1's exact
# stream protocol, whose active branches have separately named regressions in
# test-scoped-warning-evidence.ps1; the legacy fixture count is not its coverage.
# GNAT's POSIX signal handler may convert abort to Program_Error. Exit 1
# qualifies only with both specific diagnostics, never an arbitrary error.
function Test-WarningTermination {
    param([string] $Mode, [string] $Target, [bool] $Windows,
        [int] $Code, [string] $Diagnostic,
        [string] $CaseName = 'normal-warning', [string] $Output = '',
        [bool] $MacOS = $false)
    if ($Mode -eq 'default') { return $Code -eq 0 }
    if ($Target -eq 'ReferenceC') { return $Code -eq 1 }
    if ($Windows) { return $Code -eq 3 }
    $expectedText = if ($CaseName -eq 'shutdown-warning') { 'scoped shutdown assertion' }
        else { 'scoped unexpected warning' }
    if ($Diagnostic -notmatch ('(?m)^T warning failure: unexpected warning: [^\r\n]*' +
            [regex]::Escape($expectedText) + '[^\r\n]*\r?$')) { return $false }
    if ($CaseName -eq 'shutdown-warning' -and $Output -notmatch '(?m)^OK\r?$') { return $false }
    if ($Code -eq 134) { return $true }
    # Darwin GNAT reports this signal exception through its last-chance
    # handler rather than Execute's conversion. The actual Mac normal-warning
    # capture has both lines below; an arbitrary exception/exit remains invalid.
    if ($MacOS) {
        return $Code -eq 1 -and
            $Diagnostic -match '(?m)^Execution of [^\r\n]+ terminated by unhandled exception\r?$' -and
            $Diagnostic -match '(?m)^raised PROGRAM_ERROR : unhandled signal\r?$'
    }
    # Close runs outside Execute's error conversion and reaches Lua_CLI's
    # outer handler. This source-derived expectation still needs CI evidence.
    if ($CaseName -eq 'shutdown-warning') {
        return $Code -eq 1 -and $Diagnostic -match '(?m)^lua_ada: unhandled signal\r?$'
    }
    return $Code -eq 1 -and $Diagnostic -match `
        '(?m)^\(command line\):1: internal Ada check: unhandled signal\r?$'
}
# Fixtures validate the verifier; they do not claim foreign-platform runtime
# passes. The actual process tests below separately exercise this host.
$gnatWarning = "T warning failure: unexpected warning: scoped unexpected warning`n(command line):1: internal Ada check: unhandled signal`n"
$verifierCases = @(
    @{code=1;diagnostic=$gnatWarning;expected=$true},
    @{code=134;diagnostic='T warning failure: unexpected warning: scoped unexpected warning';expected=$true},
    @{code=2;diagnostic=$gnatWarning;expected=$false},
    @{code=139;diagnostic=$gnatWarning;expected=$false},
    @{code=1;diagnostic='T warning failure: unexpected warning: scoped unexpected warning';expected=$false},
    @{code=1;diagnostic='(command line):1: internal Ada check: unhandled signal';expected=$false},
    @{code=1;diagnostic="T warning failure: unexpected warning: scoped unexpected warning`n(command line):1: internal Ada check: unrelated error";expected=$false},
    @{code=134;diagnostic='unrelated abort';expected=$false}
)
foreach ($fixture in $verifierCases) {
    $actual = Test-WarningTermination -Mode upstream-test -Target Ada -Windows $false `
        -Code $fixture.code -Diagnostic $fixture.diagnostic
    if ($actual -ne $fixture.expected) { throw 'Warning termination verifier regression' }
}
$shutdownWarning = "T warning failure: unexpected warning: error in __gc (scoped shutdown assertion)`nlua_ada: unhandled signal`n"
$shutdownFixtures = @(
    @{name='shutdown-warning';output='OK';diagnostic=$shutdownWarning;expected=$true},
    @{name='normal-warning';output='OK';diagnostic=$shutdownWarning;expected=$false},
    @{name='normal-warning';output='OK';diagnostic=$shutdownWarning.Replace('scoped shutdown assertion','scoped unexpected warning');expected=$false},
    @{name='shutdown-warning';output='';diagnostic=$shutdownWarning;expected=$false},
    @{name='shutdown-warning';output='OK';diagnostic=$shutdownWarning.Replace('unhandled signal','unrelated error');expected=$false},
    @{name='shutdown-warning';output='OK';diagnostic=$gnatWarning.Replace('scoped unexpected warning','scoped shutdown assertion');expected=$false}
)
foreach ($fixture in $shutdownFixtures) {
    $actual = Test-WarningTermination -Mode upstream-test -Target Ada -Windows $false `
        -Code 1 -Diagnostic $fixture.diagnostic -CaseName $fixture.name -Output $fixture.output
    if ($actual -ne $fixture.expected) { throw 'Shutdown warning verifier regression' }
}
$macWarning = "T warning failure: unexpected warning: scoped unexpected warning`nExecution of /fixture/conformance_runner terminated by unhandled exception`nraised PROGRAM_ERROR : unhandled signal`n"
$macFixtures = @(
    @{name='normal-warning';output='';diagnostic=$macWarning;expected=$true},
    @{name='normal-warning';output='';diagnostic=$macWarning.Replace('PROGRAM_ERROR','STORAGE_ERROR');expected=$false},
    @{name='normal-warning';output='';diagnostic=$macWarning.Replace('unhandled signal','unrelated error');expected=$false},
    @{name='normal-warning';output='';diagnostic=$macWarning.Replace('T warning failure:','other:');expected=$false},
    @{name='shutdown-warning';output='OK';diagnostic=$macWarning.Replace('scoped unexpected warning','scoped shutdown assertion');expected=$true},
    @{name='shutdown-warning';output='';diagnostic=$macWarning.Replace('scoped unexpected warning','scoped shutdown assertion');expected=$false},
    @{name='shutdown-warning';output='OK';diagnostic=$macWarning;expected=$false})
foreach ($fixture in $macFixtures) {
    $actual = Test-WarningTermination -Mode upstream-test -Target Ada -Windows $false -MacOS $true `
        -Code 1 -Diagnostic $fixture.diagnostic -CaseName $fixture.name -Output $fixture.output
    if ($actual -ne $fixture.expected) { throw 'Darwin warning verifier regression' }
}
$root = Split-Path -Parent $PSScriptRoot
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$directory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$reference = (Resolve-Path -LiteralPath $ReferenceInterpreter).Path
$RuntimeDirectory = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$referenceLibrary = Join-Path (Split-Path -Parent (Split-Path -Parent $reference)) 'lib'
$sourceRecords = Get-ScopedWarningSources | ForEach-Object {
    [ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$libraryRecords = @()
foreach ($pair in @(@{target='Ada';directory=$RuntimeDirectory},@{target='ReferenceC';directory=$referenceLibrary})) {
    $libraries = @(Get-ChildItem -LiteralPath $pair.directory -File | Where-Object {
        $_.Extension -in @('.a','.dll','.so','.dylib') })
    if ($libraries.Count -eq 0) { throw "No measured warning-test libraries: $($pair.target)" }
    foreach ($library in $libraries) {
        $libraryRecords += [ordered]@{target=$pair.target;path=$library.FullName;
            sha256=(Get-FileHash -LiteralPath $library.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
}
$revision = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify warning-test revision' }
$repositoryStatus = @(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify warning-test checkout state' }
$environment = @{
    PATH=$RuntimeDirectory + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:PATH
    LD_LIBRARY_PATH=$RuntimeDirectory + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    DYLD_LIBRARY_PATH=$RuntimeDirectory + [IO.Path]::PathSeparator + $referenceLibrary + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
# The normal and close-time cases must be rejected by the same zero-status /
# empty-stderr criterion used by the scoped GC driver. Default Lua reports a
# warning without failing execution; the real T handler aborts unexpected
# warnings. Require the diagnostic too, so a missing DLL or crash is not a pass.
$cases = @(Get-ScopedWarningCases -Configuration $Configuration)
$platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
$link=if($LibraryType -ceq 'relocatable'){'shared'}else{$LibraryType}
$records = @()
foreach ($target in @('ReferenceC','Ada')) {
    $executable = if ($target -eq 'Ada') { (Resolve-Path -LiteralPath $Interpreter).Path } else { $reference }
    foreach ($case in $cases) {
        $process = Invoke-ConformanceProcess -Executable $executable -Arguments @('-e',$case.source) `
            -Directory $directory -OutputPrefix (Join-Path $directory "$target-$($case.name)") `
            -TimeoutSeconds 30 -Environment $environment
        Assert-ScopedWarningProcess -Process $process -Case $case -Target $target `
            -Configuration $Configuration -Platform $platform
        $records += [ordered]@{name=$case.name;target=$target;expected_rejection=$case.reject;process=$process}
        Write-Output "WARNING TEST PASS: $target/$($case.name)"
    }
}
[ordered]@{schema_version=1;scope=$Scope;configuration=$Configuration;
    context="$Configuration/$platform/$Profile/$link";repository_revision=$revision;
    repository_dirty=($repositoryStatus.Count -ne 0);repository_status=$repositoryStatus;
    source_records=@($sourceRecords);library_records=$libraryRecords;
    verifier_fixture_count=($verifierCases.Count + $shutdownFixtures.Count + $macFixtures.Count);cases=$records} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'index.json') -Encoding utf8
Write-Output "PASS: $($records.Count) actual scoped warning regressions"
