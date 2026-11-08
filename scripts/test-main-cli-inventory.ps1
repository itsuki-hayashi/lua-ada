param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$packetPath = Join-Path $projectRoot 'tests/conformance/targets/remaining-upstream-compatibility/main-cli-windows.inventory.author-proposal.json'
$packet = Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json -Depth 100
$script:checks = 0

function Require-Inventory {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Get-ByteHash {
    param([byte[]] $Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Test-Inventory {
    param($Document)

    # This author inventory deliberately is not a policy/review input. Keep
    # its zero-execution and pending-authority boundary machine checked.
    Require-Inventory ($Document.schema_version -eq 1 -and
        $Document.kind -ceq 'main-cli-windows-read-only-inventory-author-proposal') 'Unexpected inventory schema'
    Require-Inventory ($Document.source_only -eq $true) 'Not a source-only inventory'
    foreach ($field in 'source_approval', 'adaptation_approval',
        'native_applicability_approval', 'runtime_acceptance',
        'coverage_authority', 'policy_installation', 'transformed_source_emitted') {
        Require-Inventory ($Document.$field -eq $false) "Authority/emission flag changed: $field"
    }
    Require-Inventory ($Document.review.status -ceq 'pending-independent-review' -and
        $null -eq $Document.review.reviewer -and $null -eq $Document.review.artifact) 'Review is not pending'
    Require-Inventory ($Document.actual_new_lua_executions -eq 0 -and
        $Document.actual_new_builds -eq 0) 'Execution was attributed to source inspection'
    foreach ($field in 'source_mappings', 'source_exclusions', 'mode_flags') {
        Require-Inventory (@($Document.$field).Count -eq 0) "Unexpected mapping/mode: $field"
    }

    $bindings = @{}
    foreach ($binding in $Document.bindings) {
        Require-Inventory (-not $bindings.ContainsKey($binding.path)) 'Duplicate source binding'
        $bindings[$binding.path] = $binding
        $resolved = [IO.Path]::GetFullPath((Join-Path $projectRoot $binding.path))
        Require-Inventory ($resolved.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) 'Binding escaped project root'
        $bytes = [IO.File]::ReadAllBytes($resolved)
        Require-Inventory ($bytes.Length -eq $binding.bytes -and
            (Get-ByteHash $bytes) -ceq $binding.sha256) "Source binding changed: $($binding.path)"
    }
    Require-Inventory ($bindings.Count -eq 26) 'Source binding list changed'
    $mainPath = 'references/lua/testes/main.lua'
    $main = [IO.File]::ReadAllBytes((Join-Path $projectRoot $mainPath))
    $lineStarts = [Collections.Generic.List[int]]::new()
    $lineStarts.Add(0)
    for ($i = 0; $i -lt $main.Length; $i++) {
        if ($main[$i] -eq 10 -and $i + 1 -lt $main.Length) { $lineStarts.Add($i + 1) }
    }
    Require-Inventory ($lineStarts.Count -eq 600) 'Pinned main line count changed'

    # Parse PowerShell syntax without invoking the harness or evaluating any
    # hashtable values. Argument/environment/input/result bodies remain bound
    # by the complete file hash, while each exact Title/location is indexed.
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $projectRoot 'scripts/check-cli.ps1'), [ref]$tokens, [ref]$errors)
    Require-Inventory (@($errors).Count -eq 0) 'CLI harness syntax is invalid'
    $actualControls = @($ast.FindAll({
        param($node) $node -is [Management.Automation.Language.HashtableAst]
    }, $true) | ForEach-Object {
        $node = $_
        $keys = @($node.KeyValuePairs | Where-Object {
            $_.Item1 -is [Management.Automation.Language.StringConstantExpressionAst] -and
            $_.Item1.Value -ceq 'Title'
        })
        if ($keys.Count -eq 1) {
            [pscustomobject]@{
                title = $keys[0].Item2.PipelineElements[0].Expression.Value
                line = $node.Extent.StartLineNumber
            }
        }
    })
    Require-Inventory ($actualControls.Count -eq 112 -and
        @($Document.cli_controls).Count -eq 112) 'CLI control count changed'
    $controls = @{}
    $nativeCount = 0
    $promptCount = 0
    foreach ($index in 0..111) {
        $entry = $Document.cli_controls[$index]
        $actual = $actualControls[$index]
        Require-Inventory ($entry.id -ceq ('CLI-{0:d3}' -f ($index + 1)) -and
            $entry.title -ceq $actual.title -and $entry.line -eq $actual.line -and
            $entry.source -ceq 'scripts/check-cli.ps1') 'CLI Title/location changed'
        Require-Inventory ($entry.original_main_execution_credit -eq $false) 'Control granted original coverage'
        Require-Inventory (-not $controls.ContainsKey($entry.id)) 'Duplicate CLI control'
        $controls[$entry.id] = $entry
        if ($entry.protocol_selection -cin @('always-captured-default',
            'native-and-full', 'prompt-and-native-and-full')) { $nativeCount++ }
        if ($entry.protocol_selection -cin @('always-captured-default',
            'prompt-and-native-and-full')) { $promptCount++ }
    }
    $nativeTitles = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Extent.StartLineNumber -ge 400 -and $node.Extent.StartLineNumber -le 437
    }, $true) | ForEach-Object { $_.Value })
    Require-Inventory ($nativeTitles.Count -eq 38) 'Static native selection changed'
    foreach ($entry in $Document.cli_controls) {
        $selection = if ($entry.line -lt 130) { 'always-captured-default' }
            elseif ($entry.line -ge 442) { 'prompt-and-native-and-full' }
            elseif ($entry.title -cin $nativeTitles) { 'native-and-full' }
            else { 'full-only' }
        Require-Inventory ($entry.protocol_selection -ceq $selection) 'Wrong static selection'
    }
    Require-Inventory ($nativeCount -eq 59 -and $promptCount -eq 21 -and
        $Document.first_party_control_selection.full_selection -eq 112 -and
        $Document.first_party_control_selection.native_protocol_selection -eq 59 -and
        $Document.first_party_control_selection.prompt_protocol_selection -eq 21) 'Wrong protocol totals'

    $blocks = @{}
    $nextLine = 1
    $nextByte = 0
    Require-Inventory (@($Document.source_blocks).Count -eq 47) 'Wrong source block count'
    foreach ($block in $Document.source_blocks) {
        $source = $block.source
        Require-Inventory (-not $blocks.ContainsKey($block.id)) 'Duplicate source block'
        $blocks[$block.id] = $block
        Require-Inventory ($source.path -ceq $mainPath -and
            $source.first_line -eq $nextLine -and $source.last_line -ge $nextLine -and
            $source.last_line -le 600 -and $source.byte_offset -eq $nextByte) 'Source block gap/overlap'
        $expectedEnd = if ($source.last_line -eq 600) { $main.Length }
            else { $lineStarts[$source.last_line] }
        Require-Inventory ($source.byte_offset -eq $lineStarts[$source.first_line - 1] -and
            $source.byte_length -eq $expectedEnd - $source.byte_offset) 'Source span differs from lines'
        $slice = [byte[]]::new($source.byte_length)
        [Array]::Copy($main, $source.byte_offset, $slice, 0, $slice.Length)
        Require-Inventory ((Get-ByteHash $slice) -ceq $source.sha256) 'Source block bytes changed'
        Require-Inventory ($block.original_execution_credit -eq $false -and
            $block.independent_review -ceq 'pending') 'Block granted authority'
        foreach ($id in $block.related_cli_controls) {
            Require-Inventory ($controls.ContainsKey($id) -and
                $block.id -cin $controls[$id].mapped_blocks) 'Invalid block-to-control edge'
        }
        $nextLine = $source.last_line + 1
        $nextByte = $expectedEnd
    }
    Require-Inventory ($nextLine -eq 601 -and $nextByte -eq $main.Length) 'Main source not fully indexed'
    foreach ($control in $Document.cli_controls) {
        foreach ($id in $control.mapped_blocks) {
            Require-Inventory ($blocks.ContainsKey($id) -and
                $control.id -cin $blocks[$id].related_cli_controls) 'Invalid control-to-block edge'
        }
    }
}

Test-Inventory $packet
$positiveChecks = $script:checks
$rejections = 0
function Reject-ChangedInventory {
    param([scriptblock] $Change)
    $copy = $packet | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    & $Change $copy
    $rejected = $false
    try { Test-Inventory $copy } catch { $rejected = $true }
    if (-not $rejected) { throw 'Mutated inventory was accepted' }
    $script:rejections++
}

Reject-ChangedInventory { param($d) $d.runtime_acceptance = $true }
Reject-ChangedInventory { param($d) $d.review.status = 'approved' }
Reject-ChangedInventory { param($d) $d.actual_new_lua_executions = 1 }
Reject-ChangedInventory { param($d) $d.source_exclusions = @('main.lua') }
Reject-ChangedInventory { param($d) $d.mode_flags = @('_port') }
Reject-ChangedInventory { param($d) $d.bindings[0].sha256 = '0' * 64 }
Reject-ChangedInventory { param($d) $d.cli_controls = @($d.cli_controls | Select-Object -Skip 1) }
Reject-ChangedInventory { param($d) $d.cli_controls[0].title = 'invented control' }
Reject-ChangedInventory { param($d) $d.cli_controls[0].protocol_selection = 'full-only' }
Reject-ChangedInventory { param($d) $d.source_blocks[1].source.first_line++ }
Reject-ChangedInventory { param($d) $d.source_blocks[1].source.byte_offset++ }
Reject-ChangedInventory { param($d) $d.source_blocks[1].source.sha256 = '0' * 64 }
Reject-ChangedInventory { param($d) $d.source_blocks[2].related_cli_controls = @('CLI-999') }
Reject-ChangedInventory { param($d) $d.cli_controls[0].mapped_blocks = @('MAIN-99') }
Reject-ChangedInventory { param($d) $d.source_blocks[0].original_execution_credit = $true }

Write-Output "PASS: main CLI source inventory: 47 source blocks, 112 authored controls, 26 bindings ($positiveChecks checks)"
Write-Output "PASS: $rejections source/authority/selection/edge rejection controls"
Write-Output 'No Lua program, transformed main.lua, subprocess counterpart or build was executed.'
