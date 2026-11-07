param([string] $Output='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'HeaderDeclarationProbes.psm1')
if($Output -eq ''){$Output=Join-Path $root 'tests/conformance/targets/remaining-upstream-compatibility/compiled-witnesses.author-proposal.json'}
$full=[IO.Path]::GetFullPath($Output);$relative=[IO.Path]::GetRelativePath($root,$full).Replace('\','/')
if($relative -cne 'tests/conformance/targets/remaining-upstream-compatibility/compiled-witnesses.author-proposal.json' -and
    -not $relative.StartsWith('reports/',[StringComparison]::Ordinal)){throw 'Header probe mapping must remain target-owned or disposable'}
$mapping=New-HeaderDeclarationMapping -Root $root
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
[IO.File]::WriteAllText($full,(ConvertTo-Json $mapping -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "INSTALLED AUTHOR PROBES: $($mapping.cases.Count) actual SDK/native pairs across 26 contexts; 228 declaration anchors and $($mapping.applicability_anchors.Count) conditional applicability anchors; source/global reviews pending"
