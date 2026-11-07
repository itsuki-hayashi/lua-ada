Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')

function Get-FileConsumerTextInput {
    # This is the actual shared-source driver's input, with a Lua \0 escape,
    # not a host NUL in its source. The driver asserts the resulting string's
    # thirteen bytes, three results, source metadata and balanced close.
    return ,[Text.Encoding]::ASCII.GetBytes("return 17, 'input\0payload', true`n")
}

function Invoke-FileConsumerIO {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $Context,
          [Parameter(Mandatory)][string] $AdaExecutable,[Parameter(Mandatory)][string] $ReferenceExecutable,
          [Parameter(Mandatory)][string] $RecordDirectory,[hashtable] $Environment=@{})
    $directory=[IO.Path]::GetFullPath($RecordDirectory)
    if(Test-Path -LiteralPath $directory){throw 'File stdin observation directory must be new'}
    [void][IO.Directory]::CreateDirectory($directory)
    $drivers=@{}
    foreach($implementation in @('Ada','ReferenceC')){
        $source=if($implementation -ceq 'Ada'){$AdaExecutable}else{$ReferenceExecutable}
        $snapshot=Join-Path $directory ($implementation+'/host/'+[IO.Path]::GetFileName($source))
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $snapshot))
        [IO.File]::Copy($source,$snapshot,$false)
        if(-not $IsWindows){[IO.File]::SetUnixFileMode($snapshot,[IO.File]::GetUnixFileMode($source))}
        $hash=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()
        if((Get-FileHash -LiteralPath $snapshot).Hash.ToLowerInvariant() -cne $hash){throw 'Freezing the actual file consumer changed its bytes'}
        $drivers[$implementation]=@{source_path=[IO.Path]::GetFullPath($source);path=$snapshot;sha256=$hash;bytes=(Get-Item $snapshot).Length}
    }
    $inputPath=Join-Path $directory 'stdin-source.lua'
    [IO.File]::WriteAllBytes($inputPath,(Get-FileConsumerTextInput))
    $text=@{path=$inputPath;sha256=(Get-FileHash $inputPath).Hash.ToLowerInvariant();bytes=(Get-Item $inputPath).Length}
    $producers=@();$consumers=@()
    foreach($implementation in @('Ada','ReferenceC')){
        $process=Invoke-ConformanceProcess -Executable $drivers[$implementation].path -Arguments @('--stdin-text') `
            -Directory $Root -OutputPrefix (Join-Path $directory ($implementation+'-stdin-text')) `
            -TimeoutSeconds 60 -StandardInputPath $inputPath -InputLimitBytes 1048576 -Environment $Environment
        $consumers+=@{implementation=$implementation;input_kind='text';producer=$null;process=$process}
    }
    foreach($implementation in @('Ada','ReferenceC')){
        # Each runtime produces its own real Lua binary chunk. Never decode
        # its stdout or substitute a canned signature/completion record.
        $process=Invoke-ConformanceProcess -Executable $drivers[$implementation].path -Arguments @('--emit-stdin-chunk') `
            -Directory $Root -OutputPrefix (Join-Path $directory ($implementation+'-emit-stdin-chunk')) `
            -TimeoutSeconds 60 -Environment $Environment
        $producers+=@{implementation=$implementation;process=$process}
        foreach($consumer in @('Ada','ReferenceC')){
            $read=Invoke-ConformanceProcess -Executable $drivers[$consumer].path -Arguments @('--stdin-binary') `
                -Directory $Root -OutputPrefix (Join-Path $directory ($implementation+'-to-'+$consumer+'-stdin-binary')) `
                -TimeoutSeconds 60 -StandardInputPath $process.stdout_path -InputLimitBytes 1048576 -Environment $Environment
            $consumers+=@{implementation=$consumer;input_kind='binary';producer=$implementation;process=$read}
        }
    }
    $report=@{schema_version=1;kind='public-file-stdin-observations';context=$Context;source_root=[IO.Path]::GetFullPath($Root);synthetic_fixture=$false;
        drivers=$drivers;text_input=$text;producers=$producers;consumers=$consumers;runtime_acceptance=$false;coverage_authority=$false}
    [IO.File]::WriteAllText((Join-Path $directory 'observations.json'),(ConvertTo-Json $report -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
    return $report
}

function Test-FileConsumerIO {
    param([Parameter(Mandatory)][Collections.IDictionary] $Observation,[Parameter(Mandatory)][string] $Context,
          [Parameter(Mandatory)][Collections.IDictionary] $DriverHashes,[Parameter(Mandatory)][scriptblock] $ResolveCapture,
          [switch] $AllowSynthetic)
    # This replay supplies no semantic approval or target acceptance. Its
    # final caller also requires the source-reviewed C driver, ordinary
    # twenty-one-case counterpart process and exact frozen context image.
    if($Observation.schema_version -ne 1 -or $Observation.kind -cne 'public-file-stdin-observations' -or
        $Observation.context -cne $Context -or [string]::IsNullOrWhiteSpace([string]$Observation.source_root) -or
        $Observation.synthetic_fixture -isnot [bool] -or
        ($Observation.synthetic_fixture -and -not $AllowSynthetic) -or
        $Observation.runtime_acceptance -isnot [bool] -or $Observation.runtime_acceptance -or
        $Observation.coverage_authority -isnot [bool] -or $Observation.coverage_authority -or
        $Observation.drivers -isnot [Collections.IDictionary] -or $Observation.drivers.Count -ne 2){
        throw 'File stdin observations lack their actual matching context and false authority'
    }
    foreach($implementation in @('Ada','ReferenceC')){
        $driver=$Observation.drivers[$implementation]
        if($DriverHashes[$implementation] -cnotmatch '^[0-9a-f]{64}$' -or $driver.sha256 -cne $DriverHashes[$implementation]){
            throw 'File stdin driver differs from the actual ordinary file consumer'
        }
        $path=& $ResolveCapture $driver.path $driver.sha256
        if(-not $driver.path.Replace('\','/').StartsWith($Observation.source_root.Replace('\','/').TrimEnd('/')+'/reports/',[StringComparison]::Ordinal)){
            throw 'File stdin frozen driver is outside the exact source reports root'
        }
        if(($driver.bytes -isnot [int] -and $driver.bytes -isnot [long]) -or
            (Get-Item $path).Length -ne $driver.bytes -or $driver.bytes -le 0){throw 'File stdin frozen driver extent differs'}
    }
    $textPath=& $ResolveCapture $Observation.text_input.path $Observation.text_input.sha256
    $expectedText=Get-FileConsumerTextInput
    if(($Observation.text_input.bytes -isnot [int] -and $Observation.text_input.bytes -isnot [long]) -or
        (Get-Item $textPath).Length -ne $Observation.text_input.bytes -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($textPath)) -cne [Convert]::ToBase64String($expectedText)){
        throw 'File stdin source text is not the exact shared-source input'
    }
    function Check-Process($Process,[string]$Implementation,[string]$Argument){
        if(($Process.exit_code -isnot [int] -and $Process.exit_code -isnot [long]) -or $Process.exit_code -ne 0 -or
            $Process.timed_out -isnot [bool] -or $Process.timed_out -or
            $Process.capture_exceeded -isnot [bool] -or $Process.capture_exceeded -or
            $Process.pipe_drain_failed -isnot [bool] -or $Process.pipe_drain_failed -or
            $Process.process_tree_kill_error -or $Process.abnormal_exit_kind -or $Process.arguments -isnot [Array] -or
            ($Process.arguments -join '|') -cne $Argument -or $Process.executable_sha256 -cne $DriverHashes[$Implementation] -or
            $Process.working_directory.Replace('\','/') -cne $Observation.source_root.Replace('\','/') -or
            $Process.executable.Replace('\','/') -cne $Observation.drivers[$Implementation].path.Replace('\','/')){
            throw 'File stdin actual process driver arguments or completion differs'
        }
        $paths=@{}
        foreach($stream in @('stdout','stderr')){
            $paths[$stream]=& $ResolveCapture $Process["${stream}_path"] $Process["${stream}_sha256"]
            if(($Process["${stream}_bytes"] -isnot [int] -and $Process["${stream}_bytes"] -isnot [long]) -or
                (Get-Item $paths[$stream]).Length -ne $Process["${stream}_bytes"]){throw 'File stdin raw stream extent differs'}
        }
        if((Get-Item $paths.stderr).Length -ne 0){throw 'File stdin child has unreviewed stderr'}
        return $paths
    }
    if($Observation.producers -isnot [Array] -or $Observation.producers.Count -ne 2 -or
        $Observation.consumers -isnot [Array] -or $Observation.consumers.Count -ne 6){throw 'File stdin requires two dump producers and all six consumers'}
    $producers=@{}
    foreach($implementation in @('Ada','ReferenceC')){
        $matches=@($Observation.producers|Where-Object implementation -CEQ $implementation)
        if($matches.Count -ne 1){throw 'File stdin dump producer is missing or duplicated'}
        $process=$matches[0].process;$paths=Check-Process $process $implementation '--emit-stdin-chunk'
        if($process.Contains('standard_input')){throw 'File stdin dump producer acquired an unreviewed input'}
        $bytes=[IO.File]::ReadAllBytes($paths.stdout)
        if($bytes.Length -lt 5 -or [Convert]::ToBase64String($bytes[0..3]) -cne 'G0x1YQ=='){
            throw 'File stdin producer did not emit an actual Lua binary chunk'
        }
        $producers[$implementation]=$process
    }
    $outputs=@{};$seen=@{};$pairedHash=$null
    foreach($consumer in $Observation.consumers){
        $implementation=$consumer.implementation;$kind=$consumer.input_kind;$producer=$consumer.producer
        if($implementation -cnotin @('Ada','ReferenceC') -or $kind -cnotin @('text','binary') -or
            ($kind -ceq 'text' -and $null -ne $producer) -or ($kind -ceq 'binary' -and $producer -cnotin @('Ada','ReferenceC'))){
            throw 'File stdin consumer identifies an unreviewed input role'
        }
        $key=$implementation+'/'+$kind+'/'+$producer
        if($seen.ContainsKey($key)){throw 'File stdin consumer is duplicated'};$seen[$key]=$true
        $process=$consumer.process;$paths=Check-Process $process $implementation ('--stdin-'+$kind)
        if(-not $process.Contains('standard_input') -or $process.standard_input -isnot [Collections.IDictionary]){
            throw 'File stdin consumer lacks its actual raw input snapshot'
        }
        $inputRecord=$process.standard_input
        $expected=if($kind -ceq 'text'){$Observation.text_input}else{@{path=$producers[$producer].stdout_path;sha256=$producers[$producer].stdout_sha256;bytes=$producers[$producer].stdout_bytes}}
        if($inputRecord.write_completed -isnot [bool] -or -not $inputRecord.write_completed -or
            $inputRecord.eof_sent -isnot [bool] -or -not $inputRecord.eof_sent -or
            ($inputRecord.bytes -isnot [int] -and $inputRecord.bytes -isnot [long]) -or
            ($inputRecord.byte_limit -isnot [int] -and $inputRecord.byte_limit -isnot [long]) -or
            $inputRecord.byte_limit -ne 1048576 -or $inputRecord.sha256 -cne $expected.sha256 -or
            $inputRecord.bytes -ne $expected.bytes -or $inputRecord.source_path.Replace('\','/') -cne $expected.path.Replace('\','/')){
            throw 'File stdin consumer did not receive its exact selected producer through completed raw stdin'
        }
        $snapshot=& $ResolveCapture $inputRecord.path $inputRecord.sha256
        if((Get-Item $snapshot).Length -ne $inputRecord.bytes){throw 'File stdin consumed snapshot extent differs'}
        $stdout=[IO.File]::ReadAllText($paths.stdout)
        if($stdout.Replace("`r`n","`n") -cne "PASS: public loadfile stdin`n"){throw 'File stdin actual return stack source and close completion protocol differs'}
        if($null -eq $pairedHash){$pairedHash=$process.stdout_sha256}
        elseif($process.stdout_sha256 -cne $pairedHash){throw 'File stdin actual C/Ada counterpart bytes differ'}
        # These two named mappings refer to actual Ada children. The entire
        # six-child matrix above remains mandatory even if a global API row
        # chooses only one of these source-linked witnesses.
        if($implementation -ceq 'Ada' -and $kind -ceq 'text'){$outputs['loadfile-stdin-text-api']=@{text=$stdout;hash=$process.stdout_sha256}}
        if($implementation -ceq 'Ada' -and $kind -ceq 'binary' -and $producer -ceq 'ReferenceC'){$outputs['loadfile-stdin-binary-c-api']=@{text=$stdout;hash=$process.stdout_sha256}}
    }
    foreach($implementation in @('Ada','ReferenceC')){
        if(-not $seen.ContainsKey($implementation+'/text/')){throw 'File stdin text counterpart was omitted'}
        foreach($producer in @('Ada','ReferenceC')){if(-not $seen.ContainsKey($implementation+'/binary/'+$producer)){throw 'File stdin binary cross-runtime producer/consumer path was omitted'}}
    }
    return @{named_outputs=$outputs;runtime_acceptance=$false;coverage_authority=$false}
}

function Assert-FileConsumerIOImageBinding {
    param([Collections.IDictionary] $Image,[Collections.IDictionary] $Observation)
    $artifacts=@($Observation.text_input)+@($Observation.drivers.Values)
    foreach($entry in @($Observation.producers)+@($Observation.consumers)){
        foreach($stream in @('stdout','stderr')){$artifacts+=@{path=$entry.process["${stream}_path"];sha256=$entry.process["${stream}_sha256"]}}
        if($entry.process.Contains('standard_input')){$artifacts+=$entry.process.standard_input}
    }
    foreach($artifact in $artifacts){
        $original=$artifact.path.Replace('\','/');$offset=$original.LastIndexOf('/reports/',[StringComparison]::Ordinal)
        if($offset -lt 0){throw 'File stdin artifact is outside the captured reports tree'}
        $relative=$original.Substring($offset+1)
        if(@($Image.files|Where-Object{ $_.path -ceq $relative -and $_.sha256 -ceq $artifact.sha256 }).Count -ne 1){
            throw 'File stdin actual driver input producer or consumer capture is not part of the exact frozen image'
        }
    }
}

Export-ModuleMember -Function Invoke-FileConsumerIO, Test-FileConsumerIO, Assert-FileConsumerIOImageBinding
