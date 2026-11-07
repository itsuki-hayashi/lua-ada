param(
    [Parameter(Mandatory)][string] $Executable,
    [ValidateSet('default','upstream-test')][string] $Configuration = 'default',
    [ValidateSet('development','validation','release')][string] $Profile = 'validation',
    [ValidateSet('static','static-pic','relocatable')][string] $LibraryType = 'static'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root ('reports/core-image/aunit-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$revision = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify AUnit revision' }
$changes = @(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect AUnit source state' }
$executable = (Resolve-Path -LiteralPath $Executable).Path
$prefix = if ($Configuration -eq 'default') { '' } else { 'upstream-test/' }
$suffix = if ($IsWindows) { '.exe' } else { '' }
$expected = [IO.Path]::GetFullPath((Join-Path $root "tests/bin/$prefix$LibraryType/test_runner$suffix"))
if ($executable -cne $expected) { throw 'AUnit executable is outside the selected build path' }
$probe = Join-Path (Split-Path -Parent $executable) "lua-configuration_probe$suffix"
$probeOut = Join-Path $directory 'configuration.stdout'
$probeErr = Join-Path $directory 'configuration.stderr'
# The sibling probe is built by the same test project and observes actual
# runtime compatibility behavior. Preserve its bytes rather than trusting the
# requested configuration label alone.
& alr exec -- $probe 1> $probeOut 2> $probeErr
if ($LASTEXITCODE -ne 0 -or (Get-Item $probeErr).Length -ne 0) { throw 'AUnit configuration probe failed' }
$probeValue = Get-Content -LiteralPath $probeOut -Raw | ConvertFrom-Json
if ($probeValue.configuration -cne $Configuration) { throw 'AUnit compiled configuration differs' }
$start = [Diagnostics.ProcessStartInfo]::new('alr')
$start.WorkingDirectory = Join-Path $root 'tests'
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($argument in @('exec','--',$executable)) { $start.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::new()
$process.StartInfo = $start
try {
    if (-not $process.Start()) { throw 'Cannot start AUnit evidence process' }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit(900000)
    if (-not $completed) { $process.Kill($true); $process.WaitForExit() }
    $stdout = $outTask.GetAwaiter().GetResult()
    $stderr = $errTask.GetAwaiter().GetResult()
    $outPath = Join-Path $directory 'aunit.stdout'
    $errPath = Join-Path $directory 'aunit.stderr'
    [IO.File]::WriteAllText($outPath,$stdout)
    [IO.File]::WriteAllText($errPath,$stderr)
    $runtime = Join-Path $root "lib/$prefix$Profile/$LibraryType"
    $libraries = @(Get-ChildItem -LiteralPath $runtime -File | Where-Object {
        $_.Name -match '^(lib)?lua(\.dll(\.a)?|\.a|\.so(\.[0-9.]+)?|\.dylib)$'
    } | ForEach-Object { @{file=$_.Name; sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()} })
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $root 'tests/src') -File | Where-Object {
        $_.Extension -in @('.adb','.ads')
    } | ForEach-Object { @{file='tests/src/' + $_.Name; sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()} })
    $record = [ordered]@{schema_version=1; repository_revision=$revision; repository_dirty=($changes.Count -ne 0);
        configuration=$Configuration; profile=$Profile; library_type=$LibraryType;
        platform=$(if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'});
        executable=$executable; executable_sha256=(Get-FileHash $executable).Hash.ToLowerInvariant();
        configuration_probe=@{executable=$probe; executable_sha256=(Get-FileHash $probe).Hash.ToLowerInvariant();
            stdout=$probeOut; stdout_sha256=(Get-FileHash $probeOut).Hash.ToLowerInvariant();
            stderr=$probeErr; stderr_sha256=(Get-FileHash $probeErr).Hash.ToLowerInvariant()};
        library_files=$libraries; sources=$sources; completed=$completed; exit_code=$process.ExitCode;
        stdout=$outPath; stdout_sha256=(Get-FileHash $outPath).Hash.ToLowerInvariant();
        stderr=$errPath; stderr_sha256=(Get-FileHash $errPath).Hash.ToLowerInvariant();
        scoped_acceptance=$false}
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'result.json') -Encoding utf8
    # Preserve the familiar full AUnit report in CI while retaining exact bytes
    # for later named-case replay. The expected warning belongs to one explicit
    # finalizer regression; any additional diagnostic fails this campaign.
    Write-Output $stdout
    $expectedError = "Lua warning: error in __gc ([string `"file-abort-test`"]:1: ordinary failure)`n"
    if (-not $completed -or $process.ExitCode -ne 0 -or $libraries.Count -eq 0 -or
        $stderr.Replace("`r`n","`n") -cne $expectedError -or
        $stdout -notmatch 'Total Tests Run:\s+([1-9][0-9]*)' -or
        $stdout -notmatch 'Failed Assertions:\s+0\s+Unexpected Errors:\s+0') {
        [Console]::Error.WriteLine($stderr)
        throw "AUnit evidence execution failed: $directory"
    }
    Write-Output "PASS: captured AUnit evidence ($Configuration/$Profile/$LibraryType)"
} finally { $process.Dispose() }
