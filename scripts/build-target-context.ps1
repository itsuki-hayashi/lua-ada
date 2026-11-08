param(
    [Parameter(Mandatory)][string] $Context,
    [string] $WitnessPolicy = '',
    [switch] $DevelopmentObservation,
    [switch] $PlanOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TargetContext.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
$plan = Get-TargetContextPlan -Root $root
$selected = @($plan.contexts | Where-Object context -CEQ $Context)
if ($selected.Count -ne 1) { throw 'Unknown target build context' }
$selected = $selected[0]
$hostPlatform = if ($IsWindows) {'windows'} elseif ($IsMacOS) {'macos'} else {'linux'}
if ($selected.platform -cne $hostPlatform -and -not $PlanOnly) { throw 'Target build context identifies another host' }
$configurationPart = if ($selected.configuration -ceq 'upstream-test') {'upstream-test/'} else {''}
$suffix = if ($selected.platform -ceq 'windows') {'.exe'} else {''}
$paths = @{ada_launcher="tests/bin/$configurationPart$($selected.library_type)/conformance_runner$suffix";
    c_oracle="build/conformance/$($selected.configuration)/bin/lua$suffix";
    ada_runtime="lib/$configurationPart$($selected.profile)/$($selected.library_type)";
    c_runtime="build/conformance/$($selected.configuration)/lib";
    compiler_support="reports/target-support/$($selected.id)"}
$scriptName = if ($selected.configuration -ceq 'upstream-test') {'check-instrumented.ps1'} else {'check.ps1'}
if ($PlanOnly) {
    @{context=$Context;script=$scriptName;paths=$paths;configuration=$selected.configuration;
        profile=$selected.profile;library_type=$selected.library_type;runtime_acceptance=$false;coverage_authority=$false} |
        ConvertTo-Json -Depth 12
    exit 0
}
$dirty = @(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Target context build requires a clean source checkout' }
Test-ConformanceReferenceTree -Root $root
$buildDirectory = Join-Path $root ('reports/target-builds/' + $selected.id)
if ($WitnessPolicy -eq '') {
    if ($DevelopmentObservation) {
        $proposals = Join-Path $buildDirectory 'author-proposals'
        $proposalArguments=@{OutputDirectory=$proposals}
        $compiledProposal=Join-Path $proposals 'compiled-witnesses.author-proposal.json'
        & (Join-Path $PSScriptRoot 'new-target-header-probes.ps1') -Output $compiledProposal
        if($LASTEXITCODE -ne 0){throw 'Header probe source mapping generation failed'}
        $proposalArguments.CompiledWitnessMapping=$compiledProposal
        if((Test-Path -LiteralPath (Join-Path $root 'c_api/tests/value_api_contract.c')) -and
            (Test-Path -LiteralPath (Join-Path $root 'c_api/tests/auxiliary_api_contract.c'))){
            $proposalArguments.AdditionalConsumerCases='tests/conformance/targets/remaining-upstream-compatibility/additional-public-consumer.author-cases.json'
            $proposalArguments.AdditionalAUnitCases='tests/conformance/targets/remaining-upstream-compatibility/additional-public-aunit.author-cases.json'
            $proposalArguments.AdditionalApiRoutes='tests/conformance/targets/remaining-upstream-compatibility/additional-public-api.author-routes.json'
        }elseif(Test-Path -LiteralPath (Join-Path $root 'c_api/tests/format_api_contract.c')){
            $proposalArguments.AdditionalConsumerCases='tests/conformance/targets/remaining-upstream-compatibility/formatter-consumer.author-cases.json'
            $proposalArguments.AdditionalAUnitCases='tests/conformance/targets/remaining-upstream-compatibility/formatter-aunit.author-cases.json'
        }
        & (Join-Path $PSScriptRoot 'new-target-witness-proposals.ps1') @proposalArguments
        if ($LASTEXITCODE -ne 0) { throw 'Target witness author proposal generation failed' }
        $WitnessPolicy = Join-Path $proposals 'witness-policy.author-proposal.json'
    } else { $WitnessPolicy = 'tests/conformance/targets/remaining-upstream-compatibility/witness-policy.json' }
}
$arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot $scriptName),'-LibraryType',$selected.library_type,
    '-TargetPolicy','remaining-upstream-compatibility','-TargetWitnessPolicy',$WitnessPolicy)
if($DevelopmentObservation){$arguments+='-TargetDevelopmentObservation'}
if($selected.configuration -ceq 'default'){$arguments+=@('-Profile',$selected.profile)}
[void][IO.Directory]::CreateDirectory($buildDirectory)
$build=Invoke-ConformanceProcess -Executable (Get-Command pwsh -ErrorAction Stop).Source -Arguments $arguments -Directory $root `
    -OutputPrefix (Join-Path $buildDirectory 'build') -TimeoutSeconds 3600
Write-Output ([IO.File]::ReadAllText($build.stdout_path))
Write-Output ([IO.File]::ReadAllText($build.stderr_path))
if($build.exit_code -ne 0 -or $build.timed_out -or $build.capture_exceeded -or $build.pipe_drain_failed -or
    $build.process_tree_kill_error -or $build.abnormal_exit_kind){throw 'Target context build/regression phase failed'}
$buildLogPath=Join-Path $buildDirectory 'build-log.json'
$buildLog=@{schema_version=1;kind='target-context-build-log';context=$Context;revision=(& git -C $root rev-parse HEAD).Trim();
    process=$build;source_bindings=@(foreach($file in @('scripts/build-target-context.ps1',('scripts/'+$scriptName),
        'scripts/check-core-image.ps1','scripts/check-aunit-evidence.ps1','scripts/TargetWitnessPolicy.psm1',
        'scripts/AUnitLaunch.psm1','scripts/run-aunit-in-context.ps1')){
        @{path=$file;sha256=(Get-FileHash -LiteralPath (Join-Path $root $file)).Hash.ToLowerInvariant()}
    });runtime_acceptance=$false;coverage_authority=$false}
[IO.File]::WriteAllText($buildLogPath,(ConvertTo-Json -InputObject $buildLog -Depth 48).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
$receiptPath = Join-Path $buildDirectory 'witnesses.json'
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -Depth 48
if ($receipt.context -cne $Context -or -not $receipt.runtime_observed -or
    $receipt.runtime_acceptance -ne $false -or $receipt.coverage_authority -ne $false) { throw 'Target build receipt is incomplete' }

# Disposable hosts in later jobs need the exact selected compiler's dynamic
# support libraries too. Copy only runtime-library files from the selected
# compiler directories, never an ambient PATH directory or tool installation.
$compilerOutput = & alr exec -- pwsh -NoProfile -Command '(Get-Command gcc -ErrorAction Stop).Source'
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify selected compiler binary' }
$compiler = ($compilerOutput -join '').Trim()
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Selected compiler binary is missing' }
& (Join-Path $PSScriptRoot 'run-target-compiled-witnesses.ps1') -Context $Context -WitnessPolicy $WitnessPolicy `
    -Compiler $compiler -DevelopmentObservation:$DevelopmentObservation
if($LASTEXITCODE -ne 0){throw 'Compiled ABI/layout/header context witness phase failed'}
Import-Module (Join-Path $PSScriptRoot 'RuntimeSupport.psm1')
$runtime = Get-SelectedAdaRuntime
$support = Join-Path $root $paths.compiler_support
if (Test-Path -LiteralPath $support) { throw 'Compiler support snapshot directory must be new' }
[void][IO.Directory]::CreateDirectory($support)
$supportNames = @{}
foreach ($directory in @((Split-Path -Parent $compiler),$runtime.Directory) | Sort-Object -Unique) {
    foreach ($file in Get-ChildItem -LiteralPath $directory -File | Where-Object { $_.Name -cmatch '\.(?:dll|dylib|so(?:\.[0-9.]+)?)$' }) {
        $hash = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        if ($supportNames.ContainsKey($file.Name)) {
            if ($supportNames[$file.Name] -cne $hash) { throw 'Selected compiler support library basename collision' }
            continue
        }
        $supportNames[$file.Name]=$hash
        [IO.File]::Copy($file.FullName,(Join-Path $support $file.Name))
    }
}
$directories = @((Split-Path -Parent $paths.ada_launcher).Replace('\','/'),
    (Split-Path -Parent $paths.c_oracle).Replace('\','/'),$paths.ada_runtime,$paths.c_runtime,
    ('reports/target-builds/' + $selected.id),$paths.compiler_support)
$imageDirectory = Join-Path $root ('reports/target-images/' + $selected.id)
$toolchain = @{compiler_sha256=(Get-FileHash -LiteralPath $compiler).Hash.ToLowerInvariant()}
foreach($frontendName in @('cc1','cc1plus')){
    $frontendOutput=& $compiler ('-print-prog-name='+$frontendName)
    if($LASTEXITCODE -ne 0){throw 'Cannot identify selected C/C++ frontend'}
    $frontendPath=($frontendOutput -join '').Trim()
    if(-not [IO.Path]::IsPathRooted($frontendPath) -or -not (Test-Path -LiteralPath $frontendPath -PathType Leaf)){
        throw 'Actual selected C/C++ frontend is missing'
    }
    $toolchain[$(if($frontendName -ceq 'cc1'){'c_frontend_sha256'}else{'cpp_frontend_sha256'})]=(Get-FileHash $frontendPath).Hash.ToLowerInvariant()
}
if ($IsWindows) {
    $dlltool = Join-Path (Split-Path -Parent $compiler) 'dlltool.exe'
    $toolchain.dlltool_sha256 = (Get-FileHash -LiteralPath $dlltool).Hash.ToLowerInvariant()
} else {
    $nm = Join-Path (Split-Path -Parent $compiler) 'nm'
    if (-not (Test-Path -LiteralPath $nm -PathType Leaf)) { $nm = (Get-Command nm -ErrorAction Stop).Source }
    $toolchain.nm_sha256 = (Get-FileHash -LiteralPath $nm).Hash.ToLowerInvariant()
}
$image = New-TargetContextImage -Root $root -Context $Context -OutputDirectory $imageDirectory -Paths $paths `
    -Directories $directories -WitnessReports @($receiptPath,$receipt.consumer.path,$receipt.aunit.path,$buildLogPath) `
    -Toolchain $toolchain
Write-Output "FROZEN: $Context image=$imageDirectory sha256=$($image.sha256); target acceptance=False"
