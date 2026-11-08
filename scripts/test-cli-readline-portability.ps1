param([Parameter(Mandatory)][string]$Compiler)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$Compiler=(Resolve-Path -LiteralPath $Compiler).Path
$directory=Join-Path $root ('reports/readline-types/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$rows=@()
foreach($returnType in @('int','void')){
    $include=Join-Path $directory $returnType
    [void][IO.Directory]::CreateDirectory((Join-Path $include 'readline'))
    # These are deliberately minimal first-party type fixtures, not Apple/GNU
    # SDK headers. Compile-only checks cannot establish either platform build.
    [IO.File]::WriteAllText((Join-Path $include 'readline/readline.h'),
        "extern char *rl_readline_name;`nchar *readline(const char *);`n")
    [IO.File]::WriteAllText((Join-Path $include 'readline/history.h'),
        "$returnType add_history(const char *);`n")
    foreach($testCrate in @($false,$true)){
        $arguments=@('-std=c99','-Wall','-Wextra','-Werror','-pedantic','-fsyntax-only',
            '-DLUA_ADA_CLI_MACOS','-I',$include,'-I',(Join-Path $root 'c_api/include/api'))
        if($testCrate){$arguments+='-DLUA_ADA_TEST_BUILD_PROFILE=validation'}
        $arguments+=Join-Path $root 'cli/shared/lua_ada_cli_readline.c'
        $process=Invoke-ConformanceProcess -Executable $Compiler -Arguments $arguments `
            -Directory $root -OutputPrefix (Join-Path $directory ($returnType+'-'+$testCrate)) -TimeoutSeconds 30
        $rows+=@{history_return_type=$returnType;test_crate=$testCrate;process=$process}
    }
}
$report=@{schema_version=1;kind='readline-function-type-compile-regression';synthetic_headers=$true;
    runtime_acceptance=$false;coverage_authority=$false;native_sdk_validation=$false;processes=$rows}
[IO.File]::WriteAllText((Join-Path $directory 'result.json'),($report|ConvertTo-Json -Depth 16)+"`n")
foreach($row in $rows){
    if($row.process.exit_code -ne 0 -or $row.process.stderr_bytes -ne 0 -or
        $row.process.timed_out -or $row.process.capture_exceeded -or $row.process.pipe_drain_failed){
        throw "Readline callback type regression: $directory"
    }
}
Write-Output "PASS:4 strict C callback-type compile cases; synthetic declarations, no native SDK/runtime credit; $directory"
