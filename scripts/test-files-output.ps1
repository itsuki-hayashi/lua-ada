$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/FilesOutput.psm1" -Force
$missing = "sh: not-to-be-found-command: command not found`n"
$signal = "sh: line 1: 123 Hangup: 1               sh -c 'kill -s HUP `$`$'`n"
$sample = $missing * 2 + $signal * 4 + $missing * 2 + $signal * 2
$normalized = Convert-MacFilesError $sample
if ($normalized -cne (Convert-MacFilesError ($sample.Replace('123', '456')))) {
    throw 'PID normalization failed'
}
$cases = @(
    $sample.Replace('Hangup: 1', 'Hangup: 2'),
    $sample.Replace('HUP', 'KILL'),
    $sample.Replace('sh: line 1:', 'bash: line 1:'),
    $sample.Replace('123', 'abc'),
    $sample.Replace('123', '0'),
    $sample.Substring($signal.Length),
    ($sample + $signal),
    ($sample + "unexpected warning`n"),
    ($sample.Replace($missing, ''))
)
foreach ($text in $cases) {
    $rejected = $false
    try { $null = Convert-MacFilesError $text } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid shell output accepted' }
}
Write-Output 'PASS: 10 macOS shell output regressions; no runtime acceptance'
