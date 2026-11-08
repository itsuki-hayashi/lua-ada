Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'CliFixtureEvidence.psm1')

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
        $metadata=@('First_Protected','Nested_Protected','Numeric_Error','False_Result','Byte_Ceiling','Repeated_Entry',
            'Outstanding_Shrink','Error_After_Shrink','Cross_Context_Return','Cross_Context_Error','ResetCI_Outstanding','ResetCI_Refusal','Primitive_Strings',
            'Primitive_Numbers','Primitive_False_Nil','Same_Object_Equality','Table_Equality_Yields','Userdata_Equality_Handler',
            'Assert_Success_Tuple','Assert_Protected_Tuple','Independent_Checkstack_Refusal')
        $definitions+=@{id='call-metadata-windows';source='tests/lua/call_metadata_windows.lua';
            setup="$guard;assert(type(T.testC)=='function' and type(T.alloccount)=='function' and type(T.totalmem)=='function' and rawget(_G,'_CALL_METADATA_CASE')==nil);print('CONFIGURED-FIXTURE: real T call metadata')";
            stdout="CONFIGURED-FIXTURE: real T call metadata`n"+
                (($metadata|ForEach-Object{"PASS call metadata $_"})-join "`n")+"`n"}
        $tail=@('Optimized_Vararg_Count','Optimized_Vararg_Bytes','Tail_Tuple','Tail_Chain','Tail_Weak_Argument',
            'Tail_Hook_Mutation','Tail_Hook_Error','Tail_Yield','Tail_Close_Error','Tail_Refusal_Recovery')
        $definitions+=@{id='canonical-tail-ownership';source='tests/lua/canonical_tail_ownership.lua';
            setup="$guard;assert(type(T.testC)=='function' and type(T.alloccount)=='function' and type(T.totalmem)=='function' and rawget(_G,'_TAIL_OWNERSHIP_CASE')==nil);print('CONFIGURED-FIXTURE: real T canonical tail ownership')";
            stdout="CONFIGURED-FIXTURE: real T canonical tail ownership`n"+
                (($tail|ForEach-Object{"PASS tail ownership $_"})-join "`n")+"`n"}
        $closing=@('Original_Failure','Multiple_Failure','Closer_Failure','Cold_True','Nil_Entry','False_Entry',
            'Closed_Upvalue','Mutable_Stack','Suspended_Roots','Captured_Suspended','Generic_For_Scope','Jump_Scope')
        $definitions+=@{id='scalar-closing-refusal';source='tests/lua/scalar_closing_refusal.lua';
            setup="$guard;assert(type(T.alloccount)=='function' and rawget(_G,'_SCALAR_CLOSING_CASE')==nil);print('CONFIGURED-FIXTURE: real T scalar closing')";
            stdout="CONFIGURED-FIXTURE: real T scalar closing`n"+
                (($closing|ForEach-Object{"PASS scalar closing $_"})-join "`n")+"`n"}
        $materialized=@('Count_Faults','Byte_Faults','Partial_Release','Retained_Recovery')
        $definitions+=@{id='materialized-vararg-refusal';source='tests/lua/materialized_vararg_refusal.lua';
            setup="$guard;assert(type(T.testC)=='function' and type(T.alloccount)=='function' and type(T.totalmem)=='function' and rawget(_G,'_MATERIALIZED_VARARG_CASE')==nil);print('CONFIGURED-FIXTURE: real T materialized vararg refusal')";
            stdout="CONFIGURED-FIXTURE: real T materialized vararg refusal`n"+
                (($materialized|ForEach-Object{"PASS materialized vararg refusal $_"})-join "`n")+"`n"}
        $external=@('Short_Binary','Long_Borrow','Child_State','Invalid_Type')
        $definitions+=@{id='fixed-external-strings';source='tests/lua/fixed_external_strings.lua';
            setup="$guard;assert(type(T.externKstr)=='function' and rawget(_G,'_FIXED_EXTERNAL_CASE')==nil);print('CONFIGURED-FIXTURE: real T fixed external strings')";
            stdout="CONFIGURED-FIXTURE: real T fixed external strings`n"+
                (($external|ForEach-Object{"PASS fixed external $_"})-join "`n")+"`n"}
        $hashCases=@('Length_0','Length_10','Length_39','Length_40','Length_41','Length_1000','Binary','Invalid_Type')
        $definitions+=@{id='string-hash-invariants';source='tests/lua/string_hash_invariants.lua';
            setup="$guard;assert(type(T.hash)=='function' and type(T.externstr)=='function' and type(T.externKstr)=='function');print('CONFIGURED-FIXTURE: real T string hash')";
            stdout="CONFIGURED-FIXTURE: real T string hash`n"+
                (($hashCases|ForEach-Object{"PASS string hash $_"})-join "`n")+"`n"}
        foreach($name in @('length-result-refusal','length-empty-result-refusal')){
            $definitions+=@{id=$name;source=('tests/lua/'+$name.Replace('-','_')+'.lua');
                setup="$guard;assert(type(T.alloccount)=='function');print('CONFIGURED-FIXTURE: real T $name')";
                stdout="CONFIGURED-FIXTURE: real T $name`nPASS: $name`n"}
        }
        $definitions+=@{id='nextvar-storage-private';source='tests/lua/nextvar_storage_invariants.lua';roles=@('Ada');
            script_arguments=@('ada-storage');call_return=29;
            setup="$guard;assert(type(T.ada_check_table_storage)=='function');print('CONFIGURED-FIXTURE: actual Ada nextvar storage')";
            stdout="CONFIGURED-FIXTURE: actual Ada nextvar storage`n"+(Get-NextvarStorageProtocol)}
    }
    # This fixture deliberately counts instructions. Its own source contract
    # requires one C-compiled graph, consumed unchanged by both interpreters;
    # comparing different source compilers would compare optimization choices.
    $marker="CONFIGURED-FIXTURE: identical C iterator chunk $Configuration"
    $definitions+=@{id='debug-iterator-counts';source='tests/lua/debug_iterator_counts.lua';
        execution='native-dumped-chunk';setup="$guard;print('$marker')";
        stdout="$marker`niterator count`t1`t6`niterator count`t2`t13`nOK`n"}
    # Keep this ordinary source in the generic default glob too. The separate
    # pair supplies structured source/runtime/cleanup evidence for the private
    # optimizer exclusions' retained public semantics in every configuration.
    $definitions+=@{id='code-public-semantics';source='tests/lua/code_public_semantics.lua';generic_default=$true;
        setup="$guard;print('CONFIGURED-FIXTURE: public optimizer semantics')";
        stdout="CONFIGURED-FIXTURE: public optimizer semantics`nCode public semantics OK`n"}
    foreach($case in @('first','empty','failure')){
        $definitions+=@{id=('length-result-'+$case);source='tests/lua/length_result_semantics.lua';script_arguments=@($case);
            setup="$guard;print('CONFIGURED-FIXTURE: public length result $case')";
            stdout="CONFIGURED-FIXTURE: public length result $case`nPASS: length-result-$case`n"}
    }
    $definitions+=@{id='nextvar-storage-public';source='tests/lua/nextvar_storage_invariants.lua';script_arguments=@('public');call_return=29;
        setup="$guard;print('CONFIGURED-FIXTURE: public nextvar storage')";
        stdout="CONFIGURED-FIXTURE: public nextvar storage`n"+(Get-NextvarStorageProtocol)}
    return $definitions
}

function Get-NextvarStorageProtocol {
    return ((@('Library','Constructors','Open_Constructor','Dense','Hash','Reverse','Sparse','Array_Churn',
        'Hash_Churn','Vararg','Object_Lifetime')|ForEach-Object{"PASS nextvar storage $_"})-join "`n")+"`n"
}

function Get-ConfiguredFixtureArguments {
    param([string]$Root,[Collections.IDictionary]$Definition,[string]$FixtureInput='')
    if($FixtureInput -eq ''){$FixtureInput=$Root.Replace('\','/').TrimEnd('/')+'/'+$Definition.source}
    $arguments=@('-e',$Definition.setup,$FixtureInput)
    if($Definition.Contains('call_return')){
        # These two source-owned modes execute the complete unchanged helper
        # and retain its one integer result. No original primary is patched.
        $mode=if($Definition.id -ceq 'nextvar-storage-public'){'public'}elseif($Definition.id -ceq 'nextvar-storage-private'){'ada-storage'}else{throw 'Unknown configured source-call protocol'}
        if($Definition.call_return -ne 29 -or ($Definition.script_arguments -join '|') -cne $mode){throw 'Configured nextvar mode or return protocol differs'}
        $quoted=$FixtureInput.Replace('\','/').Replace("'","\'")
        return @('-e',($Definition.setup+";local r=table.pack(assert(loadfile('$quoted'))('$mode'));assert(r.n==1 and math.type(r[1])=='integer' and r[1]==29)"))
    }
    if($Definition.Contains('script_arguments')){$arguments+=@($Definition.script_arguments)}
    return $arguments
}

function Get-ConfiguredFixtureRoles {
    param([Parameter(Mandatory)][Collections.IDictionary]$Definition)
    if(-not $Definition.Contains('roles')){return @('ReferenceC','Ada')}
    # This is a real Ada invariant inspector, not a querytab implementation or
    # a facade on native T. Its separate observation cannot credit a C pair.
    if($Definition.id -cnotin @('table-storage-private','nextvar-storage-private') -or $Definition.roles -isnot [Array] -or
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
        'scripts/ConformanceRunner.psm1','scripts/ManagedTelemetry.psm1','scripts/ConformanceInventory.psm1',
        'tests/lua/coroutine_result_portal.lua','tests/lua/stack_inspection.lua','tests/lua/primitive_not_refusal.lua',
        'tests/lua/public_api_commands.lua','tests/lua/public_panic_controls.lua','tests/lua/public_panic_file.lua',
        'tests/lua/reader_refusal_phases.lua','tests/lua/string_refusal_phases.lua','tests/lua/hook_transition_c.lua',
        'tests/lua/debug_iterator_counts.lua',
        'tests/lua/table_storage_public.lua','tests/lua/table_storage_private.lua',
        'tests/lua/code_public_semantics.lua','tests/lua/call_metadata_windows.lua','tests/lua/call_metadata_public.lua',
        'tests/lua/canonical_tail_ownership.lua','tests/lua/canonical_tail_public.lua',
        'tests/lua/scalar_closing_refusal.lua','tests/lua/scalar_closing_public.lua',
        'tests/lua/scalar_closing_mutation.lua','tests/lua/materialized_vararg.lua','tests/lua/materialized_vararg_refusal.lua',
        'tests/lua/fixed_external_strings.lua','tests/lua/table_error_arguments.lua','tests/lua/locale_strings.lua',
        'tests/lua/string_hash_invariants.lua','tests/src/lua-string_hash_tests.adb','tests/src/lua-string_hash_tests.ads',
        'tests/lua/nextvar_storage_invariants.lua','tests/src/lua-nextvar_storage_tests.adb','tests/src/lua-nextvar_storage_tests.ads',
        'tests/lua/length_result_semantics.lua','tests/lua/length_result_refusal.lua','tests/lua/length_empty_result_refusal.lua',
        'tests/src/lua-sessions-length_result_tests.adb','tests/src/lua-sessions-length_result_tests.ads',
        'tests/lua/cli_argument_controls.lua','tests/src/lua-sessions-cli_argument_tests.adb','tests/src/lua-sessions-cli_argument_tests.ads',
        'scripts/observe-cli-dynamic-arg.ps1','scripts/observe-cli-arg-lifecycle.ps1',
        'tests/conformance/targets/remaining-upstream-compatibility/cli-dynamic-arg.author-cases.json',
        'tests/conformance/targets/remaining-upstream-compatibility/cli-arg-lifecycle.author-cases.json',
        'tests/conformance/platform/cli-dynamic-arg.lua',
        'tests/lua/cli_prompt_controls.lua','scripts/CliFixtureCases.psm1','scripts/CliFixtureEvidence.psm1',
        'scripts/check-configured-cli.ps1','scripts/check-cli.ps1',
        'cli/shared/lua_ada_cli_readline.c','cli/shared/lua_ada_cli_prompt.c',
        'cli/shared/lua-sessions-cli.adb','cli/shared/lua-sessions-cli.ads','cli/shared/lua_cli.adb',
        'cli/lua_ada_cli.gpr','tests/lua_ada_tests.gpr','scripts/check-cli-readline.ps1','scripts/test-cli-readline-portability.ps1',
        'scripts/TargetHostCampaignContracts.psm1',
        'tests/src/lua-sessions-cli_prompt_tests.adb','tests/src/lua-sessions-cli_prompt_tests.ads',
        'tests/src/code_public_semantic_tests.adb','tests/src/code_public_semantic_tests.ads',
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
    $ordinaryIds=@(Get-ConfiguredFixtureDefinitions default|ForEach-Object id)
    $only=@(Get-ConfiguredFixtureDefinitions upstream-test|Where-Object{$_.id -cnotin $ordinaryIds})
    $classification=Get-Content (Join-Path $Root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable
    $hostOnly=@(Assert-CliHostClassification -Root $Root -Classification $classification)
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
        $ordinaryPolicy=switch -CaseSensitive ($definition.id){
            'call-metadata-windows' {@{path='tests/lua/call_metadata_public.lua';names=@('Assert_Protected_Tuple','Table_Equality_Yields')}}
            'canonical-tail-ownership' {@{path='tests/lua/canonical_tail_public.lua';names=@('Tail_Close_Error','Tail_Hook_Error','Tail_Hook_Mutation','Tail_Weak_Argument','Tail_Yield')}}
            'scalar-closing-refusal' {@{path='tests/lua/scalar_closing_public.lua';names=@('Closed_Upvalue','Mutable_Stack','Suspended_Roots','Captured_Suspended','Jump_Scope')}}
            default {$null}
        }
        if($null -ne $ordinaryPolicy){
            # Keep the two T-free public case bodies in ordinary execution,
            # rather than hiding them behind the full provider campaign's
            # unconditional T requirement. Both sides are exact source bytes;
            # a copied case name or successful marker cannot replace a body.
            if(-not $record[0].Contains('retained_default_counterpart')){throw 'Configured mixed fixture lacks its ordinary counterpart'}
            $ordinaryCounterpart=$record[0].retained_default_counterpart
            if($ordinaryCounterpart.path -cne $ordinaryPolicy.path -or
                $ordinaryCounterpart.runtime_evidence -isnot [Array] -or $ordinaryCounterpart.runtime_evidence.Count -ne 0 -or
                $ordinaryCounterpart.case_spans -isnot [Array] -or $ordinaryCounterpart.case_spans.Count -ne $ordinaryPolicy.names.Count -or
                (($ordinaryCounterpart.case_spans.name|Sort-Object) -join '|') -cne (($ordinaryPolicy.names|Sort-Object)-join '|')){
                throw 'Configured mixed fixture ordinary correspondence is incomplete or invents evidence'
            }
            $ordinaryPath=Join-Path $Root $ordinaryCounterpart.path
            if((Get-FileHash $ordinaryPath).Hash.ToLowerInvariant() -cne $ordinaryCounterpart.sha256){throw 'Configured mixed fixture ordinary counterpart source is stale'}
            $originalBytes=[IO.File]::ReadAllBytes((Join-Path $Root $path));$ordinaryBytes=[IO.File]::ReadAllBytes($ordinaryPath)
            foreach($case in $ordinaryCounterpart.case_spans){
                $slices=@()
                foreach($role in @('original','ordinary')){
                    $span=$case[$role];$data=if($role -ceq 'original'){$originalBytes}else{$ordinaryBytes}
                    if(($span.byte_offset -isnot [int] -and $span.byte_offset -isnot [long]) -or $span.byte_offset -lt 0 -or
                        ($span.byte_length -isnot [int] -and $span.byte_length -isnot [long]) -or $span.byte_length -le 0 -or
                        $span.byte_offset -gt $data.Length -or $span.byte_length -gt $data.Length-$span.byte_offset){
                        throw 'Configured mixed fixture ordinary correspondence is outside its source'
                    }
                    $bytes=[byte[]]::new($span.byte_length);[Array]::Copy($data,$span.byte_offset,$bytes,0,$bytes.Length)
                    if((Get-ConformanceHash $bytes) -cne $span.sha256 -or
                        -not [regex]::IsMatch([Text.Encoding]::UTF8.GetString($bytes),
                            "\A {1,2}\{'"+[regex]::Escape($case.name)+"',function\(\)")){
                        throw 'Configured mixed fixture ordinary correspondence source bytes differ'
                    }
                    $slices+=,(Get-ConformanceHash $bytes)
                }
                if($slices[0] -cne $slices[1]){throw 'Configured mixed fixture ordinary correspondence bodies differ'}
            }
            if($definition.id -ceq 'scalar-closing-refusal'){
                # These public bodies share an actual metatable constructor.
                # Matching case text alone must not permit a changed helper
                # to alter their finalizer/closing behavior in the companion.
                $helperText='local function closable(fn)return setmetatable({},{__close=fn})end'
                if(-not $ordinaryCounterpart.Contains('helper_spans') -or
                    $ordinaryCounterpart.helper_spans -isnot [Array] -or $ordinaryCounterpart.helper_spans.Count -ne 1 -or
                    $ordinaryCounterpart.helper_spans[0].name -cne 'closable'){
                    throw 'Scalar closing ordinary counterpart lacks its exact shared helper'
                }
                foreach($role in @('original','ordinary')){
                    $span=$ordinaryCounterpart.helper_spans[0][$role]
                    $data=if($role -ceq 'original'){$originalBytes}else{$ordinaryBytes}
                    if(($span.byte_offset -isnot [int] -and $span.byte_offset -isnot [long]) -or $span.byte_offset -lt 0 -or
                        ($span.byte_length -isnot [int] -and $span.byte_length -isnot [long]) -or
                        $span.byte_length -ne [Text.Encoding]::UTF8.GetByteCount($helperText) -or
                        $span.byte_offset -gt $data.Length -or $span.byte_length -gt $data.Length-$span.byte_offset){
                        throw 'Scalar closing ordinary helper correspondence is outside its source'
                    }
                    $slice=[byte[]]::new($span.byte_length);[Array]::Copy($data,$span.byte_offset,$slice,0,$slice.Length)
                    if((Get-ConformanceHash $slice) -cne $span.sha256 -or [Text.Encoding]::UTF8.GetString($slice) -cne $helperText){
                        throw 'Scalar closing ordinary helper differs from its actual source'
                    }
                }
            }
        }
        if($roles.Count -eq 1){
            $links=$record[0].source_linkage
            $requiredLinks=@('tests/src/lua-conformance_adapter.adb','tests/c/conformance_adapter.c',
                'tests/src/lua-table_storage_inspection_tests.adb','tests/src/lua-table_storage_inspection_tests.ads',
                'tests/src/lua-engine-table_storage_probe.ads','tests/src/lua-engine-table_storage_probe.adb')
            if($definition.id -ceq 'nextvar-storage-private'){
                $requiredLinks+=@('tests/src/lua-nextvar_storage_tests.adb','tests/src/lua-nextvar_storage_tests.ads')
            }
            $expectedNames=if($definition.id -ceq 'nextvar-storage-private'){17}else{22}
            if($links.kind -cne 'source-linkage-only' -or $links.runtime_evidence -isnot [Array] -or $links.runtime_evidence.Count -ne 0 -or
                $links.aunit_named_cases -isnot [Array] -or $links.aunit_named_cases.Count -ne $expectedNames -or
                $links.bindings -isnot [Array] -or (($links.bindings.path|Sort-Object) -join '|') -cne (($requiredLinks|Sort-Object) -join '|')){
                throw 'Configured Ada invariant source linkage is incomplete or invents execution evidence'
            }
            foreach($binding in $links.bindings){
                if($binding.path -cnotin (Get-ConfiguredFixtureSources upstream-test) -or
                    (Get-FileHash (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){
                    throw 'Configured Ada invariant implementation linkage is stale'
                }
            }
            $source=if($definition.id -ceq 'nextvar-storage-private'){'tests/src/lua-nextvar_storage_tests.adb'}else{'tests/src/lua-table_storage_inspection_tests.adb'}
            $text=Get-Content (Join-Path $Root $source) -Raw
            $named=@([regex]::Matches($text,"(?s)Test_Support\.Add\s*\(Suite,\s*`"([^`"]+)`"\s*,\s*([A-Za-z0-9_]+)'Access")|
                ForEach-Object{$source+'#'+$_.Groups[2].Value+'|OK '+$_.Groups[1].Value}|Sort-Object)
            $declared=@($links.aunit_named_cases|ForEach-Object{$_.case+'|'+$_.required_stdout_line}|Sort-Object)
            $expectedNames=if($definition.id -ceq 'nextvar-storage-private'){17}else{22}
            if($named.Count -ne $expectedNames -or ($named -join "`n") -cne ($declared -join "`n")){
                throw 'Configured Ada invariant named AUnit linkage differs; links are not runtime evidence'
            }
        }
    }
    $entries=@(foreach($file in Get-ChildItem (Join-Path $Root 'tests/lua') -File -Filter '*.lua'|Sort-Object Name){
        $path='tests/lua/'+$file.Name
        $tokens=Get-ConformanceTokens -Bytes ([IO.File]::ReadAllBytes($file.FullName))
        $references=@($tokens|Where-Object{$_.Text -ceq 'T' -and -not $_.IsString})
        if($references.Count -and $path -cnotin $instrumented -and $path -cnotin $hostOnly){
            throw "Unclassified T-bearing fixture requires an explicit mixed/default/T campaign audit: $path"
        }
        # This is an explicit selection audit, not a Lua scope parser or proof
        # of compatibility. New T-bearing files fail closed for human review;
        # mixed ordinary/T files must appear in both configured selections.
        [ordered]@{path=$path;sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();T_identifiers=$references.Count;
            selection=$(if($path -cin $hostOnly){'configured-host-CLI-only'}elseif($path -ceq 'tests/lua/code_public_semantics.lua'){'generic-default-plus-paired-configured'}elseif($path -cin $ordinary){'paired-configured-default-and-T'}elseif($path -cin $instrumented){
                @($classification.entries|Where-Object path -CEQ $path)[0].selection}else{'generic-default-source-comparison'})}
    })
    return [ordered]@{schema_version=1;kind='first-party-fixture-selection-audit';entries=$entries;
        runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-ConfiguredFixtureNamedCounterparts {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][Collections.IDictionary]$NamedEvidence)
    if($NamedEvidence.context -cne $Context -or $NamedEvidence.runtime_observed -isnot [bool] -or -not $NamedEvidence.runtime_observed){
        throw 'Configured semantic counterparts require actual same-context named AUnit observations'
    }
    $codeSource='tests/src/code_public_semantic_tests.adb'
    $codeNames=@([regex]::Matches((Get-Content (Join-Path $Root $codeSource) -Raw),
        "(?s)Test_Support\.Add\s*\(Suite,\s*`"([^`"]+)`"\s*,\s*([A-Za-z0-9_]+)'Access")|
        ForEach-Object{$codeSource+'#'+$_.Groups[2].Value})
    if($codeNames.Count -ne 29 -or @($codeNames|Sort-Object -Unique).Count -ne 29){throw 'Configured public optimizer source requires its exact29 named registrations'}
    foreach($case in $codeNames){
        if($case -cnotin $NamedEvidence.named_aunit_cases){throw 'Configured public optimizer lacks an actual required named AUnit counterpart'}
    }
    if(-not $Context.StartsWith('upstream-test/',[StringComparison]::Ordinal)){return}
    # These identities are only linkage until the named-evidence reader has
    # checked fresh source-bound raw AUnit receipts. The final image consumer
    # separately requires independent source review and frozen membership.
    $classification=Get-Content (Join-Path $Root 'tests/conformance/targets/configured-fixture-classification.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 24
    $row=@($classification.entries|Where-Object selection -CEQ configured-Ada-internal-counterpart-only)
    if($row.Count -ne 2 -or @($row.source_linkage.aunit_named_cases).Count -ne 39){throw 'Configured Ada invariant named linkage is incomplete'}
    foreach($case in @($row.source_linkage.aunit_named_cases)){
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
                $expectedArguments=Get-ConfiguredFixtureArguments -Root $origin -Definition $definition -FixtureInput $fixtureInput
                $actualArguments=@($p.arguments)
                if($actualArguments.Count -ge 3){$actualArguments[2]=$actualArguments[2].Replace('\','/')}
                if($p.arguments -isnot [Array] -or ($actualArguments -join "`0") -cne ($expectedArguments -join "`0")){
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

Export-ModuleMember -Function Get-ConfiguredFixtureDefinitions,Get-ConfiguredFixtureRoles,Get-ConfiguredFixtureArguments,Get-ConfiguredFixtureProducerArguments,Get-ConfiguredFixtureSources,Get-ConfiguredFixtureAudit,Assert-ConfiguredFixtureReport,Assert-ConfiguredFixtureNamedCounterparts,Assert-ConfiguredFixtureImageReport
