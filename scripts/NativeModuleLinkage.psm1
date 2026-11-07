Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')

function Read-PEAscii {
    param([object] $Reader,[int] $Rva)
    if($Rva -le 0){throw 'PE name has an invalid address'}
    $block=$Reader.GetSectionData($Rva)
    [byte[]]$bytes=$block.GetContent(0,[Math]::Min(4096,$block.Length))
    $end=[Array]::IndexOf($bytes,[byte]0)
    if($end -le 0 -or @($bytes[0..($end-1)]|Where-Object{$_ -gt 127 -or $_ -lt 32}).Count){
        throw 'PE name is unterminated empty or non-ASCII'
    }
    return [Text.Encoding]::ASCII.GetString($bytes,0,$end)
}

function Get-PEImageExports {
    param([Parameter(Mandatory)][string] $Path)
    $full=[IO.Path]::GetFullPath($Path)
    # Parse an immutable byte snapshot without retaining a handle to another
    # build's executable. The caller rechecks its image hash when consuming
    # the definition/import library; a concurrent replacement cannot inherit
    # this snapshot's binding.
    $bytes=[IO.File]::ReadAllBytes($full)
    $stream=[IO.MemoryStream]::new($bytes,$false)
    $reader=$null
    try{
        $reader=[System.Reflection.PortableExecutable.PEReader]::new($stream,[System.Reflection.PortableExecutable.PEStreamOptions]::LeaveOpen)
        $directory=$reader.PEHeaders.PEHeader.ExportTableDirectory
        $exports=@();$imageName=$null
        if($directory.RelativeVirtualAddress -ne 0){
            if($directory.Size -lt 40){throw 'PE export directory is truncated'}
            [byte[]]$header=$reader.GetSectionData($directory.RelativeVirtualAddress).GetContent(0,40)
            $count=[BitConverter]::ToUInt32($header,24)
            $functions=[BitConverter]::ToUInt32($header,20)
            if([long]$count*4 -gt $bytes.Length -or [long]$functions*4 -gt $bytes.Length){throw 'PE export table count exceeds the image'}
            $nameRva=[BitConverter]::ToInt32($header,12)
            if($nameRva -ne 0){$imageName=Read-PEAscii $reader $nameRva}
            if($count -gt 0){
                [byte[]]$names=$reader.GetSectionData([BitConverter]::ToInt32($header,32)).GetContent(0,[int]($count*4))
                [byte[]]$ordinals=$reader.GetSectionData([BitConverter]::ToInt32($header,36)).GetContent(0,[int]($count*2))
                [byte[]]$addresses=$reader.GetSectionData([BitConverter]::ToInt32($header,28)).GetContent(0,[int]($functions*4))
                $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                for($i=0;$i -lt $count;$i++){
                    $name=Read-PEAscii $reader ([BitConverter]::ToInt32($names,$i*4))
                    $ordinal=[BitConverter]::ToUInt16($ordinals,$i*2)
                    if(-not $seen.Add($name) -or $ordinal -ge $functions){throw 'PE exports contain duplicate names or invalid ordinals'}
                    $address=[BitConverter]::ToUInt32($addresses,$ordinal*4)
                    if($address -eq 0){throw 'Named PE export has no actual address'}
                    $forwarder=$null;$isData=$null
                    if($address -ge $directory.RelativeVirtualAddress -and [long]$address -lt [long]$directory.RelativeVirtualAddress+$directory.Size){
                        $forwarder=Read-PEAscii $reader ([int]$address)
                    }else{
                        $section=@($reader.PEHeaders.SectionHeaders|Where-Object{
                            $address -ge $_.VirtualAddress -and [long]$address -lt [long]$_.VirtualAddress+[Math]::Max($_.VirtualSize,$_.SizeOfRawData)
                        })
                        if($section.Count -ne 1){throw 'PE export address is outside one actual image section'}
                        $isData=([long]$section[0].SectionCharacteristics -band 0x20000000) -eq 0
                    }
                    $exports+=@{name=$name;ordinal=([long][BitConverter]::ToUInt32($header,16)+$ordinal);
                        rva=$address;is_data=$isData;forwarder=$forwarder}
                }
            }
        }
        return @{path=$full;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant();
            basename=[IO.Path]::GetFileName($full);machine=[string]$reader.PEHeaders.CoffHeader.Machine;
            is_dll=([int]$reader.PEHeaders.CoffHeader.Characteristics -band 0x2000) -ne 0;
            original_export_image_name=$imageName;exports=@($exports|Sort-Object name);
            runtime_acceptance=$false;coverage_authority=$false}
    }finally{if($null -ne $reader){$reader.Dispose()};$stream.Dispose()}
}

function Get-PEImageImports {
    param([Parameter(Mandatory)][string] $Path)
    $bytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path))
    $stream=[IO.MemoryStream]::new($bytes,$false);$reader=$null
    try{
        $reader=[System.Reflection.PortableExecutable.PEReader]::new($stream,[System.Reflection.PortableExecutable.PEStreamOptions]::LeaveOpen)
        $directory=$reader.PEHeaders.PEHeader.ImportTableDirectory;$imports=@()
        if($directory.RelativeVirtualAddress -eq 0){return ,$imports}
        $wide=$reader.PEHeaders.PEHeader.Magic -eq [System.Reflection.PortableExecutable.PEMagic]::PE32Plus
        $width=if($wide){8}else{4}
        $ordinalFlag=if($wide){[UInt64]::Parse('8000000000000000',[Globalization.NumberStyles]::HexNumber)}else{[UInt64]0x80000000L}
        $block=$reader.GetSectionData($directory.RelativeVirtualAddress)
        $limit=[Math]::Min($directory.Size,$block.Length);$terminated=$false
        for($offset=0;$offset+20 -le $limit;$offset+=20){
            [byte[]]$row=$block.GetContent($offset,20)
            if(@($row|Where-Object{$_ -ne 0}).Count -eq 0){$terminated=$true;break}
            $library=Read-PEAscii $reader ([BitConverter]::ToInt32($row,12))
            $thunk=[BitConverter]::ToInt32($row,0)
            if($thunk -eq 0){$thunk=[BitConverter]::ToInt32($row,16)}
            if($thunk -le 0){throw 'PE import table lacks a symbol thunk'}
            $symbols=$reader.GetSectionData($thunk);$names=@();$ended=$false
            for($index=0;$index+$width -le $symbols.Length;$index+=$width){
                [byte[]]$slot=$symbols.GetContent($index,$width)
                $value=if($wide){[BitConverter]::ToUInt64($slot,0)}else{[UInt64][BitConverter]::ToUInt32($slot,0)}
                if($value -eq 0){$ended=$true;break}
                if(($value -band $ordinalFlag) -ne 0){$names+=('#'+($value -band 0xffff))}
                else{
                    if($value -gt [int]::MaxValue-2){throw 'PE import name address is invalid'}
                    $names+=Read-PEAscii $reader ([int]$value+2)
                }
            }
            if(-not $ended){throw 'PE import symbol table is unterminated'}
            $imports+=@{library=$library;symbols=$names}
        }
        if(-not $terminated){throw 'PE import descriptor table is unterminated'}
        return ,$imports
    }finally{if($null -ne $reader){$reader.Dispose()};$stream.Dispose()}
}

function New-PEHostDefinition {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $ImagePath,
          [Parameter(Mandatory)][string] $OutputDirectory,
          [string[]] $ExportNames=@())
    $image=Get-PEImageExports -Path $ImagePath
    if($image.machine -cne 'Amd64' -or $image.basename -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]*$'){
        throw 'Host import library requires an actual AMD64 image with a safe basename'
    }
    $selected=@(if($ExportNames.Count){$image.exports|Where-Object{ $_.name -cin $ExportNames }}
        else{$image.exports|Where-Object name -CMatch '^lua(L_|_|open_)'})
    if($selected.Count -eq 0 -or ($ExportNames.Count -gt 0 -and $selected.Count -ne $ExportNames.Count)){
        throw 'Host image lacks its required actual public exports'
    }
    $output=[IO.Path]::GetFullPath($OutputDirectory)
    $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$output).Replace('\','/')
    if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $output)){
        throw 'Host import artifacts require a new disposable reports directory'
    }
    $lines=@(('LIBRARY '+$image.basename),'EXPORTS')
    foreach($export in $selected){
        if($export.name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $null -ne $export.forwarder -or $export.is_data -isnot [bool]){
            throw 'Host public export is not an owned function or data address'
        }
        $lines+=($export.name+$(if($export.is_data){' DATA'}else{''}))
    }
    [void][IO.Directory]::CreateDirectory($output)
    $definition=Join-Path $output 'host.def'
    [IO.File]::WriteAllText($definition,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    return @{schema_version=1;kind='actual-pe-image-definition';owner=$image;exports=$selected;
        definition=@{path=$definition;sha256=(Get-FileHash -LiteralPath $definition).Hash.ToLowerInvariant()};
        runtime_acceptance=$false;coverage_authority=$false}
}

function New-PEHostImportLibrary {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $ImagePath,
          [Parameter(Mandatory)][string] $DllTool,[Parameter(Mandatory)][string] $OutputDirectory,
          [string[]] $ExportNames=@())
    $result=New-PEHostDefinition -Root $Root -ImagePath $ImagePath -OutputDirectory $OutputDirectory -ExportNames $ExportNames
    $image=$result.owner;$output=Split-Path -Parent $result.definition.path;$library=Join-Path $output 'host.a'
    $tool=[IO.Path]::GetFullPath($DllTool)
    # GNU dlltool derives temporary filenames from -l. Relative short names
    # avoid its absolute-path expansion exceeding Windows path limits in a
    # managed worktree; the captured working directory binds their location.
    $process=Invoke-ConformanceProcess -Executable $tool -Arguments @('-m','i386:x86-64','-D',$image.basename,'-d','host.def','-l','host.a') `
        -Directory $output -OutputPrefix (Join-Path $output 'dlltool') -TimeoutSeconds 120 `
        -Environment @{PATH=((Split-Path -Parent $tool)+[IO.Path]::PathSeparator+$env:PATH)}
    if($process.exit_code -ne 0 -or $process.timed_out -or $process.stderr_bytes -ne 0 -or -not (Test-Path -LiteralPath $library)){
        throw 'Host import library tool failed or emitted an unreviewed diagnostic'
    }
    if((Get-FileHash -LiteralPath $ImagePath).Hash.ToLowerInvariant() -cne $image.sha256){throw 'Host image changed while its import library was built'}
    $result.kind='actual-pe-image-import-library'
    $result.import_library=@{path=$library;sha256=(Get-FileHash -LiteralPath $library).Hash.ToLowerInvariant()}
    $result.tool=@{path=$tool;sha256=(Get-FileHash -LiteralPath $tool).Hash.ToLowerInvariant()};$result.process=$process
    return $result
}

function Assert-PEModuleOwner {
    param([Parameter(Mandatory)][Collections.IDictionary] $OwnerImage,[Parameter(Mandatory)][string] $ModulePath,
          [Collections.IDictionary[]] $DependencyImages=@(),[switch] $RequireDirectImport,
          [string[]] $OwnedNames=@())
    if((Get-FileHash -LiteralPath $OwnerImage.path).Hash.ToLowerInvariant() -cne $OwnerImage.sha256 -or
        [IO.Path]::GetFileName($OwnerImage.path) -cne $OwnerImage.basename){throw 'Native owner image bytes or final basename changed'}
    # Never trust an export list supplied by a report. Reparse the content-
    # addressed image and each dependency before inspecting the import graph.
    $OwnerImage=Get-PEImageExports -Path $OwnerImage.path
    $exports=@{};foreach($export in $OwnerImage.exports){
        if(($OwnedNames.Count -gt 0 -and $export.name -cin $OwnedNames) -or
            ($OwnedNames.Count -eq 0 -and $export.name -cmatch '^lua(L_|_|open_)')){$exports[$export.name]=$true}
    }
    if($exports.Count -eq 0){throw 'Native owner image has no selected actual API exports'}
    $module=Get-PEImageExports -Path $ModulePath
    $dependencies=@{}
    foreach($dependency in $DependencyImages){
        if((Get-FileHash -LiteralPath $dependency.path).Hash.ToLowerInvariant() -cne $dependency.sha256){throw 'Native fixture dependency bytes changed'}
        $actual=Get-PEImageExports -Path $dependency.path;$key=$actual.basename.ToLowerInvariant()
        if($dependencies.ContainsKey($key)){throw 'Duplicate native fixture dependency basename'}
        $dependencies[$key]=$actual
    }
    $nodes=@{};$moduleKey=$module.basename.ToLowerInvariant()
    foreach($image in @($module)+@($dependencies.Values)){
        if(-not $image.is_dll -or $image.machine -cne $OwnerImage.machine){throw 'Native module is not a DLL for the selected owner machine'}
        foreach($export in $image.exports){if($exports.ContainsKey($export.name)){throw 'Native fixture defines an interpreter API instead of importing its owner'}}
        $imports=Get-PEImageImports -Path $image.path;$used=@();$transitive=@();$edges=@()
        foreach($import in $imports){foreach($symbol in $import.symbols){
            $key=$import.library.ToLowerInvariant()
            if($exports.ContainsKey($symbol)){
                if($import.library -ine $OwnerImage.basename){throw 'Native fixture imports an interpreter API from another image'}
                $used+=$symbol
            }elseif($dependencies.ContainsKey($key)){
                if(@($dependencies[$key].exports|Where-Object name -CEQ $symbol).Count -ne 1){throw 'Native fixture imports a missing dependency symbol'}
                $transitive+=$symbol;$edges+=$key
            }elseif($symbol -cmatch '^lua(L_|_|open_)'){
                throw 'Native fixture imports an API absent from its actual owner or named dependencies'
            }
        }}
        $nodes[$image.basename.ToLowerInvariant()]=@{imports=$imports;used=$used;transitive=$transitive;edges=@($edges|Sort-Object -Unique)}
    }
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($moduleKey)
    $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$reachesOwner=$false
    while($pending.Count){
        $key=$pending.Pop();if(-not $visited.Add($key)){continue}
        if($nodes[$key].used.Count){$reachesOwner=$true}
        foreach($edge in $nodes[$key].edges){$pending.Push($edge)}
    }
    $node=$nodes[$moduleKey]
    if(($RequireDirectImport -and $node.used.Count -eq 0) -or -not $reachesOwner){
        throw 'Native fixture has no actual direct or reviewed transitive owner imports'
    }
    return @{owner_sha256=$OwnerImage.sha256;owner_basename=$OwnerImage.basename;module_sha256=$module.sha256;
        imported_owner_symbols=@($node.used|Sort-Object -Unique);imported_dependency_symbols=@($node.transitive|Sort-Object -Unique);
        imports=$node.imports;runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function Get-PEImageExports, Get-PEImageImports, New-PEHostDefinition, New-PEHostImportLibrary,
    Assert-PEModuleOwner
