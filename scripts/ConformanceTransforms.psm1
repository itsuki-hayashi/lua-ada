Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$script:TransformReference = '7579fc9d7ed90240487251dfb69168f8e64e9294'

function Get-ConformancePatchedBytes {
    param([Parameter(Mandatory)][byte[]] $SourceBytes,
          [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Replacements)
    # Reconstruction writes untouched slices verbatim, in original byte order.
    # It does not normalize pinned CRLF, decode source text, or edit references.
    $stream = [IO.MemoryStream]::new()
    $cursor = 0; $seen = @{}
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    try {
        foreach ($change in ($Replacements | Sort-Object start_byte)) {
            if ($change.id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or $seen.ContainsKey($change.id) -or
                ($change.start_byte -isnot [int] -and $change.start_byte -isnot [long]) -or
                ($change.length_bytes -isnot [int] -and $change.length_bytes -isnot [long]) -or
                $change.start_byte -lt $cursor -or $change.length_bytes -le 0 -or
                $change.start_byte -gt $SourceBytes.Length -or
                $change.length_bytes -gt $SourceBytes.Length - $change.start_byte -or
                $change.replacement -isnot [string]) { throw 'Invalid, duplicate or overlapping transform span' }
            $seen[$change.id] = $true
            $span = [byte[]]::new($change.length_bytes)
            [Array]::Copy($SourceBytes,$change.start_byte,$span,0,$span.Length)
            if ((Get-ConformanceHash $span) -cne $change.source_sha256) { throw 'Transform original span hash differs' }
            $stream.Write($SourceBytes,$cursor,$change.start_byte - $cursor)
            $replacement = $utf8.GetBytes($change.replacement)
            $stream.Write($replacement,0,$replacement.Length)
            $cursor = $change.start_byte + $change.length_bytes
        }
        $stream.Write($SourceBytes,$cursor,$SourceBytes.Length - $cursor)
        return ,$stream.ToArray()
    } finally { $stream.Dispose() }
}

function Get-ConformanceEquivalentReplay {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][Collections.IDictionary] $Specification)
    if ($Specification.schema_version -ne 1 -or
        $Specification.id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
        $Specification.source -cnotmatch '^references/lua/testes/[a-z0-9]+\.lua$' -or
        $Specification.configuration -cnotin @('default','upstream-test','default-and-upstream-test')) {
        throw 'Invalid equivalent replay identity'
    }
    $disposition = if ($Specification.Contains('disposition')) { $Specification.disposition } else { 'ada-internal-equivalent' }
    if ($disposition -cnotin @('ada-internal-equivalent','native-platform-equivalent')) { throw 'Invalid equivalent replay disposition' }
    $path = Resolve-ReviewedFile -Root $Root -Path $Specification.source -Sha256 $Specification.source_sha256
    foreach ($change in $Specification.replacements) {
        if ([string]::IsNullOrWhiteSpace([string]$change.invariant) -or @($change.counterpart_tests).Count -eq 0) {
            throw 'Equivalent replay lacks an invariant or counterpart'
        }
    }
    $bytes = Get-ConformancePatchedBytes -SourceBytes ([IO.File]::ReadAllBytes($path)) -Replacements @($Specification.replacements)
    $hash = Get-ConformanceHash $bytes
    Assert-EquivalentReviewBinding -Root $Root -Specification $Specification -GeneratedSha256 $hash
    return @{bytes=$bytes;sha256=$hash;source=$Specification.source;source_sha256=$Specification.source_sha256;
        id=$Specification.id;disposition=$disposition;diagnostic_only=$false;review_status='accepted'}
}

function Assert-TTransformReplacement {
    param([Collections.IDictionary] $Change, [Collections.IDictionary] $Exclusion)
    # A transform can replace only the exact independently excluded private
    # span. It cannot widen that decision to a surrounding mixed helper/block.
    if ($Change.exclusion_id -cne $Exclusion.id -or $Change.start_byte -ne $Exclusion.byte_offset -or
        $Change.length_bytes -ne $Exclusion.byte_length -or $Change.source_sha256 -cne $Exclusion.anchor_sha256 -or
        $Exclusion.status -cne 'excluded' -or $Exclusion.disposition -cne 'reviewed-t-internal-exclusion' -or
        $Exclusion.eligibility -cne 't-only-private-invariant' -or
        $Exclusion.public_api -isnot [bool] -or $Exclusion.public_api -or
        $Exclusion.mixed_obligation -isnot [bool] -or $Exclusion.mixed_obligation -or
        $Exclusion.module_observable -isnot [bool] -or $Exclusion.module_observable) {
        throw 'T transform span is wider than or differs from its approved private exclusion'
    }
    # Excluding private checks needs no executable replacement statements.
    # Permit an empty/comment-only replacement, or punctuation preserving an
    # enclosing public expression. New names, calls, assignments, control flow
    # and early returns are deliberately unavailable, even with a claimed review.
    $tokens = @(Get-ConformanceTokens -Bytes ([Text.UTF8Encoding]::new($false,$true).GetBytes($Change.replacement)))
    if ($Change.replacement.Contains('--')) {
        # An unterminated line comment could swallow untouched public code
        # after an otherwise exact private span. Only complete line comments
        # are permitted; block-comment delimiters are unnecessary here.
        if (-not $Change.replacement.EndsWith("`n",[StringComparison]::Ordinal)) {
            throw 'T transform comment must terminate before untouched source'
        }
        foreach ($line in ($Change.replacement -split "`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -ne '' -and ($trimmed -cnotmatch '^--(?:[^\[]|$)' -or $trimmed.StartsWith('--['))) {
                throw 'T transform permits only complete simple line comments'
            }
        }
    }
    if (@($tokens | Where-Object { $_.IsString -or $_.Text -cnotin @('(',')',';',',') }).Count -ne 0) {
        throw 'T transform replacement introduces executable behavior or a blanket bypass'
    }
}

function Get-ConformanceTReplay {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][Collections.IDictionary] $Specification,
          [Parameter(Mandatory)][string] $PolicySha256,
          [Parameter(Mandatory)][Collections.IDictionary] $ResolvedExclusions,
          [switch] $AllowUnreviewedDiagnostics)
    if ($Specification.schema_version -ne 1 -or $Specification.kind -cne 't-private-transform' -or
        $Specification.target -cne 'remaining-upstream-compatibility' -or
        $Specification.reference_revision -cne $script:TransformReference -or
        $Specification.configuration -cne 'upstream-test' -or
        $Specification.id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or
        $Specification.source -cnotmatch '^references/lua/testes/[a-z0-9]+\.lua$' -or
        $Specification.exclusion_policy_sha256 -cne $PolicySha256 -or $PolicySha256 -cnotmatch '^[0-9a-f]{64}$' -or
        @($Specification.replacements).Count -eq 0) { throw 'Invalid T transform identity or exclusion policy hash' }
    $path = Resolve-ReviewedFile -Root $Root -Path $Specification.source -Sha256 $Specification.source_sha256
    $sourceBytes = [IO.File]::ReadAllBytes($path)
    $protectedCheckR = $null
    if ($Specification.source -ceq 'references/lua/testes/code.lua') {
        # This pinned helper executes the supplied function and checks both
        # its value and numeric type. Excluding opcode layout must never make
        # those actual public behavior checks disappear with the inspection.
        $text = [Text.Encoding]::Latin1.GetString($sourceBytes)
        $protectedCheckR = [regex]::Match($text,'(?ms)^local function checkR \(f, p, r, \.\.\.\)\r?\n.*?^end\r?$')
        if (-not $protectedCheckR.Success) { throw 'Pinned code.lua checkR preservation span is missing' }
    }
    $seen = @{}
    foreach ($change in $Specification.replacements) {
        if ($null -ne $protectedCheckR -and $change.start_byte -lt $protectedCheckR.Index + $protectedCheckR.Length -and
            $change.start_byte + $change.length_bytes -gt $protectedCheckR.Index) {
            throw 'T transform cannot alter code.lua checkR execution or type assertions'
        }
        if (-not $ResolvedExclusions.Contains($change.exclusion_id) -or $seen.ContainsKey($change.exclusion_id)) {
            throw 'T transform has missing or duplicate approved exclusions'
        }
        $excluded = $ResolvedExclusions[$change.exclusion_id]
        if (('references/lua/testes/' + $excluded.source) -cne $Specification.source -or
            $excluded.source_sha256 -cne $Specification.source_sha256 -or
            @($excluded.configurations).Count -ne 1 -or $excluded.configurations[0] -cne 'upstream-test') {
            throw 'T transform exclusion identifies another source or configuration'
        }
        Assert-TTransformReplacement -Change $change -Exclusion $excluded
        $seen[$change.exclusion_id] = $true
    }
    $bytes = Get-ConformancePatchedBytes -SourceBytes $sourceBytes -Replacements @($Specification.replacements)
    $hash = Get-ConformanceHash $bytes
    if ($Specification.output_sha256 -cne $hash) { throw 'T transform exact generated hash differs' }
    $accepted = $Specification.review.status -ceq 'accepted'
    if (-not $accepted -and -not $AllowUnreviewedDiagnostics) { throw 'T transform lacks independent semantic approval' }
    if ($accepted) {
        $review = $Specification.review
        if ([string]::IsNullOrWhiteSpace([string]$review.author) -or
            [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer) {
            throw 'T transform author cannot approve their own mapping'
        }
        $approvalPath = Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
        $approval = Get-Content -LiteralPath $approvalPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($approval.schema_version -ne 1 -or $approval.kind -cne 't-private-transform-approval' -or
            $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
            $approval.decision -cne 'accepted' -or @($approval.decisions).Count -ne @($Specification.replacements).Count) {
            throw 'T transform semantic approval identity or decision set differs'
        }
        foreach ($field in @('id','target','reference_revision','source','source_sha256','configuration','exclusion_policy_sha256','output_sha256')) {
            if ($approval.transform[$field] -cne $Specification[$field]) { throw "T transform approved identity differs: $field" }
        }
        foreach ($change in $Specification.replacements) {
            $decision = @($approval.decisions | Where-Object id -CEQ $change.id)
            if ($decision.Count -ne 1 -or $decision[0].decision -cne 'accepted' -or
                [string]::IsNullOrWhiteSpace([string]$decision[0].rationale) -or
                $decision[0].private_only -isnot [bool] -or -not $decision[0].private_only -or
                $decision[0].preserves_public_assertions -isnot [bool] -or -not $decision[0].preserves_public_assertions) {
                throw 'T transform patch lacks accepted private-only semantic review'
            }
            foreach ($field in @('exclusion_id','start_byte','length_bytes','source_sha256')) {
                if ($decision[0][$field] -cne $change[$field]) { throw 'T transform approved patch span differs' }
            }
            if ($decision[0].replacement_sha256 -cne
                (Get-ConformanceHash ([Text.UTF8Encoding]::new($false,$true).GetBytes($change.replacement)))) {
                throw 'T transform approved replacement bytes differ'
            }
        }
        $narrative = $approval.review_evidence
        $narrativePath = Resolve-ReviewedFile -Root $Root -Path $narrative.path -Sha256 $narrative.sha256
        $evidence = Get-Content -LiteralPath $narrativePath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
        if ($evidence.reviewer -cne $review.reviewer -or $evidence.decision -cne 'accepted' -or
            $evidence.transform_id -cne $Specification.id -or
            [string]::IsNullOrWhiteSpace([string]$evidence.public_assertion_preservation)) {
            throw 'T transform independent semantic narrative differs'
        }
    }
    return @{bytes=$bytes;sha256=$hash;source=$Specification.source;source_sha256=$Specification.source_sha256;
        id=$Specification.id;disposition='reviewed-t-adapted';diagnostic_only=(-not $accepted);
        review_status=$(if($accepted){'accepted'}else{'pending'});excluded_obligations=@($seen.Keys | Sort-Object)}
}

function Resolve-ConformanceObservation {
    param([string] $Root, [Collections.IDictionary] $Identity)
    # Runtime applicability evidence lives in captured reports, not arbitrary
    # host paths. Rebase the reports subtree when replaying downloaded bundles.
    $name = $Identity.path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($name)) {
        $offset = $name.LastIndexOf('/reports/',[StringComparison]::Ordinal)
        if ($offset -lt 0) { throw 'Transform observation is outside reports' }
        $name = $name.Substring($offset + 1)
    }
    if (-not $name.StartsWith('reports/',[StringComparison]::Ordinal)) { throw 'Transform observation is outside reports' }
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $path = [IO.Path]::GetFullPath((Join-Path $fullRoot $name))
    $relative = [IO.Path]::GetRelativePath($fullRoot,$path)
    if ($relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
        [IO.Path]::IsPathRooted($relative) -or $Identity.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Identity.sha256) {
        throw 'Transform observation path or hash differs'
    }
    return $path
}

function Assert-ConformanceNativeApplicability {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][string] $ArtifactRoot,
          [Parameter(Mandatory)][Collections.IDictionary] $Identity,
          [Parameter(Mandatory)][Collections.IDictionary] $Specification,
          [Parameter(Mandatory)][string] $ManifestSha256,
          [Parameter(Mandatory)][string] $Configuration,
          [Parameter(Mandatory)][string] $Platform,
          [Parameter(Mandatory)][string] $Revision,
          [switch] $RequireRuntimeEvidence)
    $path = Resolve-ConformanceObservation -Root $ArtifactRoot -Identity $Identity
    $proof = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($proof.schema_version -ne 1 -or $proof.kind -cne 'native-platform-applicability' -or
        $proof.reference_revision -cne $script:TransformReference -or $proof.repository_revision -cne $Revision -or
        $proof.mapping_id -cne $Specification.id -or $proof.mapping_sha256 -cne $ManifestSha256 -or
        $proof.source -cne $Specification.source -or $proof.source_sha256 -cne $Specification.source_sha256 -or
        $proof.configuration -cne $Configuration -or $proof.platform -cne $Platform -or
        $proof.synthetic_fixture -isnot [bool] -or
        @($proof.observations).Count -eq 0) { throw 'Native applicability identity differs or lacks C observations' }
    if ($RequireRuntimeEvidence -and $proof.synthetic_fixture) { throw 'Synthetic native applicability is not runtime evidence' }
    $runtimeVerified = -not $proof.synthetic_fixture
    $review = $proof.review
    if ($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$review.author) -or
        [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer) {
        throw 'Native applicability requires independent semantic review'
    }
    $approvalPath = Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval = Get-Content -LiteralPath $approvalPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($approval.schema_version -ne 1 -or $approval.kind -cne 'native-platform-applicability-approval' -or
        $approval.decision -cne 'accepted' -or $approval.author -cne $review.author -or
        $approval.reviewer -cne $review.reviewer) { throw 'Native applicability approval identity differs' }
    foreach ($field in @('reference_revision','repository_revision','mapping_id','mapping_sha256','source','source_sha256','configuration','platform')) {
        if ($approval[$field] -cne $proof[$field]) { throw 'Native applicability approved source or context differs' }
    }
    $encoded = (ConvertTo-Json -InputObject @($proof.observations) -Depth 64 -Compress)
    if ($approval.observations_sha256 -cne (Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes($encoded)))) {
        throw 'Native applicability approved observation bindings differ'
    }
    $seen = @{}; $covered = @{}
    foreach ($observation in $proof.observations) {
        if ($observation.id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or $seen.ContainsKey($observation.id) -or
            [string]::IsNullOrWhiteSpace([string]$observation.native_limitation) -or
            @($observation.source_spans).Count -eq 0 -or @($observation.stdout_required).Count -eq 0) {
            throw 'Native applicability lacks a distinct source-linked C invariant'
        }
        $seen[$observation.id] = $true
        foreach ($span in $observation.source_spans) {
            $matched = @($Specification.replacements | Where-Object id -CEQ $span.replacement_id)
            if ($matched.Count -ne 1 -or $span.start_byte -ne $matched[0].start_byte -or
                $span.length_bytes -ne $matched[0].length_bytes -or $span.source_sha256 -cne $matched[0].source_sha256) {
                throw 'Native applicability original source span differs'
            }
            $covered[$span.replacement_id] = $true
        }
        $reportPath = Resolve-ConformanceObservation -Root $ArtifactRoot -Identity $observation.original_c_report
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
        if ($report.synthetic_fixture -isnot [bool] -or ($RequireRuntimeEvidence -and $report.synthetic_fixture)) {
            throw 'Synthetic or unidentified native C observation is not runtime evidence'
        }
        if ($report.synthetic_fixture) { $runtimeVerified = $false }
        $sourceName = [IO.Path]::GetFileName($Specification.source)
        $original = @($report.fixture_records | Where-Object path -CEQ $sourceName)
        if ($report.target -cne 'ReferenceC' -or $report.execution_disposition -cne 'unchanged' -or
            $report.reference_revision -cne $script:TransformReference -or $report.repository_revision -cne $Revision -or
            $report.repository_dirty -ne $false -or $report.host.platform -cne $Platform -or
            $report.requested_configuration -cne $Configuration -or $report.reference_tree_verified -ne $true -or
            $report.configuration_verified -ne $true -or $report.setup_error -or
            $original.Count -ne 1 -or $original[0].sha256 -cne $Specification.source_sha256 -or
            $report.process.executable_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $report.process.exit_code -ne $observation.expected_exit_code -or $report.process.timed_out -ne $false -or
            $report.process.capture_exceeded -ne $false -or $report.process.pipe_drain_failed -ne $false -or
            $report.process.process_tree_kill_error -or $report.process.abnormal_exit_kind) {
            throw 'Native applicability is not matching original C execution'
        }
        [void](Test-ConformanceConfiguration -Observed $report.observed_configuration -Configuration $Configuration `
            -Target ReferenceC -AllocatorLimitBytes $report.allocator_limit_bytes)
        foreach ($stream in @('stdout','stderr')) {
            $capture = Resolve-ConformanceObservation -Root $ArtifactRoot -Identity @{
                path=$report.process["${stream}_path"];sha256=$report.process["${stream}_sha256"]}
            if ((Get-Item -LiteralPath $capture).Length -ne $report.process["${stream}_bytes"]) {
                throw 'Native applicability captured byte count differs'
            }
            $text = [IO.File]::ReadAllText($capture)
            $expectations = if ($stream -ceq 'stdout') { @($observation.stdout_required) } else { @($observation.stderr_expected) }
            foreach ($expectation in $expectations) {
                if ($expectation.count -lt 1 -or -not $expectation.pattern.StartsWith('^') -or
                    -not $expectation.pattern.EndsWith('$') -or
                    [regex]::Matches($text,'(?m)' + $expectation.pattern).Count -ne $expectation.count) {
                    throw 'Native applicability measured C witness differs'
                }
            }
            if ($stream -ceq 'stderr') {
                foreach ($line in ($text -split '\r\n|\n|\r' | Where-Object { $_ -ne '' })) {
                    if (@($expectations | Where-Object { [regex]::IsMatch($line,$_.pattern) }).Count -eq 0) {
                        throw 'Native applicability has unreviewed C stderr'
                    }
                }
            }
        }
    }
    if ($covered.Count -ne @($Specification.replacements).Count) { throw 'Native applicability does not cover every transformed invariant' }
    $narrative = $approval.review_evidence
    $narrativePath = Resolve-ReviewedFile -Root $Root -Path $narrative.path -Sha256 $narrative.sha256
    $decision = Get-Content -LiteralPath $narrativePath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    if ($decision.reviewer -cne $review.reviewer -or $decision.decision -cne 'accepted' -or
        [string]::IsNullOrWhiteSpace([string]$decision.source_linked_c_applicability)) {
        throw 'Native applicability lacks independent source-linked rationale'
    }
    $proof['runtime_verified'] = $runtimeVerified
    return $proof
}

Export-ModuleMember -Function Get-ConformancePatchedBytes, Get-ConformanceEquivalentReplay,
    Get-ConformanceTReplay, Resolve-ConformanceObservation, Assert-ConformanceNativeApplicability
