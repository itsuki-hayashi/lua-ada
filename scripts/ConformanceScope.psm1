Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')

function Get-ConformanceScopePolicy {
    param([ValidateSet('gc-io-events','expanded-t-conformance')][string] $Scope = 'gc-io-events')
    # A definition cannot shrink its own mandatory coverage. Keep the reviewed
    # delivery boundaries explicit while sharing all validation mechanisms.
    $files = @('events.lua','files.lua','gc.lua','gengc.lua')
    $helpers = @()
    if ($Scope -ceq 'expanded-t-conformance') {
        $files += @('bitwise.lua','closure.lua','constructs.lua','coroutine.lua',
            'goto.lua','math.lua','pm.lua','tpack.lua','utf8.lua')
        $helpers = @('bwcoercion.lua')
    }
    return @{ Files=@($files | Sort-Object); Helpers=$helpers;
        Prerequisites=@('native-platform-counterparts','stdio','subprocess','temporary-files') }
}

function Assert-ScopedBuildIdentity {
    param([Parameter(Mandatory)][Collections.IDictionary] $Observed,
          [Parameter(Mandatory)][string] $Context)
    # Read compiled identities, never infer a build from its report filename.
    # The runtime profile and launcher profile come from their separate crates.
    $parts = $Context.Split('/')
    $link = if ($Observed.launcher_library_type -ceq 'relocatable') {
        'shared'
    } else { $Observed.launcher_library_type }
    if ($parts.Count -ne 4 -or $Observed.runtime_build_profile -cne $parts[2] -or
        $Observed.launcher_build_profile -cne $parts[2] -or $link -cne $parts[3]) {
        throw 'Scoped context differs from measured runtime/launcher build identity'
    }
}

function Test-ScopedLauncher {
    param([Parameter(Mandatory)][string] $Executable,
          [Parameter(Mandatory)][string] $Directory,
          [Parameter(Mandatory)][string] $OutputPrefix,
          [Parameter(Mandatory)][Collections.IDictionary] $Environment,
          [Parameter(Mandatory)][string] $Configuration,
          [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string] $Target)
    # The same measured protocol is used by platform equivalents and unchanged
    # executions. A T-presence test alone cannot identify the inherited limits,
    # numeric configuration or executable selected through PATH and arg.
    $probeEnvironment = @{}
    foreach ($key in $Environment.Keys) { $probeEnvironment[$key] = $Environment[$key] }
    # Preflight sessions have their own lifetime. Do not contaminate the file
    # execution's precise parent/child telemetry cardinality with these probes.
    $telemetryPrefix = "$OutputPrefix-allocator"
    $probeRunId = [Guid]::NewGuid().ToString('N')
    $probeEnvironment.LUA_ADA_CONFORMANCE_TELEMETRY = $telemetryPrefix
    $probeEnvironment.LUA_ADA_CONFORMANCE_RUN_ID = $probeRunId
    $bare = 'local p=assert(io.popen("lua --conformance-config","r")); ' +
        'local s=p:read("a"); assert(p:close()); io.write(s)'
    $arg = 'local i=0; while arg[i] do i=i-1 end; local exe=arg[i+1]; '
    $arg += if ($IsWindows) {
        'local command=''""''..exe..''" --conformance-config"''; '
    } else {
        'local command="''"..exe:gsub("''", "''\"''\"''").."'' --conformance-config"; '
    }
    $arg += 'local p=assert(io.popen(command,"r")); local s=p:read("a"); assert(p:close()); io.write(s)'
    $records = @{}
    $expected = $null
    $observed = $null
    foreach ($name in @('parent','bare','arg')) {
        $arguments = switch ($name) {
            'parent' { @('--conformance-config') }
            'bare' { @('-e', $bare) }
            'arg' { @('-e', $arg) }
        }
        $process = Invoke-ConformanceProcess -Executable $Executable -Arguments $arguments `
            -Directory $Directory -OutputPrefix "$OutputPrefix-$name" -TimeoutSeconds 30 `
            -Environment $probeEnvironment
        $records[$name] = $process
        if ($process.exit_code -ne 0 -or $process.timed_out -or $process.stderr_bytes -ne 0 -or
            $process.capture_exceeded -or $process.pipe_drain_failed -or $process.process_tree_kill_error) {
            throw "Scoped launcher $name configuration probe failed"
        }
        $actual = [IO.File]::ReadAllText($process.stdout_path).Trim()
        if ($name -eq 'parent') {
            $expected = $actual
            $observed = $actual | ConvertFrom-Json -AsHashtable
            [void](Test-ConformanceConfiguration -Observed $observed -Configuration $Configuration `
                -Target $Target -AllocatorLimitBytes 2147483648)
        } elseif ($actual -cne $expected) {
            throw "Scoped launcher $name child configuration differs"
        }
    }
    $telemetry = @()
    foreach ($sidecar in Get-ChildItem -LiteralPath (Split-Path -Parent $telemetryPrefix) `
        -Filter ((Split-Path -Leaf $telemetryPrefix) + '.*.json')) {
        $measured = Get-Content -LiteralPath $sidecar.FullName -Raw | ConvertFrom-Json -AsHashtable
        $pidValue = [int]($sidecar.BaseName.Split('.')[-1])
        Assert-ManagedTelemetry -Telemetry $measured -RunId $probeRunId -ProcessId $pidValue `
            -Configuration $Configuration -RequireShutdown:($Target -eq 'Ada')
        $telemetry += $measured
    }
    # C's --conformance-config returns before constructing a state; only its
    # two Lua probe parents have allocator records. Ada's measured protocol
    # constructs/disposes a real session in all five participating processes.
    Assert-ScopedProbeTelemetry -Telemetry $telemetry -Processes $records `
        -RunId $probeRunId -Configuration $Configuration -Target $Target
    return [ordered]@{ verified=$true; observed=$observed; processes=$records; telemetry=$telemetry;
        executable_sha256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function Assert-ScopedProbeTelemetry {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Telemetry,
          [Parameter(Mandatory)][Collections.IDictionary] $Processes,
          [Parameter(Mandatory)][string] $RunId,
          [Parameter(Mandatory)][string] $Configuration,
          [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string] $Target,
          [long] $LimitBytes = 2147483648)
    # Parent configuration, bare-child and arg-child probes have their own
    # state lifetimes. Reconcile actual PID records, not merely their matching
    # JSON output: successful probes must not conceal leaked child sessions.
    $seen = @{}
    foreach ($item in $Telemetry) {
        $id = [int]$item.process_id
        if ($seen.ContainsKey($id)) { throw 'Scoped launcher probe telemetry duplicates a process' }
        Assert-ManagedTelemetry -Telemetry $item -RunId $RunId -ProcessId $id `
            -Configuration $Configuration -LimitBytes $LimitBytes -RequireShutdown:($Target -eq 'Ada')
        $seen[$id] = $true
    }
    $required = if ($Target -eq 'Ada') { @('parent','bare','arg') } else { @('bare','arg') }
    $expectedCount = if ($Target -eq 'Ada') { 5 } else { 2 }
    if ($seen.Count -ne $expectedCount) { throw 'Scoped launcher probe telemetry missing' }
    foreach ($name in $required) {
        if (-not $seen.ContainsKey([int]$Processes[$name].process_id)) {
            throw "Scoped launcher probe telemetry missing parent: $name"
        }
    }
}

function Get-ScopedNativeBranchFacts {
    param([Parameter(Mandatory)][string] $Output)
    # Exact, unique facts distinguish native guarded paths. A successful
    # counterpart on one path cannot stand in for C choosing another path.
    $patterns = [ordered]@{
        widths='cint=[48] lua_integer=[48]'
        time='time_2pow40=(?:representable|field-bound|representation)'
        year='year4000=(?:representable|representation)'
        dst='isdst=(?:absent|boolean)'
    }
    $facts = [ordered]@{}
    foreach ($key in $patterns.Keys) {
        $matches = [regex]::Matches($Output, '(?m)^native branch facts: (' + $patterns[$key] + ')\r?$')
        if ($matches.Count -ne 1) { throw "Missing or duplicate native branch fact: $key" }
        $facts[$key] = $matches[0].Groups[1].Value
    }
    return $facts
}

function Get-ScopedSourceProfileFacts {
    param([Parameter(Mandatory)][string] $Output,
          [Parameter(Mandatory)][Collections.IDictionary] $Observed)
    # Branch applicability is measured in the same process that executes the
    # unchanged source. A process-wide OK cannot certify an inactive endian or
    # numeric-width alternative. Preserve these facts as distinct evidence.
    $matches = [regex]::Matches($Output, '(?m)^source profile facts: (\{[^\r\n]+\})\r?$')
    if ($matches.Count -ne 1) { throw 'Source profile facts missing or duplicated' }
    $facts = $matches[0].Groups[1].Value | ConvertFrom-Json -AsHashtable
    $fields=@('byte_order','bitwise_precision','integer_bits','mantissa_bits','max_exponent')
    if ((@($facts.Keys | Sort-Object) -join '|') -cne (@($fields | Sort-Object) -join '|')) {
        throw 'Source profile field set differs'
    }
    foreach ($name in @('integer_bits','mantissa_bits','max_exponent')) {
        if ($facts[$name] -isnot [int] -and $facts[$name] -isnot [long]) {
            throw 'Source profile numeric measurement is not an integer'
        }
    }
    if ($Observed.integer_bytes -ne 8 -or $Observed.number_bytes -ne 8 -or
        $facts.integer_bits -ne 64 -or $facts.mantissa_bits -ne 53 -or
        $facts.max_exponent -ne 1023 -or $facts.byte_order -cnotin @('little','big') -or
        $facts.bitwise_precision -isnot [bool] -or -not $facts.bitwise_precision) {
        throw 'Source profile differs from supported int64/binary64 configuration'
    }
    return $facts
}

function Get-ScopedMeasuredConditionResults {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records,
          [Parameter(Mandatory)][Collections.IDictionary] $Facts)
    # Only this small declarative vocabulary can describe source conditions.
    # Never evaluate author-provided code. A false result records that the
    # corresponding body did not execute; it is not a passing body assertion.
    $results = [ordered]@{}
    foreach ($record in $Records) {
        if (-not $record.Contains('measured_condition')) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$record.id) -or $results.Contains($record.id)) {
            throw 'Measured source condition duplicate or missing identity'
        }
        $condition = $record.measured_condition
        if ($null -eq $condition -or $condition.operator -cnotin @('eq','lt','le','ge') -or
            -not $Facts.Contains($condition.fact) -or
            $condition.Contains('value') -eq $condition.Contains('value_fact') -or
            $condition.Count -ne 3) {
            throw 'Invalid measured source condition'
        }
        $left = $Facts[$condition.fact]
        $right = if ($condition.Contains('value_fact')) {
            if (-not $Facts.Contains($condition.value_fact)) { throw 'Measured condition fact missing' }
            $Facts[$condition.value_fact]
        } else { $condition.value }
        $integers = ($left -is [int] -or $left -is [long]) -and
            ($right -is [int] -or $right -is [long])
        if (($condition.operator -cne 'eq' -and -not $integers) -or
            ($condition.operator -ceq 'eq' -and -not $integers -and
             ($null -eq $right -or $left.GetType() -ne $right.GetType()))) {
            throw 'Measured source condition types differ'
        }
        $results[$record.id] = switch ($condition.operator) {
            'eq' { $left -ceq $right }
            'lt' { $left -lt $right }
            'le' { $left -le $right }
            'ge' { $left -ge $right }
        }
    }
    return $results
}

function Assert-ScopedConditionalReferences {
    param([Parameter(Mandatory)][object[]] $Records)
    foreach ($record in $Records) {
        if (-not $record.Contains('conditional_applicability')) { continue }
        $applicability = $record.conditional_applicability
        if ($record.status -eq 'passed' -or
            $applicability.inactive_body -cne 'reviewed-reference-only' -or
            $applicability.Contains('when') -eq $applicability.Contains('guard_evaluation') -or
            ($applicability.Contains('when') -and $applicability.when -isnot [bool]) -or
            ($applicability.Contains('guard_evaluation') -and
             ($applicability.guard_evaluation -isnot [bool] -or -not $applicability.guard_evaluation))) {
            throw 'Conditional lexical anchors cannot claim inactive body execution'
        }
        $target = @($Records | Where-Object id -CEQ $applicability.measured_guard_obligation)
        if ($target.Count -ne 1 -or -not $target[0].Contains('measured_condition') -or
            ($record.status -eq 'reviewed' -and
             $applicability.measured_guard_obligation -cnotin $record.obligations)) {
            throw 'Conditional lexical anchor lacks its measured guard obligation'
        }
        # Canonical key order preserves scalar types when comparing the author
        # applicability predicate with the actual runtime guard descriptor.
        $descriptors = @($applicability.condition, $target[0].measured_condition)
        $encoded = @(foreach ($descriptor in $descriptors) {
            $ordered = [ordered]@{}
            foreach ($key in $descriptor.Keys | Sort-Object) { $ordered[$key]=$descriptor[$key] }
            $ordered | ConvertTo-Json -Compress
        })
        if ($encoded[0] -cne $encoded[1]) { throw 'Conditional lexical predicate differs from measured guard' }
    }
}

function ConvertTo-ScopedSemanticJson {
    param([AllowNull()] $Value)
    # JSON object ordering is irrelevant to an approved semantic descriptor.
    # Sort object keys recursively while preserving array order and scalar
    # types, so a string "false" cannot replace a measured Boolean false.
    function Normalize-ScopedValue($Item) {
        if ($Item -is [Collections.IDictionary]) {
            $result=[ordered]@{}
            foreach ($key in $Item.Keys | Sort-Object) { $result[$key]=Normalize-ScopedValue $Item[$key] }
            return $result
        }
        if ($Item -is [array]) {
            $result=@(foreach ($entry in $Item) { Normalize-ScopedValue $entry })
            return ,$result
        }
        return $Item
    }
    return ConvertTo-Json -InputObject (Normalize-ScopedValue $Value) -Depth 32 -Compress
}

function Get-ScopedApprovedSourceClassifications {
    param([string] $Root, [Collections.IDictionary] $Definition,
          [Collections.IDictionary] $Suite)
    if (-not $Definition.Contains('source_classification_review')) {
        throw 'Expanded source classification review identity missing'
    }
    $binding=$Definition.source_classification_review
    $path=Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256
    $review=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($review.kind -cne 'independent-expanded-source-semantic-review' -or
        $review.scope -cne $Definition.id -or $review.reference_revision -cne $Suite.reference_revision -or
        $review.decision -cne 'accepted-source-classification-with-runtime-obligations-pending' -or
        [string]::IsNullOrWhiteSpace($review.author) -or [string]::IsNullOrWhiteSpace($review.reviewer) -or
        $review.author -ceq $review.reviewer) { throw 'Expanded source classification approval differs' }
    $required=@('bitwise.lua','bwcoercion.lua','closure.lua','constructs.lua','coroutine.lua',
        'goto.lua','math.lua','pm.lua','tpack.lua','utf8.lua')
    if ((@($review.files.file | Sort-Object) -join '|') -cne ($required -join '|')) {
        throw 'Expanded reviewed source classification set differs'
    }
    $result=@{}
    foreach ($file in $review.files) {
        $source=@($Suite.files | Where-Object path -CEQ $file.file)
        if ($source.Count -ne 1 -or $file.source.path -cne "references/lua/testes/$($file.file)" -or
            $file.source.sha256 -cne $source[0].sha256) { throw 'Reviewed classification source differs' }
        $path=Resolve-ReviewedFile -Root $Root -Path $file.proposal.path -Sha256 $file.proposal.sha256
        $result[$file.file]=@(Read-ConformanceJsonLines -Path $path)
    }
    return $result
}

function Assert-ScopedSourceClassificationBinding {
    param([object[]] $Records, [object[]] $Approved)
    if ($Records.Count -ne $Approved.Count) { throw 'Reviewed source classification record set differs' }
    $byId=@{}
    foreach ($proposal in $Approved) {
        if ($byId.ContainsKey($proposal.id)) { throw 'Reviewed source classification identity missing/duplicate' }
        $byId[$proposal.id]=$proposal
    }
    foreach ($record in $Records) {
        if (-not $byId.ContainsKey($record.id)) { throw 'Reviewed source classification identity missing/duplicate' }
        $proposal=$byId[$record.id]
        if ($record.kind -cne $proposal.original_kind) { throw 'Reviewed source classification kind differs' }
        foreach ($field in @('byte_offset','byte_length','line','end_line','anchor_sha256')) {
            if ($record[$field] -cne $proposal[$field]) { throw 'Reviewed source classification anchor differs' }
        }
        foreach ($field in @('measured_condition','conditional_applicability')) {
            if ($record.Contains($field) -ne $proposal.Contains($field) -or
                ($record.Contains($field) -and
                 (ConvertTo-ScopedSemanticJson $record[$field]) -cne (ConvertTo-ScopedSemanticJson $proposal[$field]))) {
                throw 'Reviewed source applicability descriptor differs'
            }
        }
        if ($record.status -eq 'reviewed' -and
            ($record.classification -cne $proposal.proposed_classification -or
             (@($record.obligations) -join '|') -cne (@($proposal.obligation_links) -join '|'))) {
            throw 'Reviewed source classification or obligation linkage differs'
        }
        if ($record.status -ne 'pending' -and
            ($record.invariant -cne $proposal.invariant -or
             (@($record.configurations) -join '|') -cne (@($proposal.configurations) -join '|'))) {
            throw 'Reviewed source invariant or applicability configuration differs'
        }
    }
}

function Get-ScopedApprovedApiSemantics {
    param([string] $Root, [Collections.IDictionary] $Definition)
    if (-not $Definition.Contains('api_semantic_review')) {
        throw 'Expanded API semantic review identity missing'
    }
    $binding=$Definition.api_semantic_review
    $path=Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256
    $review=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($review.schema_version -ne 1 -or
        $review.kind -cne 'independent-expanded-api-semantic-witness-review' -or
        $review.scope -cne $Definition.id -or
        $review.decision -cne 'accepted-semantic-witness-mapping' -or
        [string]::IsNullOrWhiteSpace($review.author) -or
        [string]::IsNullOrWhiteSpace($review.reviewer) -or
        $review.author -ceq $review.reviewer) { throw 'Expanded API semantic approval differs' }
    $path=Resolve-ReviewedFile -Root $Root -Path $review.proposal.path -Sha256 $review.proposal.sha256
    $proposal=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if ($proposal.schema_version -ne 1 -or
        $proposal.kind -cne 'expanded-api-semantic-witness-author-proposal' -or
        $proposal.scope -cne $Definition.id -or $proposal.author -cne $review.author -or
        $proposal.reference_revision -cne $Definition.reference_revision -or
        $proposal.entry_count -ne @($proposal.entries).Count -or
        (@($proposal.entries.id | Sort-Object) -join '|') -cne
        (@($Definition.api_ids | Sort-Object) -join '|') -or
        (@($review.verified_api_ids | Sort-Object) -join '|') -cne
        (@($Definition.api_ids | Sort-Object) -join '|')) {
        throw 'Expanded approved API selection differs'
    }
    # The semantic decision covers these exact consumer, test and T-driver
    # sources. Runtime evidence may later change status/evidence fields, but
    # cannot silently broaden the accepted claims or their source witnesses.
    foreach ($source in $review.source_bindings) {
        [void](Resolve-ReviewedFile -Root $Root -Path $source.path -Sha256 $source.sha256)
    }
    return @($proposal.entries)
}

function Assert-ScopedApiSemanticBinding {
    param([object[]] $Records, [object[]] $Approved)
    if ($Records.Count -ne $Approved.Count) { throw 'Reviewed API semantic record set differs' }
    $byId=@{}
    foreach ($entry in $Approved) {
        if ($byId.ContainsKey($entry.id)) { throw 'Reviewed API semantic identity duplicate' }
        $byId[$entry.id]=$entry
    }
    foreach ($record in $Records) {
        if (-not $byId.ContainsKey($record.id)) { throw 'Reviewed API semantic identity missing' }
        $proposal=$byId[$record.id]
        foreach ($field in @('invariant','scoped_boundaries','named_cases',
                'named_aunit_cases','selected_lua_runtime_obligations')) {
            if (-not $record.Contains($field) -or -not $proposal.Contains($field) -or
                (ConvertTo-ScopedSemanticJson $record[$field]) -cne
                (ConvertTo-ScopedSemanticJson $proposal[$field])) {
                throw "Reviewed API semantic descriptor differs: $($record.id)/$field"
            }
        }
    }
}

function Assert-ScopedProcessCompletion {
    param([ValidateSet('events.lua','files.lua','gc.lua','gengc.lua','bitwise.lua',
        'closure.lua','constructs.lua','coroutine.lua','goto.lua','math.lua',
        'pm.lua','tpack.lua','utf8.lua')][string] $File,
          [Parameter(Mandatory)][Collections.IDictionary] $Process,
          [Parameter(Mandatory)][Collections.IDictionary] $Telemetry,
          [Parameter(Mandatory)][string] $RunId,
          [Parameter(Mandatory)][string] $Configuration,
          [string] $Platform = '',
          [switch] $NativeOracle)
    if ($Process.exit_code -ne 0 -or $Process.timed_out -or $Process.capture_exceeded -or
        $Process.pipe_drain_failed -or $Process.process_tree_kill_error) {
        throw 'Scoped process did not complete cleanly'
    }
    Assert-ManagedTelemetry -Telemetry $Telemetry -RunId $RunId `
        -ProcessId $Process.process_id -Configuration $Configuration -RequireShutdown:(-not $NativeOracle)
    # C's T.allocfailnext refuses inside ltests' allocator, below the outer
    # conformance wrapper counter. Ada's measured provider owns this refusal.
    if (-not $NativeOracle -and $File -eq 'events.lua' -and $Configuration -eq 'upstream-test' -and
        $Telemetry.managed_refusals -lt 1) {
        throw 'Instrumented events lacks actual allocator refusal'
    }
    $stdout = [IO.File]::ReadAllText($Process.stdout_path)
    if ($File -eq 'events.lua' -and
        ([regex]::Matches($stdout, '(?m)^OK\r?$').Count -ne 1 -or
         [regex]::Matches($stdout, '(?m)^events return witness OK\r?$').Count -ne 1 -or
         $stdout -notmatch '(?m)^OK\r?\nevents return witness OK\r?\n\z')) {
        throw 'Events return witness missing, duplicate or out of order'
    }
    if ($File -eq 'files.lua') {
        if ($stdout -notmatch '(?m)^test done on \d{2}/\d{2}/\d+, at \d{2}:\d{2}:\d{2}\r?\nLua 5\.5\r?\n\z') {
            throw 'File date/version completion witness missing'
        }
        # The original file continues into date tests even when os.tmpname
        # cannot be opened. Its final date is not evidence for that skipped
        # block. Require each branch witness with the full scope's facilities.
        if ($stdout -match '(?i)skipping|omitted|not implemented') {
            throw 'File execution omitted required IO obligations'
        }
        $markers = @('native unbuffered visibility counterpart OK',
            'native C-int field boundary counterpart OK',
            'native time range recovery counterpart OK',
            'native DST inference counterpart OK',
            'testing i/o', 'testing flush', 'testing large files (> BUFSIZ)',
            'testing popen/pclose and execute', 'testing date/time')
        if ($Configuration -eq 'upstream-test') { $markers += 'testing failed write' }
        if ($Platform -eq 'macos') {
            $markers += 'native macOS nested shell status counterpart OK'
            $markers += 'native macOS calendar boundary counterpart OK'
        }
        foreach ($marker in $markers) {
            if ($stdout -notmatch ('(?m)^' + [regex]::Escape($marker) + '\r?$')) {
                throw "File IO completion witness missing: $marker"
            }
        }
        [void](Get-ScopedNativeBranchFacts -Output $stdout)
    } elseif ($File -eq 'utf8.lua') {
        if ($stdout -cnotmatch '(?m)^ok\r?\n?\z') { throw 'UTF-8 final ok witness missing' }
    } elseif ($stdout -notmatch '(?m)^OK\r?$') {
        throw 'Scoped final OK witness missing'
    }
    # Phase witnesses protect nonterminal output and configuration-selected
    # paths. Exact templates/aliases still require their reviewed ledger links.
    $phases = switch ($File) {
        'bitwise.lua' { @('testing bitwise operations','testing bitwise library') }
        'closure.lua' { @('testing closures') }
        'constructs.lua' { @('testing syntax') }
        'coroutine.lua' { @('testing coroutines','testing yields inside metamethods',
            "testing yields inside 'for' iterators") }
        'goto.lua' { @('testing goto and global declarations',
            'testing initialization in global declarations') }
        'math.lua' { @('testing numbers and math lib',"testing 'math.random'",
            "testing precision of 'tostring'") }
        'pm.lua' { @('testing pattern matching','big strings') }
        'tpack.lua' { @('testing pack/unpack','testing invalid formats','testing alignment') }
        'utf8.lua' { @('testing UTF-8 library') }
        default { @() }
    }
    foreach ($phase in $phases) {
        if ($stdout -notmatch ('(?m)^' + [regex]::Escape($phase) + '\r?$')) {
            throw "Scoped phase witness missing: $File/$phase"
        }
    }
    if ($File -ceq 'bitwise.lua' -and $stdout -notmatch '(?m)^OK\r?\nBWCOERCION HELPER OK\r?\n?\z') {
        throw 'Bitwise unchanged helper completion witness missing'
    }
    if ($File -ceq 'math.lua' -and
        [regex]::Matches($stdout, '(?m)^random seeds: -?\d+, -?\d+\r?$').Count -ne 1) {
        throw 'Math actual random seed witness missing or duplicated'
    }
    if ($File -ceq 'goto.lua') {
        $message = "  ('global' is not a reserved word)"
        $count = [regex]::Matches($stdout, '(?m)^' + [regex]::Escape($message) + '\r?$').Count
        if (($Configuration -ceq 'default' -and $count -ne 1) -or
            ($Configuration -ceq 'upstream-test' -and $count -ne 0)) {
            throw 'Goto configuration-specific global declaration witness differs'
        }
    }
    if ($File -cin @('closure.lua','constructs.lua','coroutine.lua','goto.lua','math.lua','pm.lua','tpack.lua') -and
        $stdout -notmatch '(?m)^OK\r?\n?\z') {
        throw 'Scoped terminal OK witness missing'
    }
    if ($File -eq 'coroutine.lua' -and $Configuration -eq 'upstream-test' -and
        ($stdout -notmatch '(?m)^testing yields inside hooks\r?$' -or
         [regex]::Matches($stdout, '(?m)^testing coroutine API\r?$').Count -ne 2)) {
        throw 'Coroutine instrumented hook/API tail witnesses missing'
    }
    if ($File -eq 'gc.lua' -and $stdout -notmatch '(?ms)^OK\r?\n.*^>>> closing state <<<\r?$') {
        throw 'GC state-close completion witness missing'
    }
    if ($File -eq 'gc.lua' -and $Configuration -eq 'upstream-test' -and
        (-not $Telemetry.Contains('expected_finalizer_warnings') -or
         ($Telemetry.expected_finalizer_warnings -isnot [int] -and
          $Telemetry.expected_finalizer_warnings -isnot [long]) -or
         $Telemetry.expected_finalizer_warnings -ne 10)) {
        throw 'GC state-close finalizer delivery count differs'
    }
    if ($File -eq 'gengc.lua' -and $Configuration -eq 'upstream-test' -and
        $stdout -notmatch '(?m)^testing stop-the-world collection\r?$') {
        throw 'Generational instrumented tail witness missing'
    }
}

function Test-ConformanceScope {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root,
          [ValidateSet('gc-io-events','expanded-t-conformance')][string] $Scope = 'gc-io-events',
          [string] $InventoryDirectory = '',
          [switch] $RequireScopedComplete)
    if ($InventoryDirectory -eq '') { $InventoryDirectory = Join-Path $Root 'tests/conformance' }
    # Always regenerate/check the ENTIRE original inventory first. A scoped
    # completion request cannot conceal missing or corrupt unrelated anchors.
    $inventory = Test-ConformanceInventory -Root $Root -InventoryDirectory $InventoryDirectory
    $suite = Get-Content -LiteralPath (Join-Path $InventoryDirectory 'suite.json') -Raw |
        ConvertFrom-Json -AsHashtable -Depth 32
    $definition = Get-Content -LiteralPath (Join-Path $InventoryDirectory "scopes/$Scope.json") -Raw |
        ConvertFrom-Json -AsHashtable -Depth 32
    if ($definition.schema_version -ne 1 -or $definition.id -cne $Scope -or
        $definition.reference_revision -cne $suite.reference_revision) { throw 'Invalid coverage scope identity' }
    $approvedClassifications=if($Scope -ceq 'expanded-t-conformance') {
        Get-ScopedApprovedSourceClassifications -Root $Root -Definition $definition -Suite $suite
    } else { @{} }
    $policy = Get-ConformanceScopePolicy -Scope $Scope
    $requiredFiles = $policy.Files
    if ((@($definition.files.path | Sort-Object) -join '|') -cne ($requiredFiles -join '|')) {
        throw 'Scope must retain all four original and selected delivery files exactly once'
    }
    $helpers = @(if ($definition.Contains('helpers')) { $definition.helpers })
    if ((@($helpers | ForEach-Object { $_.path } | Sort-Object) -join '|') -cne ($policy.Helpers -join '|')) {
        throw 'Scope must retain all selected helpers exactly once'
    }
    $prerequisites = $policy.Prerequisites
    if ((@($definition.prerequisites | Sort-Object) -join '|') -cne ($prerequisites -join '|')) {
        throw 'Scope prerequisites changed'
    }
    $api = @(Read-ConformanceJsonLines -Path (Join-Path $InventoryDirectory 'c-api.jsonl'))
    $requiredNames = @('lua_newstate','lua_close','lua_getallocf','lua_setallocf','lua_gc',
        'lua_setwarnf','lua_warning','lua_newuserdatauv','lua_touserdata','lua_rawlen',
        'lua_getiuservalue','lua_setiuservalue','lua_getmetatable','lua_setmetatable',
        'luaopen_io','luaopen_os','luaL_Stream','lua_Alloc','lua_WarnFunction',
        'lua_CFunction','LUA_FILEHANDLE','lua_checkstack','lua_createtable',
        'lua_error','lua_gettop','lua_isnoneornil','lua_isyieldable','lua_newtable',
        'lua_pop','lua_pushcfunction','lua_pushglobaltable','lua_pushinteger',
        'lua_pushliteral','lua_pushlstring','lua_pushstring','lua_pushvalue',
        'lua_rawequal','lua_rawget','lua_rawset','lua_rawsetp','lua_settop',
        'lua_toboolean','lua_tointeger','lua_tointegerx','lua_type','lua_upvalueindex',
        'lua_pushcclosure','lua_rawgeti','lua_pcall','lua_pcallk','lua_call','lua_callk',
        'lua_absindex','lua_tonumber','lua_tonumberx','LUA_REGISTRYINDEX',
        'LUA_TUSERDATA','LUA_TNIL','LUA_MULTRET','LUA_OK')
    if ($Scope -ceq 'expanded-t-conformance') {
        $requiredNames += @('lua_resume','lua_yieldk','lua_xmove','lua_newthread',
            'lua_status','lua_closeslot','lua_rawseti','LUA_TNUMBER','lua_sethook','lua_gethook','lua_gethookmask','lua_gethookcount',
            'lua_getstack','lua_getinfo','lua_Debug','lua_Hook',
            'lua_KFunction','lua_KContext','luaL_openselectedlibs','luaL_requiref',
            'luaL_getsubtable','luaopen_base','luaopen_package','luaopen_coroutine',
            'luaopen_debug','luaopen_math','luaopen_string','luaopen_table','luaopen_utf8',
            'luaL_openlibs','luaL_newstate','lua_rotate','LUA_ERRERR',
            'LUA_RIDX_MAINTHREAD','LUA_RIDX_GLOBALS','LUA_TBOOLEAN','LUA_TTABLE',
            'LUA_YIELD','LUA_HOOKCALL','LUA_HOOKTAILCALL','LUA_HOOKRET',
            'LUA_HOOKLINE','LUA_HOOKCOUNT','LUA_MASKCALL','LUA_MASKRET',
            'LUA_MASKLINE','LUA_MASKCOUNT','LUA_LOADED_TABLE','LUA_PRELOAD_TABLE')
    }
    $requiredApi = @($api | Where-Object { $_.name -cin $requiredNames -or $_.name -cmatch '^LUA_GC' })
    $selectedIds = @($definition.api_ids)
    if ($selectedIds.Count -ne @($selectedIds | Select-Object -Unique).Count) {
        throw 'Duplicate scoped API obligation'
    }
    foreach ($entry in $requiredApi) {
        if ($entry.id -cnotin $selectedIds) { throw "Missing scoped API obligation: $($entry.id)" }
    }
    $originalApi = @($api | Where-Object { $_.id -cin $selectedIds })
    if ($originalApi.Count -ne $selectedIds.Count) { throw 'Unknown scoped API obligation' }
    # A scoped API invariant may cover the nonyieldable call path used here,
    # without certifying unrelated continuation behavior in the global ABI.
    # Keep independent scope records tied to the exact original header anchor.
    if ($definition.api_coverage_file -cne "scopes/$Scope.api.jsonl") {
        throw 'Unsafe scoped API coverage path'
    }
    $selectedApi = @(Read-ConformanceJsonLines -Path (Join-Path $InventoryDirectory $definition.api_coverage_file))
    if ($selectedApi.Count -ne $originalApi.Count) { throw 'Scoped API coverage set changed' }
    if ($Scope -ceq 'expanded-t-conformance') {
        $approvedApi=@(Get-ScopedApprovedApiSemantics -Root $Root -Definition $definition)
        Assert-ScopedApiSemanticBinding -Records $selectedApi -Approved $approvedApi
    }
    $seenApi = @{}
    foreach ($entry in $selectedApi) {
        if ($seenApi.ContainsKey($entry.id)) { throw 'Duplicate scoped API coverage record' }
        $seenApi[$entry.id] = $true
        $original = @($originalApi | Where-Object { $_.id -ceq $entry.id })
        if ($original.Count -ne 1) { throw 'Unknown scoped API coverage record' }
        foreach ($field in @('header','kind','name','line','byte_offset','byte_length','anchor_sha256','declaration')) {
            if ($entry[$field] -cne $original[0][$field]) { throw "Scoped API anchor drift: $($entry.id)/$field" }
        }
        if (($entry.conditions -join "`n") -cne ($original[0].conditions -join "`n")) {
            throw 'Scoped API condition drift'
        }
        if ($entry.status -eq 'passed') {
            if ([string]::IsNullOrWhiteSpace([string]$entry.invariant)) { throw 'Scoped API invariant missing' }
            foreach ($field in @('author','reviewer','artifact','rationale','original_c_evidence')) {
                if ($null -eq $entry.review -or [string]::IsNullOrWhiteSpace([string]$entry.review[$field])) {
                    throw 'Scoped API independent review missing'
                }
            }
            if ($entry.review.author -ceq $entry.review.reviewer) { throw 'Scoped API cannot self-review' }
        }
    }
    $review = $definition.review
    if ($null -eq $review -or $review.status -notin @('pending','reviewed')) {
        throw 'Invalid scope review status'
    }
    if ($RequireScopedComplete -or $review.status -eq 'reviewed') {
        foreach ($field in @('author','reviewer','artifact','rationale')) {
            if ([string]::IsNullOrWhiteSpace([string]$review[$field])) {
                throw "Scope requires independent review: $field"
            }
        }
        if ($review.status -ne 'reviewed' -or $review.author -ceq $review.reviewer) {
            throw 'Scope requires independent review'
        }
        if ($Scope -ceq 'expanded-t-conformance') {
            # Bind the selection itself, not only a reviewer name. Otherwise a
            # later edit could drop an API or helper while retaining accepted
            # metadata from a narrower selection. The approval excludes review
            # metadata from its identity to avoid a circular content hash.
            if (-not $review.Contains('artifact_sha256')) { throw 'Scope selection review hash missing' }
            $path = Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
            $approval = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 64
            if ($approval.schema_version -ne 1 -or $approval.kind -cne 'scope-definition-semantic-approval' -or
                $approval.decision -cne 'accepted' -or $approval.scope -cne $Scope -or
                $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer) {
                throw 'Scope selection review identity differs'
            }
            $identity = $approval.approved_identity
            foreach ($field in @('reference_revision','api_coverage_file')) {
                if ($identity[$field] -cne $definition[$field]) { throw 'Scope selection review differs' }
            }
            foreach ($field in @('source_classification_review','api_semantic_review')) {
                if ((ConvertTo-ScopedSemanticJson $identity[$field]) -cne
                    (ConvertTo-ScopedSemanticJson $definition[$field])) {
                    throw 'Scope selected semantic approval differs'
                }
            }
            foreach ($field in @('files','helpers')) {
                $expected = @($definition[$field] | ForEach-Object { $_.path + '#' + $_.sha256 } | Sort-Object)
                $actual = @($identity[$field] | ForEach-Object { $_.path + '#' + $_.sha256 } | Sort-Object)
                if (($expected -join '|') -cne ($actual -join '|')) { throw 'Scope selected source review differs' }
            }
            foreach ($field in @('api_ids','prerequisites')) {
                if ((@($identity[$field] | Sort-Object) -join '|') -cne
                    (@($definition[$field] | Sort-Object) -join '|')) { throw 'Scope selected obligation review differs' }
            }
        }
    }
    $sourceRecords = [Collections.Generic.List[object]]::new()
    foreach ($file in (@($definition.files) + $helpers)) {
        $original = @($suite.files | Where-Object { $_.path -ceq $file.path })
        if ($original.Count -ne 1 -or $original[0].sha256 -cne $file.sha256) {
            throw "Scoped source hash drift: $($file.path)"
        }
        $records = @(Read-ConformanceJsonLines -Path (Join-Path $InventoryDirectory $original[0].coverage_file))
        foreach ($record in $records) {
            Test-ConformanceResolvedRecord -Record $record -Contexts $suite.acceptance_contexts `
                -RequireComplete:$RequireScopedComplete
            $sourceRecords.Add($record)
        }
        Test-ConformanceSourceLinks -Records $records -RequireComplete:$RequireScopedComplete
        if ($Scope -ceq 'expanded-t-conformance') { Assert-ScopedConditionalReferences -Records $records }
        if ($approvedClassifications.Contains($file.path)) {
            Assert-ScopedSourceClassificationBinding -Records $records -Approved $approvedClassifications[$file.path]
        }
    }
    foreach ($entry in $selectedApi) {
        Test-ConformanceResolvedRecord -Record $entry -Contexts $suite.acceptance_contexts `
            -Api -RequireComplete:$RequireScopedComplete
    }
    [pscustomobject]@{ Scope=$Scope; Files=@($definition.files).Count; Helpers=$helpers.Count; SourceAnchors=$sourceRecords.Count;
        UnresolvedSourceAnchors=@($sourceRecords | Where-Object { $_.status -eq 'pending' }).Count;
        ApiEntries=$selectedApi.Count;
        UnresolvedApiEntries=@($selectedApi | Where-Object { $_.status -ne 'passed' }).Count;
        ScopeComplete=[bool]$RequireScopedComplete; FullM3Complete=$false;
        StructuralInventory=$inventory; Definition=$definition }
}

Export-ModuleMember -Function Get-ConformanceScopePolicy, Test-ConformanceScope, Assert-ScopedProcessCompletion, Test-ScopedLauncher, Assert-ScopedBuildIdentity, Assert-ScopedProbeTelemetry, Get-ScopedNativeBranchFacts, Get-ScopedSourceProfileFacts, Get-ScopedMeasuredConditionResults
