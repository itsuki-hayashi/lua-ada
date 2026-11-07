param(
    [Parameter(Mandatory)][string] $Manifest,
    [Parameter(Mandatory)][string] $Output,
    [switch] $AllowUnreviewedDiagnostics
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
$root = Split-Path -Parent $PSScriptRoot
$spec = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ($spec.schema_version -ne 1) { throw 'Unsupported equivalent manifest' }
$disposition = if ($spec.PSObject.Properties['disposition']) { $spec.disposition }
    else { 'ada-internal-equivalent' }
if ($disposition -notin @('ada-internal-equivalent', 'native-platform-equivalent')) {
    throw 'Unsupported equivalent disposition'
}
if ($spec.review.status -ne 'accepted') {
    if (-not $AllowUnreviewedDiagnostics) { throw 'Equivalent lacks independent review' }
} elseif ([string]::IsNullOrWhiteSpace($spec.review.author) -or
          [string]::IsNullOrWhiteSpace($spec.review.reviewer) -or
          $spec.review.author -ceq $spec.review.reviewer -or
          [string]::IsNullOrWhiteSpace($spec.review.artifact)) {
    throw 'Invalid independent equivalent review'
}
$source = [IO.Path]::GetFullPath((Join-Path $root $spec.source))
$target = [IO.Path]::GetFullPath($Output)
$referenceRoot = [IO.Path]::GetFullPath((Join-Path $root 'references')) + [IO.Path]::DirectorySeparatorChar
if ($target.StartsWith($referenceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Equivalent output must not modify references'
}
$bytes = [IO.File]::ReadAllBytes($source)
function Get-Hash([byte[]] $Data) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Data)).ToLowerInvariant()
}
if ((Get-Hash $bytes) -cne $spec.source_sha256) { throw 'Equivalent source hash mismatch' }
$encoding = [Text.UTF8Encoding]::new($false, $true)
$stream = [IO.MemoryStream]::new()
$cursor = 0
try {
    foreach ($change in @($spec.replacements | Sort-Object start_byte)) {
        $start = [int]$change.start_byte
        $length = [int]$change.length_bytes
        if ($start -lt $cursor -or $length -le 0 -or $start -gt $bytes.Length - $length) {
            throw "Invalid or overlapping equivalent span: $($change.id)"
        }
        $span = [byte[]]::new($length)
        [Array]::Copy($bytes, $start, $span, 0, $length)
        if ((Get-Hash $span) -cne $change.source_sha256) {
            throw "Equivalent span hash mismatch: $($change.id)"
        }
        if ([string]::IsNullOrWhiteSpace($change.invariant) -or
            @($change.counterpart_tests).Count -eq 0) {
            throw "Equivalent lacks invariant/counterpart: $($change.id)"
        }
        $stream.Write($bytes, $cursor, $start - $cursor)
        $replacement = $encoding.GetBytes([string]$change.replacement)
        $stream.Write($replacement, 0, $replacement.Length)
        $cursor = $start + $length
    }
    $stream.Write($bytes, $cursor, $bytes.Length - $cursor)
    $result = $stream.ToArray()
    if ($spec.review.status -eq 'accepted') {
        $reviewedSpec = $spec | ConvertTo-Json -Depth 64 | ConvertFrom-Json -AsHashtable -Depth 64
        Assert-EquivalentReviewBinding -Root $root -Specification $reviewedSpec -GeneratedSha256 (Get-Hash $result)
    }
    [IO.File]::WriteAllBytes($target, $result)
    [ordered]@{
        id=$spec.id
        disposition=$disposition
        review_status=$spec.review.status
        diagnostic_only=($spec.review.status -ne 'accepted')
        source_sha256=$spec.source_sha256
        output_sha256=(Get-Hash $result)
        output=$target
    } | ConvertTo-Json -Compress
} finally { $stream.Dispose() }
