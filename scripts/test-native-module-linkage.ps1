param([string] $Compiler='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'NativeModuleLinkage.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'NativeLuaFixtures.psm1')
$directory=Join-Path $root ('reports/native-module-linkage-selftest/'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$utf8=[Text.UTF8Encoding]::new($false);$script:Cases=0;$script:Serial=0
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "NATIVE LINKAGE TEST PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Expected){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($null -ne $failure -and $failure -match $Expected) "Wrong failure: $failure; expected $Expected"}
function Put16([byte[]]$Bytes,[int]$Offset,[UInt16]$Value){[BitConverter]::GetBytes($Value).CopyTo($Bytes,$Offset)}
function Put32([byte[]]$Bytes,[int]$Offset,[UInt32]$Value){[BitConverter]::GetBytes($Value).CopyTo($Bytes,$Offset)}
function Put64([byte[]]$Bytes,[int]$Offset,[UInt64]$Value){[BitConverter]::GetBytes($Value).CopyTo($Bytes,$Offset)}
function PutText([byte[]]$Bytes,[int]$Offset,[string]$Text){[Text.Encoding]::ASCII.GetBytes($Text).CopyTo($Bytes,$Offset)}
function New-PEFixture([switch]$Module){
    # These hand-built bytes exercise parser boundaries only. The synthetic
    # PE image is never launched and contains no Lua implementation or tests.
    $bytes=[byte[]]::new(0xc00);$bytes[0]=77;$bytes[1]=90;Put32 $bytes 0x3c 0x80
    PutText $bytes 0x80 "PE`0`0";Put16 $bytes 0x84 0x8664;Put16 $bytes 0x86 2
    Put16 $bytes 0x94 240;Put16 $bytes 0x96 $(if($Module){0x2022}else{0x22})
    $optional=0x98;Put16 $bytes $optional 0x20b
    Put32 $bytes ($optional+4) 0x200;Put32 $bytes ($optional+8) 0x800
    Put32 $bytes ($optional+16) 0x1000;Put32 $bytes ($optional+20) 0x1000
    Put64 $bytes ($optional+24) 0x140000000;Put32 $bytes ($optional+32) 0x1000;Put32 $bytes ($optional+36) 0x200
    Put16 $bytes ($optional+40) 6;Put16 $bytes ($optional+48) 6
    Put32 $bytes ($optional+56) 0x3000;Put32 $bytes ($optional+60) 0x200;Put16 $bytes ($optional+68) 3
    Put64 $bytes ($optional+72) 0x100000;Put64 $bytes ($optional+80) 0x1000
    Put64 $bytes ($optional+88) 0x100000;Put64 $bytes ($optional+96) 0x1000
    Put32 $bytes ($optional+108) 16
    Put32 $bytes ($optional+112) 0x2000;Put32 $bytes ($optional+116) 0x100
    PutText $bytes 0x188 '.text';Put32 $bytes 0x190 0x1000;Put32 $bytes 0x194 0x1000
    Put32 $bytes 0x198 0x200;Put32 $bytes 0x19c 0x200;Put32 $bytes 0x1ac 0x60000020
    PutText $bytes 0x1b0 '.rdata';Put32 $bytes 0x1b8 0x1000;Put32 $bytes 0x1bc 0x2000
    Put32 $bytes 0x1c0 0x800;Put32 $bytes 0x1c4 0x400;Put32 $bytes 0x1d4 0x40000040
    $bytes[0x200]=0xc3
    Put32 $bytes 0x40c 0x2060;Put32 $bytes 0x410 1;Put32 $bytes 0x414 2;Put32 $bytes 0x418 2
    Put32 $bytes 0x41c 0x2040;Put32 $bytes 0x420 0x2050;Put32 $bytes 0x424 0x2058
    Put32 $bytes 0x440 0x1000;Put32 $bytes 0x444 0x2200
    Put32 $bytes 0x450 0x2080;Put32 $bytes 0x454 0x20a0;Put16 $bytes 0x458 0;Put16 $bytes 0x45a 1
    PutText $bytes 0x460 "unit-host.exe`0";PutText $bytes 0x480 "fixture_function`0";PutText $bytes 0x4a0 "fixture_data`0"
    if($Module){
        # This module imports both identities and defines neither. Import
        # directory, descriptor, thunk and hint/name bytes are independent
        # inputs to the parser; they are not a serialized helper result.
        Put32 $bytes ($optional+112) 0;Put32 $bytes ($optional+116) 0
        Put32 $bytes ($optional+120) 0x2300;Put32 $bytes ($optional+124) 40
        Put32 $bytes 0x700 0x2340;Put32 $bytes 0x70c 0x2380;Put32 $bytes 0x710 0x2360
        Put64 $bytes 0x740 0x23a0;Put64 $bytes 0x748 0x23c0
        PutText $bytes 0x780 "unit-host.exe`0";PutText $bytes 0x7a2 "fixture_function`0";PutText $bytes 0x7c2 "fixture_data`0"
    }
    $script:Serial++;$path=Join-Path $directory $(if($Module){"module-$script:Serial.dll"}else{"host-$script:Serial.exe"})
    [IO.File]::WriteAllBytes($path,$bytes)
    return @{path=$path;bytes=$bytes}
}
function Save-PE([Collections.IDictionary]$Fixture){[IO.File]::WriteAllBytes($Fixture.path,$Fixture.bytes)}
Case 'synthetic PE bytes distinguish actual code data and original export-directory name'{
    $f=New-PEFixture;$r=Get-PEImageExports $f.path
    Assert-True ($r.machine -ceq 'Amd64' -and -not $r.is_dll -and $r.exports.Count -eq 2 -and
        @($r.exports|Where-Object{ $_.name -ceq 'fixture_data' -and $_.is_data }).Count -eq 1 -and
        @($r.exports|Where-Object{ $_.name -ceq 'fixture_function' -and -not $_.is_data }).Count -eq 1 -and
        $r.original_export_image_name -ceq 'unit-host.exe' -and -not $r.runtime_acceptance) 'PE byte classification changed'
}
Case 'definition binds the actual arbitrary basename and marks actual data imports'{
    $f=New-PEFixture;$renamed=Join-Path $directory 'arbitrary-consumer.exe';[IO.File]::Copy($f.path,$renamed)
    $record=New-PEHostDefinition -Root $root -ImagePath $renamed -OutputDirectory (Join-Path $directory 'definition') -ExportNames fixture_function,fixture_data
    $lines=@(Get-Content $record.definition.path)
    Assert-True ($lines[0] -ceq 'LIBRARY arbitrary-consumer.exe' -and $lines[1] -ceq 'EXPORTS' -and
        'fixture_data DATA' -cin $lines -and 'fixture_function' -cin $lines -and -not $record.coverage_authority) 'Definition inherited the original linker basename or invented data classification'
}
Case 'malformed export counts ordinals names addresses and truncated images fail closed'{
    foreach($change in @('count','ordinal','duplicate','null','address','name','truncated')){
        $f=New-PEFixture
        switch($change){count{Put32 $f.bytes 0x418 0xffffffffL};ordinal{Put16 $f.bytes 0x45a 2};duplicate{Put32 $f.bytes 0x454 0x2080};
            null{Put32 $f.bytes 0x440 0};address{Put32 $f.bytes 0x440 0x900000};name{$f.bytes[0x480]=0xff};truncated{$f.bytes=[byte[]]::new(16)}}
        Save-PE $f
        Reject {Get-PEImageExports $f.path} 'PE|Image|image|format|headers'
    }
}
Case 'missing forwarded and architecture-mismatched exports cannot create owner import definitions'{
    $f=New-PEFixture
    Reject {New-PEHostDefinition -Root $root -ImagePath $f.path -OutputDirectory (Join-Path $directory 'missing') -ExportNames missing_function} 'required actual public exports'
    Put32 $f.bytes 0x440 0x20c0;PutText $f.bytes 0x4c0 "other_image.function`0";Save-PE $f
    Reject {New-PEHostDefinition -Root $root -ImagePath $f.path -OutputDirectory (Join-Path $directory 'forwarded') -ExportNames fixture_function} 'not an owned function or data'
    $f=New-PEFixture;Put16 $f.bytes 0x84 0x14c;Save-PE $f
    Reject {New-PEHostDefinition -Root $root -ImagePath $f.path -OutputDirectory (Join-Path $directory 'machine') -ExportNames fixture_function} 'actual AMD64 image'
}
Case 'synthetic import tables preserve exact function data and imported owner names'{
    $f=New-PEFixture -Module;$imports=Get-PEImageImports $f.path
    Assert-True ($imports.Count -eq 1 -and $imports[0].library -ceq 'unit-host.exe' -and
        ($imports[0].symbols -join '|') -ceq 'fixture_function|fixture_data') 'PE imports changed'
    Put32 $f.bytes (0x98+124) 20;Save-PE $f
    Reject {Get-PEImageImports $f.path} 'descriptor table is unterminated'
}
Case 'wrong owner basename bytes embedding and invented export metadata cannot bypass import replay'{
    $f=New-PEFixture;$ownerPath=Join-Path $directory 'unit-host.exe';[IO.File]::Copy($f.path,$ownerPath)
    $owner=Get-PEImageExports $ownerPath;$module=New-PEFixture -Module
    $r=Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -OwnedNames fixture_function,fixture_data -RequireDirectImport
    Assert-True ($r.imported_owner_symbols.Count -eq 2 -and -not $r.runtime_acceptance) 'Import replay gained runtime authority'
    $owner.exports=@();$null=Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -OwnedNames fixture_function,fixture_data -RequireDirectImport
    $owner.basename='other.exe';Reject {Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -OwnedNames fixture_function,fixture_data} 'final basename changed'
    $owner=Get-PEImageExports $ownerPath
    PutText $module.bytes 0x780 "evil-host.exe`0";Save-PE $module
    Reject {Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -OwnedNames fixture_function,fixture_data} 'another image'
    $embedded=New-PEFixture;Put16 $embedded.bytes 0x96 0x2022;Save-PE $embedded
    Reject {Assert-PEModuleOwner -OwnerImage $owner -ModulePath $embedded.path -OwnedNames fixture_function,fixture_data} 'defines an interpreter API'
}
Case 'transitive fixture imports must reach the same actual owner instead of trusting dependency labels'{
    $owner=Get-PEImageExports (Join-Path $directory 'unit-host.exe')
    $dependency=New-PEFixture -Module
    Put32 $dependency.bytes (0x98+112) 0x2000;Put32 $dependency.bytes (0x98+116) 0x100
    PutText $dependency.bytes 0x480 "dependency_entry`0";PutText $dependency.bytes 0x4a0 "dependency_data`0"
    $dependency.path=Join-Path $directory 'dependency.dll';Save-PE $dependency
    $image=Get-PEImageExports $dependency.path
    $module=New-PEFixture -Module
    PutText $module.bytes 0x780 "dependency.dll`0"
    PutText $module.bytes 0x7a2 "dependency_entry`0";PutText $module.bytes 0x7c2 "dependency_data`0";Save-PE $module
    $result=Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -DependencyImages @($image) -OwnedNames fixture_function,fixture_data
    Assert-True ($result.imported_owner_symbols.Count -eq 0 -and $result.imported_dependency_symbols.Count -eq 2) 'Transitive fixture invented a direct owner import'
    Reject {Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -DependencyImages @($image) -OwnedNames fixture_function,fixture_data -RequireDirectImport} 'no actual direct'
    Put32 $dependency.bytes (0x98+120) 0;Put32 $dependency.bytes (0x98+124) 0;Save-PE $dependency
    Reject {Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -DependencyImages @($image) -OwnedNames fixture_function,fixture_data} 'dependency bytes changed'
    $image=Get-PEImageExports $dependency.path
    Reject {Assert-PEModuleOwner -OwnerImage $owner -ModulePath $module.path -DependencyImages @($image) -OwnedNames fixture_function,fixture_data} 'no actual direct or reviewed transitive'
}
Case 'fixture planning rejects a changed frozen compiler and shared archive fallback before a tool runs'{
    $compilerPath=(Get-Command pwsh).Source;$image=Join-Path $directory 'unit-host.exe'
    $runtime=Join-Path $directory 'archive-only';[void][IO.Directory]::CreateDirectory($runtime)
    [IO.File]::WriteAllText((Join-Path $runtime 'liblua.a'),'synthetic archive is never executable evidence',$utf8)
    Reject {New-NativeLuaFixturePlan -Root $root -HostPath $image -RuntimeDirectory $runtime -Compiler $compilerPath `
        -Implementation Ada -LibraryType static -Platform windows -RecordDirectory (Join-Path $directory 'wrong-compiler') -CompilerSha256 ('0'*64)} 'differs from its frozen context'
    Reject {New-NativeLuaFixturePlan -Root $root -HostPath $image -RuntimeDirectory $runtime -Compiler $compilerPath `
        -Implementation Ada -LibraryType relocatable -Platform windows -RecordDirectory (Join-Path $directory 'archive-fallback')} 'actual shared runtime image; an archive is not a fallback'
}
Case 'fixture builder rejects changed copied C bytes and output paths outside reports before compilation'{
    $fixtureDirectory=Join-Path $directory 'changed-c-source'
    $null=Copy-ConformanceFixtures -Source (Join-Path $root 'references/lua/testes/libs') -Destination (Join-Path $fixtureDirectory 'libs')
    [IO.File]::AppendAllText((Join-Path $fixtureDirectory 'libs/lib1.c'),"`n/* deliberately changed validator input */`n",$utf8)
    $compilerPath=(Get-Command pwsh).Source;$image=Join-Path $directory 'unit-host.exe'
    Reject {Build-NativeLuaFixtures -Root $root -HostPath $image -RuntimeDirectory $directory -Compiler $compilerPath `
        -Implementation Ada -LibraryType static -Platform windows -Configuration default -FixtureDirectory $fixtureDirectory `
        -RecordDirectory (Join-Path $directory 'changed-c-records')} 'source copy differs from the pinned original'
    Reject {Build-NativeLuaFixtures -Root $root -HostPath $image -RuntimeDirectory $directory -Compiler $compilerPath `
        -Implementation Ada -LibraryType static -Platform windows -Configuration default -FixtureDirectory (Join-Path $root 'tests/forbidden-fixture-output') `
        -RecordDirectory (Join-Path $directory 'forbidden-records')} 'outputs must remain in disposable reports'
}

if($Compiler -ne ''){
    if(-not $IsWindows){throw 'Optional PE loader identity experiment requires Windows'}
    $hostSource=Join-Path $directory 'host.c';$moduleSource=Join-Path $directory 'module.c'
    [IO.File]::WriteAllText($hostSource,@'
#include <windows.h>
#include <stdio.h>
#include <string.h>
__declspec(dllexport) int fixture_data = 7;
__declspec(dllexport) int fixture_function(int value) { return value + 1; }
typedef int (*probe_function)(HMODULE, int (*)(int), int *);
int main(int argc, char **argv) {
    HMODULE module; FARPROC entry; probe_function probe; int same;
    if (argc != 2) return 4;
    module = LoadLibraryA(argv[1]); if (module == NULL) return 2;
    entry = GetProcAddress(module, "fixture_probe");
    if (entry == NULL || sizeof entry != sizeof probe) return 2;
    memcpy(&probe, &entry, sizeof probe);
    same = probe(GetModuleHandleA(NULL), fixture_function, &fixture_data);
    puts(same ? "same-image" : "different-image");
    FreeLibrary(module); return same ? 0 : 3;
}
'@,$utf8)
    [IO.File]::WriteAllText($moduleSource,@'
#include <windows.h>
__declspec(dllimport) int fixture_data;
__declspec(dllimport) int fixture_function(int);
__declspec(dllexport) int fixture_probe(HMODULE host, int (*function)(int), int *data) {
    if (GetModuleHandleA(NULL) != host) return 0;
    if (&fixture_function != function || &fixture_data != data) return 0;
    return fixture_data == 7 && fixture_function(41) == 42;
}
'@,$utf8)
    $fixtureHost=Join-Path $directory 'real-owner.exe';$dlltool=Join-Path (Split-Path -Parent $Compiler) 'dlltool.exe'
    function Compile([string[]]$Arguments){
        $script:Serial++;$r=Invoke-ConformanceProcess -Executable $Compiler -Arguments (@('-std=c99','-Wall','-Wextra','-Werror','-pedantic')+$Arguments) `
            -Directory $directory -OutputPrefix (Join-Path $directory "compile-$script:Serial") -TimeoutSeconds 120
        Assert-True ($r.exit_code -eq 0 -and -not $r.timed_out -and $r.stderr_bytes -eq 0) ([IO.File]::ReadAllText($r.stderr_path))
    }
    Compile @($hostSource,'-o',$fixtureHost)
    $record=New-PEHostImportLibrary -Root $root -ImagePath $fixtureHost -DllTool $dlltool -OutputDirectory (Join-Path $directory 'real-import') -ExportNames fixture_function,fixture_data
    $module=Join-Path $directory 'real-module.dll';Compile @('-shared',$moduleSource,$record.import_library.path,'-o',$module)
    function Execute([string]$HostPath,[string]$ModulePath){
        $script:Serial++;return Invoke-ConformanceProcess -Executable $HostPath -Arguments @($ModulePath) -Directory $directory `
            -OutputPrefix (Join-Path $directory "execute-$script:Serial") -TimeoutSeconds 30
    }
    Case 'actual loader retains identical function and data pointers through a basename-bound import library'{
        $null=Assert-PEModuleOwner -OwnerImage $record.owner -ModulePath $module -OwnedNames fixture_function,fixture_data -RequireDirectImport
        $r=Execute $fixtureHost $module
        Assert-True ($r.exit_code -eq 0 -and [IO.File]::ReadAllText($r.stdout_path).Trim() -ceq 'same-image' -and $r.stderr_bytes -eq 0) 'Actual loader mapped another owner'
    }
    Case 'renaming the real host rejects old imports and rebuilding them restores the actual owner'{
        $renamed=Join-Path $directory 'different-owner.exe';[IO.File]::Copy($fixtureHost,$renamed)
        $renamedImage=Get-PEImageExports $renamed
        Reject {Assert-PEModuleOwner -OwnerImage $renamedImage -ModulePath $module -OwnedNames fixture_function,fixture_data} 'another image'
        $r=Execute $renamed $module
        Assert-True ($r.exit_code -eq 3 -and [IO.File]::ReadAllText($r.stdout_path).Trim() -ceq 'different-image') 'Old import name silently followed the renamed host'
        $fresh=New-PEHostImportLibrary -Root $root -ImagePath $renamed -DllTool $dlltool -OutputDirectory (Join-Path $directory 'renamed-import') -ExportNames fixture_function,fixture_data
        $fixed=Join-Path $directory 'renamed-module.dll';Compile @('-shared',$moduleSource,$fresh.import_library.path,'-o',$fixed)
        $r=Execute $renamed $fixed
        Assert-True ($r.exit_code -eq 0 -and [IO.File]::ReadAllText($r.stdout_path).Trim() -ceq 'same-image') 'Fresh actual-basename import failed'
    }
}else{Write-Output 'NOT RUN: optional real Windows loader identity experiment (Compiler not supplied)'}
Write-Output "PASS: $script:Cases native image linkage regressions; synthetic PE parsing and optional non-Lua C fixtures only; no Lua execution or conformance acceptance"
