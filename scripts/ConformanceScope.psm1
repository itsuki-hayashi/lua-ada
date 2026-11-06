Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ManagedTelemetry.psm1')

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
    $stdout = [IO.File]::ReadAllText($Process.stdout_path)
    if ($File -eq 'files.lua') {
        if ($stdout -notmatch '(?m)^test done on \d{2}/\d{2}/\d+, at \d{2}:\d{2}:\d{2}\r?\nLua 5\.5\r?\n\z') {
            throw 'File date/version completion witness missing'
        }
    } elseif ($stdout -notmatch '(?m)^OK\r?$') {
        throw 'Scoped final OK witness missing'
    }
    if ($File -eq 'gc.lua' -and $stdout -notmatch '(?ms)^OK\r?\n.*^>>> closing state <<<\r?$') {
        throw 'GC state-close completion witness missing'
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

Export-ModuleMember -Function Test-ConformanceScope, Assert-ScopedProcessCompletion
