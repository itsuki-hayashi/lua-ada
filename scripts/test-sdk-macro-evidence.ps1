param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SdkMacroEvidence.psm1') -Force
$script:Cases=0
# Synthetic protocol strings only. No compiler or Lua operation executes.
function Case([string]$Name,[scriptblock]$Action){&$Action;$script:Cases++;Write-Output "MACRO FIXTURE PASS: $Name"}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action){$failure=$null;try{&$Action|Out-Null}catch{$failure=$_.Exception.Message};Assert-True ($failure -match 'receiver configuration') "Unexpected failure: $failure"}
function Protocol([string]$Role,[bool]$C89){
    $opt=[int]($Role -ceq 'client-opt-ins')
    $lines=@("MACRO-CONFIG: APIINTCASTS=$opt FAILISFALSE=$opt C89=$([int]$C89)")
    foreach($name in Get-SdkMacroCaseNames -Role $Role -C89 $C89){
        if($name -ceq 'stringify-raw-bytes'){$lines+='MACRO-TOKEN-RAW: MACRO_CONTRACT_TOKEN'}
        if($name -ceq 'stringify-expanded-bytes'){$lines+='MACRO-TOKEN-EXPANDED: 41'}
        $lines+='PASS: macro-'+$name
    }
    return ($lines -join "`n")+"`nPASS: public SDK macro contract`n"
}
$ordinary=Protocol ordinary $true;$optin=Protocol client-opt-ins $true;$posix=Protocol ordinary $false
Case 'explicit receiver modes retain47or49 ordinary and53or55 opt-in operations'{
    foreach($platform in @('windows','linux','macos')){foreach($role in @('ordinary','client-opt-ins')){
        $c89=$platform -ceq 'windows';$count=if($role -ceq 'ordinary'){if($c89){47}else{49}}else{if($c89){53}else{55}}
        $value=Test-SdkMacroProtocol -Text (Protocol $role $c89) -Role $role -Platform $platform -ReportedCases $count
        Assert-True ($value.observed_cases.Count -eq $count -and -not $value.runtime_acceptance) 'Fixture acquired runtime authority or source cases narrowed'
    }}
}
Case 'matching case count cannot hide a missing public convenience operation'{
    Reject {Test-SdkMacroProtocol -Text ($ordinary.Replace("PASS: macro-register-cfunction`n",'')) -Role ordinary -Platform windows -ReportedCases 47}
}
Case 'no declaration marker can replace the actual expanded stringification bytes'{
    Reject {Test-SdkMacroProtocol -Text ($ordinary.Replace('MACRO-TOKEN-RAW: MACRO_CONTRACT_TOKEN','MACRO-TOKEN-RAW: 41')) -Role ordinary -Platform windows -ReportedCases 47}
    Reject {Test-SdkMacroProtocol -Text ($ordinary.Replace("MACRO-TOKEN-EXPANDED: 41`n",'')) -Role ordinary -Platform windows -ReportedCases 47}
}
Case 'the opt-in client cannot impersonate ordinary nil failure or absent aliases'{
    Reject {Test-SdkMacroProtocol -Text $optin -Role ordinary -Platform windows -ReportedCases 53}
    Reject {Test-SdkMacroProtocol -Text $ordinary -Role client-opt-ins -Platform windows -ReportedCases 47}
}
Case 'WindowsC89 cannot be inferred from C99language or borrowed as a POSIX counterpart'{
    Reject {Test-SdkMacroProtocol -Text $ordinary -Role ordinary -Platform linux -ReportedCases 47}
    Reject {Test-SdkMacroProtocol -Text $posix -Role ordinary -Platform windows -ReportedCases 49}
}
Case 'duplicated reordered or summary-only case output remains incomplete'{
    Reject {Test-SdkMacroProtocol -Text ("PASS: macro-isboolean`n"+$ordinary) -Role ordinary -Platform windows -ReportedCases 47}
    Reject {Test-SdkMacroProtocol -Text ($ordinary.Replace("PASS: macro-isboolean`nPASS: macro-isnone","PASS: macro-isnone`nPASS: macro-isboolean")) -Role ordinary -Platform windows -ReportedCases 47}
    Reject {Test-SdkMacroProtocol -Text "PASS: public SDK macro contract`n" -Role ordinary -Platform windows -ReportedCases 47}
    Reject {Test-SdkMacroProtocol -Text $ordinary -Role ordinary -Platform windows -ReportedCases '47'}
}
Write-Output "PASS: $script:Cases SDK macro protocol regressions; fabricated strings only, no compiler/Lua/API execution"
