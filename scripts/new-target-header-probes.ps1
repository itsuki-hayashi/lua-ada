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
# Stable field order makes source/configuration changes reviewable even when
# PowerShell enumerates fresh Hashtables differently between processes. Match
# scheduled cases by their immutable id, so inserting a new compiler role does
# not reorder every later case's fields or borrow its predecessor's identity.
function Preserve-HeaderFieldOrder($Value,$Previous){
    if($Value -is [Collections.IDictionary]){
        $ordered=[ordered]@{};$keys=@()
        if($Previous -is [Collections.IDictionary]){$keys+=@($Previous.Keys|Where-Object{$Value.Contains($_)})}
        $keys+=@($Value.Keys|Where-Object{$_ -cnotin $keys})
        foreach($key in $keys){$old=if($Previous -is [Collections.IDictionary] -and $Previous.Contains($key)){$Previous[$key]}else{$null}
            $ordered[$key]=Preserve-HeaderFieldOrder $Value[$key] $old}
        return $ordered
    }
    if($Value -is [Array]){
        $items=@(for($i=0;$i -lt $Value.Count;$i++){
            $old=if($Previous -is [Array] -and $i -lt $Previous.Count){$Previous[$i]}else{$null}
            if($Value[$i] -is [Collections.IDictionary] -and $Value[$i].Contains('id')){
                $matching=@($Previous|Where-Object{$_ -is [Collections.IDictionary] -and $_.Contains('id') -and $_.id -ceq $Value[$i].id})
                if($matching.Count -eq 1){$old=$matching[0]}
            }
            Preserve-HeaderFieldOrder $Value[$i] $old
        })
        return ,$items
    }
    return $Value
}
if(Test-Path -LiteralPath $full){
    $previous=Get-Content $full -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    $mapping=Preserve-HeaderFieldOrder $mapping $previous
}
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
[IO.File]::WriteAllText($full,(ConvertTo-Json $mapping -Depth 64).Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "INSTALLED AUTHOR PROBES: $($mapping.cases.Count) actual SDK/native pairs across 26 contexts; 228 declaration anchors and $($mapping.applicability_anchors.Count) conditional applicability anchors; source/global reviews pending"
