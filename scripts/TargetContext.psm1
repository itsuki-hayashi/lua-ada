Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TargetContextPlan {
    param([Parameter(Mandatory)][string] $Root)
    $suite = Get-Content -LiteralPath (Join-Path $Root 'tests/conformance/suite.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 32
    $files = @($suite.files | Where-Object role -CEQ primary | ForEach-Object path)
    if ($files.Count -ne 30 -or @($suite.acceptance_contexts).Count -ne 26 -or
        @($files | Sort-Object -Unique).Count -ne 30) { throw 'Target plan requires the pinned 30-primary/26-context suite' }
    $contexts = @(); $partitions = @(); $seen = @{}
    foreach ($context in $suite.acceptance_contexts) {
        if ($seen.ContainsKey($context)) { throw 'Duplicate target context' }
        $seen[$context] = $true
        $parts = $context.Split('/')
        if ($parts.Count -ne 4 -or $parts[0] -cnotin @('default','upstream-test') -or
            $parts[1] -cnotin @('windows','linux','macos') -or
            $parts[2] -cnotin @('development','validation','release') -or
            $parts[3] -cnotin @('static','shared','static-pic') -or
            ($parts[0] -ceq 'upstream-test' -and $parts[2] -cne 'validation') -or
            ($parts[3] -ceq 'static-pic' -and ($parts[1] -cne 'windows' -or $parts[2] -cne 'validation'))) {
            throw 'Unsupported target context tuple'
        }
        $id = $context.Replace('/','-')
        $os = switch -CaseSensitive ($parts[1]) { 'windows' {'windows-latest'} 'linux' {'ubuntu-latest'} 'macos' {'macos-latest'} }
        $build = @{context=$context;id=$id;os=$os;configuration=$parts[0];platform=$parts[1];profile=$parts[2];
            library_type=$(if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]})}
        $contexts += $build
        for ($shard=0;$shard -lt 3;$shard++) {
            $partitions += @{context=$context;id=$id;os=$os;partition=('files-' + ($shard + 1));
                operation='file';files=@($files[($shard * 10)..($shard * 10 + 9)]);
                constructs_supplement=($files[($shard * 10)..($shard * 10 + 9)] -ccontains 'constructs.lua')}
        }
        foreach ($operation in @('aggregate','heavy')) {
            $partitions += @{context=$context;id=$id;os=$os;partition=$operation;operation=$operation;files=@();constructs_supplement=$false}
        }
    }
    return @{schema_version=1;target='remaining-upstream-compatibility';reference_revision=$suite.reference_revision;
        contexts=$contexts;partitions=$partitions;runtime_acceptance=$false;coverage_authority=$false}
}

function Resolve-TargetImagePath {
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative.Contains('\') -or $Relative.Contains(':')) { throw 'Invalid target image relative path' }
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $full = [IO.Path]::GetFullPath((Join-Path $fullRoot $Relative))
    $canonical = [IO.Path]::GetRelativePath($fullRoot,$full).Replace('\','/')
    if ($canonical -cne $Relative -or $canonical -eq '..' -or $canonical.StartsWith('../',[StringComparison]::Ordinal)) {
        throw 'Target image path escapes or aliases its root'
    }
    return $full
}

function Test-TargetImageDestination {
    param([Parameter(Mandatory)][string] $Path)
    # A downloaded artifact may populate only generated binary/library outputs
    # and retained observations. It must never overwrite first-party/reference
    # source, manifests, configuration inputs, or toolchain installations.
    if ($Path -cnotmatch '^(?:lib/|tests/bin/|cli/bin/|build/(?:conformance/|c-api/)|reports/(?:core-image/|target-builds/|target-support/))' -or
        [IO.Path]::GetExtension($Path) -cin @('.adb','.ads','.c','.h','.lua','.ps1','.psm1','.gpr','.toml','.md')) {
        throw 'Target image destination is not an allowed generated artifact'
    }
}

function Assert-TargetContextImage {
    param([Parameter(Mandatory)][string] $ImageDirectory,
          [Parameter(Mandatory)][string] $Context,
          [Parameter(Mandatory)][string] $Revision,
          [switch] $RequireActual,
          [string] $RestoredRoot = '')
    $manifestPath = Join-Path $ImageDirectory 'image.json'
    $image = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 48
    if ($image.schema_version -ne 1 -or $image.kind -cne 'immutable-target-context-image' -or
        $image.target -cne 'remaining-upstream-compatibility' -or $image.context -cne $Context -or
        $image.revision -cne $Revision -or $image.revision -cnotmatch '^[0-9a-f]{40}$' -or
        $image.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $image.synthetic_fixture -isnot [bool] -or $image.runtime_acceptance -isnot [bool] -or $image.runtime_acceptance -or
        $image.coverage_authority -isnot [bool] -or $image.coverage_authority -or
        $image.launcher_basename -cne $(if($Context.Split('/')[1] -ceq 'windows'){'lua.exe'}else{'lua'})) {
        throw 'Immutable target image revision, context or launcher identity differs'
    }
    if ($RequireActual -and ($image.synthetic_fixture -or $image.repository_dirty -ne $false)) {
        throw 'Immutable target image requires actual clean build evidence'
    }
    $seen = [Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $image.files) {
        $null = Test-TargetImageDestination -Path $file.path
        if ($seen.ContainsKey($file.path) -or $file.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            ($file.bytes -isnot [int] -and $file.bytes -isnot [long]) -or $file.bytes -lt 0 -or
            ($file.unix_mode -isnot [int] -and $file.unix_mode -isnot [long]) -or $file.unix_mode -lt 0 -or $file.unix_mode -gt 4095) {
            throw 'Immutable target image file identity missing or duplicated'
        }
        $seen[$file.path] = $true
        $fileRoot = if ($RestoredRoot -ne '') { $RestoredRoot } else { Join-Path $ImageDirectory 'payload' }
        $path = Resolve-TargetImagePath -Root $fileRoot -Relative $file.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-Item -LiteralPath $path).Length -ne $file.bytes -or
            (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $file.sha256) {
            throw "Immutable target image artifact bytes differ: $($file.path)"
        }
        # Artifact download transports bytes; GitHub does not retain Unix mode
        # bits. Restore applies the frozen mode before verifying the live tree.
        if ($RestoredRoot -ne '' -and -not $IsWindows -and [int][IO.File]::GetUnixFileMode($path) -ne $file.unix_mode) {
            throw 'Immutable target image executable mode differs'
        }
    }
    if ($seen.Count -eq 0) { throw 'Immutable target image is empty' }
    foreach ($kind in @('ada_launcher','c_oracle')) {
        $path = $image.paths[$kind]
        if (-not $seen.ContainsKey($path) -or @($image.files | Where-Object { $_.path -ceq $path -and $_.bytes -gt 0 }).Count -ne 1) {
            throw 'Immutable target image omits its interpreter'
        }
    }
    foreach ($kind in @('ada_runtime','c_runtime')) {
        $directory = $image.paths[$kind]
        [void](Resolve-TargetImagePath -Root (Join-Path $ImageDirectory 'payload') -Relative $directory)
        if (@($image.files | Where-Object { $_.path.StartsWith($directory + '/',[StringComparison]::Ordinal) }).Count -eq 0) {
            throw 'Immutable target image omits its runtime library'
        }
    }
    return @{manifest=$image;manifest_path=$manifestPath;sha256=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant();
        context=$Context;revision=$Revision;runtime_acceptance=$false;coverage_authority=$false}
}

function New-TargetContextImage {
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $Context,
          [Parameter(Mandatory)][string] $OutputDirectory,
          [Parameter(Mandatory)][Collections.IDictionary] $Paths,
          [Parameter(Mandatory)][string[]] $Directories,
          [Parameter(Mandatory)][string[]] $WitnessReports)
    $plan = Get-TargetContextPlan -Root $Root
    if (@($plan.contexts | Where-Object context -CEQ $Context).Count -ne 1) { throw 'Image context is not scheduled' }
    $head = (& git -C $Root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify target context revision' }
    $dirty = @(& git -C $Root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Target image must be frozen from a clean source checkout' }
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $output) { throw 'Target image output directory must be new' }
    $payload = Join-Path $output 'payload'
    [void][IO.Directory]::CreateDirectory($payload)
    $files = @(); $seen = @{}
    $selectedDirectories = @($Directories) + @($WitnessReports | ForEach-Object {
        $full = if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $Root $_ }
        [IO.Path]::GetRelativePath($Root,(Split-Path -Parent ([IO.Path]::GetFullPath($full)))).Replace('\','/')
    })
    foreach ($directory in ($selectedDirectories | Sort-Object -Unique)) {
        $sourceDirectory = Resolve-TargetImagePath -Root $Root -Relative $directory
        foreach ($source in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse | Sort-Object FullName) {
            $relative = [IO.Path]::GetRelativePath($Root,$source.FullName).Replace('\','/')
            Test-TargetImageDestination -Path $relative
            if ($seen.ContainsKey($relative)) { continue }
            $seen[$relative] = $true
            $destination = Resolve-TargetImagePath -Root $payload -Relative $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
            [IO.File]::Copy($source.FullName,$destination)
            $mode = if ($IsWindows) { 0 } else { [int][IO.File]::GetUnixFileMode($source.FullName) }
            if (-not $IsWindows) { [IO.File]::SetUnixFileMode($destination,[IO.UnixFileMode]$mode) }
            $hash = (Get-FileHash -LiteralPath $source.FullName).Hash.ToLowerInvariant()
            if ((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -cne $hash) { throw 'Freezing context image changed bytes' }
            $files += @{path=$relative;sha256=$hash;bytes=$source.Length;unix_mode=$mode}
        }
    }
    $witnesses = @($WitnessReports | ForEach-Object {
        $full = if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $Root $_ }
        $relative = [IO.Path]::GetRelativePath($Root,[IO.Path]::GetFullPath($full)).Replace('\','/')
        if (-not $seen.ContainsKey($relative)) { throw 'Build witness report is outside the captured image' }
        @{path=$relative;sha256=(Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant()}
    })
    $manifest = @{schema_version=1;kind='immutable-target-context-image';target=$plan.target;context=$Context;revision=$head;
        reference_revision=$plan.reference_revision;repository_dirty=$false;synthetic_fixture=$false;paths=$Paths;
        launcher_basename=$(if($Context.Split('/')[1] -ceq 'windows'){'lua.exe'}else{'lua'});
        files=$files;build_witnesses=$witnesses;runtime_acceptance=$false;coverage_authority=$false}
    [IO.File]::WriteAllText((Join-Path $output 'image.json'),
        (ConvertTo-Json -InputObject $manifest -Depth 48).Replace("`r`n","`n") + "`n",[Text.UTF8Encoding]::new($false))
    return Assert-TargetContextImage -ImageDirectory $output -Context $Context -Revision $head -RequireActual
}

function Restore-TargetContextImage {
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $ImageDirectory,
          [Parameter(Mandatory)][string] $Context, [Parameter(Mandatory)][string] $Revision)
    $identity = Assert-TargetContextImage -ImageDirectory $ImageDirectory -Context $Context -Revision $Revision -RequireActual
    foreach ($file in $identity.manifest.files) {
        $source = Resolve-TargetImagePath -Root (Join-Path $ImageDirectory 'payload') -Relative $file.path
        $destination = Resolve-TargetImagePath -Root $Root -Relative $file.path
        # Reject an existing redirected directory/file before a write. Artifact
        # restoration must stay inside the generated outputs of this checkout.
        $cursor = $destination
        $rootPath = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
        while ($cursor -cne $rootPath) {
            if ((Test-Path -LiteralPath $cursor) -and
                ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Target image restore destination contains a reparse point'
            }
            $cursor = Split-Path -Parent $cursor
        }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy($source,$destination,$true)
        if (-not $IsWindows) { [IO.File]::SetUnixFileMode($destination,[IO.UnixFileMode]$file.unix_mode) }
    }
    return Assert-TargetContextImage -ImageDirectory $ImageDirectory -Context $Context -Revision $Revision -RequireActual -RestoredRoot $Root
}

Export-ModuleMember -Function Get-TargetContextPlan, Resolve-TargetImagePath,
    Assert-TargetContextImage, New-TargetContextImage, Restore-TargetContextImage
