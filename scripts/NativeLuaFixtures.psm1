Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'NativeModuleLinkage.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')

function Invoke-NativeFixtureTool {
    param([string] $Executable,[string[]] $Arguments,[string] $Directory,[string] $Prefix)
    $result=Invoke-ConformanceProcess -Executable $Executable -Arguments $Arguments -Directory $Directory -OutputPrefix $Prefix `
        -TimeoutSeconds 120 -Environment @{PATH=((Split-Path -Parent $Executable)+[IO.Path]::PathSeparator+$env:PATH)}
    if($result.exit_code -ne 0 -or $result.timed_out -or $result.capture_exceeded -or $result.pipe_drain_failed -or
        $result.process_tree_kill_error -or $result.abnormal_exit_kind -or $result.stderr_bytes -ne 0){
        throw "Native fixture tool failed: $($result.stderr_path)"
    }
    return $result
}

function Get-NativeDynamicSymbols {
    param([string] $ImagePath,[string] $Compiler,[string] $Platform,[string] $Prefix,[switch] $Undefined)
    $nm=Join-Path (Split-Path -Parent $Compiler) 'nm'
    if(-not (Test-Path -LiteralPath $nm -PathType Leaf)){$nm=(Get-Command nm -ErrorAction Stop).Source}
    $arguments=if($Platform -ceq 'macos'){@('-g',$(if($Undefined){'-u'}else{'-U'}),$ImagePath)}
        else{@('-D',$(if($Undefined){'--undefined-only'}else{'--defined-only'}),$ImagePath)}
    $process=Invoke-NativeFixtureTool -Executable $nm -Arguments $arguments -Directory (Split-Path -Parent $Prefix) -Prefix $Prefix
    $symbols=@(ConvertFrom-NativeSymbolTable -Lines ([IO.File]::ReadAllLines($process.stdout_path)) -Platform $Platform)
    return @{symbols=$symbols;process=$process;tool=@{path=$nm;sha256=(Get-FileHash $nm).Hash.ToLowerInvariant()}}
}

function New-NativeLuaFixturePlan {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $HostPath,
          [Parameter(Mandatory)][string] $RuntimeDirectory,[Parameter(Mandatory)][string] $Compiler,
          [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string] $Implementation,
          [Parameter(Mandatory)][ValidateSet('static','static-pic','relocatable','shared')][string] $LibraryType,
          [Parameter(Mandatory)][ValidateSet('windows','linux','macos')][string] $Platform,
          [Parameter(Mandatory)][string] $RecordDirectory,[string] $CompilerSha256='')
    $compilerPath=[IO.Path]::GetFullPath($Compiler)
    $actualCompilerHash=(Get-FileHash -LiteralPath $compilerPath).Hash.ToLowerInvariant()
    if($CompilerSha256 -ne '' -and $actualCompilerHash -cne $CompilerSha256){throw 'Native fixture compiler differs from its frozen context'}
    $hostImage=[IO.Path]::GetFullPath($HostPath)
    $hostIdentity=@{path=$hostImage;basename=[IO.Path]::GetFileName($hostImage);sha256=(Get-FileHash $hostImage).Hash.ToLowerInvariant()}
    $static=$Implementation -ceq 'Ada' -and $LibraryType -cin @('static','static-pic')
    $owner=$hostImage;$runtime=$null
    if(-not $static){
        $stem=if($Implementation -ceq 'Ada'){'liblua'}else{'libconformance_lua'}
        $suffix=if($Platform -ceq 'windows'){'.dll'}elseif($Platform -ceq 'macos'){'.dylib'}else{'.so'}
        $owner=Join-Path ([IO.Path]::GetFullPath($RuntimeDirectory)) ($stem+$suffix)
        if(-not (Test-Path -LiteralPath $owner -PathType Leaf)){throw 'Native modules require the actual shared runtime image; an archive is not a fallback'}
        $runtime=@{path=$owner;sha256=(Get-FileHash $owner).Hash.ToLowerInvariant()}
    }
    $import=$null;$symbols=$null;$link=@()
    if($Platform -ceq 'windows'){
        $hostImports=Get-PEImageImports -Path $hostImage
        if(-not $static -and @($hostImports|Where-Object library -IEQ ([IO.Path]::GetFileName($owner))).Count -ne 1){
            throw 'Native fixture host does not import its selected actual shared runtime image'
        }
        if($static -and @($hostImports|Where-Object library -IMatch '^(lib)?lua\.dll$').Count -ne 0){
            throw 'Static native fixture host imports a different shared interpreter image'
        }
        $dlltool=Join-Path (Split-Path -Parent $compilerPath) 'dlltool.exe'
        $import=New-PEHostImportLibrary -Root $Root -ImagePath $owner -DllTool $dlltool -OutputDirectory (Join-Path $RecordDirectory 'owner-import')
        if($static -eq $import.owner.is_dll){throw 'Native module linkage selected an EXE/DLL inconsistent with its runtime kind'}
        $link=@($import.import_library.path)
    }else{
        $symbols=Get-NativeDynamicSymbols -ImagePath $owner -Compiler $compilerPath -Platform $Platform -Prefix (Join-Path $RecordDirectory 'owner-symbols')
        if(@($symbols.symbols|Where-Object{ $_ -cmatch '^lua(L_|_|open_)' }).Count -eq 0){throw 'Native owner lacks actual exported public symbols'}
        if(-not $static){$link=@($owner)}
        if($Platform -ceq 'macos'){$link+=@('-Wl,-undefined,dynamic_lookup')}
    }
    return @{schema_version=1;kind='same-image-native-fixture-plan';platform=$Platform;implementation=$Implementation;
        library_type=$LibraryType;mode=$(if($static){'exported-host'}else{'shared-runtime'});host=$hostIdentity;
        owner=@{path=$owner;basename=[IO.Path]::GetFileName($owner);sha256=(Get-FileHash $owner).Hash.ToLowerInvariant()};
        runtime=$runtime;compiler=@{path=$compilerPath;sha256=$actualCompilerHash};pe_import=$import;dynamic_symbols=$symbols;
        link_arguments=$link;runtime_acceptance=$false;coverage_authority=$false}
}

function Build-NativeLuaFixtures {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $HostPath,
          [Parameter(Mandatory)][string] $RuntimeDirectory,[Parameter(Mandatory)][string] $Compiler,
          [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string] $Implementation,
          [Parameter(Mandatory)][ValidateSet('static','static-pic','relocatable','shared')][string] $LibraryType,
          [Parameter(Mandatory)][ValidateSet('windows','linux','macos')][string] $Platform,
          [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string] $Configuration,
          [Parameter(Mandatory)][string] $FixtureDirectory,[Parameter(Mandatory)][string] $RecordDirectory,
          [string] $CompilerSha256='')
    foreach($path in @($FixtureDirectory,$RecordDirectory)){
        $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),[IO.Path]::GetFullPath($path)).Replace('\','/')
        if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal)){throw 'Native fixture outputs must remain in disposable reports directories'}
    }
    if(Test-Path -LiteralPath $RecordDirectory){throw 'Native fixture linkage record directory must be new'}
    [void][IO.Directory]::CreateDirectory($RecordDirectory)
    Test-ConformanceReferenceTree -Root $Root
    $sourceDirectory=Join-Path $Root 'references/lua/testes/libs'
    $libraries=Join-Path $FixtureDirectory 'libs'
    if(-not (Test-Path -LiteralPath $libraries)){$null=Copy-ConformanceFixtures -Source $sourceDirectory -Destination $libraries}
    # Verify every original support source alongside the five translation
    # units. lib22.c independently implements the alternate lib2-v2 module;
    # lib11/lib21 refer to the separately linked fixture exports. None of
    # these copied reference bytes is a generated implementation substitute.
    foreach($source in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse){
        $relative=[IO.Path]::GetRelativePath($sourceDirectory,$source.FullName)
        if((Get-FileHash (Join-Path $libraries $relative)).Hash -cne (Get-FileHash $source.FullName).Hash){throw 'Native fixture source copy differs from the pinned original'}
    }
    $plan=New-NativeLuaFixturePlan -Root $Root -HostPath $HostPath -RuntimeDirectory $RuntimeDirectory -Compiler $Compiler `
        -Implementation $Implementation -LibraryType $LibraryType -Platform $Platform -RecordDirectory $RecordDirectory -CompilerSha256 $CompilerSha256
    # Preserve the exact linked host as evidence even when the caller runs a
    # C consumer from build/. The snapshot keeps its real basename so final
    # PE import replay cannot inherit a different launcher's identity.
    $hostDirectory=Join-Path $RecordDirectory 'host'
    [void][IO.Directory]::CreateDirectory($hostDirectory)
    $hostCapture=Join-Path $hostDirectory $plan.host.basename
    [IO.File]::Copy($HostPath,$hostCapture)
    $hostHash=(Get-FileHash $hostCapture).Hash.ToLowerInvariant()
    if($hostHash -cne $plan.host.sha256){throw 'Native fixture host changed while its evidence snapshot was copied'}
    $include=Join-Path $Root 'references/lua';$header=Join-Path $Root 'experiments/conformance/c/module_exports.h'
    $common=@('-std=c99','-O2','-I',$include,'-include',$header)
    if($Configuration -ceq 'upstream-test'){$common+='-DLUA_USER_H=<ltests.h>'}
    if($Platform -cne 'windows'){$common+='-fPIC'}
    $shared=if($Platform -ceq 'macos'){'-dynamiclib'}else{'-shared'}
    $extension=if($Platform -ceq 'windows'){'.dll'}else{'.so'}
    $cases=@(@{name='lib1';source='lib1.c';dependency=$null},@{name='lib11';source='lib11.c';dependency='lib1'},
        @{name='lib2';source='lib2.c';dependency=$null},@{name='lib21';source='lib21.c';dependency='lib2'},
        @{name='lib2-v2';source='lib22.c';dependency=$null})
    $records=@();$bindings=@();$known=@{}
    foreach($case in $cases){
        $source=Join-Path $libraries $case.source;$artifact=Join-Path $libraries ($case.name+$extension)
        if(Test-Path -LiteralPath $artifact){throw 'Native fixture binary output must be new'}
        $arguments=$common+@($shared,$source,'-o',$artifact)+@($plan.link_arguments)
        if($Platform -ceq 'windows' -and $case.name -cin @('lib1','lib2')){
            $arguments+=('-Wl,--out-implib,'+(Join-Path $libraries ($case.name+'.a')))
        }
        if($Platform -ceq 'windows' -and $null -ne $case.dependency){$arguments+=Join-Path $libraries ($case.dependency+'.a')}
        $compile=Invoke-NativeFixtureTool -Executable $plan.compiler.path -Arguments $arguments -Directory $Root -Prefix (Join-Path $RecordDirectory ($case.name+'-compile'))
        $hash=(Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant()
        $record=@{source=('libs/'+$case.source);source_sha256=(Get-FileHash $source).Hash.ToLowerInvariant();artifact=$artifact;artifact_sha256=$hash}
        $records+=$record
        if($Platform -ceq 'windows'){
            $deps=if($null -ne $case.dependency){@($known[$case.dependency])}else{@()}
            $binding=Assert-PEModuleOwner -OwnerImage $plan.pe_import.owner -ModulePath $artifact -DependencyImages $deps -RequireDirectImport:($null -eq $case.dependency)
            $known[$case.name]=Get-PEImageExports -Path $artifact
            # attrib.lua's exact DC helper requests .dll on Windows; other
            # unchanged tests and package templates use .so. Keep both names
            # as explicitly recorded byte-identical module artifacts.
            $alias=Join-Path $libraries ($case.name+'.so')
            if(Test-Path -LiteralPath $alias){throw 'Native fixture alias output must be new'}
            [IO.File]::Copy($artifact,$alias)
            if((Get-FileHash $alias).Hash.ToLowerInvariant() -cne $hash){throw 'Native fixture alias changed module bytes'}
            $records+=@{source=$record.source;source_sha256=$record.source_sha256;artifact=$alias;artifact_sha256=$hash;alias_of=$artifact}
        }else{
            $undefined=Get-NativeDynamicSymbols -ImagePath $artifact -Compiler $Compiler -Platform $Platform -Prefix (Join-Path $RecordDirectory ($case.name+'-imports')) -Undefined
            $defined=Get-NativeDynamicSymbols -ImagePath $artifact -Compiler $Compiler -Platform $Platform -Prefix (Join-Path $RecordDirectory ($case.name+'-exports'))
            $api=@($undefined.symbols|Where-Object{ $_ -cmatch '^lua(L_|_|open_)' -and $_ -cin $plan.dynamic_symbols.symbols })
            if(@($defined.symbols|Where-Object{ $_ -cmatch '^lua(L_|_|open_)' -and $_ -cin $plan.dynamic_symbols.symbols }).Count){throw 'Native fixture embeds interpreter API definitions'}
            if($api.Count -eq 0 -and $null -eq $case.dependency){throw 'Native fixture lacks actual owner API lookup symbols'}
            $binding=@{imported_owner_symbols=$api;undefined=$undefined;defined=$defined;runtime_acceptance=$false;coverage_authority=$false}
        }
        $bindings+=@{source=$record.source;artifact=$artifact;artifact_sha256=$hash;compile=$compile;binding=$binding}
    }
    $evidence=@{schema_version=1;kind='same-image-native-fixture-observations';plan=$plan;configuration=$Configuration;synthetic_fixture=$false;
        host_capture=@{path=$hostCapture;sha256=$hostHash};
        source_root=[IO.Path]::GetFullPath($Root);
        source_bindings=@(foreach($relative in @('scripts/NativeLuaFixtures.psm1','scripts/NativeModuleLinkage.psm1')){
            @{path=$relative;sha256=(Get-FileHash (Join-Path $Root $relative)).Hash.ToLowerInvariant()}
        });
        forced_header=@{path='experiments/conformance/c/module_exports.h';sha256=(Get-FileHash $header).Hash.ToLowerInvariant()};
        dependency_import_libraries=@(if($Platform -ceq 'windows'){foreach($name in @('lib1','lib2')){
            $archive=Join-Path $libraries ($name+'.a');@{path=$archive;sha256=(Get-FileHash $archive).Hash.ToLowerInvariant()}
        }});
        modules=$bindings;artifacts=$records;runtime_acceptance=$false;coverage_authority=$false}
    $path=Join-Path $RecordDirectory 'linkage.json'
    [IO.File]::WriteAllText($path,(ConvertTo-Json $evidence -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return @{identity=@{path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant()};evidence=$evidence;records=$records;
        library_directory=$libraries;runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function New-NativeLuaFixturePlan, Build-NativeLuaFixtures
