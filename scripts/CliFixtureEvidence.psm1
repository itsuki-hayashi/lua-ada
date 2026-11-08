Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CliFixtureCases.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')

function Get-CliFixtureSources {
    return @('tests/lua/cli_prompt_controls.lua','scripts/check-cli.ps1',
        'scripts/CliFixtureCases.psm1','scripts/CliFixtureEvidence.psm1',
        'scripts/check-configured-cli.ps1','scripts/ConformanceRunner.psm1',
        'cli/shared/lua_ada_cli_readline.c','cli/shared/lua_ada_cli_prompt.c',
        'cli/shared/lua-sessions-cli.adb','cli/shared/lua-sessions-cli.ads','cli/shared/lua_cli.adb',
        'cli/lua_ada_cli.gpr','tests/lua_ada_tests.gpr','scripts/check-cli-readline.ps1',
        'scripts/test-cli-readline-portability.ps1',
        'tests/conformance/targets/configured-fixture-classification.json')
}

function Assert-CliNativeTestExitDirection {
    param([Parameter(Mandatory)][string]$Root,[switch]$RequireProtocolReview)
    $feature='tests/conformance/targets/remaining-upstream-compatibility/reviews/cli-native-t-exit-no-close.independent-feature-review.json'
    $featureHash='01c86546143077d126b2c23716a7ee49a3f9dc25106ff44c45a0dd2b759615ad'
    if((Get-FileHash (Join-Path $Root $feature)).Hash.ToLowerInvariant() -cne $featureHash){throw 'CLI native diagnostic feature review differs'}
    $review=Get-Content (Join-Path $Root $feature) -Raw|ConvertFrom-Json -AsHashtable -Depth 24
    if($review.decision -cne 'accepted-narrow-native-test-diagnostic-direction' -or
        $review.author -ceq $review.reviewer -or $review.synthetic_fixture -isnot [bool] -or $review.synthetic_fixture){throw 'CLI diagnostic feature review lacks independent authority'}
    foreach($binding in $review.source_bindings){
        # The former harness hash is explicitly a dated direction input. It
        # never approves this successor implementation; final use below needs
        # a separate current protocol review. The original Lua/C facts stay exact.
        if($binding.path -ceq 'scripts/check-cli.ps1'){continue}
        if((Get-FileHash (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){throw 'CLI native diagnostic original source is stale'}
    }
    if($RequireProtocolReview){
        $path='tests/conformance/targets/remaining-upstream-compatibility/reviews/cli-native-t-exit-no-close.independent-protocol-review.json'
        if(-not (Test-Path (Join-Path $Root $path))){throw 'Final CLI native diagnostic requires independent current protocol review'}
        $approval=Get-Content (Join-Path $Root $path) -Raw|ConvertFrom-Json -AsHashtable -Depth 24
        $required=@('scripts/CliFixtureCases.psm1','scripts/CliFixtureEvidence.psm1','scripts/ConformanceRunner.psm1',
            'scripts/check-cli.ps1','scripts/check-configured-cli.ps1','scripts/ConfiguredFixtureEvidence.psm1',
            'scripts/compare.ps1','scripts/check.ps1','scripts/check-instrumented.ps1',
            'scripts/TargetWitnessPolicy.psm1','scripts/TargetObservationEnvelope.psm1','scripts/TargetContext.psm1',
            'scripts/build-target-context.ps1','tests/conformance/targets/configured-fixture-classification.json',
            'cli/shared/lua_ada_cli_readline.c','cli/shared/lua_ada_cli_prompt.c',
            'cli/shared/lua-sessions-cli.adb','cli/shared/lua-sessions-cli.ads','cli/shared/lua_cli.adb',
            'cli/lua_ada_cli.gpr','tests/lua_ada_tests.gpr','scripts/check-cli-readline.ps1','scripts/test-cli-readline-portability.ps1')
        if($approval.schema_version -ne 1 -or $approval.kind -cne 'native-t-exit-no-close-independent-protocol-review' -or
            $approval.decision -cne 'accepted-source-diagnostic-protocol' -or
            [string]::IsNullOrWhiteSpace($approval.author) -or [string]::IsNullOrWhiteSpace($approval.reviewer) -or
            $approval.author -ceq $approval.reviewer -or $approval.synthetic_fixture -isnot [bool] -or $approval.synthetic_fixture -or
            $approval.feature_review.path -cne $feature -or $approval.feature_review.sha256 -cne $featureHash -or
            $approval.source_bindings -isnot [Array] -or $approval.source_bindings.Count -ne $required.Count -or
            (($approval.source_bindings.path|Sort-Object)-join '|') -cne (($required|Sort-Object)-join '|')){throw 'CLI diagnostic current protocol approval differs'}
        foreach($flag in @('runtime_acceptance','coverage_authority','source_adaptation_authority')){
            if($approval[$flag] -isnot [bool] -or $approval[$flag]){throw 'CLI protocol approval cannot invent execution authority'}
        }
        if($approval.execution_evidence -isnot [Array] -or $approval.execution_evidence.Count -ne 0){throw 'CLI protocol approval cannot invent execution evidence'}
        foreach($binding in $approval.source_bindings){
            if((Get-FileHash (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){throw 'CLI diagnostic current protocol source binding is stale'}
        }
    }
    return @{path=$feature;sha256=$featureHash}
}

function Assert-CliHostClassification {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Classification)
    $path='tests/lua/cli_prompt_controls.lua'
    if(-not $Classification.Contains('host_entries') -or $Classification.host_entries -isnot [Array] -or
        $Classification.host_entries.Count -ne 2){throw 'Host CLI fixture classification is incomplete'}
    $row=$Classification.host_entries[0]
    $cases=@('primary-nil','secondary-nil','custom-string','empty-string','number','boolean','embedded-nul',
        'global-tostring','dynamic-tostring','numeric-tostring','index-value','tostring-frame','index-frame',
        'bad-tostring','error-tostring','error-table','error-boolean','error-nul','index-error','yield-tostring',
        'retired-root','budget','exit-no-close','exit-close')
    if($row.path -cne $path -or $row.selection -cne 'configured-host-CLI-only' -or
        $row.sha256 -cne (Get-FileHash (Join-Path $Root $path)).Hash.ToLowerInvariant() -or
        $row.driver -cne 'scripts/check-configured-cli.ps1' -or
        ($row.full_ada_operation_count -isnot [int] -and $row.full_ada_operation_count -isnot [long]) -or $row.full_ada_operation_count -ne 112 -or
        ($row.native_prompt_operation_count -isnot [int] -and $row.native_prompt_operation_count -isnot [long]) -or $row.native_prompt_operation_count -ne 19 -or
        $row.required_vararg_cases -isnot [Array] -or
        (($row.required_vararg_cases|Sort-Object)-join '|') -cne (($cases|Sort-Object)-join '|') -or
        $row.execution_evidence -isnot [Array] -or $row.execution_evidence.Count -ne 0){
        throw 'Host CLI fixture requires its closed source setup and operation contract'
    }
    $required=@('tests/src/lua-sessions-cli_prompt_tests.adb','tests/src/lua-sessions-cli_prompt_tests.ads',
        'scripts/CliFixtureCases.psm1','scripts/check-cli.ps1',
        'cli/shared/lua_ada_cli_readline.c','cli/shared/lua_ada_cli_prompt.c',
        'cli/shared/lua-sessions-cli.adb','cli/shared/lua-sessions-cli.ads','cli/shared/lua_cli.adb',
        'cli/lua_ada_cli.gpr','tests/lua_ada_tests.gpr','scripts/check-cli-readline.ps1','scripts/test-cli-readline-portability.ps1')
    if($row.bindings -isnot [Array] -or $row.bindings.Count -ne $required.Count -or
        (($row.bindings.path|Sort-Object)-join '|') -cne (($required|Sort-Object)-join '|')){throw 'Host CLI fixture linkage is incomplete'}
    foreach($binding in $row.bindings){
        if((Get-FileHash (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){throw 'Host CLI fixture linkage is stale'}
    }
    $source='tests/src/lua-sessions-cli_prompt_tests.adb'
    $actual=@([regex]::Matches((Get-Content (Join-Path $Root $source) -Raw),
        "(?s)Test_Support\.Add\s*\(Suite,\s*`"([^`"]+)`"\s*,\s*([A-Za-z0-9_]+)'Access")|
        ForEach-Object{$source+'#'+$_.Groups[2].Value+'|OK '+$_.Groups[1].Value}|Sort-Object)
    if($row.aunit_named_cases -isnot [Array] -or $row.aunit_named_cases.Count -ne 29 -or
        $actual.Count -ne 29 -or ($actual -join "`n") -cne
        (($row.aunit_named_cases|ForEach-Object{$_.case+'|'+$_.required_stdout_line}|Sort-Object)-join "`n")){
        throw 'Host CLI setup requires all29 actual named source registrations'
    }
    $argumentPath='tests/lua/cli_argument_controls.lua'
    $argument=$Classification.host_entries[1]
    $argumentCases=@('unchanged-strings','numeric-slot','boolean-slot','replace-table','replace-empty','mixed-object-identity',
        'metalen-holes','raw-indexing','metalen-number-string','metalen-float-integer','metalen-mutates-values',
        'metalen-replaces-global-gc','global-handler','non-table-number','non-table-nil','metalen-fraction',
        'metalen-table-result','metalen-error','metalen-yield','arg-zero-does-not-retarget','negative-index-does-not-retarget',
        'length-real-c-frame','global-real-c-frame','syntax-before-length','missing-file-before-length',
        'loaded-initial-environment','length-exit-close','length-refusal-recovery','refused-script-entry')
    if($argument.path -cne $argumentPath -or $argument.selection -cne 'configured-host-CLI-only' -or
        $argument.sha256 -cne (Get-FileHash (Join-Path $Root $argumentPath)).Hash.ToLowerInvariant() -or
        $argument.driver -cne 'scripts/observe-cli-dynamic-arg.ps1' -or
        $argument.lifecycle_driver -cne 'scripts/observe-cli-arg-lifecycle.ps1' -or
        $argument.required_vararg_cases -isnot [Array] -or
        (($argument.required_vararg_cases|Sort-Object)-join '|') -cne (($argumentCases|Sort-Object)-join '|') -or
        $argument.runtime_acceptance -isnot [bool] -or $argument.runtime_acceptance -or
        $argument.coverage_authority -isnot [bool] -or $argument.coverage_authority -or
        $argument.context_reconciliation -cne 'pending-portable-frozen-context-protocol' -or
        $argument.execution_evidence -isnot [Array] -or $argument.execution_evidence.Count){
        throw 'CLI argument helper requires its closed source setup; author observations are not context acceptance'
    }
    $requiredArgumentBindings=@('scripts/observe-cli-dynamic-arg.ps1','scripts/observe-cli-arg-lifecycle.ps1',
        'tests/conformance/targets/remaining-upstream-compatibility/cli-dynamic-arg.author-cases.json',
        'tests/conformance/targets/remaining-upstream-compatibility/cli-arg-lifecycle.author-cases.json',
        'tests/conformance/platform/cli-dynamic-arg.lua','tests/src/lua-sessions-cli_argument_tests.adb',
        'tests/src/lua-sessions-cli_argument_tests.ads')
    if($argument.bindings -isnot [Array] -or
        (($argument.bindings.path|Sort-Object)-join '|') -cne (($requiredArgumentBindings|Sort-Object)-join '|')){
        throw 'CLI argument helper source linkage is incomplete'
    }
    foreach($binding in $argument.bindings){
        if((Get-FileHash (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){throw 'CLI argument helper source linkage is stale'}
    }
    $argumentSource='tests/src/lua-sessions-cli_argument_tests.adb'
    $actualArgumentNames=@([regex]::Matches((Get-Content (Join-Path $Root $argumentSource) -Raw),
        "(?s)Test_Support\.Add\s*\(Suite,\s*`"([^`"]+)`"\s*,\s*([A-Za-z0-9_]+)'Access")|
        ForEach-Object{$argumentSource+'#'+$_.Groups[2].Value+'|OK '+$_.Groups[1].Value}|Sort-Object)
    if($actualArgumentNames.Count -ne 28 -or $argument.aunit_named_cases.Count -ne 28 -or
        ($actualArgumentNames -join "`n") -cne
        (($argument.aunit_named_cases|ForEach-Object{$_.case+'|'+$_.required_stdout_line}|Sort-Object)-join "`n")){
        throw 'CLI argument helper requires all28 actual named source registrations'
    }
    return @($path,$argumentPath)
}

function Get-CliProbeCases {
    return @(@{Title='capture clean package.path default';Args=@('-E','-e','io.write(package.path)')},
        @{Title='capture clean package.cpath default';Args=@('-E','-e','io.write(package.cpath)')})
}

function Get-CliConfigurationCase {
    param([ValidateSet('default','upstream-test')][string]$Configuration)
    $guard=if($Configuration -ceq 'upstream-test'){"assert(type(T)=='table' and type(T.stacklevel)=='function')"}else{"assert(rawget(_G,'T')==nil)"}
    return @{Title='measured native CLI configuration';Args=@('-e',"$guard;io.write('CLI CONFIGURATION $Configuration')");Output="CLI CONFIGURATION $Configuration"}
}

function Assert-CliCaseCapture {
    param([Parameter(Mandatory)][Collections.IDictionary]$Case,
          [Parameter(Mandatory)][Collections.IDictionary]$Row,
          [Parameter(Mandatory)][string]$Executable,
          [Parameter(Mandatory)][string]$ExecutableHash,
          [Parameter(Mandatory)][string]$Directory,[scriptblock]$ResolveFile,
          [switch]$NativeTestDiagnostic)
    $p=$Row.process
    if($Row.title -cne $Case.Title -or $p.executable -cne $Executable -or
        $p.executable_sha256 -cne $ExecutableHash -or $p.working_directory -cne $Directory -or
        $p.arguments -isnot [Array] -or
        (ConvertTo-Json -InputObject @($p.arguments) -Compress) -cne
        (ConvertTo-Json -InputObject @($Case.Args) -Compress)){
        throw 'CLI operation title runtime directory or exact arguments differ'
    }
    foreach($flag in @('timed_out','capture_exceeded','output_drain_failed')){
        if($p[$flag] -isnot [bool] -or $p[$flag]){throw 'CLI process lacks complete actual capture'}
    }
    $early=$Case.Contains('InputMayCloseEarly') -and $Case.InputMayCloseEarly
    if($p.input_write_failed -isnot [bool] -or $p.pipe_drain_failed -isnot [bool] -or
        $p.early_input_close_requested -isnot [bool] -or $p.early_input_close_requested -ne $early -or
        ($p.input_write_failed -and -not $early) -or $p.pipe_drain_failed -ne $p.input_write_failed){
        throw 'CLI input or output capture protocol differs'
    }
    if(($p.exit_code -isnot [int] -and $p.exit_code -isnot [long]) -or $p.process_tree_kill_error){throw 'CLI process has no actual exit status'}
    # A deliberate native -1 exit has a high-bit Windows status. No other
    # operation may turn an OS exception or signal into an expected Lua error.
    if($p.abnormal_exit_kind -and (-not $Case.Contains('ExitCode') -or $Case.ExitCode -ne -1 -or
        $p.exit_code -ne -1 -or $p.abnormal_exit_kind -cne 'windows-high-bit-status')){throw 'CLI process exited abnormally'}
    $environment=if($Case.Contains('Env')){$Case.Env}else{@{}}
    if($Row.environment -isnot [Collections.IDictionary] -or
        (($Row.environment.Keys|Sort-Object)-join '|') -cne (($environment.Keys|Sort-Object)-join '|')){throw 'CLI operation environment differs'}
    foreach($name in $environment.Keys){if($Row.environment[$name] -cne $environment[$name]){throw 'CLI operation environment differs'}}
    function Read-Capture($Path,$Hash,$Length){
        $actual=if($null -ne $ResolveFile){&$ResolveFile $Path $Hash}else{$Path}
        if(($Length -isnot [int] -and $Length -isnot [long]) -or
            (Get-Item -LiteralPath $actual).Length -ne $Length -or
            (Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $Hash){throw 'CLI actual capture bytes differ'}
        return ,[IO.File]::ReadAllBytes($actual)
    }
    $out=Read-Capture $p.stdout_path $p.stdout_sha256 $p.stdout_bytes
    $err=Read-Capture $p.stderr_path $p.stderr_sha256 $p.stderr_bytes
    if(-not $p.Contains('standard_input')){throw 'CLI operation lacks actual selected input'}
    $stdin=$p.standard_input
    if($stdin.eof_sent -isnot [bool] -or $stdin.close_requested -isnot [bool] -or -not $stdin.close_requested -or
        $stdin.write_completed -isnot [bool] -or $stdin.write_completed -eq $p.input_write_failed -or
        $stdin.eof_sent -ne $stdin.write_completed -or
        ($p.input_write_failed -and (-not $stdin.Contains('write_error') -or
         [string]::IsNullOrWhiteSpace($stdin.write_error)))){throw 'CLI operation input was not completed or its early close was not recorded'}
    $input=Read-Capture $stdin.path $stdin.sha256 $stdin.bytes
    $expectedInput=[Text.Encoding]::UTF8.GetBytes($(if($Case.Contains('Input')){$Case.Input}else{''}))
    if([Convert]::ToBase64String($input) -cne [Convert]::ToBase64String($expectedInput)){throw 'CLI selected input differs'}
    # Expected text contracts are converted to bytes. Raw captures remain
    # unchanged; replacement decoding cannot make invalid bytes pass equality.
    $output=[Text.UTF8Encoding]::new($false,$true).GetString($out)
    $errorOutput=[Text.UTF8Encoding]::new($false,$true).GetString($err)
    $disposition=if($NativeTestDiagnostic){'observed-native-test-teardown-diagnostic'}else{'clean-operation'}
    if($Row.observation_disposition -cne $disposition -or $Row.passing_execution_evidence -isnot [bool] -or
        $Row.passing_execution_evidence -ne (-not $NativeTestDiagnostic)){throw 'CLI diagnostic cannot masquerade as a clean operation'}
    if($NativeTestDiagnostic){
        if(-not $Row.Contains('feature_review') -or
            $Row.feature_review.path -cne 'tests/conformance/targets/remaining-upstream-compatibility/reviews/cli-native-t-exit-no-close.independent-feature-review.json' -or
            $Row.feature_review.sha256 -cne '01c86546143077d126b2c23716a7ee49a3f9dc25106ff44c45a0dd2b759615ad'){
            throw 'CLI native diagnostic lacks its independent source direction'
        }
    }elseif($Row.Contains('feature_review')){throw 'Another CLI case cannot borrow the native diagnostic direction'}
    if($Case.Contains('ExitCode')){
        $expectedError=if($Case.Contains('StderrExact')){$Case.StderrExact}else{''}
        if($NativeTestDiagnostic){
            if($Case.Title -cne 'REPL prompt typed exit without close retains status' -or $Case.ExitCode -ne 37 -or
                $p.exit_code -ne 37 -or $errorOutput -cnotmatch '\AAssertion failed: l_memcontrol\.numblocks == 0, file [^\r\n]+[/\\]references[/\\]lua[/\\]ltests\.c, line 2226\r\n\z'){
                throw 'CLI native test teardown diagnostic is not the exact measured Windows assertion'
            }
        }elseif($p.exit_code -ne $Case.ExitCode -or $errorOutput -cne $expectedError){throw 'CLI typed exit or error differs'}
    }elseif($Case.Contains('StderrExact')){
        if($p.exit_code -ne 0 -or $errorOutput -cne $Case.StderrExact){throw 'CLI stderr differs'}
    }elseif($Case.Contains('Stderr')){
        if($p.exit_code -ne 0 -or -not $errorOutput.Contains($Case.Stderr)){throw 'CLI expected diagnostic differs'}
    }elseif($Case.Contains('Fail') -and $Case.Fail){
        if($p.exit_code -eq 0 -or -not $errorOutput.Contains($Case.Error)){throw 'CLI expected failure differs'}
    }elseif($p.exit_code -ne 0 -or $errorOutput -cne ''){throw 'CLI operation failed'}
    if($Case.Contains('Output') -and [Convert]::ToBase64String($out) -cne
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Case.Output))){throw 'CLI exact output differs'}
    if($Case.Contains('Contains') -and -not $output.Contains($Case.Contains)){throw 'CLI required output differs'}
    return $output
}

function Assert-CliFixtureReport {
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][Collections.IDictionary]$Report,
          [Parameter(Mandatory)][string]$Interpreter,
          [ValidateSet('full','native','prompt')][string]$Mode='full',
          [scriptblock]$ResolveFile,[switch]$RequireProtocolReview)
    if($Report.schema_version -ne 1 -or $Report.kind -cne 'cli-fixture-observations' -or
        $Report.mode -cne $Mode -or $Report.synthetic_fixture -isnot [bool] -or $Report.synthetic_fixture){throw 'CLI report identity or actual mode differs'}
    if(($Report.Contains('development_observation') -and
         ($Report.development_observation -isnot [bool] -or $Report.development_observation)) -or
        ($Report.Contains('contract_failures') -and @($Report.contract_failures).Count)){
        throw 'Development CLI collection cannot supply strict passing evidence'
    }
    foreach($flag in @('runtime_acceptance','coverage_authority')){
        if($Report[$flag] -isnot [bool] -or $Report[$flag]){throw 'CLI observation cannot claim acceptance'}
    }
    $required=Get-CliFixtureSources
    if($Report.source_bindings -isnot [Array] -or $Report.source_bindings.Count -ne $required.Count){throw 'CLI source bindings are incomplete'}
    foreach($path in $required){
        $binding=@($Report.source_bindings|Where-Object path -CEQ $path)
        if($binding.Count -ne 1 -or (Get-FileHash (Join-Path $Root $path)).Hash.ToLowerInvariant() -cne $binding[0].sha256){throw 'CLI source binding is missing duplicate or stale'}
    }
    $suite=Get-Content (Join-Path $Root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable
    if($Report.context -cnotin $suite.acceptance_contexts -or $Report.context.Split('/')[1] -cne $Report.platform){throw 'CLI context differs'}
    if($Report.runtime_role -cnotin @('Ada','ReferenceC')){throw 'CLI implementation role differs'}
    $nativeDiagnostic=$Report.runtime_role -ceq 'ReferenceC' -and $Report.context.StartsWith('upstream-test/',[StringComparison]::Ordinal) -and $Mode -ceq 'prompt'
    if($nativeDiagnostic){$feature=Assert-CliNativeTestExitDirection -Root $Root -RequireProtocolReview:$RequireProtocolReview}
    $actual=if($null -ne $ResolveFile){&$ResolveFile $Report.executable $Report.executable_sha256}else{$Report.executable}
    if([IO.Path]::GetFullPath($actual) -cne [IO.Path]::GetFullPath($Interpreter) -or
        (Get-FileHash $actual).Hash.ToLowerInvariant() -cne $Report.executable_sha256){throw 'CLI actual runtime differs'}
    if($Report.library_files -isnot [Array] -or $Report.library_files.Count -eq 0 -or
        @($Report.library_files.path|Sort-Object -Unique).Count -ne $Report.library_files.Count){throw 'CLI selected runtime libraries are incomplete'}
    foreach($library in $Report.library_files){
        if($library.path.Replace('\','/') -cne ($Report.runtime_directory.Replace('\','/').TrimEnd('/')+'/'+[IO.Path]::GetFileName($library.path.Replace('\','/')))){
            throw 'CLI selected runtime library directory differs'
        }
        $resolved=if($null -ne $ResolveFile){&$ResolveFile $library.path $library.sha256}else{$library.path}
        if((Get-FileHash $resolved).Hash.ToLowerInvariant() -cne $library.sha256){throw 'CLI selected runtime library bytes differ'}
    }
    if($Report.runtime_role -ceq 'ReferenceC'){
        if(-not $Report.Contains('configuration_probe')){throw 'CLI native configuration probe is missing'}
        $case=Get-CliConfigurationCase $Report.context.Split('/')[0]
        $null=Assert-CliCaseCapture -Case $case -Row $Report.configuration_probe -Executable $Report.executable `
            -ExecutableHash $Report.executable_sha256 -Directory $Report.working_directory -ResolveFile $ResolveFile
    }elseif($Report.Contains('configuration_probe')){throw 'Ada CLI cannot borrow a native T configuration probe'}
    $copy=@($Report.fixture_files|Where-Object name -CEQ 'prompt-controls.lua')
    $fixtureNames=@('arguments.lua','-script.lua','empty.lua','source-name.lua','shebang.lua',
        'bom.lua','cli_lib.lua','cli_init.lua','large-source.lua','prompt-controls.lua')
    if($Report.fixture_files -isnot [Array] -or $Report.fixture_files.Count -ne $fixtureNames.Count -or
        (($Report.fixture_files.name|Sort-Object)-join '|') -cne (($fixtureNames|Sort-Object)-join '|')){
        throw 'CLI input fixture set is incomplete or duplicated'
    }
    if($copy.Count -ne 1 -or $copy[0].sha256 -cne (Get-FileHash (Join-Path $Root 'tests/lua/cli_prompt_controls.lua')).Hash.ToLowerInvariant()){
        throw 'CLI host setup source copy differs'
    }
    foreach($file in $Report.fixture_files){
        $path=$Report.working_directory.TrimEnd('/','\')+'/'+$file.name
        $resolved=if($null -ne $ResolveFile){&$ResolveFile $path $file.sha256}else{$path}
        if((Get-FileHash $resolved).Hash.ToLowerInvariant() -cne $file.sha256){throw 'CLI input fixture changed'}
    }
    $probes=@(Get-CliProbeCases)
    if($Report.processes -isnot [Array] -or $Report.processes.Count -lt 2){throw 'CLI actual process set is incomplete'}
    $defaults=@()
    for($i=0;$i -lt 2;$i++){
        $value=Assert-CliCaseCapture -Case $probes[$i] -Row $Report.processes[$i] -Executable $Report.executable `
            -ExecutableHash $Report.executable_sha256 -Directory $Report.working_directory -ResolveFile $ResolveFile
        if([string]::IsNullOrEmpty($value)){throw 'CLI default package path probe is empty'}
        $defaults+=,$value
    }
    $definitions=Get-CliCaseDefinitions -DefaultPackagePath $defaults[0] -DefaultPackageCPath $defaults[1] -Platform $Report.platform -Mode $Mode
    $cases=@($definitions.cases)
    if($Report.processes.Count -ne $cases.Count+2 -or
        @($Report.processes.title|Sort-Object -Unique).Count -ne $Report.processes.Count){throw 'CLI complete ordered process set differs'}
    for($i=0;$i -lt $cases.Count;$i++){
        $diagnostic=$nativeDiagnostic -and $cases[$i].Title -ceq 'REPL prompt typed exit without close retains status'
        if($diagnostic -and $Report.platform -cne 'windows'){throw 'Native T no-close diagnostic requires fresh platform applicability review'}
        $null=Assert-CliCaseCapture -Case $cases[$i] -Row $Report.processes[$i+2] -Executable $Report.executable `
            -ExecutableHash $Report.executable_sha256 -Directory $Report.working_directory -ResolveFile $ResolveFile -NativeTestDiagnostic:$diagnostic
    }
    if($Mode -ceq 'full' -and $Report.processes.Count -ne 112){throw 'CLI full host campaign must retain all112 operations'}
    if($definitions.prompt_titles.Count -ne 19){throw 'CLI prompt contract must retain all19 operations'}
    $diagnostics=@($Report.processes|Where-Object observation_disposition -CEQ 'observed-native-test-teardown-diagnostic')
    if($diagnostics.Count -ne $(if($nativeDiagnostic){1}else{0})){throw 'CLI native diagnostic set differs'}
    return @{runtime_observed=$true;operations=@($Report.processes.title);prompt_titles=$definitions.prompt_titles;
        clean_operations=@($Report.processes|Where-Object observation_disposition -CEQ 'clean-operation'|ForEach-Object title);
        native_test_diagnostics=@($diagnostics|ForEach-Object{@{operation=$_.title;disposition=$_.observation_disposition;passing_execution_evidence=$false}});
        runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-CliFixturePair {
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][Collections.IDictionary]$Report,
          [Parameter(Mandatory)][string]$Interpreter,[scriptblock]$ResolveFile,[switch]$RequireProtocolReview)
    if($Report.schema_version -ne 1 -or $Report.kind -cne 'host-cli-fixture-pair' -or
        $Report.synthetic_fixture -isnot [bool] -or $Report.synthetic_fixture -or
        $Report.runtime_acceptance -isnot [bool] -or $Report.runtime_acceptance -or
        $Report.coverage_authority -isnot [bool] -or $Report.coverage_authority){throw 'CLI pair identity differs'}
    $ada=$Report.ada;$native=$Report.native
    if($ada.runtime_role -cne 'Ada' -or $native.runtime_role -cne 'ReferenceC'){throw 'CLI paired implementation roles differ'}
    foreach($raw in @($ada,$native)){
        if($raw.context -cne $Report.context -or $raw.repository_revision -cne $Report.repository_revision -or
            $raw.repository_dirty -isnot [bool] -or $raw.repository_dirty -ne $Report.repository_dirty){throw 'CLI paired source or context differs'}
    }
    $observed=Assert-CliFixtureReport -Root $Root -Report $ada -Interpreter $Interpreter -Mode full -ResolveFile $ResolveFile
    $nativePath=if($null -ne $ResolveFile){&$ResolveFile $native.executable $native.executable_sha256}else{$native.executable}
    $nativeObserved=Assert-CliFixtureReport -Root $Root -Report $native -Interpreter $nativePath -Mode prompt -ResolveFile $ResolveFile -RequireProtocolReview:$RequireProtocolReview
    $isT=$Report.context.StartsWith('upstream-test/',[StringComparison]::Ordinal)
    if($isT){
        if(-not $Report.Contains('native_default')){throw 'CLI native T diagnostic lacks its clean native default counterpart'}
        $ordinary=$Report.native_default
        $expectedContext='default/'+($Report.context.Split('/')[1..3]-join '/')
        if($ordinary.context -cne $expectedContext -or $ordinary.runtime_role -cne 'ReferenceC' -or
            $ordinary.repository_revision -cne $Report.repository_revision -or $ordinary.repository_dirty -ne $Report.repository_dirty){throw 'CLI default counterpart source or configuration differs'}
        $ordinaryPath=if($null -ne $ResolveFile){&$ResolveFile $ordinary.executable $ordinary.executable_sha256}else{$ordinary.executable}
        $null=Assert-CliFixtureReport -Root $Root -Report $ordinary -Interpreter $ordinaryPath -Mode prompt -ResolveFile $ResolveFile
        $title='REPL prompt typed exit without close retains status'
        $a=@($ada.processes|Where-Object title -CEQ $title)[0].process
        $c=@($ordinary.processes|Where-Object title -CEQ $title)[0].process
        if($a.exit_code -ne $c.exit_code -or $a.stdout_sha256 -cne $c.stdout_sha256 -or $a.stderr_sha256 -cne $c.stderr_sha256){throw 'CLI no-close public native default counterpart differs'}
        # The mandatory native-T close=true sibling is still an ordinary clean
        # operation, checked above. It proves actual requested state closure
        # without calling the no-close diagnostic cleanup success.
    }elseif($Report.Contains('native_default')){throw 'Default CLI context cannot invent an extra diagnostic counterpart'}
    foreach($title in $observed.prompt_titles){
        $a=@($ada.processes|Where-Object title -CEQ $title)[0].process
        $c=@($native.processes|Where-Object title -CEQ $title)[0].process
        if($isT -and $title -ceq 'REPL prompt typed exit without close retains status'){continue}
        if($a.exit_code -ne $c.exit_code -or $a.stdout_sha256 -cne $c.stdout_sha256 -or
            $a.stderr_sha256 -cne $c.stderr_sha256){throw 'CLI paired prompt observations differ'}
    }
    $observed['native_test_diagnostics']=$nativeObserved.native_test_diagnostics
    return $observed
}

function Assert-CliFixtureImagePair {
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][Collections.IDictionary]$Report,
          [Parameter(Mandatory)][Collections.IDictionary]$Image,
          [Parameter(Mandatory)][string]$Payload)
    if($Report.repository_dirty -isnot [bool] -or $Report.repository_dirty -or
        $Report.repository_revision -cne $Image.revision -or $Report.context -cne $Image.context){throw 'CLI image source or context differs'}
    $origin=$Report.ada.source_repository_root.Replace('\','/').TrimEnd('/')+'/'
    if($Report.native.source_repository_root.Replace('\','/').TrimEnd('/')+'/' -cne $origin){throw 'CLI pair repository origins differ'}
    $resolve={param($path,$hash)
        $normal=$path.Replace('\','/')
        if(-not $normal.StartsWith($origin,[StringComparison]::Ordinal)){throw 'CLI image path is outside its repository'}
        $relative=$normal.Substring($origin.Length)
        if($relative -match '(^|/)\.\.?(/|$)|:' -or $relative.StartsWith('/') -or
            @($Image.files|Where-Object{$_.path -ceq $relative -and $_.sha256 -ceq $hash}).Count -ne 1){throw 'CLI capture is absent from its exact frozen image'}
        return (Join-Path $Payload $relative)
    }
    if(-not $Image.paths.Contains('ada_cli') -or
        $Report.ada.executable.Replace('\','/') -cne ($origin+$Image.paths.ada_cli) -or
        $Report.native.executable.Replace('\','/') -cne ($origin+$Image.paths.c_oracle)){
        throw 'CLI pair uses another frozen host runtime'
    }
    $runtimes=@(@{report=$Report.ada;directory=$Image.paths.ada_runtime},@{report=$Report.native;directory=$Image.paths.c_runtime})
    if($Report.context.StartsWith('upstream-test/',[StringComparison]::Ordinal)){
        if(-not $Image.paths.Contains('c_default_oracle') -or
            $Report.native_default.executable.Replace('\','/') -cne ($origin+$Image.paths.c_default_oracle)){
            throw 'CLI diagnostic lacks its frozen native default counterpart runtime'
        }
        $runtimes+=@{report=$Report.native_default;directory=$Image.paths.c_default_runtime}
    }
    foreach($runtime in $runtimes){
        if($runtime.report.runtime_directory.Replace('\','/') -cne ($origin+$runtime.directory)){
            throw 'CLI pair uses a different frozen runtime library directory'
        }
    }
    return Assert-CliFixturePair -Root $Root -Report $Report -Interpreter (Join-Path $Payload $Image.paths.ada_cli) -ResolveFile $resolve -RequireProtocolReview
}

function Assert-CliNamedCounterparts {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Context,
          [Parameter(Mandatory)][Collections.IDictionary]$NamedEvidence)
    if($NamedEvidence.context -cne $Context -or $NamedEvidence.runtime_observed -isnot [bool] -or
        -not $NamedEvidence.runtime_observed){throw 'CLI counterparts require actual same-context named AUnit receipts'}
    $classification=Get-Content (Join-Path $Root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 24
    $null=Assert-CliHostClassification -Root $Root -Classification $classification
    foreach($case in $classification.host_entries.aunit_named_cases.case){
        if($case -cnotin $NamedEvidence.named_aunit_cases){throw 'CLI setup lacks an actual required named AUnit counterpart'}
    }
    # The source-only author observers are Windows/static component packets.
    # Their existence and the 28 actual Ada names do not supply mandatory
    # paired CLI process receipts for the final portable frozen context.
    if($classification.host_entries[1].context_reconciliation -ceq 'pending-portable-frozen-context-protocol'){
        throw 'CLI argument helper still needs its actual portable frozen-context process protocol'
    }
}

Export-ModuleMember -Function Get-CliFixtureSources,Get-CliProbeCases,Get-CliConfigurationCase,Assert-CliHostClassification,Assert-CliCaseCapture,Assert-CliFixtureReport,Assert-CliFixturePair,Assert-CliFixtureImagePair,Assert-CliNamedCounterparts,Assert-CliNativeTestExitDirection
