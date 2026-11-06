param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('development', 'validation', 'release')]
    [string] $Profile = 'validation',
    [ValidateSet('default', 'upstream-test')]
    [string] $Configuration = 'default'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$savedPath = $env:PATH
$savedLdPath = $env:LD_LIBRARY_PATH
$savedDyldPath = $env:DYLD_LIBRARY_PATH
$savedArchive = $env:LUA_ADA_ABI_RUNTIME_ARCHIVE
$configurationPart = if ($Configuration -eq 'default') { '' } else { 'upstream-test/' }
$reportDirectory = Join-Path $projectRoot ('reports/core-image/' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $reportDirectory -Force
$records = [Collections.Generic.List[object]]::new()
$scenarios = @("-XLUA_ADA_LIBRARY_TYPE=$LibraryType",
    "-XLUA_ADA_CONFIGURATION=$Configuration")

function Invoke-Build {
    param([string[]] $Arguments)
    & alr @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Core-image build failed: $($Arguments -join ' ')" }
}

function Invoke-Consumer {
    param([string] $Name, [string] $Executable, [string] $Marker)
    # Redirect both pipes before waiting so even an unexpected diagnostic flood
    # cannot deadlock the driver. Empty stderr is part of this consumer contract.
    $start = [Diagnostics.ProcessStartInfo]::new('alr')
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('exec', '--', $Executable)) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "Cannot start $Name consumer" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(60000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $reportDirectory "$Name.stdout"), $stdout)
    [IO.File]::WriteAllText((Join-Path $reportDirectory "$Name.stderr"), $stderr)
    $record = [ordered]@{ name = $Name; executable = $Executable;
        executable_sha256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant();
        exit_code = $process.ExitCode; timed_out = $timedOut;
        profile = $Profile; library_type = $LibraryType;
        configuration = $Configuration }
    $records.Add($record)
    if ($timedOut -or $process.ExitCode -ne 0 -or $stderr.Length -ne 0 -or
        -not $stdout.Contains($Marker)) {
        throw "Core-image consumer failed: $Name; see $reportDirectory"
    }
    Write-Output "PASS: $Name ($Profile/$LibraryType/$Configuration)"
    $process.Dispose()
}

try {
    Set-Location $projectRoot
    # Select the requested generated profile through Alire, never by editing
    # generated configuration. All subsequent projects import this same root.
    Invoke-Build (@('-n', 'build', "--$Profile", '--') + $scenarios)
    if ($IsMacOS) {
        $archive = & alr exec -- gcc '-print-file-name=adalib/libgnat.a'
        if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath (($archive -join '').Trim()) -PathType Leaf)) {
            throw 'Cannot locate the selected GNAT archive for the C-only main'
        }
        $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = ($archive -join '').Trim()
    }
    Invoke-Build (@('exec', '--', 'gprbuild', '-P', 'c_api/consumer.gpr', '-p') + $scenarios)
    Invoke-Build (@('exec', '--', 'gprbuild', '-P', 'c_api/image_consumer.gpr', '-p') + $scenarios)

    $runtimeDirectory = Join-Path $projectRoot "lib/$configurationPart$Profile/$LibraryType"
    $env:PATH = $runtimeDirectory + [IO.Path]::PathSeparator + $savedPath
    $env:LD_LIBRARY_PATH = $runtimeDirectory + [IO.Path]::PathSeparator + $savedLdPath
    $env:DYLD_LIBRARY_PATH = $runtimeDirectory + [IO.Path]::PathSeparator + $savedDyldPath
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    Invoke-Consumer 'c-api' (Join-Path $projectRoot "build/c-api/bin/$configurationPart$Profile/$LibraryType/c_api_consumer$suffix") 'PASS: real Ada C API bootstrap consumer'
    Invoke-Consumer 'mixed' (Join-Path $projectRoot "build/c-api/image/bin/$configurationPart$Profile/$LibraryType/lua-core_image_check$suffix") 'CORE IMAGE ADA+C OK'
    Invoke-Consumer 'c-startup' (Join-Path $projectRoot "build/c-api/image/bin/$configurationPart$Profile/$LibraryType/c_image_client$suffix") 'CORE IMAGE C STARTUP OK'
    # Old ignored products can remain after the library rename. Hash only the
    # selected lua image, never stale lua_ada archives or unrelated ALI files.
    $libraries = @(Get-ChildItem -LiteralPath $runtimeDirectory -File |
        Where-Object { $_.Name -match '^(lib)?lua(\.dll(\.a)?|\.a|\.so(\.[0-9.]+)?|\.dylib)$' } |
        ForEach-Object {
        [ordered]@{ file = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    if ($libraries.Count -eq 0) { throw 'Selected root lua image is absent' }
    [ordered]@{ profile = $Profile; library_type = $LibraryType;
        configuration = $Configuration; consumers = $records.ToArray();
        library_files = $libraries } | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $reportDirectory 'result.json') -Encoding utf8
    Write-Output 'PASS: one production interpreter image; Ada/C state, pool, allocator and startup checks'
}
finally {
    # Even a failed run retains which processes actually ran. A missing result
    # file is a failed/incomplete campaign, never a successful skipped consumer.
    $records.ToArray() | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $reportDirectory 'processes.json') -Encoding utf8
    Set-Location $originalLocation
    $env:PATH = $savedPath
    $env:LD_LIBRARY_PATH = $savedLdPath
    $env:DYLD_LIBRARY_PATH = $savedDyldPath
    $env:LUA_ADA_ABI_RUNTIME_ARCHIVE = $savedArchive
}
exit 0
