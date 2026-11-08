Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')

function Assert-LocalsProgressSourceContract {
    param([string]$Root,[Collections.IDictionary]$Contract)
    $reviewPath='tests/conformance/targets/remaining-upstream-compatibility/reviews/locals-progress-output.independent-source-review.json'
    $reviewHash='34df68857cd9b39732804f6e8ee3a2e98bb121160fba118d3870dfff9612d9fb'
    if($null -eq $Contract -or (($Contract.Keys|Sort-Object)-join '|') -cne 'dependency|kind|source_review|validator' -or
        $Contract.kind -cne 'locals-literal-dot-progress' -or $Contract.source_review.path -cne $reviewPath -or
        $Contract.source_review.sha256 -cne $reviewHash -or
        $Contract.dependency.path -cne 'references/lua/testes/tracegc.lua' -or
        $Contract.dependency.sha256 -cne 'b064a642e2d5d22c2101ec4fe0a5d805ba633ca5b69470d20ec48b4ee5ca360b' -or
        $Contract.validator.path -cne 'scripts/ConformanceFileProtocols.psm1'){
        throw 'Locals progress lacks its bounded independent source contract'
    }
    [void](Resolve-ReviewedFile -Root $Root -Path $Contract.dependency.path -Sha256 $Contract.dependency.sha256)
    [void](Resolve-ReviewedFile -Root $Root -Path $Contract.validator.path -Sha256 $Contract.validator.sha256)
    $review=Get-Content (Resolve-ReviewedFile -Root $Root -Path $reviewPath -Sha256 $reviewHash) -Raw|
        ConvertFrom-Json -AsHashtable -Depth 48
    Assert-TargetCompletionSourceReviewFlags $review
    if($review.schema_version -ne 1 -or $review.kind -cne 'locals-progress-output-independent-source-review' -or
        $review.decision -cne 'accepted-output-contract-direction' -or $review.author -ceq $review.reviewer -or
        $review.source_adaptation_authority -isnot [bool] -or $review.source_adaptation_authority -or
        $review.source_exclusions -isnot [Array] -or $review.source_exclusions.Count -ne 0){
        throw 'Locals progress source direction cannot grant adaptation or runtime authority'
    }
    [void](Resolve-ReviewedFile -Root $Root -Path $review.proposal.path.Replace('\','/') -Sha256 $review.proposal.sha256)
    $expected=@('references/lua/testes/tracegc.lua','references/lua/testes/locals.lua','references/lua/manual/manual.of',
        'tests/conformance/target-file-completion.lua','scripts/ConformanceFileProtocols.psm1')
    if($review.source_bindings -isnot [Array] -or
        (($review.source_bindings.path|Sort-Object)-join '|') -cne (($expected|Sort-Object)-join '|')){
        throw 'Locals progress source direction lacks its exact dependency set'
    }
    foreach($binding in $review.source_bindings){
        if($binding.path -ceq 'scripts/ConformanceFileProtocols.psm1'){
            # This is the reviewed pre-change checker, a direction input rather
            # than current implementation authority. The manifest above binds
            # the actual new validator; final acceptance additionally requires
            # a fresh independent per-file source decision over that manifest.
            if($binding.sha256 -cne '249f86e108691b24d975fb7b691b6658a4c328c3f8655ad7477c5d0cc974823d'){
                throw 'Locals progress reviewed baseline checker differs'
            }
        }else{[void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)}
    }
}

function Assert-TargetCompletionSourceReviewFlags {
    param([Collections.IDictionary]$Artifact,[switch]$AllowSyntheticReview)
    # Source decisions may authorize only this observation protocol. Labelled
    # synthetic unit fixtures must never discharge the actual final target's
    # review gate, even if their binding hashes and claimed reviewers match.
    if(-not $Artifact.Contains('synthetic_fixture') -or $Artifact.synthetic_fixture -isnot [bool]){
        throw 'Completion source review requires an explicit boolean synthetic label'
    }
    if($Artifact.synthetic_fixture -and -not $AllowSyntheticReview){
        throw 'Synthetic completion source review cannot authorize the actual target'
    }
    foreach($flag in @('runtime_acceptance','coverage_authority')){
        if(-not $Artifact.Contains($flag) -or $Artifact[$flag] -isnot [bool] -or $Artifact[$flag]){
            throw 'Completion source review cannot supply runtime or coverage authority'
        }
    }
    if(-not $Artifact.Contains('execution_evidence') -or $Artifact.execution_evidence -isnot [Array] -or
        $Artifact.execution_evidence.Count -ne 0){
        throw 'Completion source review cannot supply execution evidence'
    }
}

function Get-TargetFileProtocolDefinition {
    param([Parameter(Mandatory)][string] $File)
    # These entry operations and return observations follow all.lua, not the
    # host's command-line treatment of discarded chunk results. The retained
    # thirteen-file scopes keep their own immutable completion protocols.
    $entry = switch -CaseSensitive ($File) {
        { $_ -cin @('strings.lua','literals.lua') } { 'direct'; break }
        { $_ -cin @('code.lua','sort.lua','verybig.lua') } { 'strip'; break }
        'big.lua' { 'coroutine'; break }
        { $_ -cin @('api.lua','attrib.lua','calls.lua','cstack.lua','db.lua','errors.lua',
            'locals.lua','main.lua','memerr.lua','nextvar.lua','vararg.lua') } { 'dump'; break }
        default { return $null }
    }
    $phase = switch -CaseSensitive ($File) {
        'big.lua' { @('yielded b','returned a') }
        'calls.lua' { @('returned deep') }
        'attrib.lua' { @('returned 27') }
        'locals.lua' { @('returned 5') }
        'verybig.lua' { @('returned 10') }
        default { @() }
    }
    $returns = switch -CaseSensitive ($File) {
        'big.lua' { 'one-yield-b-one-return-a' }
        'calls.lua' { 'one-deep-function' }
        'attrib.lua' { 'one-integer-27' }
        'locals.lua' { 'integer-5-and-function' }
        'verybig.lua' { 'one-integer-10' }
        default { 'no-values' }
    }
    return @{file=$File;entry=$entry;return_protocol=$returns;source_marker=$(if($File -ceq 'memerr.lua'){'Ok'}else{'OK'});
        phases=@($phase);t_absent_return=($File -cin @('api.lua','code.lua','memerr.lua'))}
}

function Read-TargetFileProtocolManifest {
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $Path,
          [switch] $RequireReview,[switch]$AllowSyntheticReview)
    $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $Root $Path }
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),[IO.Path]::GetFullPath($full)).Replace('\','/')
    $hash = (Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant()
    [void](Resolve-ReviewedFile -Root $Root -Path $relative -Sha256 $hash)
    $manifest = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -AsHashtable -Depth 48
    if ($manifest.schema_version -ne 1 -or $manifest.kind -cne 'target-file-completion-protocols' -or
        $manifest.target -cne 'remaining-upstream-compatibility' -or
        $manifest.reference_revision -cne '7579fc9d7ed90240487251dfb69168f8e64e9294' -or
        $manifest.runtime_acceptance -isnot [bool] -or $manifest.runtime_acceptance -or
        $manifest.coverage_authority -isnot [bool] -or $manifest.coverage_authority -or
        $manifest.wrapper.path -cne 'tests/conformance/target-file-completion.lua' -or
        $manifest.orchestrator.path -cne 'references/lua/testes/all.lua') {
        throw 'Invalid target file completion manifest identity'
    }
    foreach ($identity in @($manifest.wrapper,$manifest.orchestrator)) {
        [void](Resolve-ReviewedFile -Root $Root -Path $identity.path -Sha256 $identity.sha256)
    }
    $expected = @('api','attrib','big','calls','code','cstack','db','errors','literals',
        'locals','main','memerr','nextvar','sort','strings','vararg','verybig' | ForEach-Object { $_ + '.lua' })
    if (@($manifest.files).Count -ne $expected.Count) { throw 'Target completion source set differs' }
    $seen = @{}
    foreach ($item in $manifest.files) {
        if ($item.file -cnotin $expected -or $seen.ContainsKey($item.file)) { throw 'Target completion source missing or duplicated' }
        $seen[$item.file] = $true
        $definition = Get-TargetFileProtocolDefinition -File $item.file
        foreach ($field in @('entry','return_protocol','source_marker','t_absent_return')) {
            if ($item[$field] -cne $definition[$field]) { throw "Target completion definition differs: $($item.file)/$field" }
        }
        if ((@($item.phases) -join '|') -cne (@($definition.phases) -join '|') -or
            @($item.phases).Count -ne @($definition.phases).Count -or
            $item.source.path -cne ('references/lua/testes/' + $item.file) -or
            @($item.source_links).Count -eq 0) { throw 'Target completion phases or source links differ' }
        [void](Resolve-ReviewedFile -Root $Root -Path $item.source.path -Sha256 $item.source.sha256)
        $bytes = [IO.File]::ReadAllBytes((Join-Path $Root $item.source.path))
        foreach ($span in $item.source_links) {
            if (($span.start_byte -isnot [long] -and $span.start_byte -isnot [int]) -or
                ($span.length_bytes -isnot [long] -and $span.length_bytes -isnot [int])) { throw 'Completion source span is not integral' }
            if ($span.start_byte -lt 0 -or $span.length_bytes -lt 1 -or
                $span.start_byte + $span.length_bytes -gt $bytes.Length) { throw 'Completion source span outside original' }
            $part = [byte[]]::new($span.length_bytes)
            [Array]::Copy($bytes,$span.start_byte,$part,0,$span.length_bytes)
            $actual = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($part)).ToLowerInvariant()
            if ($actual -cne $span.sha256 -or [string]::IsNullOrWhiteSpace([string]$span.rationale)) {
                throw 'Completion source span hash or rationale differs'
            }
        }
        if($item.file -ceq 'locals.lua'){
            if(-not $item.Contains('stderr_progress')){throw 'Locals completion lacks its source-bound literal progress contract'}
            Assert-LocalsProgressSourceContract -Root $Root -Contract $item.stderr_progress
        }elseif($item.Contains('stderr_progress')){throw 'Locals progress contract cannot relax another file'}
    }
    if ($RequireReview) {
        $review = $manifest.review
        if ($null -eq $review -or $review.status -cne 'accepted' -or
            [string]::IsNullOrWhiteSpace([string]$review.author) -or
            [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer) {
            throw 'Target completion protocol requires accepted independent review'
        }
        Assert-TargetCompletionSourceReviewFlags $manifest -AllowSyntheticReview:$AllowSyntheticReview
        $approvalPath = Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
        $approval = Get-Content -LiteralPath $approvalPath -Raw | ConvertFrom-Json -AsHashtable -Depth 48
        Assert-TargetCompletionSourceReviewFlags $approval -AllowSyntheticReview:$AllowSyntheticReview
        if ($approval.schema_version -ne 1 -or $approval.kind -cne 'target-file-completion-approval' -or
            $approval.decision -cne 'accepted' -or $approval.author -cne $review.author -or
            $approval.reviewer -cne $review.reviewer) { throw 'Completion approval identity differs' }
        # Hash the semantic payload without review to avoid a circular approval
        # hash. The approval additionally repeats each full original source hash.
        if ($approval.target -cne $manifest.target -or $approval.wrapper_sha256 -cne $manifest.wrapper.sha256 -or
            $approval.orchestrator_sha256 -cne $manifest.orchestrator.sha256 -or
            @($approval.decisions).Count -ne $expected.Count) { throw 'Completion approval source set differs' }
        foreach ($item in $manifest.files) {
            $decision = @($approval.decisions | Where-Object file -CEQ $item.file)
            $payload = ConvertTo-Json -InputObject $item -Compress -Depth 32
            $payloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant()
            if ($decision.Count -ne 1 -or $decision[0].decision -cne 'accepted' -or
                $decision[0].source_sha256 -cne $item.source.sha256 -or
                $decision[0].protocol_sha256 -cne $payloadHash -or
                [string]::IsNullOrWhiteSpace([string]$decision[0].rationale)) { throw 'Completion approval decision differs' }
        }
        $narrativePath = Resolve-ReviewedFile -Root $Root -Path $approval.review_evidence.path -Sha256 $approval.review_evidence.sha256
        $narrative = Get-Content -LiteralPath $narrativePath -Raw | ConvertFrom-Json -AsHashtable -Depth 48
        Assert-TargetCompletionSourceReviewFlags $narrative -AllowSyntheticReview:$AllowSyntheticReview
        if ($narrative.reviewer -cne $review.reviewer -or $narrative.decision -cne 'accepted' -or
            $narrative.target -cne $manifest.target) { throw 'Completion independent review narrative differs' }
    }
    return @{manifest=$manifest;path=$relative;sha256=$hash}
}

function Assert-TargetFileCompletion {
    param([Parameter(Mandatory)][string] $File,
          [Parameter(Mandatory)][ValidateSet('default','upstream-test')][string] $Configuration,
          [Parameter(Mandatory)][Collections.IDictionary] $Process,
          [string]$Root=(Split-Path -Parent $PSScriptRoot),[Collections.IDictionary]$StderrProgress)
    $definition = Get-TargetFileProtocolDefinition -File $File
    if ($null -eq $definition) { throw 'File has no remaining-target completion protocol' }
    if ($Process.exit_code -ne 0 -or $Process.timed_out -ne $false -or $Process.capture_exceeded -ne $false -or
        $Process.pipe_drain_failed -ne $false -or $Process.abnormal_exit_kind -or $Process.process_tree_kill_error) {
        throw 'Target file protocol process did not finish cleanly'
    }
    $stdout = [IO.File]::ReadAllText($Process.stdout_path)
    $stderr = [IO.File]::ReadAllText($Process.stderr_path)
    $absent = $Configuration -ceq 'default' -and $definition.t_absent_return
    $disposition = if ($absent) { 'T absent' } else { 'complete' }
    $terminal = 'target file completion ' + $File + ': ' + $disposition
    $matches = [regex]::Matches($stdout,'(?m)^' + [regex]::Escape($terminal) + '\r?$')
    if ($matches.Count -ne 1 -or [regex]::Matches($stdout,'(?m)^target file completion .*\r?$').Count -ne 1) {
        throw 'Target file terminal return witness missing, duplicated or wrong'
    }
    $cursor = -1
    if (-not $absent) {
        $marker = [regex]::Matches($stdout,'(?m)^' + $definition.source_marker + '\r?$')
        if ($marker.Count -ne 1 -or $marker[0].Index -ge $matches[0].Index) { throw 'Target original completion marker missing or out of order' }
        foreach ($phase in $definition.phases) {
            $found = [regex]::Matches($stdout,'(?m)^' + [regex]::Escape('target file phase ' + $File + ': ' + $phase) + '\r?$')
            if ($found.Count -ne 1 -or $found[0].Index -le $cursor -or $found[0].Index -ge $matches[0].Index) {
                throw 'Target return or yield phase missing, duplicated or out of order'
            }
            if ($File -cne 'big.lua' -and $found[0].Index -le $marker[0].Index) {
                throw 'Target return phase precedes original completion marker'
            }
            $cursor = $found[0].Index
        }
        if ($File -ceq 'big.lua' -and ($marker[0].Index -lt $stdout.IndexOf('target file phase big.lua: yielded b') -or
            $marker[0].Index -gt $stdout.IndexOf('target file phase big.lua: returned a'))) { throw 'Big completion did not occur between yield and return' }
    } elseif ([regex]::IsMatch($stdout,'(?m)^' + $definition.source_marker + '\r?$')) {
        throw 'T-absent original unexpectedly claims full source completion'
    }
    # The API's continued warning fragments are two exact complete warnings.
    # memerr's progress counter is dynamic: require its whole increasing
    # sequence, rather than permitting arbitrary numeric stderr or hiding it.
    $progress=$null
    if($File -cne 'locals.lua' -and $null -ne $StderrProgress){throw 'Locals progress contract cannot relax another file'}
    $lines = @($stderr -split '\r\n|\n|\r' | Where-Object { $_ -ne '' })
    if ($File -ceq 'api.lua' -and -not $absent) {
        if (($lines -join '|') -cne 'Lua warning: #This should be a single warning|Lua warning: #This should be another one') {
            throw 'API continued warning protocol differs'
        }
    } elseif ($File -ceq 'memerr.lua' -and -not $absent) {
        if ($lines.Count -eq 0) { throw 'Memory-error numbered progress missing' }
        for ($i=0;$i -lt $lines.Count;$i++) {
            if ($lines[$i] -cne [string]($i + 1)) { throw 'Memory-error progress sequence differs' }
        }
    } elseif($File -ceq 'locals.lua'){
        Assert-LocalsProgressSourceContract -Root $Root -Contract $StderrProgress
        $bytes=[IO.File]::ReadAllBytes($Process.stderr_path)
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        if(-not $Process.Contains('stderr_bytes') -or
            ($Process.stderr_bytes -isnot [int] -and $Process.stderr_bytes -isnot [long]) -or
            $Process.stderr_bytes -ne $bytes.Length -or -not $Process.Contains('stderr_sha256') -or
            $Process.stderr_sha256 -cne $hash){throw 'Locals progress raw byte count or hash differs'}
        # Inspect raw octets without decoding or allocating a filtered copy.
        # In particular CR/LF, warnings and replacement-decoder characters can
        # never be reclassified as the original finalizer's literal progress.
        $onlyDots=$bytes.Length -gt 0
        foreach($octet in $bytes){if($octet -ne 46){$onlyDots=$false;break}}
        if(-not $onlyDots){
            throw 'Locals progress requires one or more literal ASCII dots only'
        }
        $progress=@{kind='locals-literal-dot-progress';observed_count=$bytes.Length;raw_bytes=$bytes.Length;
            raw_sha256=$hash;source_review_sha256=$StderrProgress.source_review.sha256;
            dependency_sha256=$StderrProgress.dependency.sha256;validator_sha256=$StderrProgress.validator.sha256;
            runtime_acceptance=$false;coverage_authority=$false}
    } elseif ($File -cne 'main.lua' -and $lines.Count -ne 0) { throw 'Unexpected target file protocol stderr' }
    if ($File -ceq 'main.lua') {
        # Subprocess outputs/warnings are asserted inside unchanged main.lua.
        # Its two Ctrl-C checks have distinct terminal messages before OK;
        # a protocol contract still independently reviews actual child captures
        # and counts. These source markers do not replace that review.
        $patterns = @('(?m)^testing warnings\r?$','(?m)^testing Ctrl C\r?$','(?m)^done\r?$',
            '(?m)^done \(with (?:[2-9]|[1-9][0-9]+) kills\)\r?$')
        $cursor = -1
        foreach ($pattern in $patterns) {
            $found = [regex]::Matches($stdout,$pattern)
            if ($found.Count -ne 1 -or $found[0].Index -le $cursor -or $found[0].Index -ge $marker[0].Index) {
                throw 'Main warning or interrupt subprocess completion differs'
            }
            $cursor = $found[0].Index
        }
    }
    return @{file=$File;entry=$definition.entry;disposition=$disposition;terminal_witness=$terminal;
        source_completed=(-not $absent);stderr_progress=$progress;coverage_authority=$false;runtime_acceptance=$false}
}

function Assert-TargetFileProtocolBinding {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][Collections.IDictionary] $Report,
          [Parameter(Mandatory)][string] $WrapperPath,
          [Collections.IDictionary] $Contract, [switch] $RequireReview,
          [switch]$AllowSyntheticReview)
    if (-not $Report.operation.StartsWith('file:',[StringComparison]::Ordinal)) { return }
    $file = $Report.operation.Substring(5)
    $definition = Get-TargetFileProtocolDefinition -File $file
    if ($null -eq $definition) { return }
    if (-not $Report.Contains('file_completion_protocol') -or $null -eq $Report.file_completion_protocol) {
        throw 'Full-target File report lacks its completion protocol'
    }
    $identity = $Report.file_completion_protocol
    $reviewed = Read-TargetFileProtocolManifest -Root $Root -Path $identity.manifest_path -RequireReview:$RequireReview `
        -AllowSyntheticReview:$AllowSyntheticReview
    if ($reviewed.sha256 -cne $identity.manifest_sha256 -or
        $reviewed.manifest.wrapper.sha256 -cne $identity.wrapper_sha256 -or
        (Get-FileHash -LiteralPath $WrapperPath).Hash.ToLowerInvariant() -cne $identity.wrapper_sha256 -or
        $identity.file -cne $file -or $identity.entry -cne $definition.entry -or
        $identity.runtime_acceptance -isnot [bool] -or $identity.runtime_acceptance -or
        $identity.coverage_authority -isnot [bool] -or $identity.coverage_authority) {
        throw 'Full-target completion protocol or wrapper identity differs'
    }
    $args = @($Report.process.arguments)
    $setup = "assert(_soft==nil and _port==nil and _U==nil and _nomsg==nil); warn('@on'); "
    $setup += if ($Report.requested_configuration -ceq 'upstream-test') {
        "assert(type(T)=='table' and type(T.checkmemory)=='function'); T.checkmemory()"
    } else { 'assert(T==nil)' }
    $setup += "; dofile('equivalent-source-profile-witness.lua')"
    if ($args.Count -ne 5 -or $args[0] -cne '-e' -or $args[2] -cne $identity.wrapper_artifact -or
        $args[1] -cne $setup -or $args[3] -cne $file -or $args[4] -cne $identity.chunk_path) {
        throw 'Full-target completion wrapper was not the executed entry point'
    }
    $executedHash = switch -CaseSensitive ($Report.execution_disposition) {
        'unchanged' { @($reviewed.manifest.files | Where-Object file -CEQ $file)[0].source.sha256 }
        'reviewed-t-adapted' { $Report.t_adaptation.output_sha256 }
        default { $Report.equivalent.output_sha256 }
    }
    if ($identity.executed_sha256 -cne $executedHash) { throw 'Completion protocol selected chunk hash differs' }
    $progress=if($file -ceq 'locals.lua'){@($reviewed.manifest.files|Where-Object file -CEQ $file)[0].stderr_progress}else{$null}
    $actual = Assert-TargetFileCompletion -File $file -Configuration $Report.requested_configuration -Process $Report.process `
        -Root $Root -StderrProgress $progress
    foreach ($field in @('disposition','terminal_witness','source_completed')) {
        if ($identity[$field] -cne $actual[$field]) { throw 'Recorded completion result differs from captured protocol' }
    }
    if($file -ceq 'locals.lua'){
        if(-not $identity.Contains('stderr_progress') -or $identity.stderr_progress -isnot [Collections.IDictionary]){
            throw 'Recorded locals progress receipt is missing'
        }
        if((($identity.stderr_progress.Keys|Sort-Object)-join '|') -cne
            (($actual.stderr_progress.Keys|Sort-Object)-join '|')){throw 'Recorded locals progress field set differs'}
        foreach($field in $actual.stderr_progress.Keys){
            if(-not $identity.stderr_progress.Contains($field) -or
                $identity.stderr_progress[$field] -cne $actual.stderr_progress[$field]){
                throw 'Recorded locals progress differs from the unchanged raw capture'
            }
            $value=$identity.stderr_progress[$field]
            if(($field -cin @('observed_count','raw_bytes') -and $value -isnot [int] -and $value -isnot [long]) -or
                ($field -cin @('runtime_acceptance','coverage_authority') -and $value -isnot [bool]) -or
                ($field -cnotin @('observed_count','raw_bytes','runtime_acceptance','coverage_authority') -and $value -isnot [string])){
                throw 'Recorded locals progress types differ'
            }
        }
    }elseif($identity.Contains('stderr_progress') -and $null -ne $identity.stderr_progress){
        throw 'Locals progress receipt cannot relax another file'
    }
    if ($RequireReview -and ($null -eq $Contract -or
        -not $Contract.Contains('file_completion_protocol_sha256') -or
        -not $Contract.Contains('file_completion_wrapper_sha256') -or
        $Contract.file_completion_protocol_sha256 -cne $identity.manifest_sha256 -or
        $Contract.file_completion_wrapper_sha256 -cne $identity.wrapper_sha256)) {
        throw 'Execution contract does not bind the target file completion protocol'
    }
    return $actual
}

Export-ModuleMember -Function Get-TargetFileProtocolDefinition, Read-TargetFileProtocolManifest,
    Assert-TargetFileCompletion, Assert-TargetFileProtocolBinding
