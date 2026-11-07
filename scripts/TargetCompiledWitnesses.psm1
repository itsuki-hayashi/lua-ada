Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')

function Test-TargetCompiledWitnesses {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][Collections.IDictionary] $Mapping,
          [Parameter(Mandatory)][Collections.IDictionary] $Report,[Parameter(Mandatory)][string] $ArtifactRoot,
          [Parameter(Mandatory)][string] $Context,[Parameter(Mandatory)][string] $Revision,
          [Parameter(Mandatory)][string] $CompilerSha256)
    # Compiled declarations are not invented runtime calls. Their source-bound
    # probes still require actual compiler success, an identified output image,
    # and its executed, exact observed assertion/witness protocol.
    if($Mapping.kind -cne 'target-compiled-witness-mapping' -or $Report.schema_version -ne 1 -or
        $Report.kind -cne 'target-compiled-context-observations' -or $Report.context -cne $Context -or
        $Report.revision -cne $Revision -or $Report.repository_dirty -ne $false -or
        $Report.synthetic_fixture -isnot [bool] -or $Report.synthetic_fixture -or
        $CompilerSha256 -cnotmatch '^[0-9a-f]{64}$' -or $Report.compiler_sha256 -cne $CompilerSha256 -or
        [string]::IsNullOrWhiteSpace([string]$Report.source_root)){throw 'Compiled witness report lacks actual matching context/revision evidence'}
    $expected=@($Mapping.cases|Where-Object{ $Context -cin $_.contexts })
    if($expected.Count -eq 0 -or @($Report.cases).Count -ne $expected.Count){throw 'Compiled witness case set is incomplete'}
    $seen=@{};$result=@{}
    foreach($case in $expected){
        $matches=@($Report.cases|Where-Object id -CEQ $case.id)
        if($matches.Count -ne 1 -or $seen.ContainsKey($case.id) -or [string]::IsNullOrWhiteSpace([string]$case.required_stdout_line)){
            throw 'Compiled witness identity missing duplicated or without a reviewed observation'
        }
        $seen[$case.id]=$true;$actual=$matches[0]
        if(@($case.source_bindings).Count -eq 0 -or @($actual.source_bindings).Count -ne @($case.source_bindings).Count){
            throw 'Compiled witness source/header binding set differs'
        }
        foreach($source in $case.source_bindings){
            [void](Resolve-ReviewedFile -Root $Root -Path $source.path -Sha256 $source.sha256)
            if(@($actual.source_bindings|Where-Object{ $_.path -ceq $source.path -and $_.sha256 -ceq $source.sha256 }).Count -ne 1){
                throw 'Compiled witness used different original or implementation header/source bytes'
            }
        }
        foreach($kind in @('compile','execution')){
            $process=$actual[$kind]
            if($null -eq $process -or $process.exit_code -ne 0 -or $process.timed_out -ne $false -or
                $process.capture_exceeded -ne $false -or $process.pipe_drain_failed -ne $false -or
                $process.process_tree_kill_error -or $process.abnormal_exit_kind -or
                $process.executable_sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Compiled witness compiler or execution did not finish cleanly'}
            foreach($stream in @('stdout','stderr')){
                $original=$process["${stream}_path"].Replace('\','/')
                $offset=$original.LastIndexOf('/reports/',[StringComparison]::Ordinal)
                if($offset -lt 0){throw 'Compiled witness capture is outside reports'}
                $fullRoot=[IO.Path]::GetFullPath($ArtifactRoot)
                $path=[IO.Path]::GetFullPath((Join-Path $fullRoot $original.Substring($offset+1)))
                $relative=[IO.Path]::GetRelativePath($fullRoot,$path).Replace('\','/')
                if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or
                    (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $process["${stream}_sha256"] -or
                    (Get-Item -LiteralPath $path).Length -ne $process["${stream}_bytes"]){throw 'Compiled witness capture path/hash/length differs'}
                if($stream -ceq 'stderr' -and (Get-Item -LiteralPath $path).Length -ne 0){throw 'Compiled witness has unreviewed compiler/execution stderr'}
                if($kind -ceq 'execution' -and $stream -ceq 'stdout'){
                    if([IO.File]::ReadAllText($path).Replace("`r`n","`n") -cne ($case.required_stdout_line+"`n")){
                        throw 'Compiled witness exact observed assertion line differs'
                    }
                }
            }
            $field=if($kind -ceq 'compile'){'compile_arguments'}else{'execution_arguments'}
            if(-not $case.Contains($field) -or $case[$field] -isnot [Collections.IList]){throw 'Compiled witness lacks reviewed argument protocol'}
            $arguments=@($case[$field]|ForEach-Object{ $_.Replace('\','/') })
            $observedArguments=@($process.arguments|ForEach-Object{
                $_.Replace('\','/').Replace($Report.source_root.Replace('\','/'),'{root}')
            })
            if(($observedArguments-join [char]0) -cne ($arguments-join [char]0) -or $observedArguments.Count -ne $arguments.Count){
                throw 'Compiled witness did not use its reviewed compiler/execution arguments'
            }
        }
        $artifact=$actual.artifact
        $original=$artifact.path.Replace('\','/');$offset=$original.LastIndexOf('/reports/',[StringComparison]::Ordinal)
        if($offset -lt 0){throw 'Compiled witness executable artifact is outside reports'}
        $path=[IO.Path]::GetFullPath((Join-Path $ArtifactRoot $original.Substring($offset+1)))
        $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($ArtifactRoot),$path).Replace('\','/')
        if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal)){throw 'Compiled executable artifact escapes reports'}
        if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $artifact.sha256 -or
            $actual.execution.executable_sha256 -cne $artifact.sha256 -or
            $actual.compile.executable_sha256 -cne $Report.compiler_sha256){throw 'Compiled witness executable/compiler identity differs'}
        $result[$case.id]=@{context=$Context;revision=$Revision;runtime_observed=$true;actual_evidence=$true;
            validation_kind='verified-compiled-context-witness';artifact_sha256=$artifact.sha256;
            runtime_acceptance=$false;coverage_authority=$false}
    }
    return $result
}

Export-ModuleMember -Function Test-TargetCompiledWitnesses
