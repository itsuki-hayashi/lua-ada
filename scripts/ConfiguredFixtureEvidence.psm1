Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')

function Get-ConfiguredFixtureDefinitions {
    param([ValidateSet('default','upstream-test')][string]$Configuration)
    $limit=if($Configuration -ceq 'default'){1000000}else{68000}
    $guard=if($Configuration -ceq 'default'){"assert(rawget(_G,'T')==nil)"}
        else{"assert(type(T)=='table' and type(T.stacklevel)=='function')"}
    $portal="CONFIGURED-FIXTURE: portal $Configuration $limit"
    $definitions=@(@{id='portal';source='tests/lua/coroutine_result_portal.lua';
        setup="_PORTAL_LIMIT=$limit;$guard;print('$portal')";
        stdout="$portal`nPASS: coroutine result capacity and recipients`n"})
    if($Configuration -ceq 'upstream-test'){
        $definitions+=@{id='stack-inspection';source='tests/lua/stack_inspection.lua';
            setup="$guard;print('CONFIGURED-FIXTURE: real T stack inspection')";
            stdout="CONFIGURED-FIXTURE: real T stack inspection`n"+
                ((1..4|ForEach-Object{"PASS: stack inspection $_"})-join "`n")+"`n"}
    }
    return $definitions
}

function Get-ConfiguredFixtureSources {
    param([ValidateSet('default','upstream-test')][string]$Configuration)
    # Source selection and measured executable handshakes are separate facts.
    # Keep both: a freshly copied source hash cannot certify a stale binary.
    return @('scripts/ConfiguredFixtureEvidence.psm1','scripts/check-configured-fixtures.ps1',
        'scripts/ConformanceRunner.psm1','scripts/ManagedTelemetry.psm1',
        'tests/lua/coroutine_result_portal.lua','tests/lua/stack_inspection.lua',
        ('src/configurations/'+$Configuration+'/lua-runtime_configuration.ads'),
        'references/lua/llimits.h','references/lua/ltests.h','references/lua/luaconf.h',
        'experiments/conformance/reference.gpr','experiments/conformance/c/conformance_cli.c',
        'experiments/conformance/c/observed_ldo.c','tests/src/conformance_runner.adb',
        'tests/src/lua-conformance_adapter.adb','tests/c/conformance_adapter.c')
}

function Assert-ConfiguredFixtureReport {
    param([Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][Collections.IDictionary]$Report,
        [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string]$Configuration,
        [Parameter(Mandatory)][string]$Interpreter)
    if($Report.schema_version -ne 1 -or $Report.kind -cne 'configured-fixture-observations' -or
        $Report.configuration -cne $Configuration -or $Report.synthetic_fixture -isnot [bool] -or $Report.synthetic_fixture -or
        $Report.runtime_acceptance -isnot [bool] -or $Report.runtime_acceptance -or
        $Report.coverage_authority -isnot [bool] -or $Report.coverage_authority -or
        $Report.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294'){
        throw 'Configured fixture report kind/configuration or observation authority differs'
    }
    $required=Get-ConfiguredFixtureSources $Configuration
    if($Report.source_bindings -isnot [Array] -or $Report.source_bindings.Count -ne $required.Count){throw 'Configured fixture source bindings are incomplete'}
    foreach($path in $required){
        $binding=@($Report.source_bindings|Where-Object path -CEQ $path)
        if($binding.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $Root $path)).Hash.ToLowerInvariant() -cne $binding[0].sha256){
            throw 'Configured fixture source identity is missing duplicated or stale'
        }
    }
    $ada=@($Report.runtimes|Where-Object role -CEQ Ada)
    if($ada.Count -ne 1 -or [IO.Path]::GetFullPath($ada[0].executable) -cne [IO.Path]::GetFullPath($Interpreter)){
        throw 'Configured fixture report identifies another Ada interpreter'
    }
    if($Report.runtimes.Count -ne 2 -or @($Report.runtimes.role|Sort-Object -Unique).Count -ne 2){throw 'Configured fixture runtime pair is incomplete'}
    $definitions=@(Get-ConfiguredFixtureDefinitions $Configuration)
    if($Report.processes.Count -ne (2*($definitions.Count+1))){throw 'Configured fixture process set is incomplete or duplicated'}
    foreach($runtime in $Report.runtimes){
        if($runtime.role -cnotin @('Ada','ReferenceC') -or
            (Get-FileHash -LiteralPath $runtime.executable).Hash.ToLowerInvariant() -cne $runtime.executable_sha256 -or
            $runtime.library_files -isnot [Array] -or $runtime.library_files.Count -eq 0){throw 'Configured fixture runtime identity differs'}
        foreach($library in $runtime.library_files){
            if((Get-FileHash -LiteralPath $library.path).Hash.ToLowerInvariant() -cne $library.sha256){throw 'Configured fixture runtime library identity differs'}
        }
        foreach($operation in @('configuration')+@($definitions.id)){
            $rows=@($Report.processes|Where-Object{$_.role -ceq $runtime.role -and $_.operation -ceq $operation})
            if($rows.Count -ne 1){throw 'Configured fixture actual process is missing or duplicated'}
            $row=$rows[0];$p=$row.process
            if($p.executable -cne $runtime.executable -or $p.executable_sha256 -cne $runtime.executable_sha256 -or
                $p.working_directory -cne $Root -or $p.exit_code -ne 0 -or $p.timed_out -or $p.abnormal_exit_kind -or
                $p.capture_exceeded -or $p.pipe_drain_failed -or $p.process_tree_kill_error -or $p.stderr_bytes -ne 0){
                throw 'Configured fixture process failed or used another runtime/directory'
            }
            foreach($stream in @('stdout','stderr')){
                if((Get-FileHash -LiteralPath $p[$stream+'_path']).Hash.ToLowerInvariant() -cne $p[$stream+'_sha256'] -or
                    (Get-Item -LiteralPath $p[$stream+'_path']).Length -ne $p[$stream+'_bytes']){throw 'Configured fixture raw capture identity differs'}
            }
            $out=[IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n")
            if($operation -ceq 'configuration'){
                if(($p.arguments -join '|') -cne '--conformance-config'){throw 'Configured fixture configuration arguments differ'}
                $observed=$out|ConvertFrom-Json -AsHashtable
                [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration -Target $runtime.role -AllocatorLimitBytes 2147483648)
            }else{
                $definition=@($definitions|Where-Object id -CEQ $operation)[0]
                $arguments=@('-e',$definition.setup,(Join-Path $Root $definition.source))
                if($p.arguments -isnot [Array] -or ($p.arguments -join '|') -cne ($arguments -join '|')){throw 'Configured fixture explicit setup or source argument differs'}
                if($out -cne $definition.stdout){throw 'Configured fixture complete ordered protocol or real T witness differs'}
                if((Get-FileHash -LiteralPath $row.telemetry.path).Hash.ToLowerInvariant() -cne $row.telemetry.sha256){throw 'Configured fixture allocator capture identity differs'}
                $telemetry=Get-Content -LiteralPath $row.telemetry.path -Raw|ConvertFrom-Json -AsHashtable
                Assert-ManagedTelemetry -Telemetry $telemetry -RunId $row.telemetry.run_id -ProcessId $p.process_id `
                    -Configuration $Configuration -RequireShutdown:($runtime.role -ceq 'Ada')
            }
        }
    }
    # Each role must independently produce the complete normative protocol;
    # agreeing partial output is insufficient. No result here closes a source
    # ledger or grants runtime/target acceptance.
    return @{configuration=$Configuration;operations=@($definitions.id);runtime_observed=$true;
        runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Get-ConfiguredFixtureDefinitions,Get-ConfiguredFixtureSources,Assert-ConfiguredFixtureReport
