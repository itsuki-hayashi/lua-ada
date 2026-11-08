Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-ForeignContractHookMaximum {
    param([Parameter(Mandatory)][string]$Root)
    # The public driver emits one line per actual operation, in four source
    # loops. Bind the hook upper bound to its source so later cases (including
    # cases after the private native lock exception) cannot silently disappear.
    $source=[IO.File]::ReadAllText((Join-Path $Root 'c_api/tests/foreign_api_contract.c'))
    $loops=[regex]::Matches($source,'for \(which = 1; which <= ([1-9][0-9]*); \+\+which\)')
    if($loops.Count -ne 4 -or $loops[0].Groups[1].Value -cne '25' -or
        $loops[2].Groups[1].Value -cne '5' -or $loops[3].Groups[1].Value -cne '4' -or
        [int]$loops[1].Groups[1].Value -lt 24 -or [int]$loops[1].Groups[1].Value -gt 100){
        throw 'Foreign public driver operation layout needs explicit protocol review'
    }
    return [int]$loops[1].Groups[1].Value
}

function Get-ForeignContractOutput {
    param([ValidateRange(24,100)][int]$HookMaximum,[switch]$WithoutPrivateLockReentry)
    $lines=@(1..25|ForEach-Object{"PASS: foreign-continuation-$_"})
    $lines+=@(1..$HookMaximum|Where-Object{$_ -ne 6 -and (-not $WithoutPrivateLockReentry -or $_ -ne 24)}|
        ForEach-Object{"PASS: foreign-hook-$_"})
    $lines+=@(1..5|ForEach-Object{"PASS: foreign-math-reopen-$_"})
    $lines+=@(1..4|ForEach-Object{"PASS: foreign-library-opener-$_"})
    return ($lines -join "`n")+"`nPASS: public foreign contract`n"
}

function Assert-ForeignContractEvidence {
    param([Parameter(Mandatory)][Collections.IDictionary]$Report,
          [Parameter(Mandatory)][string]$Context,
          [ValidateRange(24,100)][int]$HookMaximum,
          [Parameter(Mandatory)][scriptblock]$ResolveCapture)
    $parts=$Context.Split('/');$instrumented=$parts[0] -ceq 'upstream-test'
    $libraryType=if($parts[3] -ceq 'shared'){'relocatable'}else{$parts[3]}
    $contract=$Report.foreign_contract
    $skip=if($instrumented){1}else{0}
    $fullCount=25+$HookMaximum-1+5+4
    $expectedArguments=@();$omitted=@()
    if($instrumented){$expectedArguments=@('--without-release-reentry');$omitted=@('foreign-hook-24')}
    foreach($field in @('hook_case_maximum','matched_cases','skipped_native_lock_cases')){
        if($contract[$field] -isnot [int] -and $contract[$field] -isnot [long]){throw 'Foreign case counts must be integral observations'}
    }
    if($contract.hook_case_maximum -ne $HookMaximum -or $contract.matched_cases -ne $fullCount-$skip -or
        $contract.skipped_native_lock_cases -ne $skip -or $contract.native_omitted_cases -isnot [Array] -or
        (ConvertTo-Json -InputObject $contract.native_omitted_cases -Compress) -cne (ConvertTo-Json -InputObject @($omitted) -Compress)){
        throw 'Foreign source-bound case counts or native private lock omissions differ'
    }
    $paired=Get-ForeignContractOutput -HookMaximum $HookMaximum -WithoutPrivateLockReentry:$instrumented
    $full=Get-ForeignContractOutput -HookMaximum $HookMaximum
    $fullName=if($instrumented){'foreign-full-api'}else{'foreign-api'}
    if($contract.ada_full_consumer -cne $fullName){throw 'Foreign complete Ada observation is missing or identifies a reduced process'}
    $pairedAda=@($Report.consumers|Where-Object name -CEQ 'foreign-api')
    if($pairedAda.Count -ne 1){throw 'Foreign paired Ada observation missing or duplicate'}
    $names=@('foreign-api','foreign-oracle')
    if($instrumented){$names+='foreign-full-api'}
    foreach($name in $names){
        $record=@($Report.consumers|Where-Object name -CEQ $name)
        if($record.Count -ne 1){throw 'Foreign actual operation observation missing or duplicate'}
        $record=$record[0]
        $arguments=@()
        if($name -cne 'foreign-full-api'){$arguments=$expectedArguments}
        if($record.arguments -isnot [Array] -or
            (ConvertTo-Json -InputObject $record.arguments -Compress) -cne (ConvertTo-Json -InputObject @($arguments) -Compress) -or
            $record.exit_code -ne 0 -or $record.timed_out -ne $false -or
            $record.configuration -cne $parts[0] -or $record.profile -cne $parts[2] -or $record.library_type -cne $libraryType){
            throw 'Foreign actual process mode, context or completion differs'
        }
        if($name -ceq 'foreign-full-api' -and ($record.executable -cne $pairedAda[0].executable -or
            $record.executable_sha256 -cne $pairedAda[0].executable_sha256)){
            throw 'Foreign full Ada operation uses a different executable image'
        }
        $out=&$ResolveCapture $record.stdout $record.stdout_sha256
        $err=&$ResolveCapture $record.stderr $record.stderr_sha256
        $expected=if($name -ceq $fullName){$full}else{$paired}
        if((Get-Item -LiteralPath $err).Length -ne 0 -or [IO.File]::ReadAllText($out).Replace("`r`n","`n") -cne $expected){
            throw 'Foreign complete ordered public protocol differs'
        }
    }
}

Export-ModuleMember -Function Get-ForeignContractHookMaximum, Get-ForeignContractOutput, Assert-ForeignContractEvidence
