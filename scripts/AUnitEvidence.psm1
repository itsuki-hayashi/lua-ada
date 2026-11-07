Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NamedAUnitEvidence {
    param([Collections.IDictionary] $Report, [Collections.IDictionary] $Mapping,
          [string] $Revision, [string] $Context, [scriptblock] $ResolveCapture)
    $parts = $Context.Split('/')
    $libraryType = if ($parts.Count -eq 4 -and $parts[3] -eq 'shared') { 'relocatable' } elseif ($parts.Count -eq 4) { $parts[3] } else { '' }
    if ($parts.Count -ne 4 -or $Report.repository_revision -cne $Revision -or
        $Report.repository_dirty -ne $false -or $Report.configuration -cne $parts[0] -or
        $Report.platform -cne $parts[1] -or $Report.profile -cne $parts[2] -or
        $Report.library_type -cne $libraryType -or $Report.completed -ne $true -or
        $Report.exit_code -ne 0 -or $Report.executable_sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'AUnit evidence identity or completion differs'
    }
    if (@($Report.library_files).Count -eq 0) { throw 'AUnit library identity missing' }
    foreach ($library in $Report.library_files) {
        if ($library.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'AUnit library hash invalid' }
    }
    $probe = $Report.configuration_probe
    if ($probe.executable_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'AUnit probe executable identity missing' }
    $probeOut = & $ResolveCapture $probe.stdout $probe.stdout_sha256
    $probeErr = & $ResolveCapture $probe.stderr $probe.stderr_sha256
    $observed = Get-Content -LiteralPath $probeOut -Raw | ConvertFrom-Json
    if ((Get-Item $probeErr).Length -ne 0 -or $observed.configuration -cne $parts[0]) {
        throw 'AUnit compiled configuration differs'
    }
    $outPath = & $ResolveCapture $Report.stdout $Report.stdout_sha256
    $errPath = & $ResolveCapture $Report.stderr $Report.stderr_sha256
    $stdout = [IO.File]::ReadAllText($outPath)
    $stderr = [IO.File]::ReadAllText($errPath).Replace("`r`n","`n")
    if ($stderr -cne "Lua warning: error in __gc ((native):1: ordinary failure)`n") {
        throw 'AUnit expected finalizer warning differs'
    }
    # A positive summary is necessary but insufficient. Check the full case
    # count and exact independently reviewed labels below. This is named-case
    # replay with a consistent suite summary; retained whole-suite CI remains
    # a separate gate, since the number of registered cases is host dependent.
    $summary = [regex]::Matches($stdout,
        '(?m)^Total Tests Run:\s+([1-9][0-9]*)\r?\nSuccessful Tests:\s+([1-9][0-9]*)\r?\nFailed Assertions:\s+0\r?\nUnexpected Errors:\s+0\r?$')
    $ok = [regex]::Matches($stdout,'(?m)^OK .+\r?$')
    if ($summary.Count -ne 1 -or $summary[0].Groups[1].Value -cne $summary[0].Groups[2].Value -or
        $ok.Count -ne [int]$summary[0].Groups[1].Value) { throw 'AUnit complete suite summary differs' }
    $seen = @{}
    foreach ($entry in $Mapping.entries) {
        if ([string]::IsNullOrWhiteSpace($entry.case) -or $seen.ContainsKey($entry.case) -or
            [string]::IsNullOrWhiteSpace($entry.required_stdout_line)) {
            throw 'AUnit named mapping duplicate/empty'
        }
        $source = @($Report.sources | Where-Object { $_.file -ceq $entry.case.Split('#')[0] })
        if ($source.Count -ne 1 -or $source[0].sha256 -cne $entry.source_sha256) { throw 'AUnit named source differs' }
        if ([regex]::Matches($stdout,'(?m)^' + [regex]::Escape($entry.required_stdout_line) + '\r?$').Count -ne 1) {
            throw 'AUnit named case missing/duplicate'
        }
        $seen[$entry.case] = $true
    }
    if ($seen.Count -eq 0) { throw 'AUnit named mapping empty' }
    return @{context=$Context; revision=$Revision; cases=@($seen.Keys | Sort-Object);
        total_cases=$ok.Count; runtime_observed=$true; scoped_acceptance=$false}
}

Export-ModuleMember -Function Test-NamedAUnitEvidence
