Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NamedConsumerEvidence {
    param([Collections.IDictionary] $Report,
          [Collections.IDictionary] $Mapping,
          [string] $Revision, [string] $Context,
          [scriptblock] $ResolveCapture)
    # This replay checks actual observations, not review authority. Its caller
    # must bind the mapping and report to independently reviewed artifacts.
    $parts = $Context.Split('/')
    $libraryType = if ($parts.Count -eq 4 -and $parts[3] -eq 'shared') { 'relocatable' } elseif ($parts.Count -eq 4) { $parts[3] } else { '' }
    if ($parts.Count -ne 4 -or $Report.repository_revision -cne $Revision -or
        $Report.repository_dirty -ne $false -or
        $Report.configuration -cne $parts[0] -or
        $Report.platform -cne $parts[1] -or
        $Report.profile -cne $parts[2] -or $Report.library_type -cne $libraryType) {
        throw 'Named consumer context/revision differs or is dirty'
    }
    if (@($Report.library_files).Count -eq 0) { throw 'Named consumer library identity missing' }
    foreach ($library in $Report.library_files) {
        if ($library.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Named consumer library hash invalid' }
    }
    $outputs = @{}
    $markers = @{'c-api'='PASS: real Ada C API bootstrap consumer';
        'gc-api'='PASS: public GC contract'; 'io-api'='PASS: public IO/OS contract';
        'gc-oracle'='PASS: public GC contract'; 'io-oracle'='PASS: public IO/OS contract'}
    foreach ($name in $markers.Keys) {
        $matches = @($Report.consumers | Where-Object { $_.name -ceq $name })
        if ($matches.Count -ne 1) { throw "Named consumer missing/duplicate: $name" }
        $record = $matches[0]
        if ($record.exit_code -ne 0 -or $record.timed_out -ne $false -or
            $record.configuration -cne $parts[0] -or $record.profile -cne $parts[2] -or
            $record.library_type -cne $libraryType -or
            $record.executable_sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Named consumer process failed or differs: $name"
        }
        $outPath = & $ResolveCapture $record.stdout $record.stdout_sha256
        $errPath = & $ResolveCapture $record.stderr $record.stderr_sha256
        if ((Get-Item -LiteralPath $errPath).Length -ne 0) { throw "Named consumer stderr: $name" }
        $stdout = [IO.File]::ReadAllText($outPath)
        if ([regex]::Matches($stdout, '(?m)^' + [regex]::Escape($markers[$name]) + '\r?$').Count -ne 1) {
            throw "Named consumer completion missing/duplicate: $name"
        }
        $outputs[$name] = @{text=$stdout; hash=$record.stdout_sha256}
    }
    foreach ($kind in @('gc','io')) {
        $contract = $Report["${kind}_contract"]
        if ($Report.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
            $null -eq $contract -or $contract.matching_output -ne $true -or
            @($contract.reference_library_files).Count -eq 0) {
            throw 'Named consumer oracle provenance missing'
        }
        foreach ($library in $contract.reference_library_files) {
            if ($library.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Named consumer oracle library hash invalid' }
        }
        if ($outputs["$kind-api"].hash -cne $outputs["$kind-oracle"].hash) {
            throw "Named consumer oracle bytes differ: $kind"
        }
    }
    $seen = @{}
    foreach ($case in $Mapping.cases) {
        $key = $case.source + '#' + $case.case_id
        if ($seen.ContainsKey($key) -or $case.expected_count -ne 1 -or
            $case.consumer -cnotin @('c-api','gc-api','io-api')) {
            throw "Invalid/duplicate named consumer mapping: $key"
        }
        $source = @($Report.consumer_sources | Where-Object { $_.file -ceq $case.source })
        if ($source.Count -ne 1 -or $source[0].sha256 -cne $case.source_sha256) {
            throw "Named consumer source differs: $key"
        }
        $patterns = @($case.exact_witnesses | ForEach-Object { '(?m)^' + [regex]::Escape($_) + '\r?$' })
        if ($null -ne $case.pattern_witness) { $patterns += '(?m)' + $case.pattern_witness }
        if ($patterns.Count -eq 0) { throw "Named consumer has no witness: $key" }
        foreach ($pattern in $patterns) {
            if ([regex]::Matches($outputs[$case.consumer].text, $pattern).Count -ne 1) {
                throw "Named consumer witness missing/duplicate: $key"
            }
        }
        $seen[$key] = $true
    }
    if ($seen.Count -eq 0) { throw 'Named consumer mapping empty' }
    return [ordered]@{context=$Context; revision=$Revision; cases=@($seen.Keys | Sort-Object);
        runtime_observed=$true; scoped_acceptance=$false}
}

Export-ModuleMember -Function Test-NamedConsumerEvidence
