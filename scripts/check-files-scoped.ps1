param(
    [Parameter(Mandatory)][string] $Interpreter,
    [Parameter(Mandatory)][string] $ReferenceInterpreter,
    [Parameter(Mandatory)][string] $RuntimeDirectory,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [ValidateSet('development','validation','release')][string] $Profile = 'validation',
    [ValidateSet('static','static-pic','relocatable')][string] $LibraryType = 'static'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/scoped-files/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$hostName = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$link = if ($LibraryType -eq 'relocatable') { 'shared' } else { $LibraryType }
$context = "$Configuration/$hostName/$Profile/$link"
$records = @()
$referenceOutput = $null
$referenceError = $null
try {
    foreach ($target in @('ReferenceC','Ada')) {
        $report = Join-Path $directory "$target-files.lua.json"
        $arguments = @{Target=$target; Configuration=$Configuration; Scope='gc-io-events';
            Mode='File'; File='files.lua'; Report=$report; ReportOnly=$true; Context=$context;
            Interpreter=$(if ($target -eq 'Ada') { $Interpreter } else { $ReferenceInterpreter })}
        if ($target -eq 'Ada') { $arguments.RuntimeDirectory = $RuntimeDirectory }
        if ($IsWindows) {
            $arguments.EquivalentManifest = Join-Path $root 'tests/conformance/equivalents/files-windows-platform.json'
            $arguments.AllowUnreviewedEquivalent = $true
        } elseif ($IsMacOS) {
            $arguments.EquivalentManifest = Join-Path $root 'tests/conformance/equivalents/files-macos-platform.json'
            $arguments.AllowUnreviewedEquivalent = $true
        }
        & "$PSScriptRoot/run-conformance.ps1" @arguments
        $code = $LASTEXITCODE
        $observation = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -Depth 32
        $records += [ordered]@{file='files.lua'; target=$target; report=$report;
            report_sha256=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash.ToLowerInvariant();
            disposition=$observation.execution_disposition; status=$observation.status; context=$context;
            exit_code=$code; scope_accepted=$false}
        if ($code -ne 0 -or $observation.status -cne 'passed' -or
            @($observation.outcome.skip_messages).Count -ne 0) {
            throw "Scoped files observation failed: $target"
        }
        $stdout = [IO.File]::ReadAllText($observation.process.stdout_path)
        if ($IsMacOS -and $stdout -notmatch '(?m)^native macOS buffered failure counterpart OK\r?$') {
            throw 'Missing executed macOS native flush counterpart'
        }
        $stderr = [IO.File]::ReadAllText($observation.process.stderr_path)
        # Date values can change between independent executions. Their exact
        # shape and final version are checked by the shared completion gate.
        # Everything else, including the native stderr, must agree with C.
        $normalized = $stdout -replace '(?m)^test done on .*\r?\n', "[date witness]`n"
        if ($IsWindows) {
            $expected = "'not-to-be-found-command' is not recognized as an internal or external command,`r`noperable program or batch file.`r`n" * 2
            if ($stderr -cne $expected) { throw "Unexpected scoped file stderr: $target" }
        } else {
            foreach ($line in $stderr.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
                if ($line -notmatch '^(?:.*not-to-be-found-command.*|Hangup.*|Killed.*)$') {
                    throw "Unexpected scoped file stderr: $target/$line"
                }
            }
        }
        if ($target -eq 'ReferenceC') { $referenceOutput=$normalized; $referenceError=$stderr }
        elseif ($normalized -cne $referenceOutput -or $stderr -cne $referenceError) {
            throw 'Scoped C/Ada file output differs outside the final date value'
        }
    }
    Write-Output "PASS: matching $Configuration scoped C/Ada file observations; semantic/mapping review pending"
} finally {
    [ordered]@{schema_version=1; scope='gc-io-events'; configuration=$Configuration; context=$context;
        diagnostic_only=$true; scope_accepted=$false; observations=$records} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'index.json') -Encoding utf8
}
