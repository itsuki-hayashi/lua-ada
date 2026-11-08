param([Parameter(Mandatory)][string]$Interpreter,[string]$RuntimeDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1') -Force
$directory=Join-Path $root ('reports/cli-transport-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$inputPath=Join-Path $directory 'large.input'
[IO.File]::WriteAllBytes($inputPath,[byte[]]::new(1048576))
$executable=(Resolve-Path $Interpreter).Path
$environment=@{}
if($RuntimeDirectory -ne ''){
    foreach($name in @('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH')){
        $environment[$name]=[IO.Path]::GetFullPath($RuntimeDirectory)+[IO.Path]::PathSeparator+[Environment]::GetEnvironmentVariable($name)
    }
}
foreach($observe in @($false,$true)){
    # Two tiny authored Lua transport processes, unrelated to upstream source
    # acceptance: exit without reading the supplied megabyte of input.
    $p=Invoke-ConformanceProcess -Executable $executable -Arguments @('-e',
        'io.write("CLOSED");os.exit(37,true)') -Directory $root `
        -OutputPrefix (Join-Path $directory ([string]$observe)) -TimeoutSeconds 10 `
        -StandardInputPath $inputPath -ObserveEarlyInputClose:$observe -Environment $environment
    if(-not $p.input_write_failed -or -not $p.pipe_drain_failed -or $p.standard_input.write_completed -or
        [string]::IsNullOrWhiteSpace($p.standard_input.write_error) -or $p.standard_input.eof_sent -or
        -not $p.standard_input.close_requested -or
        $p.early_input_close_requested -ne $observe){throw 'Input failure was not truthfully preserved'}
    if($observe -and ($p.output_drain_failed -or $p.exit_code -ne 37 -or
        [IO.File]::ReadAllText($p.stdout_path) -cne 'CLOSED' -or $p.stderr_bytes -ne 0)){
        throw 'Observed early input close corrupted actual output or status'
    }
    if((Get-ConformanceOutcome -Process $p).status -cne 'capture-failed'){
        throw 'A generic process outcome accepted deliberately incomplete input'
    }
    Write-Output "CLI TRANSPORT PASS: early input close observation=$observe remains a generic failed pipe"
}
Write-Output 'PASS: 2 actual tiny transport processes; no upstream fixture or runtime acceptance'
