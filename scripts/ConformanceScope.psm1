Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')

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
          [Parameter(Mandatory)][ValidateSet('Ada','ReferenceC')][string] $Target)
    # Parent configuration, bare-child and arg-child probes have their own
    # state lifetimes. Reconcile actual PID records, not merely their matching
    # JSON output: successful probes must not conceal leaked child sessions.
    $seen = @{}
    foreach ($item in $Telemetry) {
        $id = [int]$item.process_id
        if ($seen.ContainsKey($id)) { throw 'Scoped launcher probe telemetry duplicates a process' }
        Assert-ManagedTelemetry -Telemetry $item -RunId $RunId -ProcessId $id `
            -Configuration $Configuration -RequireShutdown:($Target -eq 'Ada')
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

function Assert-ScopedProcessCompletion {
    param([ValidateSet('events.lua','files.lua','gc.lua','gengc.lua')][string] $File,
          [Parameter(Mandatory)][Collections.IDictionary] $Process,
          [Parameter(Mandatory)][Collections.IDictionary] $Telemetry,
          [Parameter(Mandatory)][string] $RunId,
          [Parameter(Mandatory)][string] $Configuration,
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
            'testing i/o', 'testing flush', 'testing large files (> BUFSIZ)',
            'testing popen/pclose and execute', 'testing date/time')
        if ($Configuration -eq 'upstream-test') { $markers += 'testing failed write' }
        foreach ($marker in $markers) {
            if ($stdout -notmatch ('(?m)^' + [regex]::Escape($marker) + '\r?$')) {
                throw "File IO completion witness missing: $marker"
            }
        }
    } elseif ($stdout -notmatch '(?m)^OK\r?$') {
        throw 'Scoped final OK witness missing'
    }
    if ($File -eq 'gc.lua' -and $stdout -notmatch '(?ms)^OK\r?\n.*^>>> closing state <<<\r?$') {
        throw 'GC state-close completion witness missing'
    }
    if ($File -eq 'gengc.lua' -and $Configuration -eq 'upstream-test' -and
        $stdout -notmatch '(?m)^testing stop-the-world collection\r?$') {
        throw 'Generational instrumented tail witness missing'
    }
}

function Test-ConformanceScope {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root,
          [ValidateSet('gc-io-events')][string] $Scope = 'gc-io-events',
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
    $requiredFiles = @('events.lua','files.lua','gc.lua','gengc.lua')
    if ((@($definition.files.path | Sort-Object) -join '|') -cne ($requiredFiles -join '|')) {
        throw 'Scope must retain all four selected files exactly once'
    }
    $prerequisites = @('native-platform-counterparts','stdio','subprocess','temporary-files')
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
    }
    $sourceRecords = [Collections.Generic.List[object]]::new()
    foreach ($file in $definition.files) {
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
    }
    foreach ($entry in $selectedApi) {
        Test-ConformanceResolvedRecord -Record $entry -Contexts $suite.acceptance_contexts `
            -Api -RequireComplete:$RequireScopedComplete
    }
    [pscustomobject]@{ Scope=$Scope; Files=4; SourceAnchors=$sourceRecords.Count;
        UnresolvedSourceAnchors=@($sourceRecords | Where-Object { $_.status -eq 'pending' }).Count;
        ApiEntries=$selectedApi.Count;
        UnresolvedApiEntries=@($selectedApi | Where-Object { $_.status -ne 'passed' }).Count;
        ScopeComplete=[bool]$RequireScopedComplete; FullM3Complete=$false;
        StructuralInventory=$inventory; Definition=$definition }
}

Export-ModuleMember -Function Test-ConformanceScope, Assert-ScopedProcessCompletion, Test-ScopedLauncher, Assert-ScopedBuildIdentity, Assert-ScopedProbeTelemetry
