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
        $definitions+=@{id='table-storage-private';source='tests/lua/table_storage_private.lua';roles=@('Ada');
            setup="$guard;assert(type(T.ada_check_table_storage)=='function');print('CONFIGURED-FIXTURE: actual Ada table storage')";
            stdout="CONFIGURED-FIXTURE: actual Ada table storage`n"+
                ((@('Initial_Live_Entries','Deleted_Key_Reclamation','Same_Table_Reuse')|
                    ForEach-Object{"PASS: Ada table storage $_"})-join "`n")+"`nTable storage private OK`n"}
    }
    # This fixture deliberately counts instructions. Its own source contract
    # requires one C-compiled graph, consumed unchanged by both interpreters;
    # comparing different source compilers would compare optimization choices.
    $marker="CONFIGURED-FIXTURE: identical C iterator chunk $Configuration"
    $definitions+=@{id='debug-iterator-counts';source='tests/lua/debug_iterator_counts.lua';
        execution='native-dumped-chunk';setup="$guard;print('$marker')";
        stdout="$marker`niterator count`t1`t6`niterator count`t2`t13`nOK`n"}
    return $definitions
}

function Get-ConfiguredFixtureRoles {
    param([Parameter(Mandatory)][Collections.IDictionary]$Definition)
    if(-not $Definition.Contains('roles')){return @('ReferenceC','Ada')}
    # This is a real Ada invariant inspector, not a querytab implementation or
    # a facade on native T. Its separate observation cannot credit a C pair.
    if($Definition.id -cne 'table-storage-private' -or $Definition.roles -isnot [Array] -or
        $Definition.roles.Count -ne 1 -or $Definition.roles[0] -cne 'Ada'){
        throw 'Configured fixture internal counterpart roles differ'
    }
    return @('Ada')
}

function Get-ConfiguredFixtureProducerArguments {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Definition,
        [Parameter(Mandatory)][string]$Output)
    if(-not $Definition.Contains('execution') -or $Definition.execution -cne 'native-dumped-chunk' -or
        $Definition.id -cne 'debug-iterator-counts' -or $Definition.source -cne 'tests/lua/debug_iterator_counts.lua'){
        throw 'Configured fixture has no reviewed native chunk producer'
    }
    # Use a text-only load of the exact source path. The generated complete
    # graph is written with wb: Windows text stdout would alter embedded LF
    # bytes. Ada never compiles this fixture separately in this campaign.
    $source=(Join-Path $Root $Definition.source).Replace('\','/').Replace("'","\'")
    $destination=$Output.Replace('\','/').Replace("'","\'")
    return @('-e',"local f=assert(loadfile('$source','t'));local out=assert(io.open('$destination','wb'));assert(out:write(string.dump(f)));assert(out:close());print('CONFIGURED-FIXTURE: C iterator graph produced')")
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
        'tests/lua/debug_iterator_counts.lua',
        'tests/lua/table_storage_public.lua','tests/lua/table_storage_private.lua',
        'tests/src/lua-table_storage_inspection_tests.ads','tests/src/lua-table_storage_inspection_tests.adb',
        'tests/src/lua-engine-table_storage_probe.ads','tests/src/lua-engine-table_storage_probe.adb',
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
    $only=@(Get-ConfiguredFixtureDefinitions upstream-test|Where-Object{$_.source -cnotin $ordinary})
    $classification=Get-Content (Join-Path $Root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable
    if($classification.schema_version -ne 1 -or $classification.kind -cne 'first-party-configured-fixture-classification' -or
        $classification.runtime_acceptance -isnot [bool] -or $classification.runtime_acceptance -or
        $classification.coverage_authority -isnot [bool] -or $classification.coverage_authority -or
        $classification.entries -isnot [Array] -or $classification.entries.Count -ne $only.Count){
        throw 'Configured fixture classification is incomplete or claims runtime authority'
    }
    foreach($definition in $only){
        $path=$definition.source
        $roles=@(Get-ConfiguredFixtureRoles $definition)
        $selection=if($roles.Count -eq 1){'configured-Ada-internal-counterpart-only'}else{'paired-configured-T-only'}
        $record=@($classification.entries|Where-Object path -CEQ $path)
        if($record.Count -ne 1 -or $record[0].selection -cne $selection -or
            [string]::IsNullOrWhiteSpace($record[0].rationale) -or
            (Get-FileHash (Join-Path $Root $path)).Hash.ToLowerInvariant() -cne $record[0].sha256){
            throw "Configured T-only classification requires a fresh mixed/default/T source review: $path"
        }
        if($roles.Count -eq 1){
            $links=$record[0].source_linkage
            $requiredLinks=@('tests/src/lua-conformance_adapter.adb','tests/c/conformance_adapter.c',
                'tests/src/lua-table_storage_inspection_tests.adb','tests/src/lua-table_storage_inspection_tests.ads',
                'tests/src/lua-engine-table_storage_probe.ads','tests/src/lua-engine-table_storage_probe.adb')
            if($links.kind -cne 'source-linkage-only' -or $links.runtime_evidence -isnot [Array] -or $links.runtime_evidence.Count -ne 0 -or
                $links.aunit_named_cases -isnot [Array] -or $links.aunit_named_cases.Count -ne 22 -or
                $links.bindings -isnot [Array] -or (($links.bindings.path|Sort-Object) -join '|') -cne (($requiredLinks|Sort-Object) -join '|')){
                throw 'Configured Ada invariant source linkage is incomplete or invents execution evidence'
            }
            foreach($binding in $links.bindings){
                if($binding.path -cnotin (Get-ConfiguredFixtureSources upstream-test) -or
                    (Get-FileHash (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){
                    throw 'Configured Ada invariant implementation linkage is stale'
                }
            }
            $source='tests/src/lua-table_storage_inspection_tests.adb'
            $text=Get-Content (Join-Path $Root $source) -Raw
            $named=@([regex]::Matches($text,"(?s)Test_Support\.Add\s*\(Suite,\s*`"([^`"]+)`"\s*,\s*([A-Za-z0-9_]+)'Access")|
                ForEach-Object{$source+'#'+$_.Groups[2].Value+'|OK '+$_.Groups[1].Value}|Sort-Object)
            $declared=@($links.aunit_named_cases|ForEach-Object{$_.case+'|'+$_.required_stdout_line}|Sort-Object)
            if($named.Count -ne 22 -or ($named -join "`n") -cne ($declared -join "`n")){
                throw 'Configured Ada invariant named AUnit linkage differs; links are not runtime evidence'
            }
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
            selection=$(if($path -cin $ordinary){'paired-configured-default-and-T'}elseif($path -cin $instrumented){
                @($classification.entries|Where-Object path -CEQ $path)[0].selection}else{'generic-default-source-comparison'})}
    })
    return [ordered]@{schema_version=1;kind='first-party-fixture-selection-audit';entries=$entries;
        runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-ConfiguredFixtureNamedCounterparts {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][Collections.IDictionary]$NamedEvidence)
    if(-not $Context.StartsWith('upstream-test/',[StringComparison]::Ordinal)){return}
    if($NamedEvidence.context -cne $Context -or $NamedEvidence.runtime_observed -isnot [bool] -or -not $NamedEvidence.runtime_observed){
        throw 'Configured Ada invariant requires actual same-context named AUnit observations'
    }
    # These identities are only linkage until the named-evidence reader has
    # checked fresh source-bound raw AUnit receipts. The final image consumer
    # separately requires independent source review and frozen membership.
    $classification=Get-Content (Join-Path $Root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 24
    $row=@($classification.entries|Where-Object selection -CEQ configured-Ada-internal-counterpart-only)
    if($row.Count -ne 1 -or $row[0].source_linkage.aunit_named_cases.Count -ne 22){throw 'Configured Ada invariant named linkage is incomplete'}
    foreach($case in $row[0].source_linkage.aunit_named_cases){
        if($case.case -cnotin $NamedEvidence.named_aunit_cases){throw 'Configured Ada invariant lacks an actual required named AUnit counterpart'}
    }
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
    $binary=@($definitions|Where-Object{$_.Contains('execution') -and $_.execution -ceq 'native-dumped-chunk'})
    $processCount=2+$binary.Count
    foreach($definition in $definitions){$processCount+=@(Get-ConfiguredFixtureRoles $definition).Count}
    if($Report.processes.Count -ne $processCount){throw 'Configured fixture process set is incomplete or duplicated'}
    foreach($runtime in $Report.runtimes){
        if($runtime.role -cnotin @('Ada','ReferenceC') -or
            [string]::IsNullOrWhiteSpace((Resolve-Observation $runtime.executable $runtime.executable_sha256)) -or
            $runtime.library_files -isnot [Array] -or $runtime.library_files.Count -eq 0){throw 'Configured fixture runtime identity differs'}
        if(@($runtime.library_files.path|Sort-Object -Unique).Count -ne $runtime.library_files.Count){throw 'Configured fixture runtime library identities are duplicated'}
        foreach($library in $runtime.library_files){
            [void](Resolve-Observation $library.path $library.sha256)
        }
        $operations=@('configuration')+@($definitions|Where-Object{$runtime.role -cin @(Get-ConfiguredFixtureRoles $_)}|ForEach-Object id)
        if($runtime.role -ceq 'ReferenceC'){$operations+=@($binary|ForEach-Object{'produce-'+$_.id})}
        foreach($operation in $operations){
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
            $producer=$operation.StartsWith('produce-',[StringComparison]::Ordinal)
            $out=if($producer){$null}else{[IO.File]::ReadAllText($captures.stdout).Replace("`r`n","`n")}
            if($operation -ceq 'configuration'){
                if($p.arguments -isnot [Array] -or $p.arguments.Count -ne 1 -or ($p.arguments -join '|') -cne '--conformance-config'){throw 'Configured fixture configuration arguments differ'}
                $observed=$out|ConvertFrom-Json -AsHashtable
                [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration -Target $runtime.role -AllocatorLimitBytes 2147483648)
            }elseif($producer){
                $definition=@($binary|Where-Object{('produce-'+$_.id) -ceq $operation})[0]
                $chunkPath=$p.stdout_path.Substring(0,$p.stdout_path.Length-'.stdout'.Length)+'.luac'
                $arguments=Get-ConfiguredFixtureProducerArguments -Root $origin -Definition $definition -Output $chunkPath
                if($p.arguments -isnot [Array] -or $p.arguments.Count -ne $arguments.Count -or
                    ($p.arguments -join "`0") -cne ($arguments -join "`0")){
                    throw 'Configured native chunk producer source or arguments differ'
                }
                if(-not $row.Contains('output_chunk') -or $row.output_chunk.path -cne $chunkPath -or
                    [IO.File]::ReadAllText($captures.stdout).Replace("`r`n","`n") -cne "CONFIGURED-FIXTURE: C iterator graph produced`n"){
                    throw 'Configured native chunk producer completion/output identity differs'
                }
                $chunk=Resolve-Observation $row.output_chunk.path $row.output_chunk.sha256
                $bytes=[IO.File]::ReadAllBytes($chunk)
                if($bytes.Length -ne $row.output_chunk.bytes){throw 'Configured native chunk byte count differs'}
                if($bytes.Length -lt 40 -or $bytes[0] -ne 27 -or
                    [Text.Encoding]::ASCII.GetString($bytes,1,3) -cne 'Lua'){
                    throw 'Configured native chunk producer did not emit an actual Lua binary graph'
                }
            }else{
                $definition=@($definitions|Where-Object id -CEQ $operation)[0]
                $fixtureInput=$origin.Replace('\','/').TrimEnd('/')+'/'+$definition.source
                if($definition.Contains('execution') -and $definition.execution -ceq 'native-dumped-chunk'){
                    $produced=@($Report.processes|Where-Object{$_.role -ceq 'ReferenceC' -and $_.operation -ceq ('produce-'+$definition.id)})
                    if($produced.Count -ne 1 -or -not $produced[0].Contains('output_chunk') -or -not $row.Contains('input_chunk') -or
                        $row.input_chunk.path -cne $produced[0].output_chunk.path -or
                        $row.input_chunk.sha256 -cne $produced[0].output_chunk.sha256 -or
                        $row.input_chunk.bytes -ne $produced[0].output_chunk.bytes){
                        throw 'Configured identical native chunk producer/input identity differs'
                    }
                    $fixtureInput=$produced[0].output_chunk.path.Replace('\','/')
                }
                if($p.arguments -isnot [Array] -or $p.arguments.Count -ne 3 -or $p.arguments[0] -cne '-e' -or
                    $p.arguments[1] -cne $definition.setup -or
                    $p.arguments[2].Replace('\','/') -cne $fixtureInput){
                    throw 'Configured fixture explicit setup or source argument differs'
                }
                if($out -cne $definition.stdout){throw 'Configured fixture complete ordered protocol or real T witness differs'}
            }
            if($operation -cne 'configuration'){
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
    return @{configuration=$Configuration;operations=@($definitions.id);
        operation_roles=@($definitions|ForEach-Object{@{id=$_.id;roles=@(Get-ConfiguredFixtureRoles $_)}});runtime_observed=$true;
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

Export-ModuleMember -Function Get-ConfiguredFixtureDefinitions,Get-ConfiguredFixtureRoles,Get-ConfiguredFixtureProducerArguments,Get-ConfiguredFixtureSources,Get-ConfiguredFixtureAudit,Assert-ConfiguredFixtureReport,Assert-ConfiguredFixtureNamedCounterparts,Assert-ConfiguredFixtureImageReport
