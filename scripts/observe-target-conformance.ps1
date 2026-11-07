param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $RuntimeDirectory,
    [string] $NativeLibraryDirectory = '',
    [string] $GCEquivalentManifest = '',
    [string] $FileProtocolManifest = '',
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [ValidateSet('development','validation','release')][string] $Profile = 'validation',
    [ValidateSet('static','static-pic','relocatable')][string] $LibraryType = 'static',
    [ValidateSet('Retained','All')][string] $Selection = 'Retained',
    [string] $OutputDirectory = '',
    [switch] $PlanOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceScope.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceFileProtocols.psm1')
$suite = Get-Content -LiteralPath (Join-Path $root 'tests/conformance/suite.json') -Raw |
    ConvertFrom-Json -AsHashtable -Depth 32
$platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$link = if ($LibraryType -ceq 'relocatable') { 'shared' } else { $LibraryType }
$context = "$Configuration/$platform/$Profile/$link"
if ($context -cnotin $suite.acceptance_contexts) { throw 'Observation context is not in the declared target matrix' }
$files = if ($Selection -ceq 'Retained') { (Get-ConformanceScopePolicy -Scope expanded-t-conformance).Files }
    else { @($suite.files | Where-Object role -CEQ primary | ForEach-Object path) }
$plan = @()
foreach ($file in $files) {
    foreach ($branch in $(if($file -ceq 'constructs.lua'){@(0,1)}else{@(0)})) {
        foreach ($target in @('ReferenceC','Ada')) {
            $equivalent = if ($file -ceq 'gc.lua' -and $target -ceq 'Ada') { 'gc-ada-instrumented' }
                elseif ($file -ceq 'files.lua' -and $platform -ceq 'windows') { 'files-windows-platform' }
                elseif ($file -ceq 'files.lua' -and $platform -ceq 'macos') { 'files-macos-platform' } else { '' }
            $manifest = if ($file -ceq 'gc.lua' -and $target -ceq 'Ada' -and $GCEquivalentManifest -ne '') {
                $GCEquivalentManifest
            } elseif ($equivalent -ne '') { Join-Path $root ('tests/conformance/equivalents/' + $equivalent + '.json') } else { '' }
            $plan += @{file=$file;target=$target;constructs_branch=$branch;equivalent=$equivalent;equivalent_manifest=$manifest;context=$context}
        }
    }
}
if ($PlanOnly) {
    @{schema_version=1;target='remaining-upstream-compatibility';context=$context;selection=$Selection;
        planned_processes=$plan;diagnostic_only=$true;target_acceptance=$false;coverage_authority=$false} |
        ConvertTo-Json -Depth 8
    exit 0
}
$directory = if ($OutputDirectory -ne '') { [IO.Path]::GetFullPath($OutputDirectory) }
    else { Join-Path $root ('reports/target-observations/' + [Guid]::NewGuid().ToString('N')) }
[void][IO.Directory]::CreateDirectory($directory)
$observations = @(); $failures = @(); $warningIdentity = $null; $warningFailure = $null
try {
    # This reuses only the warning process protocol, not its old scope's
    # source-bound acceptance-policy lookup or acceptance authority.
    try {
        & (Join-Path $PSScriptRoot 'test-scoped-warnings.ps1') -Interpreter $Interpreter `
            -ReferenceInterpreter $ReferenceInterpreter -RuntimeDirectory $RuntimeDirectory `
            -Configuration $Configuration -Scope expanded-t-conformance -Profile $Profile `
            -LibraryType $LibraryType -OutputDirectory (Join-Path $directory 'warnings')
        if (-not $?) { throw 'Warning observation protocol failed' }
        $warningPath = Join-Path $directory 'warnings/index.json'
        $warningIdentity = @{path=$warningPath;sha256=(Get-FileHash $warningPath).Hash.ToLowerInvariant()}
    } catch { $warningFailure = $_.Exception.Message; $failures += 'warning-protocol' }
    foreach ($entry in $plan) {
        $suffix = if ($entry.file -ceq 'constructs.lua') { '-branch-' + $entry.constructs_branch } else { '' }
        $reportPath = Join-Path $directory ($entry.target + '-' + $entry.file + $suffix + '.json')
        $arguments = @{Target=$entry.target;Configuration=$Configuration;Mode='File';File=$entry.file;
            TargetPolicy='remaining-upstream-compatibility';Context=$context;Report=$reportPath;ReportOnly=$true;
            Interpreter=$(if($entry.target -ceq 'Ada'){$Interpreter}else{$ReferenceInterpreter})}
        if ($entry.target -ceq 'Ada') {
            $arguments.RuntimeDirectory = $RuntimeDirectory
            if ($NativeLibraryDirectory -ne '') { $arguments.NativeLibraryDirectory = $NativeLibraryDirectory }
        }
        if ($entry.file -ceq 'constructs.lua') { $arguments.ConstructsBranch = $entry.constructs_branch }
        if ($entry.equivalent_manifest -ne '') {
            $arguments.EquivalentManifest = $entry.equivalent_manifest
        }
        if ($FileProtocolManifest -ne '' -and $null -ne (Get-TargetFileProtocolDefinition -File $entry.file)) {
            $arguments.FileProtocolManifest = $FileProtocolManifest
        }
        & (Join-Path $PSScriptRoot 'run-conformance.ps1') @arguments
        $code = $LASTEXITCODE
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
        $observations += @{file=$entry.file;target=$entry.target;context=$context;variant=$report.variant;
            report=$reportPath;sha256=(Get-FileHash $reportPath).Hash.ToLowerInvariant();status=$report.status;
            disposition=$report.execution_disposition;collector_exit_code=$code;target_operation_acceptance=$false}
        if ($code -ne 0 -or $report.setup_error -or $report.status -cnotin @('passed','completed-with-skips')) {
            $failures += $entry.target + '/' + $entry.file + $suffix
        }
    }
} finally {
    $index = @{schema_version=1;target='remaining-upstream-compatibility';selection=$Selection;context=$context;
        repository_revision=(& git -C $root rev-parse HEAD).Trim();diagnostic_only=$true;
        target_acceptance=$false;coverage_authority=$false;warning_observations=$warningIdentity;
        warning_failure=$warningFailure;completed=($observations.Count -eq $plan.Count);
        observations=$observations;failed_observations=$failures;planned_process_count=$plan.Count}
    [IO.File]::WriteAllText((Join-Path $directory 'index.json'),
        (ConvertTo-Json -InputObject $index -Depth 32).Replace("`r`n","`n") + "`n",[Text.UTF8Encoding]::new($false))
}
Write-Output "OBSERVED: $($observations.Count) physical file operations, $($failures.Count) failures; target acceptance=False; index=$directory/index.json"
if ($failures.Count -gt 0) { exit 1 }
exit 0
