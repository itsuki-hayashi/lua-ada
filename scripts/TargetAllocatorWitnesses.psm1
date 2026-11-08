Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceAllocatorEvidence.psm1')

function Get-TargetAllocatorSourcePaths {
    param([ValidateSet('ada-ceiling','native-observer')][string]$Kind,
        [ValidateSet('default','upstream-test')][string]$Configuration)
    $common=@('scripts/TargetAllocatorWitnesses.psm1','scripts/run-target-allocator-witnesses.ps1',
        'scripts/ConformanceRunner.psm1','scripts/TargetContext.psm1',
        'scripts/TargetObservationEnvelope.psm1','scripts/build-target-context.ps1')
    if($Kind -ceq 'ada-ceiling'){
        return $common+@('scripts/test-conformance-allocator-ceiling.ps1','scripts/ConformanceAllocatorEvidence.psm1',
            'scripts/ManagedTelemetry.psm1','tests/src/lua-conformance_allocator.adb',
            'tests/src/lua-sessions-conformance.adb','tests/src/lua-sessions-conformance.ads',
            'tests/src/lua-storage-conformance.adb','tests/src/lua-storage-conformance.ads',
            'src/lua-storage.adb','src/lua-storage.ads',
            ('src/configurations/'+$Configuration+'/lua-runtime_configuration.ads'))
    }
    return $common+@('scripts/test-native-allocator-observer.ps1',
        'experiments/conformance/c/allocator_observer_probe.c','experiments/conformance/c/bounded_ltests.c',
        'experiments/conformance/c/conformance_cli.c','experiments/conformance/c/allocator_limit.h',
        'experiments/conformance/c/conformance_exports.h','experiments/conformance/reference.gpr',
        'experiments/conformance/oracle.gpr','references/lua/ltests.c','references/lua/ltests.h',
        'references/lua/lua.h','references/lua/luaconf.h','references/lua/lprefix.h')
}

function Get-TawHash([string]$Path){(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function Assert-TawInteger($Value,[string]$Name){
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt 0){throw "Allocator witness integer differs: $Name"}
}
function Assert-TawFalse($Value,[string]$Name){
    if($Value -isnot [bool] -or $Value){throw "Allocator witness cannot claim $Name"}
}
function Get-TawRelative([string]$Origin,[string]$Path){
    # Recorded paths retain their original spelling in raw reports. Resolve
    # them against their explicit original checkout, then use the same logical
    # relative name inside an immutable image. Never search for '/reports/'
    # somewhere in a string: an injected outer directory could shadow it.
    $originName=$Origin.Replace('\','/').TrimEnd('/');$pathName=$Path.Replace('\','/')
    $windows=$originName -cmatch '^[A-Za-z]:/'
    $comparison=if($windows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(($originName -cnotmatch '^(?:[A-Za-z]:/|/)' -or $originName.StartsWith('//')) -or
        -not $pathName.StartsWith($originName+'/', $comparison)){
        throw 'Allocator witness artifact escapes its original checkout'
    }
    $relative=$pathName.Substring($originName.Length+1)
    if($relative.Contains(':') -or @($relative.Split('/')|Where-Object{$_ -cin @('','..','.')}).Count){
        throw 'Allocator witness artifact escapes its original checkout'
    }
    return $relative
}
function Resolve-TawArtifact([string]$Origin,[string]$ArtifactRoot,[string]$Path,[string]$Sha256){
    $relative=Get-TawRelative $Origin $Path
    if($relative -cnotmatch '^(reports/target-builds/|tests/bin/|build/conformance/|lib/)'){
        throw 'Allocator witness artifact is outside generated context paths'
    }
    $actual=[IO.Path]::GetFullPath((Join-Path $ArtifactRoot $relative))
    if($Sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $actual -PathType Leaf) -or
        ((Get-Item -LiteralPath $actual).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-TawHash $actual) -cne $Sha256){throw 'Allocator witness actual artifact hash or file differs'}
    return $actual
}
function Assert-TawProcess {
    param([Collections.IDictionary]$Process,[string]$Origin,[string]$ArtifactRoot,
        [string]$Executable,[string]$ExecutableHash,[string[]]$Arguments,[string]$Prefix,[switch]$NonzeroExit)
    # Invoke-ConformanceProcess polls in 50ms slices, then bounds process-exit
    # and pipe draining separately at 5s each. A false timed_out label cannot
    # excuse elapsed time outside that explicit transport allowance.
    $timeout=if($Prefix.Replace('\','/').EndsWith('/producer',[StringComparison]::Ordinal)){600}else{120}
    Assert-TawInteger $Process.elapsed_milliseconds 'elapsed_milliseconds'
    Assert-TawInteger $Process.timeout_seconds 'timeout_seconds'
    if($Process.timeout_seconds -ne $timeout -or $Process.elapsed_milliseconds -gt ([long]$timeout*1000+10050)){
        throw 'Allocator witness declared timeout or bounded elapsed duration differs'
    }
    Assert-TawInteger $Process.process_id 'process_id'
    if($Process.process_id -eq 0 -or $ExecutableHash -cnotmatch '^[0-9a-f]{64}$' -or
        ($Process.exit_code -isnot [int] -and $Process.exit_code -isnot [long]) -or
        $Process.executable -cne $Executable -or $Process.executable_sha256 -cne $ExecutableHash -or
        $Process.working_directory.Replace('\','/').TrimEnd('/') -cne $Origin.Replace('\','/').TrimEnd('/') -or
        $Process.arguments -isnot [Array] -or ($Process.arguments -join "`0") -cne ($Arguments -join "`0")){
        throw 'Allocator witness process identity directory or exact arguments differ'
    }
    foreach($flag in @('timed_out','capture_exceeded','pipe_drain_failed')){
        Assert-TawFalse $Process[$flag] $flag
    }
    if($Process.process_tree_kill_error -or $Process.abnormal_exit_kind -or
        (($Process.exit_code -ne 0) -ne [bool]$NonzeroExit)){
        throw 'Allocator witness process did not complete its required status'
    }
    $captures=@{}
    foreach($stream in @('stdout','stderr')){
        Assert-TawInteger $Process[$stream+'_bytes'] ($stream+'_bytes')
        if($Process[$stream+'_path'].Replace('\','/') -cne ($Prefix+'.'+$stream).Replace('\','/')){throw 'Allocator witness capture prefix differs'}
        $capture=Resolve-TawArtifact $Origin $ArtifactRoot $Process[$stream+'_path'] $Process[$stream+'_sha256']
        if((Get-Item -LiteralPath $capture).Length -ne $Process[$stream+'_bytes']){throw 'Allocator witness capture length differs'}
        $captures[$stream]=$capture
    }
    return $captures
}

function Get-TawCeilingOperations {
    # Exact reviewed application inputs are independent of printed markers.
    # The 64MiB operation must really try the protected 80MiB request and
    # recover, while the same request must succeed with the ordinary ceiling.
    $fault="if T then T.totalmem(0)end;local ok,err=pcall(string.rep,'x',80*1024*1024);assert(not ok and err=='not enough memory',tostring(err));collectgarbage();local t=table.create(2);t[1]=37;assert(t[1]==37);print('CEILING caught actual allocator refusal')"
    $success="local s=string.rep('x',80*1024*1024);assert(#s==80*1024*1024 and s:sub(1,1)=='x' and s:sub(-1)=='x');print('CEILING ordinary allocation succeeded')"
    $operations=@(@{name='absent-default';limit=2147483648L;selection=$null;arguments=@('--conformance-config')},
        @{name='explicit-ordinary';limit=2147483648L;selection='2147483648';arguments=@('--conformance-config')},
        @{name='explicit-heavy';limit=67108864L;selection='67108864';arguments=@('--conformance-config')})
    $index=0
    foreach($invalid in @('0','-1','67108865','67108864junk','+67108864','067108864','67108864 ','16#4000000#')){
        $index++;$operations+=@{name=('invalid-'+$index);selection=$invalid;invalid=$true;arguments=@('--conformance-config')}
    }
    $operations+=@{name='actual-heavy-refusal';limit=67108864L;selection='67108864';arguments=@('-e',$fault);
        stdout="CEILING caught actual allocator refusal`n";refusal=$true}
    $operations+=@{name='actual-ordinary-success';limit=2147483648L;selection='2147483648';arguments=@('-e',$success);
        stdout="CEILING ordinary allocation succeeded`n"}
    return $operations
}

function Assert-TawCeilingRaw {
    param([Collections.IDictionary]$Raw,[Collections.IDictionary]$Witness,[string]$ArtifactRoot)
    $parts=$Witness.context.Split('/');$origin=$Witness.source_repository_root
    if($Raw.schema_version -ne 1 -or $Raw.kind -cne 'conformance-allocator-ceiling-regressions' -or
        $Raw.configuration -cne $parts[0] -or $Raw.observations -isnot [Array] -or $Raw.observations.Count -ne 13 -or
        $Raw.executable.path -cne $Witness.selected_runtime.executable.path -or
        $Raw.executable.sha256 -cne $Witness.selected_runtime.executable.sha256){throw 'Allocator ceiling raw report identity or thirteen operations differ'}
    Assert-TawFalse $Raw.runtime_acceptance 'raw runtime acceptance';Assert-TawFalse $Raw.coverage_authority 'raw coverage authority'
    $null=Resolve-TawArtifact $origin $ArtifactRoot $Raw.executable.path $Raw.executable.sha256
    $rawDirectory=Split-Path -Parent (Resolve-TawArtifact $origin $ArtifactRoot $Witness.producer_report.path $Witness.producer_report.sha256)
    $originalDirectory=$Witness.producer_report.path.Replace('\','/');$originalDirectory=$originalDirectory.Substring(0,$originalDirectory.LastIndexOf('/'))
    $operations=@(Get-TawCeilingOperations);$runs=@{};$sidecars=0
    for($index=0;$index -lt $operations.Count;$index++){
        $expected=$operations[$index];$row=$Raw.observations[$index]
        if($row.name -cne $expected.name -or $row.environment -isnot [Collections.IDictionary]){throw 'Allocator ceiling ordered operation differs'}
        $keys=@('LUA_ADA_CONFORMANCE_TELEMETRY','LUA_ADA_CONFORMANCE_RUN_ID')
        if($null -ne $expected.selection){$keys+='LUA_ADA_CONFORMANCE_ALLOCATOR'}
        $run=$row.environment.LUA_ADA_CONFORMANCE_RUN_ID
        if((($row.environment.Keys|Sort-Object)-join '|') -cne (($keys|Sort-Object)-join '|') -or
            $run -isnot [string] -or $run -cnotmatch '^[0-9a-f]{32}$' -or $runs.ContainsKey($run) -or
            ($null -ne $expected.selection -and ($row.environment.LUA_ADA_CONFORMANCE_ALLOCATOR -isnot [string] -or
             $row.environment.LUA_ADA_CONFORMANCE_ALLOCATOR -cne $expected.selection)) -or
            $row.environment.LUA_ADA_CONFORMANCE_TELEMETRY.Replace('\','/') -cne ($originalDirectory+'/'+$expected.name+'.telemetry')){
            throw 'Allocator ceiling selected environment or unique run identity differs'
        }
        $runs[$run]=$true
        $invalid=$expected.Contains('invalid') -and $expected.invalid
        $captures=Assert-TawProcess -Process $row.process -Origin $origin -ArtifactRoot $ArtifactRoot `
            -Executable $Raw.executable.path -ExecutableHash $Raw.executable.sha256 -Arguments $expected.arguments `
            -Prefix ($originalDirectory+'/'+$expected.name) -NonzeroExit:$invalid
        $out=[IO.File]::ReadAllText($captures.stdout);$err=[IO.File]::ReadAllText($captures.stderr)
        if($invalid){
            if($row.process.stdout_bytes -ne 0 -or -not $err.Contains('invalid conformance allocator ceiling',[StringComparison]::Ordinal) -or
                $row.Contains('telemetry') -or @(Get-ChildItem -LiteralPath $rawDirectory -Filter ($expected.name+'.telemetry.*.json')).Count){
                throw 'Invalid allocator selection acquired output or attached allocator evidence'
            }
            continue
        }
        if($row.process.stderr_bytes -ne 0 -or -not $row.Contains('telemetry')){throw 'Allocator ceiling operation lacks its real sidecar or has errors'}
        $sidecar=Read-ConformanceAllocatorSidecar -Observation $row -OutputDirectory $rawDirectory -Configuration $parts[0] `
            -Limit $expected.limit -ExpectedSha256 $row.telemetry.sha256
        $sidecars++
        $originalSidecar=$originalDirectory+'/'+$expected.name+'.telemetry.'+$row.process.process_id+'.json'
        if($row.telemetry.path.Replace('\','/') -cne $originalSidecar){throw 'Allocator ceiling sidecar path differs from its actual PID'}
        if($index -lt 3){
            $config=$out|ConvertFrom-Json -AsHashtable
            [void](Test-ConformanceConfiguration -Observed $config -Configuration $parts[0] -Target Ada -AllocatorLimitBytes $expected.limit)
            $link=if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]}
            if($config.runtime_build_profile -cne $parts[2] -or $config.launcher_build_profile -cne $parts[2] -or
                $config.launcher_library_type -cne $link){throw 'Allocator ceiling measured profile or library type differs'}
        }elseif($out.Replace("`r`n","`n") -cne $expected.stdout){throw 'Allocator ceiling refusal or recovery completion differs'}
        if($expected.Contains('refusal') -and $sidecar.observed.managed_refusals -lt 1 -and $sidecar.observed.provider_refusals -lt 1){
            throw 'Allocator ceiling refusal lacks an actual managed or provider refusal'
        }
    }
    return @{operations=13;sidecars=$sidecars;runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-TawNativeRaw {
    param([Collections.IDictionary]$Raw,[Collections.IDictionary]$Witness,[string]$ArtifactRoot,[string]$CompilerHash)
    $origin=$Witness.source_repository_root;$parts=$Witness.context.Split('/')
    if($parts[0] -cne 'upstream-test' -or $Raw.schema_version -ne 1 -or
        $Raw.kind -cne 'native-allocator-observer-regressions' -or
        $Raw.loaded_runtime_linkage_verified -isnot [bool] -or -not $Raw.loaded_runtime_linkage_verified -or
        $Raw.compiler.sha256 -cne $CompilerHash -or $Raw.compile.executable_sha256 -cne $CompilerHash){
        throw 'Native allocator observer role or actual compiler identity differs'
    }
    Assert-TawFalse $Raw.runtime_acceptance 'raw runtime acceptance';Assert-TawFalse $Raw.coverage_authority 'raw coverage authority'
    $directory=$Witness.producer_report.path.Replace('\','/');$directory=$directory.Substring(0,$directory.LastIndexOf('/'))
    $suffix=if($parts[1] -ceq 'windows'){'.exe'}else{''}
    $probe=$directory+'/allocator_observer_probe'+$suffix
    $library=$Raw.library_directory.Replace('\','/')
    if($library -cne $Witness.selected_runtime.library_directory.Replace('\','/')){throw 'Native allocator observer selected library differs'}
    $arguments=@('-std=c99','-Wall','-Wextra','-Werror','-pedantic')
    if($parts[1] -ceq 'windows'){$arguments+='-DLUA_BUILD_AS_DLL'}
    $arguments+='-DLUA_USER_H=<ltests.h>'
    if($parts[1] -ceq 'windows'){
        $arguments+=@('-include',($origin.Replace('\','/')+'/experiments/conformance/c/conformance_exports.h'))
    }
    $arguments+=@(
        ('-I'+$origin.Replace('\','/')+'/references/lua'),($origin.Replace('\','/')+'/experiments/conformance/c/allocator_observer_probe.c'),
        ('-L'+$library),'-lconformance_lua','-o',$probe)
    if($parts[1] -cne 'windows'){$arguments+='-fPIC'}
    if($parts[1] -ceq 'linux'){$arguments+='-ldl'}
    $compile=@{};foreach($key in $Raw.compile.Keys){$compile[$key]=$Raw.compile[$key]}
    $compile.arguments=@($Raw.compile.arguments|ForEach-Object{$_.Replace('\','/')})
    $captures=Assert-TawProcess -Process $compile -Origin $origin -ArtifactRoot $ArtifactRoot `
        -Executable $Raw.compiler.path -ExecutableHash $CompilerHash -Arguments $arguments -Prefix ($directory+'/compile')
    if($Raw.compile.stderr_bytes -ne 0){throw 'Native allocator strict compile emitted diagnostics'}
    $null=Resolve-TawArtifact $origin $ArtifactRoot $Raw.process.executable $Raw.process.executable_sha256
    if($Raw.process.executable.Replace('\','/') -cne $probe){throw 'Native allocator probe executable differs'}
    $captures=Assert-TawProcess -Process $Raw.process -Origin $origin -ArtifactRoot $ArtifactRoot `
        -Executable $Raw.process.executable -ExecutableHash $Raw.process.executable_sha256 -Arguments @() -Prefix ($directory+'/execute')
    $expected=@('real debug allocator identity','fail-next leaves the old block intact',
        'count refusal before backing allocation','byte refusal before backing allocation',
        'backing refusal counted once in both views','successful growth and free are not refusals',
        'original teardown and zero ownership')
    $text=[IO.File]::ReadAllText($captures.stdout).Replace("`r`n","`n")
    $lines=$text.Split("`n")
    # The OS path spelling is raw evidence. Windows module lookup ignores
    # case, so compare that identity with the same rule as the producer while
    # retaining its original bytes. POSIX paths retain case significance.
    $pathComparison=if($parts[1] -ceq 'windows'){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if($Raw.process.stderr_bytes -ne 0 -or $lines[0] -cnotmatch '^ALLOCATOR OBSERVER RUNTIME: (.+)$' -or
        -not [string]::Equals($Matches[1].Replace('\','/'),$Raw.loaded_runtime.path.Replace('\','/'),$pathComparison) -or
        (($lines|Select-Object -Skip 1)-join "`n") -cne (($expected|ForEach-Object{'ALLOCATOR OBSERVER PASS: '+$_})-join "`n")+"`n"){
        throw 'Native allocator actual OS identity or complete seven-case protocol differs'
    }
    $name=if($parts[1] -ceq 'windows'){'libconformance_lua.dll'}elseif($parts[1] -ceq 'macos'){'libconformance_lua.dylib'}else{'libconformance_lua.so'}
    if(-not [string]::Equals($Raw.loaded_runtime.path.Replace('\','/'),($library+'/'+$name),$pathComparison)){throw 'Native allocator actually loaded another runtime path'}
    $null=Resolve-TawArtifact $origin $ArtifactRoot $Raw.loaded_runtime.path $Raw.loaded_runtime.sha256
    $sources=@('experiments/conformance/c/allocator_observer_probe.c','experiments/conformance/c/bounded_ltests.c',
        'experiments/conformance/c/conformance_cli.c','experiments/conformance/c/allocator_limit.h',
        'experiments/conformance/c/conformance_exports.h','references/lua/ltests.c','references/lua/ltests.h','references/lua/lua.h')
    if($Raw.sources -isnot [Array] -or (($Raw.sources.path|Sort-Object)-join '|') -cne (($sources|Sort-Object)-join '|')){
        throw 'Native allocator actual source set differs'
    }
    foreach($source in $Raw.sources){
        $binding=@($Witness.source_bindings|Where-Object path -CEQ $source.path)
        if($binding.Count -ne 1 -or $binding[0].sha256 -cne $source.sha256){throw 'Native allocator source identity differs'}
    }
    return @{operations=7;actual_native_loaded_runtime=$Raw.loaded_runtime;runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-TargetAllocatorWitness {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Witness,
        [Parameter(Mandatory)][string]$ArtifactRoot,[Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$Revision,[Collections.IDictionary]$Image,[switch]$AllowSynthetic,
        [switch]$AllowExternalInput)
    $parts=$Context.Split('/')
    if($Witness.schema_version -ne 1 -or $Witness.kind -cne 'target-context-allocator-witness' -or
        $Witness.target -cne 'remaining-upstream-compatibility' -or $Witness.context -cne $Context -or
        $Witness.repository_revision -cne $Revision -or $Witness.repository_revision -cnotmatch '^[0-9a-f]{40}$' -or
        $Witness.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $Witness.witness_kind -cnotin @('ada-ceiling','native-observer') -or
        ($Witness.witness_kind -ceq 'native-observer' -and $parts[0] -cne 'upstream-test')){
        throw 'Target allocator witness revision context or role differs'
    }
    foreach($flag in @('runtime_acceptance','coverage_authority')){Assert-TawFalse $Witness[$flag] $flag}
    if($Witness.synthetic_fixture -isnot [bool] -or $Witness.repository_dirty -isnot [bool] -or
        (-not $AllowSynthetic -and ($Witness.synthetic_fixture -or $Witness.repository_dirty))){
        throw 'Target allocator final witness requires actual clean observations'
    }
    if($Witness.Contains('external_input_snapshot')){
        if(-not $AllowExternalInput){throw 'External allocator input observations cannot supply final context build provenance'}
        $inputPath=Resolve-TawArtifact $Witness.source_repository_root $ArtifactRoot $Witness.external_input_snapshot.path $Witness.external_input_snapshot.sha256
        $inputs=Get-Content -LiteralPath $inputPath -Raw|ConvertFrom-Json -AsHashtable -Depth 64
        if($inputs.schema_version -ne 1 -or $inputs.kind -cne 'target-allocator-external-input-snapshot' -or
            $inputs.context -cne $Context -or $inputs.repository_revision -cnotmatch '^[0-9a-f]{40}$' -or
            $inputs.repository_dirty -isnot [bool] -or $inputs.source_build_provenance_verified -isnot [bool] -or
            $inputs.source_build_provenance_verified -or $inputs.synthetic_fixture -isnot [bool] -or $inputs.synthetic_fixture -or
            $inputs.files -isnot [Array] -or $inputs.files.Count -eq 0){throw 'External allocator input snapshot lacks actual unverified provenance'}
        foreach($flag in @('runtime_acceptance','coverage_authority')){Assert-TawFalse $inputs[$flag] $flag}
        foreach($file in $inputs.files){$null=Resolve-TawArtifact $Witness.source_repository_root $ArtifactRoot $file.path $file.sha256}
        $selected=@($Witness.selected_runtime.library_files)
        if($Witness.witness_kind -ceq 'ada-ceiling'){$selected+=@($Witness.selected_runtime.executable)}
        foreach($file in $selected){
            if(@($inputs.files|Where-Object{$_.path -ceq $file.path -and $_.sha256 -ceq $file.sha256}).Count -ne 1){
                throw 'External allocator selected product is absent from its immutable input snapshot'
            }
        }
    }
    $required=@(Get-TargetAllocatorSourcePaths -Kind $Witness.witness_kind -Configuration $parts[0])
    if($Witness.source_bindings -isnot [Array] -or
        (($Witness.source_bindings.path|Sort-Object)-join '|') -cne (($required|Sort-Object)-join '|')){throw 'Target allocator source binding set differs'}
    foreach($source in $Witness.source_bindings){
        if((Get-TawHash (Join-Path $Root $source.path)) -cne $source.sha256){throw 'Target allocator source binding is stale'}
    }
    $rawPath=Resolve-TawArtifact $Witness.source_repository_root $ArtifactRoot $Witness.producer_report.path $Witness.producer_report.sha256
    $relative=Get-TawRelative $Witness.source_repository_root $Witness.producer_report.path
    if(-not $relative.StartsWith('reports/target-builds/'+$Context.Replace('/','-')+'/',[StringComparison]::Ordinal)){
        throw 'Target allocator report is outside its exact context directory'
    }
    $raw=Get-Content -LiteralPath $rawPath -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    if($Witness.selected_runtime.library_files -isnot [Array] -or $Witness.selected_runtime.library_files.Count -eq 0 -or
        @($Witness.selected_runtime.library_files.path|Sort-Object -Unique).Count -ne $Witness.selected_runtime.library_files.Count){
        throw 'Target allocator selected runtime library identities are missing or duplicate'
    }
    $libraryRelative=Get-TawRelative $Witness.source_repository_root $Witness.selected_runtime.library_directory
    foreach($library in $Witness.selected_runtime.library_files){
        $relativeLibrary=Get-TawRelative $Witness.source_repository_root $library.path
        if(-not $relativeLibrary.StartsWith($libraryRelative+'/',[StringComparison]::Ordinal) -or
            $relativeLibrary.Substring($libraryRelative.Length+1).Contains('/')){throw 'Target allocator library is outside its selected directory'}
        $null=Resolve-TawArtifact $Witness.source_repository_root $ArtifactRoot $library.path $library.sha256
    }
    $originalRaw=$Witness.producer_report.path.Replace('\','/')
    $rawDirectoryName=$originalRaw.Substring(0,$originalRaw.LastIndexOf('/'))
    $outerDirectory=$rawDirectoryName.Substring(0,$rawDirectoryName.LastIndexOf('/'))
    $scriptName=if($Witness.witness_kind -ceq 'ada-ceiling'){'test-conformance-allocator-ceiling.ps1'}else{'test-native-allocator-observer.ps1'}
    $producerArguments=@('-NoProfile','-File',($Witness.source_repository_root.Replace('\','/')+'/scripts/'+$scriptName))
    if($Witness.witness_kind -ceq 'ada-ceiling'){
        $producerArguments+=@('-Interpreter',$Witness.selected_runtime.executable.path.Replace('\','/'),'-Configuration',$parts[0])
    }else{
        $producerArguments+=@('-Compiler',$Witness.compiler.path.Replace('\','/'),'-LibraryDirectory',$Witness.selected_runtime.library_directory.Replace('\','/'))
    }
    $producerArguments+=@('-OutputDirectory',$rawDirectoryName)
    $parent=@{};foreach($key in $Witness.producer_process.Keys){$parent[$key]=$Witness.producer_process[$key]}
    $parent.arguments=@($parent.arguments|ForEach-Object{$_.Replace('\','/')})
    $parentCaptures=Assert-TawProcess -Process $parent -Origin $Witness.source_repository_root -ArtifactRoot $ArtifactRoot `
        -Executable $Witness.producer_process.executable -ExecutableHash $Witness.producer_process.executable_sha256 `
        -Arguments $producerArguments -Prefix ($outerDirectory+'/producer')
    if($parent.stderr_bytes -ne 0){throw 'Target allocator producer emitted diagnostics'}
    Assert-TawInteger $parent.elapsed_milliseconds 'producer elapsed time'
    $start=[DateTimeOffset]$parent.started_utc
    $end=$start.AddMilliseconds([long]$parent.elapsed_milliseconds).AddSeconds(2)
    $children=if($Witness.witness_kind -ceq 'ada-ceiling'){@($raw.observations.process)}else{@($raw.compile,$raw.process)}
    foreach($child in $children){
        Assert-TawInteger $child.elapsed_milliseconds 'child elapsed_milliseconds'
        $childStart=[DateTimeOffset]$child.started_utc
        $childEnd=$childStart.AddMilliseconds([long]$child.elapsed_milliseconds)
        if($childStart -lt $start.AddSeconds(-2) -or $childStart -gt $end){throw 'Target allocator raw process predates its actual producer invocation'}
        if($childEnd -gt $end){throw 'Target allocator raw child ends after its actual producer invocation'}
    }
    $result=if($Witness.witness_kind -ceq 'ada-ceiling'){
        Assert-TawCeilingRaw -Raw $raw -Witness $Witness -ArtifactRoot $ArtifactRoot
    }else{Assert-TawNativeRaw -Raw $raw -Witness $Witness -ArtifactRoot $ArtifactRoot -CompilerHash $Witness.compiler.sha256}
    if($null -ne $Image){
        if($Image.context -cne $Context -or $Image.revision -cne $Revision){throw 'Target allocator frozen image identifies another context'}
        $runtimeKey=if($Witness.witness_kind -ceq 'ada-ceiling'){'ada_runtime'}else{'c_runtime'}
        if((Get-TawRelative $Witness.source_repository_root $Witness.selected_runtime.library_directory) -cne $Image.paths[$runtimeKey]){
            throw 'Target allocator selected a different frozen runtime directory'
        }
        if($Witness.witness_kind -ceq 'ada-ceiling' -and
            (Get-TawRelative $Witness.source_repository_root $Witness.selected_runtime.executable.path) -cne $Image.paths.ada_launcher){
            throw 'Target allocator selected a different frozen Ada launcher'
        }
        if($Witness.witness_kind -ceq 'native-observer' -and $Witness.compiler.sha256 -cne $Image.toolchain.compiler_sha256){
            throw 'Target allocator compiler differs from its frozen toolchain'
        }
        if($Witness.producer_process.executable_sha256 -cne $Image.toolchain.pwsh_sha256){throw 'Target allocator producer differs from its frozen observation toolchain'}
        $prefix=$Image.paths[$runtimeKey]+'/'
        $imageLibraries=@($Image.files|Where-Object{$_.path.StartsWith($prefix,[StringComparison]::Ordinal) -and
            -not $_.path.Substring($prefix.Length).Contains('/')}|ForEach-Object path|Sort-Object)
        $recordedLibraries=@($Witness.selected_runtime.library_files|ForEach-Object{Get-TawRelative $Witness.source_repository_root $_.path}|Sort-Object)
        if(($imageLibraries-join '|') -cne ($recordedLibraries-join '|')){throw 'Target allocator selected runtime file set differs from its frozen directory'}
        $artifacts=@(@{path=$rawPath;sha256=$Witness.producer_report.sha256})
        $artifacts+=@(Get-ChildItem -LiteralPath (Split-Path -Parent $rawPath) -File -Recurse|ForEach-Object{@{path=$_.FullName;sha256=(Get-TawHash $_.FullName)}})
        foreach($stream in @('stdout','stderr')){$artifacts+=@{path=$parentCaptures[$stream];sha256=$parent[$stream+'_sha256']}}
        foreach($library in $Witness.selected_runtime.library_files){
            $actual=Resolve-TawArtifact $Witness.source_repository_root $ArtifactRoot $library.path $library.sha256
            $artifacts+=@{path=$actual;sha256=$library.sha256}
        }
        if($Witness.witness_kind -ceq 'ada-ceiling'){
            $actual=Resolve-TawArtifact $Witness.source_repository_root $ArtifactRoot $Witness.selected_runtime.executable.path $Witness.selected_runtime.executable.sha256
            $artifacts+=@{path=$actual;sha256=$Witness.selected_runtime.executable.sha256}
        }
        foreach($artifact in $artifacts){
            $name=[IO.Path]::GetRelativePath($ArtifactRoot,$artifact.path).Replace('\','/')
            $file=@($Image.files|Where-Object path -CEQ $name)
            if($file.Count -ne 1 -or $file[0].sha256 -cne $artifact.sha256){throw 'Target allocator artifact is absent from its exact frozen image'}
        }
        if($Witness.witness_kind -ceq 'native-observer'){
            $name=Get-TawRelative $Witness.source_repository_root $raw.loaded_runtime.path
            $file=@($Image.files|Where-Object path -CEQ $name)
            if($file.Count -ne 1 -or $file[0].sha256 -cne $raw.loaded_runtime.sha256){throw 'Native allocator actual runtime differs from frozen DLL'}
        }
    }
    $result['diagnostic_only']=[bool]($AllowSynthetic -or $AllowExternalInput)
    return $result
}

function New-TargetAllocatorWitness {
    param([string]$Root,[string]$Context,[ValidateSet('ada-ceiling','native-observer')][string]$Kind,
        [string]$ProducerReport,[Collections.IDictionary]$ProducerProcess,[string]$RuntimeDirectory,[string]$Executable='',[string]$Compiler='',
        [string]$Output,[Collections.IDictionary]$ExternalInputSnapshot)
    if(Test-Path -LiteralPath $Output){throw 'Target allocator witness output must be new'}
    $configuration=$Context.Split('/')[0]
    $selected=@{library_directory=[IO.Path]::GetFullPath($RuntimeDirectory);
        library_files=@(Get-ChildItem -LiteralPath $RuntimeDirectory -File|ForEach-Object{@{path=$_.FullName;sha256=(Get-TawHash $_.FullName)}})}
    if($Kind -ceq 'ada-ceiling'){
        $selected.executable=@{path=[IO.Path]::GetFullPath($Executable);sha256=(Get-TawHash $Executable)}
        $selected['linkage_observation']='Selected launcher/configuration and runtime artifacts; no Ada OS-module mapping is claimed.'
    }
    $witness=@{schema_version=1;kind='target-context-allocator-witness';target='remaining-upstream-compatibility';witness_kind=$Kind;
        context=$Context;repository_revision=(& git -C $Root rev-parse HEAD).Trim();
        repository_dirty=(@(& git -C $Root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal).Count -ne 0);
        reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';source_repository_root=[IO.Path]::GetFullPath($Root);
        producer_report=@{path=[IO.Path]::GetFullPath($ProducerReport);sha256=(Get-TawHash $ProducerReport)};
        producer_process=$ProducerProcess;
        selected_runtime=$selected;synthetic_fixture=$false;runtime_acceptance=$false;coverage_authority=$false;
        source_bindings=@(Get-TargetAllocatorSourcePaths $Kind $configuration|ForEach-Object{@{path=$_;sha256=(Get-TawHash (Join-Path $Root $_))}})}
    if($Kind -ceq 'native-observer'){$witness['compiler']=@{path=[IO.Path]::GetFullPath($Compiler);sha256=(Get-TawHash $Compiler)}}
    if($null -ne $ExternalInputSnapshot){$witness['external_input_snapshot']=$ExternalInputSnapshot}
    # Creation records observations, including dirty development runs. The
    # final reader independently refuses dirty/synthetic data; this writer
    # never upgrades source provenance or grants acceptance.
    $null=Assert-TargetAllocatorWitness -Root $Root -Witness $witness -ArtifactRoot $Root -Context $Context `
        -Revision $witness.repository_revision -AllowSynthetic -AllowExternalInput:($null -ne $ExternalInputSnapshot)
    [IO.File]::WriteAllText($Output,(ConvertTo-Json -InputObject $witness -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return @{path=[IO.Path]::GetFullPath($Output);sha256=(Get-TawHash $Output);runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Get-TargetAllocatorSourcePaths,New-TargetAllocatorWitness,Assert-TargetAllocatorWitness
