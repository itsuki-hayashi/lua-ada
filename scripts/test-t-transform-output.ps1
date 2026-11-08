param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$directory=Join-Path $root ('reports/t-output-guards/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$manifest=Join-Path $root ('tests/conformance/targets/remaining-upstream-compatibility/'+
    'code-private-optimizer-v3.transform.json')
$generator=Join-Path $PSScriptRoot 'New-ConformanceTTransform.ps1'
function Run([string]$Target,[string]$Name){
    Invoke-ConformanceProcess -Executable (Get-Command pwsh).Source -Arguments @(
        '-NoProfile','-File',$generator,'-Manifest',$manifest,'-Output',$Target) `
        -Directory $root -OutputPrefix (Join-Path $directory $Name) -TimeoutSeconds 60
}
$output=Join-Path $directory 'code.lua'
$created=Run $output 'new'
if($created.exit_code -ne 0 -or $created.stderr_bytes -ne 0 -or
    (Get-FileHash $output).Hash.ToLowerInvariant() -cne
        '676304c019ee3afe8796da7ddfaf8f14cba43c2c49332d96f19b3f4c84211fe0'){
    throw 'Approved transform did not create its exact fresh output'
}
Write-Output 'T OUTPUT GUARD PASS: approved bytes create a fresh disposable artifact'
$before=(Get-FileHash $output).Hash
$again=Run $output 'existing'
if($again.exit_code -eq 0 -or (Get-FileHash $output).Hash -cne $before -or
    [IO.File]::ReadAllText($again.stderr_path) -notmatch 'new disposable reports artifact'){
    throw 'An existing observation was overwritten or accepted'
}
Write-Output 'T OUTPUT GUARD PASS: existing source bytes remain immutable'
$source=Join-Path $root 'references/lua/testes/code.lua'
$before=(Get-FileHash $source).Hash
$pinned=Run $source 'pinned'
if($pinned.exit_code -eq 0 -or (Get-FileHash $source).Hash -cne $before -or
    [IO.File]::ReadAllText($pinned.stderr_path) -notmatch 'new disposable reports artifact'){
    throw 'Pinned source was overwritten or accepted as output'
}
Write-Output 'T OUTPUT GUARD PASS: pinned reference bytes cannot be an output'
Write-Output 'PASS:3 actual generator process guards; no Lua execution or coverage authority'
