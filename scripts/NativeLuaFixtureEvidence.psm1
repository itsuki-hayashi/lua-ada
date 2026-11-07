Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'NativeModuleLinkage.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')

function Join-NativeRecordedPath([string] $Parent,[string] $Child) {
    # Recorded Windows paths must also replay on the Linux collection host.
    # Treat their spelling as evidence, without resolving a foreign drive.
    return $Parent.Replace('\','/').TrimEnd('/')+'/'+$Child.Replace('\','/').TrimStart('/')
}
function Get-NativeRecordedDirectory([string] $Path) {
    $normalized=$Path.Replace('\','/')
    return $normalized.Substring(0,$normalized.LastIndexOf('/'))
}

function Resolve-NativeFixtureCapture {
    param([string] $Root,[string] $Original,[string] $Sha256)
    $normalized=$Original.Replace('\','/')
    $offset=$normalized.LastIndexOf('/reports/',[StringComparison]::Ordinal)
    if($offset -lt 0 -or $Sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Native fixture artifact is outside reports or lacks its hash'}
    $relative=$normalized.Substring($offset+1)
    $fullRoot=[IO.Path]::GetFullPath($Root)
    $path=[IO.Path]::GetFullPath((Join-Path $fullRoot $relative))
    $within=[IO.Path]::GetRelativePath($fullRoot,$path).Replace('\','/')
    if(-not $within.StartsWith('reports/',[StringComparison]::Ordinal) -or
        (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $Sha256){throw 'Native fixture artifact bytes or path differ'}
    return $path
}

function Assert-NativeFixtureToolCapture {
    param([Collections.IDictionary] $Process,[string] $ArtifactRoot,[string] $ToolHash,[string[]] $Arguments)
    if($ToolHash -cnotmatch '^[0-9a-f]{64}$' -or $Process.executable_sha256 -cne $ToolHash -or
        $Process.exit_code -ne 0 -or $Process.timed_out -ne $false -or $Process.capture_exceeded -ne $false -or
        $Process.pipe_drain_failed -ne $false -or $Process.process_tree_kill_error -or $Process.abnormal_exit_kind -or
        $Process.stderr_bytes -ne 0 -or $Process.arguments -isnot [Array] -or
        ((@($Process.arguments|ForEach-Object{ $_.Replace('\','/') })|ConvertTo-Json -Compress) -cne
         (@($Arguments|ForEach-Object{ $_.Replace('\','/') })|ConvertTo-Json -Compress))){
        throw 'Native fixture tool identity invocation or completion differs'
    }
    foreach($stream in @('stdout','stderr')){
        $path=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $Process["${stream}_path"] -Sha256 $Process["${stream}_sha256"]
        if((Get-Item -LiteralPath $path).Length -ne $Process["${stream}_bytes"]){throw 'Native fixture tool capture length differs'}
    }
}

function Read-NativeSymbolCapture {
    param([Collections.IDictionary] $Record,[string] $ArtifactRoot,[string] $ToolHash,
          [string] $ImagePath,[string] $Platform,[switch] $Undefined)
    $arguments=if($Platform -ceq 'macos'){@('-g',$(if($Undefined){'-u'}else{'-U'}),$ImagePath)}
        else{@('-D',$(if($Undefined){'--undefined-only'}else{'--defined-only'}),$ImagePath)}
    if($Record.tool.sha256 -cne $ToolHash){throw 'Native fixture symbol tool differs from its frozen context'}
    Assert-NativeFixtureToolCapture -Process $Record.process -ArtifactRoot $ArtifactRoot -ToolHash $ToolHash -Arguments $arguments
    $path=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $Record.process.stdout_path -Sha256 $Record.process.stdout_sha256
    $symbols=@()
    foreach($line in [IO.File]::ReadAllLines($path)){
        if($line -match '\s([A-Za-z_][A-Za-z0-9_]*(?:@[^\s]+)?)$'){
            $name=$Matches[1]
            if($Platform -ceq 'macos' -and $name.StartsWith('_')){$name=$name.Substring(1)}
            $symbols+=($name -split '@')[0]
        }
    }
    $symbols=@($symbols|Sort-Object -Unique)
    if((@($Record.symbols)-join '|') -cne ($symbols-join '|')){throw 'Native fixture recorded symbols differ from actual tool captures'}
    return ,$symbols
}

function Assert-NativeLuaFixtureEvidence {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $ArtifactRoot,
          [Parameter(Mandatory)][string] $ImagePayload,[Parameter(Mandatory)][Collections.IDictionary] $Image,
          [Parameter(Mandatory)][Collections.IDictionary] $Report,[switch] $ConsumerHost)
    # Rebuild the structural ownership facts from content-addressed bytes.
    # No receipt flag establishes execution, semantic review or lifetime
    # correctness. Those remain obligations of the named runtime witnesses.
    if(-not $Report.Contains('native_fixture_linkage') -or @($Report.native_fixture_linkage).Count -ne 1){
        throw 'Final native operation requires its exact same-image fixture linkage receipt'
    }
    $identity=$Report.native_fixture_linkage[0]
    $path=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $identity.path -Sha256 $identity.sha256
    $receipt=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $plan=$receipt.plan;$parts=$Report.acceptance_context.Split('/')
    $expectedBasename=if($ConsumerHost){[IO.Path]::GetFileName($Report.process.executable.Replace('\','/'))}else{$Image.launcher_basename}
    $static=$Report.target -ceq 'Ada' -and $parts[3] -cin @('static','static-pic')
    $libraryType=if($Report.target -ceq 'ReferenceC'){'shared'}elseif($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]}
    if($receipt.schema_version -ne 1 -or $receipt.kind -cne 'same-image-native-fixture-observations' -or
        -not $receipt.Contains('synthetic_fixture') -or $receipt.synthetic_fixture -isnot [bool] -or $receipt.synthetic_fixture -or
        $receipt.runtime_acceptance -ne $false -or $receipt.coverage_authority -ne $false -or
        $receipt.configuration -cne $parts[0] -or $plan.schema_version -ne 1 -or $plan.kind -cne 'same-image-native-fixture-plan' -or
        $plan.platform -cne $parts[1] -or $plan.implementation -cne $Report.target -or
        $plan.library_type -cne $libraryType -or $plan.mode -cne $(if($static){'exported-host'}else{'shared-runtime'}) -or
        $plan.compiler.sha256 -cne $Image.toolchain.compiler_sha256 -or
        $plan.host.sha256 -cne $Report.process.executable_sha256 -or $plan.host.basename -cne $expectedBasename -or
        $plan.host.path.Replace('\','/') -cne $Report.process.executable.Replace('\','/')){
        throw 'Native fixture receipt context compiler host or runtime mode differs'
    }
    $sourceBindings=@('scripts/NativeLuaFixtures.psm1','scripts/NativeModuleLinkage.psm1')
    if(@($receipt.source_bindings).Count -ne $sourceBindings.Count){throw 'Native fixture helper source bindings are incomplete'}
    foreach($relative in $sourceBindings){
        $record=@($receipt.source_bindings|Where-Object path -CEQ $relative)
        if($record.Count -ne 1){throw 'Native fixture helper source binding missing or duplicated'}
        [void](Resolve-ReviewedFile -Root $Root -Path $relative -Sha256 $record[0].sha256)
    }
    if($receipt.forced_header.path -cne 'experiments/conformance/c/module_exports.h'){throw 'Native fixture forced header differs'}
    [void](Resolve-ReviewedFile -Root $Root -Path $receipt.forced_header.path -Sha256 $receipt.forced_header.sha256)
    if($receipt.host_capture.sha256 -cne $plan.host.sha256){throw 'Native fixture host snapshot differs from the actual executed host'}
    $host=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $receipt.host_capture.path -Sha256 $receipt.host_capture.sha256
    if($ConsumerHost){
        $normalized=$receipt.host_capture.path.Replace('\','/');$offset=$normalized.LastIndexOf('/reports/',[StringComparison]::Ordinal)
        $relative=$normalized.Substring($offset+1)
        if(@($Image.files|Where-Object{ $_.path -ceq $relative -and $_.sha256 -ceq $plan.host.sha256 }).Count -ne 1){
            throw 'Native consumer host snapshot is outside its exact frozen context image'
        }
    }
    $owner=$host
    if(-not $static){
        $directory=$Image.paths[$(if($Report.target -ceq 'Ada'){'ada_runtime'}else{'c_runtime'})]
        $stem=if($Report.target -ceq 'Ada'){'liblua'}else{'libconformance_lua'}
        $suffix=if($parts[1] -ceq 'windows'){'.dll'}elseif($parts[1] -ceq 'macos'){'.dylib'}else{'.so'}
        $ownerRelative=$directory+'/'+$stem+$suffix
        $files=@($Image.files|Where-Object path -CEQ $ownerRelative)
        if($files.Count -ne 1 -or $files[0].sha256 -cne $plan.owner.sha256 -or $plan.runtime.sha256 -cne $plan.owner.sha256){
            throw 'Native fixture owner is a different frozen runtime image'
        }
        $owner=Join-Path $ImagePayload $ownerRelative
    }
    if((Get-FileHash -LiteralPath $owner).Hash.ToLowerInvariant() -cne $plan.owner.sha256 -or
        [IO.Path]::GetFileName($owner) -cne $plan.owner.basename -or
        ($static -and ($plan.owner.sha256 -cne $plan.host.sha256 -or $null -ne $plan.runtime))){
        throw 'Native fixture actual owner bytes basename or static host differ'
    }
    $link=@();$actualOwner=$null;$ownerSymbols=@()
    if($parts[1] -ceq 'windows'){
        $actualOwner=Get-PEImageExports -Path $owner
        $imports=Get-PEImageImports -Path $host
        if($static -eq $actualOwner.is_dll -or
            (-not $static -and @($imports|Where-Object library -IEQ $plan.owner.basename).Count -ne 1) -or
            ($static -and @($imports|Where-Object library -IMatch '^(lib)?lua\.dll$').Count -ne 0)){
            throw 'Native fixture actual host imports a different owner'
        }
        $pe=$plan.pe_import
        if($pe.owner.sha256 -cne $plan.owner.sha256 -or $pe.owner.basename -cne $plan.owner.basename -or
            $pe.tool.sha256 -cne $Image.toolchain.dlltool_sha256){throw 'Native import archive owner or frozen dlltool differs'}
        $definition=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $pe.definition.path -Sha256 $pe.definition.sha256
        $null=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $pe.import_library.path -Sha256 $pe.import_library.sha256
        $lines=@(('LIBRARY '+$actualOwner.basename),'EXPORTS')
        foreach($export in @($actualOwner.exports|Where-Object name -CMatch '^lua(L_|_|open_)')){
            if($null -ne $export.forwarder){throw 'Native owner forwards public interpreter exports'}
            $lines+=($export.name+$(if($export.is_data){' DATA'}else{''}))
        }
        if($lines.Count -le 2 -or [IO.File]::ReadAllText($definition) -cne (($lines -join "`n")+"`n")){
            throw 'Native owner import definition does not reconstruct actual function and data exports'
        }
        Assert-NativeFixtureToolCapture -Process $pe.process -ArtifactRoot $ArtifactRoot -ToolHash $Image.toolchain.dlltool_sha256 `
            -Arguments @('-m','i386:x86-64','-D',$actualOwner.basename,'-d','host.def','-l','host.a')
        if($pe.process.working_directory.Replace('\','/') -cne (Get-NativeRecordedDirectory $pe.definition.path)){
            throw 'Native import tool working directory differs'
        }
        $link=@($pe.import_library.path)
    }else{
        # The POSIX collector replays exact nm observations and the compile
        # command rather than loading foreign ELF/Mach-O images. Actual host
        # export visibility and lifetime still require the platform process.
        $ownerSymbols=Read-NativeSymbolCapture -Record $plan.dynamic_symbols -ArtifactRoot $ArtifactRoot -ToolHash $Image.toolchain.nm_sha256 `
            -ImagePath $plan.owner.path -Platform $parts[1]
        if(@($ownerSymbols|Where-Object{ $_ -cmatch '^lua(L_|_|open_)' }).Count -eq 0){throw 'Native fixture owner lacks captured public exports'}
        if(-not $static){$link=@($plan.owner.path)}
        if($parts[1] -ceq 'macos'){$link+='-Wl,-undefined,dynamic_lookup'}
    }
    if((@($plan.link_arguments)-join '|') -cne ($link-join '|')){throw 'Native fixture link arguments differ from the selected image'}
    $cases=@(@{name='lib1';source='lib1.c';dependency=$null},@{name='lib11';source='lib11.c';dependency='lib1'},
        @{name='lib2';source='lib2.c';dependency=$null},@{name='lib21';source='lib21.c';dependency='lib2'},@{name='lib2-v2';source='lib22.c';dependency=$null})
    $expectedArtifacts=if($parts[1] -ceq 'windows'){10}else{5}
    if(@($receipt.modules).Count -ne 5 -or @($receipt.artifacts).Count -ne $expectedArtifacts){throw 'Native fixture module or alias set is incomplete'}
    $known=@{};$artifacts=@{}
    $archiveCount=if($parts[1] -ceq 'windows'){2}else{0}
    if(@($receipt.dependency_import_libraries).Count -ne $archiveCount){throw 'Native fixture dependency import archive set differs'}
    foreach($case in $cases){
        $rows=@($receipt.modules|Where-Object source -CEQ ('libs/'+$case.source))
        if($rows.Count -ne 1){throw 'Native fixture translation unit missing or duplicated'}
        $module=$rows[0];$extension=if($parts[1] -ceq 'windows'){'.dll'}else{'.so'}
        if([IO.Path]::GetFileName($module.artifact.Replace('\','/')) -cne ($case.name+$extension)){throw 'Native fixture output basename differs'}
        $binary=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $module.artifact -Sha256 $module.artifact_sha256
        $records=@($receipt.artifacts|Where-Object artifact -CEQ $module.artifact)
        $sourceHash=(Get-FileHash (Join-Path $Root ('references/lua/testes/libs/'+$case.source))).Hash.ToLowerInvariant()
        if($records.Count -ne 1 -or $records[0].source -cne $module.source -or $records[0].source_sha256 -cne $sourceHash -or
            $records[0].artifact_sha256 -cne $module.artifact_sha256){throw 'Native fixture compiled source or artifact binding differs'}
        $artifactDirectory=Get-NativeRecordedDirectory $module.artifact
        if($ConsumerHost -and $artifactDirectory -cne $Report.native_fixture_directory.Replace('\','/')){
            throw 'Native consumer loaded a fixture directory different from its compiled module receipt'
        }
        $source=Join-NativeRecordedPath $artifactDirectory $case.source
        $null=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $source -Sha256 $sourceHash
        $compile=$module.compile;$originalRoot=$receipt.source_root
        if($compile.working_directory.Replace('\','/') -cne $originalRoot.Replace('\','/') -or
            $compile.executable.Replace('\','/') -cne $plan.compiler.path.Replace('\','/')){throw 'Native fixture compiler source root or executable path differs'}
        $arguments=@('-std=c99','-O2','-I',(Join-NativeRecordedPath $originalRoot 'references/lua'),'-include',(Join-NativeRecordedPath $originalRoot $receipt.forced_header.path))
        if($parts[0] -ceq 'upstream-test'){$arguments+='-DLUA_USER_H=<ltests.h>'}
        if($parts[1] -cne 'windows'){$arguments+='-fPIC'}
        $arguments+=@($(if($parts[1] -ceq 'macos'){'-dynamiclib'}else{'-shared'}),$source,'-o',$module.artifact)+$link
        if($parts[1] -ceq 'windows' -and $case.name -cin @('lib1','lib2')){
            $archive=Join-NativeRecordedPath $artifactDirectory ($case.name+'.a')
            $arguments+=('-Wl,--out-implib,'+$archive)
            $archiveRows=@($receipt.dependency_import_libraries|Where-Object{ $_.path.Replace('\','/') -ceq $archive })
            if($archiveRows.Count -ne 1){throw 'Native fixture dependency import archive missing or duplicated'}
            $null=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $archiveRows[0].path -Sha256 $archiveRows[0].sha256
        }
        if($parts[1] -ceq 'windows' -and $null -ne $case.dependency){$arguments+=Join-NativeRecordedPath $artifactDirectory ($case.dependency+'.a')}
        Assert-NativeFixtureToolCapture -Process $compile -ArtifactRoot $ArtifactRoot -ToolHash $Image.toolchain.compiler_sha256 -Arguments $arguments
        if($parts[1] -ceq 'windows'){
            $dependencies=if($null -eq $case.dependency){@()}else{@($known[$case.dependency])}
            $binding=Assert-PEModuleOwner -OwnerImage $actualOwner -ModulePath $binary -DependencyImages $dependencies -RequireDirectImport:($null -eq $case.dependency)
            if($module.binding.owner_sha256 -cne $binding.owner_sha256 -or $module.binding.owner_basename -cne $binding.owner_basename -or
                $module.binding.module_sha256 -cne $binding.module_sha256 -or
                (@($module.binding.imported_owner_symbols)-join '|') -cne (@($binding.imported_owner_symbols)-join '|')){
                throw 'Native module recorded owner facts differ from actual imports'
            }
            $known[$case.name]=Get-PEImageExports -Path $binary
            $alias=$module.artifact.Substring(0,$module.artifact.Length-4)+'.so'
            $aliasRows=@($receipt.artifacts|Where-Object artifact -CEQ $alias)
            if($aliasRows.Count -ne 1 -or $aliasRows[0].alias_of -cne $module.artifact -or
                $aliasRows[0].source -cne $module.source -or $aliasRows[0].source_sha256 -cne $sourceHash -or
                $aliasRows[0].artifact_sha256 -cne $module.artifact_sha256){throw 'Native fixture Windows alias binding differs'}
            $null=Resolve-NativeFixtureCapture -Root $ArtifactRoot -Original $alias -Sha256 $module.artifact_sha256
        }else{
            $defined=Read-NativeSymbolCapture -Record $module.binding.defined -ArtifactRoot $ArtifactRoot -ToolHash $Image.toolchain.nm_sha256 `
                -ImagePath $module.artifact -Platform $parts[1]
            $undefined=Read-NativeSymbolCapture -Record $module.binding.undefined -ArtifactRoot $ArtifactRoot -ToolHash $Image.toolchain.nm_sha256 `
                -ImagePath $module.artifact -Platform $parts[1] -Undefined
            if(@($defined|Where-Object{ $_ -cin $ownerSymbols -and $_ -cmatch '^lua(L_|_|open_)' }).Count){throw 'Native fixture embeds captured interpreter exports'}
            $used=@($undefined|Where-Object{ $_ -cin $ownerSymbols -and $_ -cmatch '^lua(L_|_|open_)' })
            $dependencySymbol=if($case.dependency -ceq 'lib1'){'lib1_export'}elseif($case.dependency -ceq 'lib2'){'luaopen_lib2'}else{$null}
            if($null -eq $dependencySymbol -and $used.Count -eq 0){throw 'Native fixture lacks captured owner API lookups'}
            if($null -ne $dependencySymbol -and ($dependencySymbol -cnotin $undefined -or $dependencySymbol -cnotin $known[$case.dependency].defined -or
                -not $known[$case.dependency].reaches_owner)){throw 'Native fixture captured dependency does not reach the same owner'}
            if(@($undefined|Where-Object{ $_ -cmatch '^lua(L_|_|open_)' -and $_ -cnotin $ownerSymbols -and $_ -cne $dependencySymbol }).Count){
                throw 'Native fixture looks up public symbols outside the selected owner and dependency'
            }
            if((@($module.binding.imported_owner_symbols)-join '|') -cne ($used-join '|')){throw 'Native fixture recorded owner lookups differ from captures'}
            $known[$case.name]=@{defined=$defined;reaches_owner=($used.Count -gt 0 -or $null -ne $dependencySymbol)}
        }
    }
    foreach($record in $receipt.artifacts){
        if($artifacts.ContainsKey($record.artifact)){throw 'Native fixture artifact duplicated'}
        $artifacts[$record.artifact]=$true
        $rows=@($Report.native_fixture_records|Where-Object artifact -CEQ $record.artifact)
        if($rows.Count -ne 1 -or $rows[0].source -cne $record.source -or $rows[0].source_sha256 -cne $record.source_sha256 -or
            $rows[0].artifact_sha256 -cne $record.artifact_sha256){throw 'Native fixture report and receipt artifact sets differ'}
    }
    return @{verified=$true;modules=5;artifacts=$expectedArtifacts;owner_sha256=$plan.owner.sha256;runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Assert-NativeLuaFixtureEvidence
