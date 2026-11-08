param([Parameter(Mandatory)][string]$Report)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConfiguredFixtureEvidence.psm1') -Force
$baseline=Get-Content -LiteralPath $Report -Raw|ConvertFrom-Json -AsHashtable -Depth 48
$interpreter=@($baseline.runtimes|Where-Object role -CEQ Ada)[0].executable
$temporary=Join-Path $root ('reports/configured-fixture-regressions/'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:cases=0
function Case($Name,[scriptblock]$Change,$Expected='',[scriptblock]$ResolveFile=$null){
    $r=ConvertTo-Json -InputObject $baseline -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48
    & $Change $r
    $failure=$null
    try{$null=Assert-ConfiguredFixtureReport -Root $root -Report $r -Configuration $baseline.configuration -Interpreter $interpreter -ResolveFile $ResolveFile}catch{$failure=$_.Exception.Message}
    if(($Expected -eq '' -and $null -ne $failure) -or ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "Configured fixture regression $Name failed: $failure; expected $Expected"}
    $script:cases++;Write-Output "CONFIGURED FIXTURE PASS: $Name"
}
function Replace-Capture($Process,$Stream,$Text){
    $path=Join-Path $temporary ([guid]::NewGuid().ToString('N')+'.'+$Stream)
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
    $Process[$Stream+'_path']=$path;$Process[$Stream+'_sha256']=(Get-FileHash $path).Hash.ToLowerInvariant()
    $Process[$Stream+'_bytes']=(Get-Item $path).Length
}
function Row($r,$Operation){return @($r.processes|Where-Object{$_.role -ceq 'Ada' -and $_.operation -ceq $Operation})[0]}
Case 'actual complete paired captures reconcile without granting acceptance' {}
Case 'configured fixture process cannot disappear' {param($r)$r.processes=@($r.processes|Select-Object -Skip 1)} 'process set is incomplete'
Case 'duplicate configuration cannot replace a mandatory actual operation' {param($r)$r.processes[1]=$r.processes[0]} 'actual process is missing or duplicated'
Case 'generic script-only arguments cannot omit the measured stack setup' {param($r)(Row $r portal).process.arguments=@('tests/lua/coroutine_result_portal.lua')} 'explicit setup'
Case 'wrong selected stack limit rejects even unchanged matching output' {param($r)(Row $r portal).process.arguments[1]='_PORTAL_LIMIT=37'} 'explicit setup'
Case 'another executable cannot reuse an Ada observation receipt' {param($r)$r.runtimes[1].executable=$r.runtimes[0].executable} 'another Ada interpreter|observed file identity'
Case 'executable hash drift rejects old observations' {param($r)$r.runtimes[1].executable_sha256='0'*64} 'observed file identity'
Case 'runtime library drift rejects old observations' {param($r)$r.runtimes[1].library_files[0].sha256='0'*64} 'observed file identity'
Case 'source changes require new configured observations' {param($r)$r.source_bindings[0].sha256='0'*64} 'source identity'
Case 'complete first-party fixture audit cannot be relabelled' {param($r)$r.fixture_selection_audit.entries[0].selection='omitted'} 'fixture selection audit'
Case 'complete first-party fixture audit cannot lose a source' {param($r)$r.fixture_selection_audit.entries=@($r.fixture_selection_audit.entries|Select-Object -Skip 1)} 'fixture selection audit'
Case 'fixture audit hash cannot be fabricated' {param($r)$r.fixture_selection_audit_sha256='0'*64} 'fixture selection audit'
Case 'configuration names cannot be relabelled after execution' {param($r)$r.configuration='wrong'} 'kind/configuration'
Case 'configuration probe must identify an actual Ada implementation' {param($r)
    $p=(Row $r configuration).process;$v=Get-Content $p.stdout_path -Raw|ConvertFrom-Json -AsHashtable
    $v.implementation='C Lua';Replace-Capture $p stdout (ConvertTo-Json -InputObject $v)
} 'actual runtime/test adapter'
Case 'successful completion alone cannot replace the explicit setup marker' {param($r)
    Replace-Capture (Row $r portal).process stdout "PASS: coroutine result capacity and recipients`n"
} 'complete ordered protocol'
Case 'rehashed stderr cannot become a passing empty-error observation' {param($r)Replace-Capture (Row $r portal).process stderr 'failure'} 'complete ordered protocol|raw capture|process failed'
Case 'labelled synthetic observations cannot discharge this actual campaign' {param($r)$r.synthetic_fixture=$true} 'observation authority'
Case 'component observations cannot claim whole runtime acceptance' {param($r)$r.runtime_acceptance=$true} 'observation authority'
Case 'public optimizer semantics need actual paired source observations in every configuration' {param($r)
    $r.processes=@($r.processes|Where-Object operation -CNE code-public-semantics)
} 'process set is incomplete'
Case 'ordinary length campaigns cannot omit the empty-result selector' {param($r)
    $r.processes=@($r.processes|Where-Object operation -CNE length-result-empty)
} 'process set is incomplete'
Case 'ordinary length first-result receipt cannot substitute the failure selector' {param($r)
    (Row $r length-result-first).process.arguments[3]='failure'
} 'explicit setup or source'
Case 'nextvar public invocation must retain its exact one-integer result check' {param($r)
    $p=(Row $r nextvar-storage-public).process
    $p.arguments[1]=$p.arguments[1].Replace('r.n==1','r.n>=0')
} 'explicit setup or source'
Case 'nextvar complete source mode cannot acquire a one-case filter' {param($r)
    $p=(Row $r nextvar-storage-public).process
    $p.arguments[1]=$p.arguments[1].Replace("('public')","('public','Library')")
} 'explicit setup or source'
Case 'iterator instruction counts require the actual C graph producer' {param($r)
    $r.processes=@($r.processes|Where-Object operation -CNE produce-debug-iterator-counts)
} 'process set is incomplete'
Case 'iterator graph producer must load the exact text source' {param($r)
    @($r.processes|Where-Object operation -CEQ produce-debug-iterator-counts)[0].process.arguments[1]="io.write('replacement graph')"
} 'native chunk producer source or arguments'
Case 'iterator execution cannot return to separate source compilation' {param($r)
    (Row $r debug-iterator-counts).process.arguments[2]=Join-Path $baseline.repository_root 'tests/lua/debug_iterator_counts.lua'
} 'explicit setup or source'
Case 'iterator consumers must bind the same actual producer bytes' {param($r)
    (Row $r debug-iterator-counts).input_chunk.sha256='0'*64
} 'native chunk producer/input identity'
Case 'iterator consumers cannot relabel a different chunk path' {param($r)
    (Row $r debug-iterator-counts).input_chunk.path='other-graph.luac'
} 'native chunk producer/input identity'
Case 'tampered native graph identity cannot borrow the producer process' {param($r)
    @($r.processes|Where-Object operation -CEQ produce-debug-iterator-counts)[0].output_chunk.sha256='0'*64
    foreach($row in @($r.processes|Where-Object operation -CEQ debug-iterator-counts)){$row.input_chunk.sha256='0'*64}
} 'observed file identity'
Case 'iterator producer requires an actual binary output graph' {param($r)
    $producer=@($r.processes|Where-Object operation -CEQ produce-debug-iterator-counts)[0]
    $script:originalChunkPath=$producer.output_chunk.path
    $script:mutatedChunkPath=Join-Path $temporary 'not-binary.luac'
    [IO.File]::WriteAllText($script:mutatedChunkPath,('text instead of actual binary graph'.PadRight(70)),[Text.UTF8Encoding]::new($false))
    # ResolveFile maps the declared output to mutated bytes without changing
    # its expected argv/path. This cannot forge an actual observation.
    $producer.output_chunk.sha256=(Get-FileHash $script:mutatedChunkPath).Hash.ToLowerInvariant()
    $producer.output_chunk.bytes=(Get-Item $script:mutatedChunkPath).Length
    foreach($row in @($r.processes|Where-Object operation -CEQ debug-iterator-counts)){
        $row.input_chunk.sha256=$producer.output_chunk.sha256;$row.input_chunk.bytes=$producer.output_chunk.bytes
    }
} 'did not emit an actual Lua binary graph' {param($path,$hash)
    if($path -ceq $script:originalChunkPath){return $script:mutatedChunkPath};return $path
}
if($baseline.configuration -ceq 'upstream-test'){
    Case 'T-absent configuration cannot certify a real instrumented fixture' {param($r)
        $p=(Row $r configuration).process;$v=Get-Content $p.stdout_path -Raw|ConvertFrom-Json -AsHashtable
        $v.test_adapter=$false;Replace-Capture $p stdout (ConvertTo-Json -InputObject $v)
    } 'actual runtime/test adapter'
    Case 'four completion lines cannot replace the real T setup witness' {param($r)
        $p=(Row $r stack-inspection).process
        Replace-Capture $p stdout ((1..4|ForEach-Object{"PASS: stack inspection $_"})-join "`n")
    } 'complete ordered protocol'
    Case 'a skipped stack inspection case is not an instrumented pass' {param($r)
        $p=(Row $r stack-inspection).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS: stack inspection 4`n",''))
    } 'complete ordered protocol'
    Case 'scalar NOT allocation refusal needs its actual paired T processes' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE primitive-not-refusal)
    } 'process set is incomplete'
    Case 'scalar NOT completion cannot omit a real false or nil operation' {param($r)
        $p=(Row $r primitive-not-refusal).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS: primitive NOT nil`n",''))
    } 'complete ordered protocol'
    Case 'actual Ada table storage cannot disappear from the instrumented campaign' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE table-storage-private)
    } 'process set is incomplete'
    Case 'a native T process cannot substitute for the actual Ada invariant inspector' {param($r)
        (Row $r table-storage-private).role='ReferenceC'
    } 'actual process is missing or duplicated'
    Case 'actual __len result refusal campaigns cannot disappear behind ordinary tests' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE length-empty-result-refusal)
    } 'process set is incomplete'
    Case 'nextvar actual storage cannot be replaced by a native T facade' {param($r)
        (Row $r nextvar-storage-private).role='ReferenceC'
    } 'actual process is missing or duplicated'
    Case 'nextvar storage completion cannot omit object reclamation and reuse' {param($r)
        $p=(Row $r nextvar-storage-private).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS nextvar storage Object_Lifetime`n",''))
    } 'complete ordered protocol'
    Case 'Ada table storage completion must retain all three actual phases' {param($r)
        $p=(Row $r table-storage-private).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS: Ada table storage Deleted_Key_Reclamation`n",''))
    } 'complete ordered protocol'
    Case 'full call metadata campaign cannot disappear from actual paired T observations' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE call-metadata-windows)
    } 'process set is incomplete'
    Case 'a call metadata case filter cannot certify the complete provider campaign' {param($r)
        (Row $r call-metadata-windows).process.arguments[1]="_CALL_METADATA_CASE='First_Protected'"
    } 'explicit setup'
    Case 'call metadata completion cannot omit actual cross-context error recovery' {param($r)
        $p=(Row $r call-metadata-windows).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS call metadata Cross_Context_Error`n",''))
    } 'complete ordered protocol'
    Case 'canonical tail lifetime and refusal campaign requires both real T processes' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE canonical-tail-ownership)
    } 'process set is incomplete'
    Case 'tail ownership filter cannot omit ordinary or refusing cases' {param($r)
        (Row $r canonical-tail-ownership).process.arguments[1]="_TAIL_OWNERSHIP_CASE='Tail_Tuple'"
    } 'explicit setup'
    Case 'tail ownership output must include actual weak-argument collection' {param($r)
        $p=(Row $r canonical-tail-ownership).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS tail ownership Tail_Weak_Argument`n",''))
    } 'complete ordered protocol'
    foreach($operation in @('public-api-commands','public-panic-controls','reader-refusal-phases','string-refusal-phases','c-hook-transitions')){
        Case "complete paired T campaign cannot omit $operation" {param($r)
            $r.processes=@($r.processes|Where-Object operation -CNE $operation)
        } 'process set is incomplete'
    }
    Case 'API command filter cannot narrow the actual command set' {param($r)
        (Row $r public-api-commands).process.arguments[1]="_API_COMMAND_CASE='Light_Upvalues'"
    } 'explicit setup'
    Case 'panic filter cannot narrow the actual provider/child case set' {param($r)
        (Row $r public-panic-controls).process.arguments[1]="_PANIC_CONTROL_CASE='Trivial'"
    } 'explicit setup'
    Case 'scalar closing filter cannot omit actual allocator failures and retained public cases' {param($r)
        (Row $r scalar-closing-refusal).process.arguments[1]="_SCALAR_CLOSING_CASE='Cold_True'"
    } 'explicit setup'
    Case 'scalar closing completion cannot omit the actual original error and closer recovery' {param($r)
        $p=(Row $r scalar-closing-refusal).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS scalar closing Original_Failure`n",''))
    } 'complete ordered protocol'
    Case 'the full instrumented campaign cannot omit scalar closing observations' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE scalar-closing-refusal)
    } 'process set is incomplete'
    Case 'materialized vararg filter cannot replace the complete fault campaign' {param($r)
        (Row $r materialized-vararg-refusal).process.arguments[1]="_MATERIALIZED_VARARG_CASE='Count_Faults'"
    } 'explicit setup'
    Case 'materialized vararg completion cannot omit actual partial payload release' {param($r)
        $p=(Row $r materialized-vararg-refusal).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS materialized vararg refusal Partial_Release`n",''))
    } 'complete ordered protocol'
    Case 'the instrumented campaign cannot omit materialized count byte and recovery operations' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE materialized-vararg-refusal)
    } 'process set is incomplete'
    Case 'fixed external selector cannot narrow binary rooting and remote-state controls' {param($r)
        (Row $r fixed-external-strings).process.arguments[1]="_FIXED_EXTERNAL_CASE='Short_Binary'"
    } 'explicit setup'
    Case 'fixed external completion must retain the remote copy before state closure' {param($r)
        $p=(Row $r fixed-external-strings).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS fixed external Child_State`n",''))
    } 'complete ordered protocol'
    Case 'instrumented execution cannot substitute a T-absent external string return' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE fixed-external-strings)
    } 'process set is incomplete'
    Case 'string hash input arguments cannot select a single public body' {param($r)
        (Row $r string-hash-invariants).process.arguments+=@('Length_0')
    } 'explicit setup'
    Case 'string hash completion cannot omit the binary borrowed-key operation' {param($r)
        $p=(Row $r string-hash-invariants).process
        Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace("PASS string hash Binary`n",''))
    } 'complete ordered protocol'
    Case 'the full T campaign cannot omit actual string hash observations' {param($r)
        $r.processes=@($r.processes|Where-Object operation -CNE string-hash-invariants)
    } 'process set is incomplete'
    foreach($pair in @(@('reader-refusal-phases','PASS: reader refusal Refused_Partial_Source'),
        @('string-refusal-phases','PASS: string refusal Refused_Error'),
        @('c-hook-transitions','PASS: C hook transition C_Count_Removes_All'))){
        Case "a final marker cannot replace $($pair[1])" {param($r)
            $p=(Row $r $pair[0]).process
            Replace-Capture $p stdout ([IO.File]::ReadAllText($p.stdout_path).Replace("`r`n","`n").Replace($pair[1]+"`n",''))
        } 'complete ordered protocol'
    }
}
$origin=$root.Replace('\','/').TrimEnd('/')+'/'
if(-not $baseline.repository_dirty -and @($baseline.runtimes|Where-Object{
    -not $_.executable.Replace('\','/').StartsWith($origin,[StringComparison]::Ordinal)}).Count -eq 0){
    # These are the files from actual clean local observations, not invented
    # execution results. Replaying through the image resolver exercises the
    # same path/hash checks as a copied image; the outer image manifest/build
    # provenance still belongs to TargetObservationEnvelope.
    $paths=@{};$files=@{};$candidatePaths=@()
    foreach($runtime in $baseline.runtimes){
        $ada=$runtime.role -ceq 'Ada'
        $paths[$(if($ada){'ada_launcher'}else{'c_oracle'})]=$runtime.executable.Replace('\','/').Substring($origin.Length)
        $directory=(Split-Path -Parent $runtime.library_files[0].path).Replace('\','/')
        $paths[$(if($ada){'ada_runtime'}else{'c_runtime'})]=$directory.Substring($origin.Length)
        $candidatePaths+=@($runtime.executable)+@($runtime.library_files.path)
    }
    foreach($row in $baseline.processes){
        $candidatePaths+=@($row.process.stdout_path,$row.process.stderr_path)
        if($row.Contains('telemetry')){$candidatePaths+=$row.telemetry.path}
        if($row.Contains('output_chunk')){$candidatePaths+=$row.output_chunk.path}
    }
    foreach($path in $candidatePaths){$relative=$path.Replace('\','/').Substring($origin.Length)
        $files[$relative]=@{path=$relative;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}}
    $image=@{revision=$baseline.repository_revision;context=$baseline.context;paths=$paths;files=@($files.Values)}
    function Image-Case($Name,[scriptblock]$Change,$Expected=''){
        $r=ConvertTo-Json -InputObject $baseline -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48
        $i=ConvertTo-Json -InputObject $image -Depth 48|ConvertFrom-Json -AsHashtable -Depth 48
        & $Change $r $i
        $failure=$null
        try{$null=Assert-ConfiguredFixtureImageReport -Root $root -Report $r -Image $i -Payload $root}catch{$failure=$_.Exception.Message}
        if(($Expected -eq '' -and $null -ne $failure) -or ($Expected -ne '' -and ($null -eq $failure -or $failure -notmatch $Expected))){throw "Configured image regression $Name failed: $failure; expected $Expected"}
        $script:cases++;Write-Output "CONFIGURED IMAGE PASS: $Name"
    }
    Image-Case 'actual clean configured captures replay through exact image membership' {}
    Image-Case 'dirty observations cannot enter the final image' {param($r,$i)$r.repository_dirty=$true} 'source/context differs'
    Image-Case 'another runtime revision cannot reuse old captures' {param($r,$i)$i.revision='0'*40} 'source/context differs'
    Image-Case 'another selected context cannot reuse old captures' {param($r,$i)$i.context='default/macos/release/shared'} 'source/context differs'
    Image-Case 'missing executable bytes cannot be replaced by a source-bound receipt' {param($r,$i)$i.files=@($i.files|Where-Object path -CNE $i.paths.ada_launcher)} 'absent from its exact frozen image'
    Image-Case 'another frozen runtime directory cannot certify the selected library' {param($r,$i)$i.paths.ada_runtime='lib/wrong-profile'} 'different frozen runtime directory'
    Image-Case 'another frozen launcher cannot certify the selected process' {param($r,$i)$i.paths.ada_launcher='tests/bin/wrong-runner'} 'different frozen interpreter'
    Image-Case 'image file hash drift cannot inherit actual raw observation authority' {param($r,$i)
        @($i.files|Where-Object path -CEQ $i.paths.ada_launcher)[0].sha256='0'*64
    } 'absent from its exact frozen image'
}else{
    Write-Output 'NOT RUN: image-membership replay requires clean repository-local actual runtimes; component captures remain observations only'
}
$reuse=Join-Path $temporary 'reused-capture-directory'
[void][IO.Directory]::CreateDirectory($reuse)
$sentinel=Join-Path $reuse 'ReferenceC-configuration.stdout'
[IO.File]::WriteAllText($sentinel,'SYNTHETIC preserved capture fixture',[Text.UTF8Encoding]::new($false))
$sentinelHash=(Get-FileHash $sentinel).Hash
$reuseReport=Join-Path $reuse 'other-configuration.json'
$failure=$null
try{
    & (Join-Path $PSScriptRoot 'check-configured-fixtures.ps1') -Interpreter 'must-not-execute' `
        -ReferenceInterpreter 'must-not-execute' -RuntimeDirectory 'must-not-resolve' `
        -ReferenceLibraryDirectory 'must-not-resolve' -Configuration default -Report $reuseReport
}catch{$failure=$_.Exception.Message}
if($failure -notmatch 'capture directory must be new' -or (Test-Path $reuseReport) -or
    (Get-FileHash $sentinel).Hash -cne $sentinelHash){
    throw 'Reusing a capture directory reached execution or changed preserved bytes'
}
$script:cases++
Write-Output 'CONFIGURED FIXTURE PASS: a different report/configuration cannot overwrite prior captures'
Write-Output "PASS: $script:cases configured fixture rejection regressions over actual observations; mutations are non-execution fixtures"
