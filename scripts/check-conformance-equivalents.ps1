Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $PSScriptRoot 'New-ConformanceEquivalent.ps1'
$manifest = Join-Path $root 'tests/conformance/equivalents/gc-ada-instrumented.json'
$fixture = Join-Path $root 'reports/equivalent-fixtures'
[void][IO.Directory]::CreateDirectory($fixture)
$output = Join-Path $fixture 'gc.lua'
$encoding = [Text.UTF8Encoding]::new($false)
$originalHash = (Get-FileHash (Join-Path $root 'references/lua/testes/gc.lua')).Hash

function Reject([string] $Name, [scriptblock] $Action, [string] $Message) {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Message) { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Accepted invalid equivalent: $Name" }
    Write-Output "PASS: equivalent rejects $Name"
}
Reject 'pending review' { & $generator -Manifest $manifest -Output $output } 'independent review'
$cases = @(
    @{Name='unknown disposition'; Mutate={param($s) $s | Add-Member -NotePropertyName disposition -NotePropertyValue 'unchanged' -Force}; Error='equivalent disposition'},
    @{Name='source drift'; Mutate={param($s) $s.source_sha256='0'*64}; Error='source hash'},
    @{Name='span drift'; Mutate={param($s) $s.replacements[0].source_sha256='0'*64}; Error='span hash'},
    @{Name='overlap'; Mutate={param($s) $s.replacements[1].start_byte=$s.replacements[0].start_byte}; Error='overlapping'},
    @{Name='missing counterpart'; Mutate={param($s) $s.replacements[0].counterpart_tests=@()}; Error='counterpart'},
    @{Name='same reviewer'; Mutate={param($s) $s.review.status='accepted'; $s.review.reviewer=$s.review.author; $s.review.artifact='invalid'}; Error='independent equivalent review'}
)
foreach ($case in $cases) {
    $spec = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    & $case.Mutate $spec
    $invalid = Join-Path $fixture 'invalid.json'
    [IO.File]::WriteAllText($invalid, ($spec | ConvertTo-Json -Depth 10), $encoding)
    Reject $case.Name { & $generator -Manifest $invalid -Output $output -AllowUnreviewedDiagnostics } $case.Error
}
Reject 'reference output' {
    & $generator -Manifest $manifest -Output (Join-Path $root 'references/lua/testes/gc.lua') -AllowUnreviewedDiagnostics
} 'must not modify references'
$result = & $generator -Manifest $manifest -Output $output -AllowUnreviewedDiagnostics | ConvertFrom-Json
if (-not $result.diagnostic_only -or $result.review_status -ne 'pending' -or
    $result.disposition -ne 'ada-internal-equivalent') {
    throw 'Diagnostic equivalent was mislabeled'
}
if ((Get-FileHash (Join-Path $root 'references/lua/testes/gc.lua')).Hash -cne $originalHash) {
    throw 'Reference bytes changed'
}
Write-Output 'PASS: equivalent preserves source bytes and diagnostic status'
