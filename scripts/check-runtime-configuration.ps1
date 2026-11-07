param(
    [Parameter(Mandatory)][string] $Probe,
    [Parameter(Mandatory)][ValidateSet('default','upstream-test')]
    [string] $Configuration,
    [string] $RuntimeDirectory = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/runtime-configuration/' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$environment = @{}
if ($RuntimeDirectory -ne '') {
    $runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
    $environment.PATH = $runtime + [IO.Path]::PathSeparator + $env:PATH
    $environment.LD_LIBRARY_PATH = $runtime + [IO.Path]::PathSeparator + $env:LD_LIBRARY_PATH
    $environment.DYLD_LIBRARY_PATH = $runtime + [IO.Path]::PathSeparator + $env:DYLD_LIBRARY_PATH
}
$result = Invoke-ConformanceProcess -Executable (Resolve-Path -LiteralPath $Probe).Path `
    -Directory $root -OutputPrefix (Join-Path $directory 'probe') -TimeoutSeconds 60 `
    -Environment $environment
if ($result.exit_code -ne 0 -or $result.stderr_bytes -ne 0 -or $result.timed_out -or
    $result.abnormal_exit_kind -or $result.capture_exceeded -or $result.pipe_drain_failed -or
    $result.process_tree_kill_error) { throw "Runtime configuration probe failed; see $directory" }
$observed = Get-Content -LiteralPath $result.stdout_path -Raw | ConvertFrom-Json -AsHashtable
$instrumented = $Configuration -eq 'upstream-test'
$expected = [ordered]@{
    configuration=$Configuration
    configured_stack_slots=$(if ($instrumented) { 68000 } else { 1000000 })
    configured_c_calls=$(if ($instrumented) { 180 } else { 200 })
    configured_aux_buffer_bytes=$(if ($instrumented) { 23 } else { 1024 })
    compatible_global=(-not $instrumented)
    world_random32=$instrumented
    world_compat_math=$instrumented
    compatibility_exports=$(if ($instrumented) { 6 } else { 0 })
    reserved_global=$instrumented
}
foreach ($entry in $expected.GetEnumerator()) {
    if (-not $observed.Contains($entry.Key) -or $observed[$entry.Key] -cne $entry.Value) {
        throw "Runtime configuration mismatch: $Configuration/$($entry.Key); see $directory"
    }
}
# This narrow check deliberately does not identify itself as the complete
# conformance --conformance-config/T adapter handshake. It checks source-selected
# constants plus actual math registration, RNG-path selection and parser behavior.
$report=[ordered]@{configuration=$Configuration;observed=$observed;process=$result;
    scope='selected build constants and parser/math behavior; no T adapter claim'}
[IO.File]::WriteAllText((Join-Path $directory 'report.json'),
    (ConvertTo-Json -InputObject $report -Depth 10)+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "PASS: $Configuration selected constants and actual parser/math configuration"
