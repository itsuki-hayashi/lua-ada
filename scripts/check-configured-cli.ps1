param([Parameter(Mandatory)][string]$Interpreter,
      [Parameter(Mandatory)][string]$ReferenceInterpreter,
      [ValidateSet('default','upstream-test')][string]$Configuration='default',
      [ValidateSet('development','validation','release')][string]$Profile='validation',
      [ValidateSet('static','static-pic','relocatable')][string]$LibraryType='static',
      [Parameter(Mandatory)][string]$Report,[string]$AdaReport='',
      [string]$ReferenceLibraryDirectory='', [string]$RuntimeDirectory='',
      [string]$ReferenceDefaultInterpreter='', [string]$ReferenceDefaultLibraryDirectory='',
      [switch]$DevelopmentObservation)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CliFixtureEvidence.psm1')
$Report=[IO.Path]::GetFullPath($Report)
$directory=Split-Path -Parent $Report
[void][IO.Directory]::CreateDirectory($directory)
$arguments=@{Configuration=$Configuration;Profile=$Profile;LibraryType=$LibraryType}
$nativeObservationArguments=@{CollectAllObservations=$DevelopmentObservation;DevelopmentObservation=$DevelopmentObservation}
if($ReferenceLibraryDirectory -eq ''){$ReferenceLibraryDirectory=Join-Path $root "build/conformance/$Configuration/lib"}
if($AdaReport -eq ''){
    $AdaReport=Join-Path $directory 'ada.json'
    & (Join-Path $PSScriptRoot 'check-cli.ps1') -Interpreter $Interpreter -Report $AdaReport -RuntimeDirectory $RuntimeDirectory @arguments
    if($LASTEXITCODE -ne 0){throw 'Actual full CLI host campaign failed'}
}
$nativeReport=Join-Path $directory 'native.json'
$saved=@{}
foreach($name in @('PATH','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH')){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
try{
    if($ReferenceLibraryDirectory -ne ''){
        foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,([IO.Path]::GetFullPath($ReferenceLibraryDirectory)+[IO.Path]::PathSeparator+$saved[$name]))}
    }
    & (Join-Path $PSScriptRoot 'check-cli.ps1') -Interpreter $ReferenceInterpreter -PromptProtocol -RuntimeRole ReferenceC -Report $nativeReport -RuntimeDirectory $ReferenceLibraryDirectory @arguments @nativeObservationArguments
    if($LASTEXITCODE -ne 0){throw 'Actual native CLI prompt campaign failed'}
}finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name])}}
$ada=Get-Content $AdaReport -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$native=Get-Content $nativeReport -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$pair=@{schema_version=1;kind='host-cli-fixture-pair';synthetic_fixture=$false;
    context=$ada.context;repository_revision=$ada.repository_revision;repository_dirty=$ada.repository_dirty;
    runtime_acceptance=$false;coverage_authority=$false;ada=$ada;native=$native}
if($Configuration -ceq 'upstream-test'){
    $suffix=if($IsWindows){'.exe'}else{''}
    if($ReferenceDefaultInterpreter -eq ''){$ReferenceDefaultInterpreter=Join-Path $root "build/conformance/default/bin/lua$suffix"}
    if($ReferenceDefaultLibraryDirectory -eq ''){$ReferenceDefaultLibraryDirectory=Join-Path $root 'build/conformance/default/lib'}
    $ordinaryReport=Join-Path $directory 'native-default.json'
    try{
        foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,([IO.Path]::GetFullPath($ReferenceDefaultLibraryDirectory)+[IO.Path]::PathSeparator+$saved[$name]))}
        & (Join-Path $PSScriptRoot 'check-cli.ps1') -Interpreter $ReferenceDefaultInterpreter -PromptProtocol -RuntimeRole ReferenceC `
            -Configuration default -Profile $Profile -LibraryType $LibraryType -Report $ordinaryReport `
            -RuntimeDirectory $ReferenceDefaultLibraryDirectory @nativeObservationArguments
        if($LASTEXITCODE -ne 0){throw 'Actual native default no-close counterpart failed'}
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name])}}
    $pair['native_default']=Get-Content $ordinaryReport -Raw|ConvertFrom-Json -AsHashtable -Depth 48
}
[IO.File]::WriteAllText($Report,(ConvertTo-Json -InputObject $pair -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
$null=Assert-CliFixturePair -Root $root -Report $pair -Interpreter (Resolve-Path $Interpreter).Path
Write-Output 'OBSERVED: full112 CLI host operations and native prompt counterparts; native test diagnostics remain separate; runtime acceptance=False'
