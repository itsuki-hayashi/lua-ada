Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')

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
        $definitions+=@{id='primitive-not-refusal';source='tests/lua/primitive_not_refusal.lua';
            setup="$guard;assert(type(T.alloccount)=='function');print('CONFIGURED-FIXTURE: real T scalar NOT refusal')";
            stdout="CONFIGURED-FIXTURE: real T scalar NOT refusal`n"+
                ((@('false','nil','zero','empty string','table','function')|ForEach-Object{"PASS: primitive NOT $_"})-join "`n")+
                "`nPASS: scalar NOT under refusal`n"}
        $commands=@('Light_Upvalues','Absent_Upvalue','Stack_Reordering','Raw_Table','Metatable_Delegation',
            'Arithmetic_Commands','C_Function_Identity','Length_Commands','Loaded_Source','Formatting_Commands',
            'Userdata_Metatable','References','Double_Bytes','Mutable_Upvalues','New_Stack','External_String',
            'Warning_Fragments','Hook_Command','Stack_Reservation','Traceback_Command','Traceback_Dynamic_Level','Traceback_Suspended_Thread')
        $definitions+=@{id='public-api-commands';source='tests/lua/public_api_commands.lua';
            setup="$guard;assert(type(T.testC)=='function' and rawget(_G,'_API_COMMAND_CASE')==nil);print('CONFIGURED-FIXTURE: real T public API commands')";
            stdout="CONFIGURED-FIXTURE: real T public API commands`n"+
                (($commands|ForEach-Object{"PASS: API command $_"})-join "`n")+"`nPASS: public API command witnesses`n"}
        $panic=@('Trivial','Status','Stack','Argument','Memory','Closing','Close_Error','Closing_Status','No_Error',
            'Count_Restores_Stack','Child_Byte_Limit','Child_Count_Limit','Load_File','Oversized_Userdata')
        $definitions+=@{id='public-panic-controls';source='tests/lua/public_panic_controls.lua';
            setup="$guard;assert(type(T.checkpanic)=='function' and rawget(_G,'_PANIC_CONTROL_CASE')==nil);print('CONFIGURED-FIXTURE: real T panic provider controls')";
            stdout="CONFIGURED-FIXTURE: real T panic provider controls`n"+
                (($panic|ForEach-Object{"PASS: panic control $_"})-join "`n")+"`nPASS: public panic/provider witnesses`n"}
        $definitions+=@{id='reader-refusal-phases';source='tests/lua/reader_refusal_phases.lua';
            setup="$guard;assert(type(T.alloccount)=='function');print('CONFIGURED-FIXTURE: real T reader refusal phases')";
            stdout="CONFIGURED-FIXTURE: real T reader refusal phases`n"+
                ((@('Refused_Cold_Reader','Refused_Warm_Reader','Refused_Partial_Source','Refused_Binary_Reader')|
                    ForEach-Object{"PASS: reader refusal $_"})-join "`n")+"`nreader refusal phases OK`n"}
        $definitions+=@{id='string-refusal-phases';source='tests/lua/string_refusal_phases.lua';
            setup="$guard;assert(type(T.alloccount)=='function');print('CONFIGURED-FIXTURE: real T string refusal phases')";
            stdout="CONFIGURED-FIXTURE: real T string refusal phases`n"+
                ((@('Refused_Find','Refused_Length','Refused_Zero','Refused_Error')|
                    ForEach-Object{"PASS: string refusal $_"})-join "`n")+"`nstring refusal phases OK`n"}
        $definitions+=@{id='c-hook-transitions';source='tests/lua/hook_transition_c.lua';
            setup="$guard;assert(type(T.sethook)=='function');print('CONFIGURED-FIXTURE: real T C hook transitions')";
            stdout="CONFIGURED-FIXTURE: real T C hook transitions`n"+
                ((@('C_Count_To_Line','C_Same_Line','C_Count_Removes_Line','C_Count_Removes_All','C_Line_To_Count')|
                    ForEach-Object{"PASS: C hook transition $_"})-join "`n")+"`nC hook transitions OK`n"}
    }
    return $definitions
}

function Get-ConfiguredFixtureSources {
    param([ValidateSet('default','upstream-test')][string]$Configuration)
    # Source selection and measured executable handshakes are separate facts.
    # Keep both: a freshly copied source hash cannot certify a stale binary.
    return @('scripts/ConfiguredFixtureEvidence.psm1','scripts/check-configured-fixtures.ps1',
        'scripts/ConformanceRunner.psm1','scripts/ManagedTelemetry.psm1',
        'tests/lua/coroutine_result_portal.lua','tests/lua/stack_inspection.lua','tests/lua/primitive_not_refusal.lua',
        'tests/lua/public_api_commands.lua','tests/lua/public_panic_controls.lua','tests/lua/public_panic_file.lua',
        'tests/lua/reader_refusal_phases.lua','tests/lua/string_refusal_phases.lua','tests/lua/hook_transition_c.lua',
        ('src/configurations/'+$Configuration+'/lua-runtime_configuration.ads'),
        'references/lua/llimits.h','references/lua/ltests.h','references/lua/luaconf.h',
        'experiments/conformance/reference.gpr','experiments/conformance/c/conformance_cli.c',
        'experiments/conformance/c/observed_ldo.c','tests/src/conformance_runner.adb',
        'tests/src/lua-conformance_adapter.adb','tests/c/conformance_adapter.c','tests/conformance/suite.json',
        'tests/conformance/targets/configured-fixture-classification.json')
}

function Get-ConfiguredFixtureAudit {
    param([Parameter(Mandatory)][string]$Root)
    $ordinary=@(Get-ConfiguredFixtureDefinitions default|ForEach-Object source)
    $instrumented=@(Get-ConfiguredFixtureDefinitions upstream-test|ForEach-Object source)
    $only=@($instrumented|Where-Object{$_ -cnotin $ordinary})
    $classification=Get-Content (Join-Path $Root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable
    if($classification.schema_version -ne 1 -or $classification.kind -cne 'first-party-configured-fixture-classification' -or
        $classification.runtime_acceptance -isnot [bool] -or $classification.runtime_acceptance -or
        $classification.coverage_authority -isnot [bool] -or $classification.coverage_authority -or
        $classification.entries -isnot [Array] -or $classification.entries.Count -ne $only.Count){
        throw 'Configured fixture classification is incomplete or claims runtime authority'
    }
    foreach($path in $only){
        $record=@($classification.entries|Where-Object path -CEQ $path)
        if($record.Count -ne 1 -or $record[0].selection -cne 'paired-configured-T-only' -or
            [string]::IsNullOrWhiteSpace($record[0].rationale) -or
            (Get-FileHash (Join-Path $Root $path)).Hash.ToLowerInvariant() -cne $record[0].sha256){
            throw "Configured T-only classification requires a fresh mixed/default/T source review: $path"
        }
    }
    $entries=@(foreach($file in Get-ChildItem (Join-Path $Root 'tests/lua') -File -Filter '*.lua'|Sort-Object Name){
        $path='tests/lua/'+$file.Name
        $tokens=Get-ConformanceTokens -Bytes ([IO.File]::ReadAllBytes($file.FullName))
        $references=@($tokens|Where-Object{$_.Text -ceq 'T' -and -not $_.IsString})
        if($references.Count -and $path -cnotin $instrumented){
            throw "Unclassified T-bearing fixture requires an explicit mixed/default/T campaign audit: $path"
        }
        # This is an explicit selection audit, not a Lua scope parser or proof
        # of compatibility. New T-bearing files fail closed for human review;
        # mixed ordinary/T files must appear in both configured selections.
        [ordered]@{path=$path;sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();T_identifiers=$references.Count;
            selection=$(if($path -cin $ordinary){'paired-configured-default-and-T'}elseif($path -cin $instrumented){'paired-configured-T-only'}else{'generic-default-source-comparison'})}
    })
    return [ordered]@{schema_version=1;kind='first-party-fixture-selection-audit';entries=$entries;
        runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-ConfiguredFixtureReport {
    param([Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][Collections.IDictionary]$Report,
        [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string]$Configuration,
        [Parameter(Mandatory)][string]$Interpreter,[scriptblock]$ResolveFile=$null)
    if($Report.schema_version -ne 1 -or $Report.kind -cne 'configured-fixture-observations' -or
        $Report.configuration -cne $Configuration -or $Report.synthetic_fixture -isnot [bool] -or $Report.synthetic_fixture -or
        $Report.runtime_acceptance -isnot [bool] -or $Report.runtime_acceptance -or
        $Report.coverage_authority -isnot [bool] -or $Report.coverage_authority -or
        $Report.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294'){
        throw 'Configured fixture report kind/configuration or observation authority differs'
    }
    $origin=$Report.repository_root
    if([string]::IsNullOrWhiteSpace($origin) -or ($null -eq $ResolveFile -and $origin -cne $Root)){
        throw 'Configured fixture execution root differs'
    }
    $suite=Get-Content (Join-Path $Root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable
    $link=if($Report.library_type -ceq 'relocatable'){'shared'}else{$Report.library_type}
    if($Report.context -cnotin $suite.acceptance_contexts -or
        $Report.context -cne ($Configuration+'/'+$Report.platform+'/'+$Report.profile+'/'+$link)){
        throw 'Configured fixture context tuple differs'
    }
    $audit=Get-ConfiguredFixtureAudit -Root $Root
    $auditBytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $audit -Depth 12 -Compress))
    $storedAuditBytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Report.fixture_selection_audit -Depth 12 -Compress))
    if($Report.fixture_selection_audit_sha256 -cne (Get-ConformanceHash $auditBytes) -or
        $Report.fixture_selection_audit_sha256 -cne (Get-ConformanceHash $storedAuditBytes)){
        throw 'Configured fixture selection audit or complete first-party source set differs'
    }
    function Resolve-Observation($Path,$Hash){
        $actual=if($null -ne $ResolveFile){&$ResolveFile $Path $Hash}else{$Path}
        if((Get-FileHash -LiteralPath $actual).Hash.ToLowerInvariant() -cne $Hash){throw 'Configured fixture observed file identity differs'}
        return $actual
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
    if($ada.Count -ne 1 -or [IO.Path]::GetFullPath((Resolve-Observation $ada[0].executable $ada[0].executable_sha256)) -cne [IO.Path]::GetFullPath($Interpreter)){
        throw 'Configured fixture report identifies another Ada interpreter'
    }
    if($Report.runtimes.Count -ne 2 -or @($Report.runtimes.role|Sort-Object -Unique).Count -ne 2){throw 'Configured fixture runtime pair is incomplete'}
    $definitions=@(Get-ConfiguredFixtureDefinitions $Configuration)
    if($Report.processes.Count -ne (2*($definitions.Count+1))){throw 'Configured fixture process set is incomplete or duplicated'}
    foreach($runtime in $Report.runtimes){
        if($runtime.role -cnotin @('Ada','ReferenceC') -or
            [string]::IsNullOrWhiteSpace((Resolve-Observation $runtime.executable $runtime.executable_sha256)) -or
            $runtime.library_files -isnot [Array] -or $runtime.library_files.Count -eq 0){throw 'Configured fixture runtime identity differs'}
        if(@($runtime.library_files.path|Sort-Object -Unique).Count -ne $runtime.library_files.Count){throw 'Configured fixture runtime library identities are duplicated'}
        foreach($library in $runtime.library_files){
            [void](Resolve-Observation $library.path $library.sha256)
        }
        foreach($operation in @('configuration')+@($definitions.id)){
            $rows=@($Report.processes|Where-Object{$_.role -ceq $runtime.role -and $_.operation -ceq $operation})
            if($rows.Count -ne 1){throw 'Configured fixture actual process is missing or duplicated'}
            $row=$rows[0];$p=$row.process
            foreach($flag in @('timed_out','capture_exceeded','pipe_drain_failed')){
                if($p[$flag] -isnot [bool] -or $p[$flag]){throw 'Configured fixture process failed or lacks actual process flags'}
            }
            if($p.executable -cne $runtime.executable -or $p.executable_sha256 -cne $runtime.executable_sha256 -or
                $p.working_directory -cne $origin -or ($p.exit_code -isnot [int] -and $p.exit_code -isnot [long]) -or $p.exit_code -ne 0 -or $p.timed_out -or $p.abnormal_exit_kind -or
                $p.capture_exceeded -or $p.pipe_drain_failed -or $p.process_tree_kill_error -or $p.stderr_bytes -ne 0){
                throw 'Configured fixture process failed or used another runtime/directory'
            }
            $captures=@{}
            foreach($stream in @('stdout','stderr')){
                $captures[$stream]=Resolve-Observation $p[$stream+'_path'] $p[$stream+'_sha256']
                if((Get-Item -LiteralPath $captures[$stream]).Length -ne $p[$stream+'_bytes']){throw 'Configured fixture raw capture identity differs'}
            }
            $out=[IO.File]::ReadAllText($captures.stdout).Replace("`r`n","`n")
            if($operation -ceq 'configuration'){
                if($p.arguments -isnot [Array] -or $p.arguments.Count -ne 1 -or ($p.arguments -join '|') -cne '--conformance-config'){throw 'Configured fixture configuration arguments differ'}
                $observed=$out|ConvertFrom-Json -AsHashtable
                [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration -Target $runtime.role -AllocatorLimitBytes 2147483648)
            }else{
                $definition=@($definitions|Where-Object id -CEQ $operation)[0]
                if($p.arguments -isnot [Array] -or $p.arguments.Count -ne 3 -or $p.arguments[0] -cne '-e' -or
                    $p.arguments[1] -cne $definition.setup -or
                    $p.arguments[2].Replace('\','/') -cne ($origin.Replace('\','/').TrimEnd('/')+'/'+$definition.source)){
                    throw 'Configured fixture explicit setup or source argument differs'
                }
                if($out -cne $definition.stdout){throw 'Configured fixture complete ordered protocol or real T witness differs'}
                $telemetryPath=Resolve-Observation $row.telemetry.path $row.telemetry.sha256
                $telemetry=Get-Content -LiteralPath $telemetryPath -Raw|ConvertFrom-Json -AsHashtable
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

function Assert-ConfiguredFixtureImageReport {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Report,
        [Parameter(Mandatory)][Collections.IDictionary]$Image,[Parameter(Mandatory)][string]$Payload)
    if($Report.repository_revision -cne $Image.revision -or $Report.repository_dirty -isnot [bool] -or $Report.repository_dirty -or
        $Report.context -cne $Image.context){throw 'Configured fixture image source/context differs or is dirty'}
    # Resolver scriptblocks use PowerShell's dynamic scope. Keep this binding
    # distinct from the ordinary report reader's unnormalized execution root.
    $imageOriginPrefix=$Report.repository_root.Replace('\','/').TrimEnd('/')+'/'
    $resolve={param($path,$hash)
        $normalized=$path.Replace('\','/')
        if(-not $normalized.StartsWith($imageOriginPrefix,[StringComparison]::Ordinal)){throw 'Configured fixture image path is outside its original repository'}
        $relative=$normalized.Substring($imageOriginPrefix.Length)
        if($relative -match '(^|/)\.\.?(/|$)|:' -or $relative.StartsWith('/') -or
            @($Image.files|Where-Object{$_.path -ceq $relative -and $_.sha256 -ceq $hash}).Count -ne 1){
            throw 'Configured fixture file is absent from its exact frozen image'
        }
        return (Join-Path $Payload $relative)
    }
    foreach($runtime in $Report.runtimes){
        $ada=$runtime.role -ceq 'Ada';$expected=$Image.paths[$(if($ada){'ada_launcher'}else{'c_oracle'})]
        if($runtime.executable.Replace('\','/') -cne ($imageOriginPrefix+$expected)){throw 'Configured fixture uses a different frozen interpreter'}
        $directory=$Image.paths[$(if($ada){'ada_runtime'}else{'c_runtime'})]
        foreach($library in $runtime.library_files){
            if($library.path.Replace('\','/') -cne ($imageOriginPrefix+$directory+'/'+[IO.Path]::GetFileName($library.path.Replace('\','/')))){
                throw 'Configured fixture uses a different frozen runtime directory'
            }
        }
    }
    return Assert-ConfiguredFixtureReport -Root $Root -Report $Report -Configuration $Image.context.Split('/')[0] `
        -Interpreter (Join-Path $Payload $Image.paths.ada_launcher) -ResolveFile $resolve
}

Export-ModuleMember -Function Get-ConfiguredFixtureDefinitions,Get-ConfiguredFixtureSources,Get-ConfiguredFixtureAudit,Assert-ConfiguredFixtureReport,Assert-ConfiguredFixtureImageReport
