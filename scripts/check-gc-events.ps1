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
$directory = Join-Path $root ('reports/gc-events/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$records = @()
$referenceOutput = @{}
$hostName = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$link = if ($LibraryType -eq 'relocatable') { 'shared' } else { $LibraryType }
$context = "$Configuration/$hostName/$Profile/$link"
try {
    & "$PSScriptRoot/test-scoped-warnings.ps1" -Interpreter $Interpreter `
        -ReferenceInterpreter $ReferenceInterpreter -RuntimeDirectory $RuntimeDirectory `
        -Configuration $Configuration -OutputDirectory (Join-Path $directory 'warnings')
    foreach ($file in @('events.lua','gengc.lua','gc.lua')) {
        foreach ($target in @('ReferenceC','Ada')) {
            $report = Join-Path $directory "$target-$file.json"
            $arguments = @{Target=$target; Configuration=$Configuration; Scope='gc-io-events';
                Mode='File'; File=$file; Report=$report; ReportOnly=$true; Context=$context;
                Interpreter=$(if ($target -eq 'Ada') { $Interpreter } else { $ReferenceInterpreter })}
            if ($target -eq 'Ada') { $arguments.RuntimeDirectory = $RuntimeDirectory }
            if ($target -eq 'Ada' -and $file -eq 'gc.lua') {
                $arguments.EquivalentManifest = Join-Path $root 'tests/conformance/equivalents/gc-ada-instrumented.json'
                $arguments.AllowUnreviewedEquivalent = $true
            }
            & "$PSScriptRoot/run-conformance.ps1" @arguments
            $code = $LASTEXITCODE
            $observation = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -Depth 32
            $records += [ordered]@{file=$file; target=$target; report=$report;
                report_sha256=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash.ToLowerInvariant();
                disposition=$observation.execution_disposition; status=$observation.status; context=$context;
                exit_code=$code; scope_accepted=$false}
            if ($code -ne 0 -or $observation.status -notin @('passed','completed-with-skips')) {
                throw "Scoped GC/events observation failed: $target/$file"
            }
            # Default omissions remain explicit, unresolved coverage links.
            # Permit only each pinned message here; instrumented execution
            # must actually exercise those blocks and print no omission.
            $expectedSkip = switch ($file) {
                'events.lua' { '>>> testC not active: skipping tests for userdata <<<' }
                'gengc.lua' { '>>> testC not active: skipping some generational tests <<<' }
                'gc.lua' { '>>> testC not active: skipping userdata GC tests <<<' }
            }
            $skips = @($observation.outcome.skip_messages)
            if (($Configuration -eq 'default' -and ($skips.Count -ne 1 -or $skips[0] -cne $expectedSkip)) -or
                ($Configuration -eq 'upstream-test' -and $skips.Count -ne 0)) {
                throw "Unexpected scoped omission: $target/$file"
            }
            $stdout = [IO.File]::ReadAllText($observation.process.stdout_path)
            $stderr = [IO.File]::ReadAllText($observation.process.stderr_path)
            if ($stderr.Length -ne 0) { throw "Unexpected scoped warning/error: $target/$file" }
            if ($target -eq 'ReferenceC') { $referenceOutput[$file] = $stdout }
            elseif ($stdout -cne $referenceOutput[$file]) { throw "Scoped C/Ada output differs: $file" }
        }
    }
    Write-Output "PASS: matching $Configuration C/Ada GC/events observations; GC mapping review pending"
} finally {
    $warningPath = Join-Path $directory 'warnings/index.json'
    $warningEvidence = if (Test-Path -LiteralPath $warningPath -PathType Leaf) {
        [ordered]@{report=$warningPath;sha256=(Get-FileHash -LiteralPath $warningPath -Algorithm SHA256).Hash.ToLowerInvariant()}
    } else { $null }
    [ordered]@{schema_version=1; scope='gc-io-events'; configuration=$Configuration; context=$context;
        diagnostic_only=$true; scope_accepted=$false; warning_regressions=$warningEvidence; observations=$records} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'index.json') -Encoding utf8
}
