param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $RuntimeDirectory,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [ValidateSet('development','validation','release')][string] $Profile = 'validation',
    [ValidateSet('static','static-pic','relocatable')][string] $LibraryType = 'static'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/expanded-conformance/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
Import-Module "$PSScriptRoot/ScopedAcceptancePolicy.psm1" -Force
$scope = 'expanded-t-conformance'
$platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$link = if ($LibraryType -ceq 'relocatable') { 'shared' } else { $LibraryType }
$context = "$Configuration/$platform/$Profile/$link"
$policy = @{acceptance=$false; contracts=@{}}
$records = @()
$groups = @()
$completed = $false
try {
    $policy = Get-ScopedAcceptancePolicy -Root $root -Context $context -Scope $scope
    # Reuse the complete, independently reviewed GC/IO process protocols. Their
    # scope identity changes, while native counterparts and refusal/close-time
    # witnesses retain the established checks and raw artifacts.
    $common = @{Interpreter=$Interpreter; ReferenceInterpreter=$ReferenceInterpreter;
        RuntimeDirectory=$RuntimeDirectory; Configuration=$Configuration;
        Profile=$Profile; LibraryType=$LibraryType; Scope=$scope}
    foreach ($group in @('gc-events','files')) {
        $output = Join-Path $directory $group
        $scriptName = if ($group -ceq 'gc-events') { 'check-gc-events.ps1' } else { 'check-files-scoped.ps1' }
        & (Join-Path $PSScriptRoot $scriptName) @common -OutputDirectory $output
        $index = Join-Path $output 'index.json'
        $groups += @{kind=$group; path=$index;
            sha256=(Get-FileHash -LiteralPath $index).Hash.ToLowerInvariant()}
    }
    foreach ($file in @('bitwise.lua','closure.lua','constructs.lua','coroutine.lua',
        'goto.lua','math.lua','pm.lua','tpack.lua','utf8.lua')) {
        # constructs.lua chooses one of two generated templates through its
        # first real random draw. Separate seeded unchanged executions cover
        # both choices, rather than replacing the random function or guessing
        # that one successful process exercised both generated programs.
        $branches = if ($file -ceq 'constructs.lua') { @(0,1) } else { @(0) }
        foreach ($branch in $branches) {
            $referenceOutput = $null
            foreach ($target in @('ReferenceC','Ada')) {
                $name = if ($file -ceq 'constructs.lua') { "$target-$file-branch-$branch" } else { "$target-$file" }
                $report = Join-Path $directory "$name.json"
                $contract = if ($policy.acceptance) { $policy.contracts[$file] } else { $null }
                $arguments = @{Target=$target; Configuration=$Configuration; Scope=$scope;
                    Mode='File'; File=$file; Report=$report; ReportOnly=$true; Context=$context;
                    Interpreter=$(if ($target -ceq 'Ada') { $Interpreter } else { $ReferenceInterpreter })}
                if ($file -ceq 'constructs.lua') { $arguments.ConstructsBranch=$branch }
                if ($target -ceq 'Ada') { $arguments.RuntimeDirectory=$RuntimeDirectory }
                if ($target -ceq 'Ada' -and $policy.acceptance) {
                    $arguments.Remove('ReportOnly')
                    $arguments.RequireScopedAcceptance=$true
                    $arguments.AcceptanceContract=$contract.path
                }
                & "$PSScriptRoot/run-conformance.ps1" @arguments
                $code = $LASTEXITCODE
                $observation = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -AsHashtable -Depth 64
                $records += @{file=$file; target=$target; context=$context; report=$report;
                    report_sha256=(Get-FileHash -LiteralPath $report).Hash.ToLowerInvariant();
                    variant=$(if($file -ceq 'constructs.lua') { "constructs-branch-$branch" } else { $null });
                    status=$observation.status; exit_code=$code;
                    disposition=$observation.execution_disposition;
                    scope_accepted=$observation.scoped_operation_acceptance; contract=$contract}
                if ($code -ne 0 -or $observation.setup_error -or
                    $observation.status -cnotin @('passed','completed-with-skips') -or
                    ($target -ceq 'Ada' -and $policy.acceptance -and
                     -not $observation.scoped_operation_acceptance)) {
                    throw "Expanded conformance execution failed: $target/$file/branch-$branch"
                }
                $skips = @($observation.outcome.skip_messages)
                if ($Configuration -ceq 'default' -and $file -ceq 'coroutine.lua') {
                    $message = '>>> testC not active: skipping coroutine API tests <<<'
                    if ($skips.Count -ne 2 -or @($skips | Where-Object { $_ -cne $message }).Count) {
                        throw 'Default coroutine omission provenance differs'
                    }
                } elseif ($skips.Count) { throw "Unexpected expanded omission: $target/$file" }
                $stdout = [IO.File]::ReadAllText($observation.process.stdout_path)
                if ((Get-Item -LiteralPath $observation.process.stderr_path).Length -ne 0) {
                    throw "Unexpected expanded stderr: $target/$file"
                }
                # math.lua chooses and prints its own RNG seeds and statistics.
                # Retain those actual bytes; deterministic suites still require
                # exact same-host C/Ada output, without broad normalization.
                if ($file -cne 'math.lua') {
                    if ($target -ceq 'ReferenceC') { $referenceOutput=$stdout }
                    elseif ($stdout -cne $referenceOutput) { throw "Expanded C/Ada output differs: $file" }
                }
            }
        }
    }
    $completed = $true
    $phase = if ($policy.acceptance) { 'operation acceptance; independent final matrix pending' } else { 'diagnostic observations; coverage acceptance pending' }
    Write-Output "PASS: $Configuration expanded 13-file processes and both constructs templates; $phase"
} finally {
    [IO.File]::WriteAllText((Join-Path $directory 'index.json'),
        (([ordered]@{schema_version=1; scope=$scope; context=$context; configuration=$Configuration;
            completed=$completed; diagnostic_only=(-not $policy.acceptance); scope_accepted=$false;
            groups=$groups; observations=$records} | ConvertTo-Json -Depth 12) + "`n"),
        [Text.UTF8Encoding]::new($false))
}
