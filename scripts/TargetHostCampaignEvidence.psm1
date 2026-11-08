Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TargetHostCampaignContracts.psm1')

function Get-ThcHash([string]$Path){(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()}
function Get-ThcRelative([string]$Origin,[string]$Path){
    $prefix=$Origin.Replace('\','/').TrimEnd('/')+'/'
    $name=$Path.Replace('\','/')
    $comparison=if($prefix -cmatch '^[A-Za-z]:/'){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if($prefix -cnotmatch '^(?:[A-Za-z]:/|/)' -or $prefix.StartsWith('//') -or
        -not $name.StartsWith($prefix,$comparison)){throw 'Host campaign artifact escapes its original checkout'}
    $relative=$name.Substring($prefix.Length)
    if($relative -cnotmatch '^reports/(?:core-image|target-builds|debug-console(?:-c)?|cli-readline)/' -or
        $relative.Contains(':') -or @($relative.Split('/')|Where-Object{$_ -cin @('','..','.')}).Count){
        throw 'Host campaign artifact is outside generated report paths'
    }
    return $relative
}
function Resolve-ThcArtifact {
    param([string]$Origin,[string]$ArtifactRoot,[string]$Path,[string]$Hash,[Collections.IDictionary]$Image)
    $relative=Get-ThcRelative $Origin $Path
    $actual=Join-Path $ArtifactRoot $relative
    if($Hash -cnotmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $actual -PathType Leaf) -or
        ((Get-Item -LiteralPath $actual).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-ThcHash $actual) -cne $Hash){throw 'Host campaign raw artifact hash or file differs'}
    if($null -ne $Image){
        $entry=@($Image.files|Where-Object path -CEQ $relative)
        if($entry.Count -ne 1 -or $entry[0].sha256 -cne $Hash -or
            $entry[0].bytes -ne (Get-Item -LiteralPath $actual).Length){throw 'Host campaign artifact is absent from the exact frozen image'}
    }
    return $actual
}
function Assert-ThcFalse($Value,[string]$Name){if($Value -isnot [bool] -or $Value){throw "Host campaign cannot claim $Name"}}
function Assert-ThcProcess {
    param([Collections.IDictionary]$Process,[string[]]$Arguments,[string]$Directory,[string]$Prefix,
        [string]$Origin,[string]$ArtifactRoot,[Collections.IDictionary]$Image)
    if(($Process.process_id -isnot [int] -and $Process.process_id -isnot [long]) -or $Process.process_id -le 0 -or
        ($Process.exit_code -isnot [int] -and $Process.exit_code -isnot [long]) -or $Process.exit_code -ne 0 -or
        $Process.arguments -isnot [Array] -or ($Process.arguments -join "`0") -cne ($Arguments -join "`0") -or
        $Process.working_directory.Replace('\','/') -cne $Directory.Replace('\','/')){throw 'Host campaign process status directory or exact arguments differ'}
    $timeout=if($Prefix.EndsWith('/compile',[StringComparison]::Ordinal)){120}else{30}
    if(($Process.timeout_seconds -isnot [int] -and $Process.timeout_seconds -isnot [long]) -or $Process.timeout_seconds -ne $timeout -or
        ($Process.elapsed_milliseconds -isnot [int] -and $Process.elapsed_milliseconds -isnot [long]) -or
        $Process.elapsed_milliseconds -lt 0 -or $Process.elapsed_milliseconds -gt ($timeout*1000+10050)){
        throw 'Host campaign timeout or elapsed transport bound differs'
    }
    foreach($flag in @('timed_out','capture_exceeded','pipe_drain_failed')){Assert-ThcFalse $Process[$flag] $flag}
    if($Process.abnormal_exit_kind -or $Process.process_tree_kill_error){throw 'Host campaign process failed abnormally'}
    $captures=@{}
    foreach($stream in @('stdout','stderr')){
        $path=$Process[$stream+'_path'];$hash=$Process[$stream+'_sha256'];$length=$Process[$stream+'_bytes']
        if(($length -isnot [int] -and $length -isnot [long]) -or $length -lt 0 -or
            $path.Replace('\','/') -cne ($Prefix+'.'+$stream).Replace('\','/')){throw 'Host campaign exact capture path or length differs'}
        $captures[$stream]=Resolve-ThcArtifact $Origin $ArtifactRoot $path $hash $Image
        if((Get-Item -LiteralPath $captures[$stream]).Length -ne $length){throw 'Host campaign capture length differs'}
    }
    return $captures
}
function Assert-ThcInput {
    param([Collections.IDictionary]$Process,[byte[]]$Expected,[string]$Origin,[string]$ArtifactRoot,[Collections.IDictionary]$Image,
        [string]$SourceInputPath)
    if(-not $Process.Contains('standard_input')){throw 'Host campaign lacks actual delivered standard input'}
    $input=$Process.standard_input
    foreach($flag in @('write_completed','eof_sent','close_requested')){
        if($input[$flag] -isnot [bool] -or -not $input[$flag]){throw 'Host campaign input delivery did not complete'}
    }
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Expected)).ToLowerInvariant()
    if($input.sha256 -cne $expectedHash -or $input.bytes -ne $Expected.Length -or
        $input.source_path.Replace('\','/') -cne $SourceInputPath.Replace('\','/') -or
        $input.path.Replace('\','/') -cne ($Process.stdout_path -replace '\.stdout$','.stdin').Replace('\','/')){
        throw 'Host campaign actual input bytes or snapshot path differ'
    }
    $null=Resolve-ThcArtifact $Origin $ArtifactRoot $input.path $input.sha256 $Image
    $null=Resolve-ThcArtifact $Origin $ArtifactRoot $input.source_path $input.sha256 $Image
}

function Assert-TargetHostCampaignReport {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][Collections.IDictionary]$Report,
        [Parameter(Mandatory)][string]$ArtifactRoot,[Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$Revision,[Collections.IDictionary]$Image,
        [Collections.IDictionary]$ConsumerReport,[switch]$AllowSynthetic)
    $parts=$Context.Split('/')
    $kinds=@{'debug-console-process-regressions'='console-lua';'debug-console-c-process-regressions'='console-c';
        'cli-readline-process-regressions'='readline'}
    if($Report.schema_version -ne 2 -or -not $kinds.ContainsKey($Report.kind) -or
        $Report.configuration -cne $parts[0] -or $Report.platform -cne $parts[1] -or
        $Report.repository_revision -cne $Revision -or $Revision -cnotmatch '^[0-9a-f]{40}$' -or
        $Report.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294'){
        throw 'Host campaign schema revision configuration or platform differs'
    }
    foreach($flag in @('runtime_acceptance','coverage_authority')){Assert-ThcFalse $Report[$flag] $flag}
    if($Report.synthetic_fixture -isnot [bool] -or $Report.repository_dirty -isnot [bool] -or
        (-not $AllowSynthetic -and ($Report.synthetic_fixture -or $Report.repository_dirty))){throw 'Host campaign final report requires actual clean observations'}
    $kind=$kinds[$Report.kind];$origin=$Report.source_repository_root;$directory=$Report.output_directory.Replace('\','/')
    $null=Get-ThcRelative $origin ($directory+'/result.json')
    $required=@(Get-TargetHostCampaignSourcePaths $kind)
    if($Report.source_bindings -isnot [Array] -or
        (($Report.source_bindings.path|Sort-Object)-join '|') -cne (($required|Sort-Object)-join '|')){throw 'Host campaign source binding set differs'}
    foreach($source in $Report.source_bindings){if((Get-ThcHash (Join-Path $Root $source.path)) -cne $source.sha256){throw 'Host campaign source binding is stale'}}
    if($kind -cne 'console-c'){
        $producer=@($Report.source_bindings|Where-Object path -CEQ $Report.source.path)
        if($producer.Count -ne 1 -or $producer[0].sha256 -cne $Report.source.sha256){throw 'Host campaign producer source identity contradicts its binding'}
    }
    if($null -ne $Image -and ($Image.context -cne $Context -or $Image.revision -cne $Revision)){throw 'Host campaign frozen context differs'}
    $cases=@(Get-TargetHostCampaignCases $kind $parts[1])
    $sequence=@()
    if($kind -ceq 'console-c'){
        foreach($case in $cases){foreach($role in @('native','ada')){$sequence+=@{role=$role;case=$case}}}
    }else{foreach($role in @('native','ada')){foreach($case in $cases){$sequence+=@{role=$role;case=$case}}}}
    if($Report.processes -isnot [Array] -or $Report.processes.Count -ne $sequence.Count){throw 'Host campaign lacks every mandatory actual paired operation'}
    if($kind -ceq 'readline' -and ($Report.comparison_failures -isnot [Array] -or $Report.comparison_failures.Count)){
        throw 'Readline campaign retained comparison failures'
    }
    $pairs=@{};$newline=if($parts[1] -ceq 'windows'){"`r`n"}else{"`n"}
    for($index=0;$index -lt $sequence.Count;$index++){
        $expected=$sequence[$index];$case=$expected.case;$row=$Report.processes[$index];$process=$row.process
        $name=if($kind -ceq 'console-c'){$row.mode}else{$row.name}
        if($row.role -cne $expected.role -or $name -cne $case.name){throw 'Host campaign operation order role or case differs'}
        if($kind -ceq 'console-lua' -and $row.setup -cne $case.setup){throw 'Console setup differs from its retained source contract'}
        $cwd=$directory+'/'+$row.role+'/'+$name
        $captures=Assert-ThcProcess $process (Get-TargetHostCampaignArguments $kind $case) $cwd ($cwd+'/process') $origin $ArtifactRoot $Image
        $inputName=if($kind -ceq 'readline'){'input'}else{'stdin'}
        Assert-ThcInput $process (Get-TargetHostCampaignInputBytes $kind $case) $origin $ArtifactRoot $Image ($cwd+'/'+$inputName)
        if($kind -ceq 'console-c' -and ($row.stdin.path -cne $process.standard_input.source_path -or
            $row.stdin.sha256 -cne $process.standard_input.sha256 -or $row.stdin.bytes -ne $process.standard_input.bytes)){
            throw 'Console C input receipt contradicts its actual delivered input'
        }
        $exe=Resolve-ThcArtifact $origin $ArtifactRoot $process.executable $process.executable_sha256 $Image
        $images=if($kind -ceq 'console-c'){@($Report.images|Where-Object{$_.path.Replace('\','/').StartsWith($directory+'/'+$row.role+'/image/',[StringComparison]::Ordinal)})}else{@($row.images)}
        if($images.Count -eq 0){throw 'Host campaign lacks selected copied image identities'}
        foreach($file in $images){
            $path=if($kind -ceq 'console-c'){$file.path}else{($directory+'/'+$row.role+'/image/'+$file.name)}
            $null=Resolve-ThcArtifact $origin $ArtifactRoot $path $file.sha256 $Image
        }
        if($process.executable.Replace('\','/') -cne ($directory+'/'+$row.role+'/image/'+[IO.Path]::GetFileName($process.executable))){throw 'Host campaign executable is outside its selected role image'}
        if(@($images|Where-Object{ $_.sha256 -ceq $process.executable_sha256 }).Count -lt 1){throw 'Host campaign executable lacks its copied identity'}
        if($null -ne $Image){
            if($kind -ceq 'console-c' -and $row.role -ceq 'ada'){
                if($null -eq $ConsumerReport){throw 'Console C campaign requires an actual built Ada consumer receipt'}
                $consumer=@($ConsumerReport.consumers|Where-Object name -CEQ builtin-api)
                if($consumer.Count -ne 1 -or $consumer[0].executable_sha256 -cne $process.executable_sha256){throw 'Console C campaign selected a different built Ada consumer'}
            }elseif($kind -cne 'console-c'){
                $key=if($row.role -ceq 'ada'){'ada_cli'}else{'c_oracle'}
                $selected=@($Image.files|Where-Object path -CEQ $Image.paths[$key])
                if($selected.Count -ne 1 -or $selected[0].sha256 -cne $process.executable_sha256){throw 'Host campaign selected another frozen CLI image'}
            }
            $runtimeKey=if($row.role -ceq 'ada'){'ada_runtime'}else{'c_runtime'}
            foreach($file in @($Image.files|Where-Object{$_.path.StartsWith($Image.paths[$runtimeKey]+'/',[StringComparison]::Ordinal) -and
                $_.path -cmatch '\.(?:dll|dylib|so(?:\.[0-9.]+)?)$'})){
                if(@($images|Where-Object{ $_.sha256 -ceq $file.sha256 }).Count -ne 1){throw 'Host campaign selected different frozen runtime library bytes'}
            }
        }
        $stdout=[IO.File]::ReadAllBytes($captures.stdout);$stderr=[IO.File]::ReadAllBytes($captures.stderr)
        if($kind -cne 'readline'){
            $expectedOut=if($kind -ceq 'console-lua'){'AFTER'+$newline}else{'PASS: builtin-debug-console-'+$case.name+$newline+'PASS: public builtin contract'+$newline}
            if([Convert]::ToBase64String($stdout) -cne [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($expectedOut))){throw 'Host console named completion differs'}
        }
        if($kind -ceq 'readline'){
            if(-not [Text.Encoding]::ASCII.GetString($stdout).StartsWith('Lua 5.5.1',[StringComparison]::Ordinal)){
                throw 'Readline operation lacks the actual CLI version banner'
            }
            $hasOverride=$case.Contains('library')
            if($hasOverride -ne $row.environment.Contains('LUA_READLINELIB') -or
                ($hasOverride -and $row.environment.LUA_READLINELIB -cne $case.library)){throw 'Readline backend environment selection differs'}
        }
        if($kind -cne 'console-c'){
            # PATH does not select a POSIX shared library. Bind the copied
            # image to the real platform loader, retaining the recorded tail.
            $loader=switch($parts[1]){'windows'{'PATH'}'macos'{'DYLD_LIBRARY_PATH'}'linux'{'LD_LIBRARY_PATH'}}
            $separator=if($parts[1] -ceq 'windows'){';'}else{':'}
            $keys=@($loader);if($kind -ceq 'readline' -and $case.Contains('library')){$keys+='LUA_READLINELIB'}
            if((($row.environment.Keys|Sort-Object)-join '|') -cne (($keys|Sort-Object)-join '|') -or
                -not $row.environment[$loader].Replace('\','/').StartsWith($directory+'/'+$row.role+'/image'+$separator,[StringComparison]::Ordinal)){
                throw 'Host campaign loader image prefix or selected environment differs'
            }
        }
        $captured=@{stdout=[Convert]::ToBase64String($stdout);stderr=[Convert]::ToBase64String($stderr)}
        if($row.role -ceq 'native'){$pairs[$name]=$captured}
        elseif(-not $pairs.ContainsKey($name) -or $pairs[$name].stdout -cne $captured.stdout -or $pairs[$name].stderr -cne $captured.stderr){
            throw 'Host campaign paired raw output bytes differ'
        }
    }
    if($kind -ceq 'console-c'){
        # The native C binary and selected SDK/header role are independent of
        # the Ada consumer's ordinary no-argument operations. Never borrow its
        # process count or unused custom allocator metrics as these four runs.
        if($Report.comparison_complete -isnot [bool] -or -not $Report.comparison_complete){throw 'Console C campaign did not finish comparison'}
        $role=if($parts[0] -ceq 'upstream-test'){'pinned-native-private-test-header'}else{'pinned-native-public-sdk'}
        if($Report.native_header_role -cne $role -or $Report.ada_consumer_source_build_verified -isnot [bool] -or
            $Report.ada_consumer_source_build_verified){throw 'Console C header role or standalone build-provenance claim differs'}
        $requiredSources=@('c_api/tests/builtin_api_contract.c','c_api/tests/consumer_allocator.h',
            'tests/c/argument_registry_callbacks.h','references/lua/lua.h','references/lua/lauxlib.h',
            'references/lua/lualib.h','references/lua/luaconf.h')
        if($parts[0] -ceq 'upstream-test'){$requiredSources+='references/lua/ltests.h'}
        if($Report.sources -isnot [Array] -or (($Report.sources.path|Sort-Object)-join '|') -cne (($requiredSources|Sort-Object)-join '|')){
            throw 'Console C actual SDK and source snapshot set differs'
        }
        foreach($source in $Report.sources){
            if($source.sha256 -cne (Get-ThcHash (Join-Path $Root $source.path)) -or $source.snapshot_sha256 -cne $source.sha256 -or
                $source.snapshot_path.Replace('\','/') -cne ($directory+'/sources/'+$source.path)){throw 'Console C source snapshot identity differs'}
            $null=Resolve-ThcArtifact $origin $ArtifactRoot $source.snapshot_path $source.snapshot_sha256 $Image
        }
        $suffix=if($parts[1] -ceq 'windows'){'.exe'}else{''}
        $nativeExecutable=$directory+'/native/image/builtin_api_contract'+$suffix
        $arguments=Get-TargetHostConsoleCompileArguments $parts[0] $parts[1] ($directory+'/sources') ($directory+'/native/image') $nativeExecutable
        $compile=Assert-ThcProcess $Report.compile $arguments $origin ($directory+'/compile') $origin $ArtifactRoot $Image
        if($Report.compile.stdout_bytes -ne 0 -or $Report.compile.stderr_bytes -ne 0 -or
            $Report.compile.executable -cne $Report.compiler.path -or $Report.compile.executable_sha256 -cne $Report.compiler.sha256){
            throw 'Console C strict compiler identity or diagnostics differ'
        }
        $native=@($Report.processes|Where-Object role -CEQ native)
        if(@($native.process.executable_sha256|Sort-Object -Unique).Count -ne 1 -or
            @($native|Where-Object{$_.process.executable.Replace('\','/') -cne $nativeExecutable}).Count){throw 'Console C execution selected another compiled native binary'}
        $condition=if($parts[0] -ceq 'upstream-test'){"type(T)=='table' and type(T.totalmem)=='function'"}else{'T==nil'}
        $code="assert($condition);io.write('DEBUG CONSOLE C CONFIG $($parts[0])\n')"
        $probe=Assert-ThcProcess $Report.configuration_probe @('-e',$code) $origin ($directory+'/native-config') $origin $ArtifactRoot $Image
        if($Report.configuration_probe.stderr_bytes -ne 0 -or
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($probe.stdout)) -cne
                [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('DEBUG CONSOLE C CONFIG '+$parts[0]+$newline))){
            throw 'Console C actual native configuration measurement differs'
        }
        $null=Resolve-ThcArtifact $origin $ArtifactRoot $Report.configuration_probe.executable $Report.configuration_probe.executable_sha256 $Image
        if($null -ne $Image){
            $oracle=@($Image.files|Where-Object path -CEQ $Image.paths.c_oracle)
            if($oracle.Count -ne 1 -or $oracle[0].sha256 -cne $Report.configuration_probe.executable_sha256 -or
                $Image.toolchain.compiler_sha256 -cne $Report.compiler.sha256){throw 'Console C probe or compiler differs from the frozen context'}
        }
    }
    return @{kind=$kind;operations=$sequence.Count;paired_cases=$cases.Count;frozen_image_verified=($null -ne $Image);
        diagnostic_only=[bool]$AllowSynthetic;runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Assert-TargetHostCampaignReport
