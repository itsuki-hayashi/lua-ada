param([string] $Output='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Test-ConformanceReferenceTree -Root $root
$target='tests/conformance/targets/remaining-upstream-compatibility'
if($Output -eq ''){$Output=Join-Path $root ($target+'/compiled-declarations.author-proposal.json')}
$outputPath=[IO.Path]::GetFullPath($Output)
$relative=[IO.Path]::GetRelativePath($root,$outputPath).Replace('\','/')
if($relative -cne ($target+'/compiled-declarations.author-proposal.json') -and -not $relative.StartsWith('reports/',[StringComparison]::Ordinal)){
    throw 'Declaration proposals must remain in target-owned metadata or disposable reports'
}
$inventoryPath='tests/conformance/c-api.jsonl'
$globalPath=$target+'/global-api.author-proposal.json'
$inventory=@(Get-Content (Join-Path $root $inventoryPath)|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json -AsHashtable -Depth 32})
$routes=Get-Content (Join-Path $root $globalPath) -Raw|ConvertFrom-Json -AsHashtable -Depth 64
if($inventory.Count -ne 473 -or $routes.entries.Count -ne 473){throw 'Global predecessor inventory changed'}
$seen=@{};$entries=@()
foreach($entry in $inventory){
    if($entry.kind -cnotin @('function','data','type','macro')){throw 'Unknown original API declaration kind'}
    $previous=@($routes.entries|Where-Object id -CEQ $entry.id)
    if($previous.Count -ne 1 -or $seen.ContainsKey($entry.id)){throw 'Global proposal identity missing or duplicated'}
    $seen[$entry.id]=$true
    $role=if($entry.kind -cin @('function','data')){'runtime-entry'}elseif($entry.kind -ceq 'type'){'type-layout'}
        elseif($entry.declaration -cmatch '^#define\s+[A-Za-z_][A-Za-z0-9_]*\('){'macro-operation'}else{'object-macro'}
    $candidate=$role -cin @('type-layout','object-macro')
    $family=if($role -ceq 'type-layout'){'callback-and-aggregate-abi'}elseif(-not $candidate){$null}
        elseif($entry.header -ceq 'luaconf.h'){'configuration-and-definition-origin'}else{'public-constant-and-token-profile'}
    $entries+=[ordered]@{id=$entry.id;header=$entry.header;kind=$entry.kind;name=$entry.name;
        byte_offset=$entry.byte_offset;byte_length=$entry.byte_length;anchor_sha256=$entry.anchor_sha256;
        declaration=$entry.declaration;conditions=@($entry.conditions);mechanical_role=$role;
        declaration_probe_candidate=$candidate;candidate_probe_family=$family;
        semantic_review_status='pending';required_runtime_route=(-not $candidate);
        existing_named_c_cases=@($previous[0].named_c_cases);existing_named_aunit_cases=@($previous[0].named_aunit_cases);
        original_definition_selection_required=(@($entry.conditions).Count -gt 0 -or $entry.header -ceq 'luaconf.h');
        runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@()}
}
$headers=@(foreach($directory in @('references/lua','c_api/include/api')){foreach($name in @('lua.h','lauxlib.h','lualib.h','luaconf.h')){
    $path=$directory+'/'+$name;[ordered]@{path=$path;sha256=(Get-FileHash (Join-Path $root $path)).Hash.ToLowerInvariant()}
}})
$revision=(& git -C $root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $revision -cnotmatch '^[0-9a-f]{40}$'){throw 'Cannot identify source proposal revision'}
$changes=@(& git -C $root -c core.fsmonitor=false status --porcelain=v1 --untracked-files=normal)
if($LASTEXITCODE -ne 0){throw 'Cannot identify source proposal revision'}
$proposal=[ordered]@{schema_version=1;kind='target-compiled-declaration-author-design';target='remaining-upstream-compatibility';
    reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';author='Codex /root/validation_delivery';
    independent_review_status='pending';runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@();
    source_snapshot=@{revision=$revision;repository_dirty=($changes.Count -gt 0)};
    original_inventory=@{path=$inventoryPath;sha256=(Get-FileHash (Join-Path $root $inventoryPath)).Hash.ToLowerInvariant()};
    existing_route_proposals=@{path=$globalPath;sha256=(Get-FileHash (Join-Path $root $globalPath)).Hash.ToLowerInvariant()};
    header_bindings=$headers;global_entries=473;declaration_candidates=@($entries|Where-Object declaration_probe_candidate).Count;
    runtime_entries=@($entries|Where-Object mechanical_role -CEQ runtime-entry).Count;
    macro_operations=@($entries|Where-Object mechanical_role -CEQ macro-operation).Count;
    installed_compiled_cases=0;entries=$entries;
    limitations=@('Mechanical roles are triage, not semantic classifications or applicability decisions.',
        'Every behavioral public macro retains a named actual behavioral route; function signatures alone never discharge calls.',
        'Pure preprocessor helpers may change category only after explicit independent source-semantic review.',
        'Actual SDK/native probes must use identical compiler, language, flags and host/configuration; no alternate ABI assumption.',
        'Original conditional definition origins and overrides need source-linked native compiler observations.',
        'C++/DLL and compatibility branches require an explicit reviewed applicability decision or an actual matching supplemental probe.',
        'No declaration probe, execution evidence, independent approval or passing ledger status is installed by this proposal.')}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath))
[IO.File]::WriteAllText($outputPath,(ConvertTo-Json $proposal -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "AUTHOR DESIGN ONLY: 473 original entries; $($proposal.declaration_candidates) declaration candidates, $($proposal.runtime_entries) runtime entries, $($proposal.macro_operations) macro operations; compiled cases installed=0"
