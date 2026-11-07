Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ConformanceRunner.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceInventory.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')

function Get-HeaderProfileFields([string] $Source) {
    $main=$Source.Substring($Source.IndexOf('int main(void)'))
    $fields=@('cplusplus','stdc_version','user_header')
    foreach($match in [regex]::Matches($main,'TYPE\(([^)]+)\)')){$fields+=@(('sizeof.'+$match.Groups[1].Value),('alignof.'+$match.Groups[1].Value))}
    foreach($match in [regex]::Matches($main,'FIELD\(([^,]+),\s*([^)]+)\)')){$fields+='offsetof.'+$match.Groups[1].Value+'.'+$match.Groups[2].Value}
    foreach($match in [regex]::Matches($main,'(?:VALUE|TEXT)\((\w+)\)')){$fields+=$match.Groups[1].Value}
    foreach($match in [regex]::Matches($main,'TOKENS\((\w+)\)')){$fields+='tokens.'+$match.Groups[1].Value}
    if($fields.Count -ne @($fields|Sort-Object -Unique).Count){throw 'Header profile source contains duplicate measurement keys'}
    $sorted=[string[]]$fields;[Array]::Sort($sorted,[StringComparer]::Ordinal)
    return ,$sorted
}

function New-HeaderDeclarationMapping {
    param([Parameter(Mandatory)][string] $Root)
    Test-ConformanceReferenceTree -Root $Root
    $suite=Get-Content (Join-Path $Root 'tests/conformance/suite.json') -Raw|ConvertFrom-Json -AsHashtable -Depth 32
    $api=@(Get-Content (Join-Path $Root 'tests/conformance/c-api.jsonl')|ForEach-Object{$_|ConvertFrom-Json -AsHashtable -Depth 32})
    $anchors=@($api|Where-Object{ $_.kind -ceq 'type' -or ($_.kind -ceq 'macro' -and $_.declaration -cnotmatch '^#define\s+[A-Za-z_][A-Za-z0-9_]*\(') })
    if($api.Count -ne 473 -or $anchors.Count -ne 228){throw 'Original declaration candidate inventory changed'}
    function Anchor-Identity($Entry){$value=[ordered]@{};foreach($field in @('id','header','kind','name','line','byte_offset','byte_length','anchor_sha256','declaration','conditions')){$value[$field]=$Entry[$field]};return $value}
    $anchors=@($anchors|ForEach-Object{Anchor-Identity $_})
    $ids=@($anchors.id)
    $applicability=@($api|Where-Object{ $_.id -cnotin $ids -and $_.conditions.Count -gt 0 }|ForEach-Object{Anchor-Identity $_})
    $source='tests/conformance/header_declarations.c';$hash=(Get-FileHash (Join-Path $Root $source)).Hash.ToLowerInvariant()
    $bindings=@(@{path=$source;sha256=$hash})
    foreach($script in @('scripts/HeaderDeclarationProbes.psm1','scripts/run-target-compiled-witnesses.ps1','scripts/TargetCompiledWitnesses.psm1')){
        $bindings+=@{path=$script;sha256=(Get-FileHash (Join-Path $Root $script)).Hash.ToLowerInvariant()}
    }
    foreach($directory in @('references/lua','c_api/include/api')){foreach($header in @('lua.h','lauxlib.h','lualib.h','luaconf.h')){
        $path=$directory+'/'+$header;$bindings+=@{path=$path;sha256=(Get-FileHash (Join-Path $Root $path)).Hash.ToLowerInvariant()}
    }}
    $fields=Get-HeaderProfileFields ([IO.File]::ReadAllText((Join-Path $Root $source)))
    $cases=@()
    foreach($context in $suite.acceptance_contexts){
        $parts=$context.Split('/');$modes=@(@{id='public-c';language='c';extra=@()},@{id='public-cpp';language='c++';extra=@()})
        if($parts[0] -ceq 'upstream-test'){$modes+=@(@{id='private-t-c';language='c';extra=@('-DLUA_USER_H=<ltests.h>')},
            @{id='private-t-cpp';language='c++';extra=@('-DLUA_USER_H=<ltests.h>')})}
        if($parts[1] -ceq 'windows'){foreach($language in @('c','c++')){foreach($role in @('import','export')){
            $extra=@('-DLUA_BUILD_AS_DLL');if($role -ceq 'export'){$extra+='-DLUA_CORE'}
            $modes+=@{id=('dll-'+$role+'-'+$(if($language -ceq 'c'){'c'}else{'cpp'}));language=$language;extra=$extra}
        }}}
        foreach($mode in $modes){
            $id='header-'+$context.Replace('/','-')+'-'+$mode.id
            $directory='{root}/reports/target-builds/'+$context.Replace('/','-')+'/compiled/'+$id
            $common=@('-x',$mode.language,('-std='+$(if($mode.language -ceq 'c'){'c11'}else{'c++17'})),
                '-Wall','-Wextra','-Werror','-pedantic')
            $common+=if($parts[1] -ceq 'linux'){@('-DLUA_USE_LINUX')}elseif($parts[1] -ceq 'macos'){@('-DLUA_USE_MACOSX')}else{@()}
            $common+=@($mode.extra)
            $sides=@{}
            foreach($side in @('sdk','native')){
                $include=if($side -ceq 'sdk'){'c_api/include/api'}else{'references/lua'}
                $arguments=$common+@('-I',('{root}/'+$include),'-I','{root}/references/lua')
                $output=$directory+'/'+$side+$(if($parts[1] -ceq 'windows'){'.exe'}else{''})
                $sides[$side]=@{compile_arguments=($arguments+@(('{root}/'+$source),'-o',$output));output=$output;
                    preprocessing_arguments=($arguments+@('-E','-dD',('{root}/'+$source)));
                    final_macros_arguments=($arguments+@('-E','-dM',('{root}/'+$source)));execution_arguments=@()}
            }
            $sourceBindings=@($bindings)
            if($mode.id.StartsWith('private-t-')){$sourceBindings+=@{path='references/lua/ltests.h';sha256=(Get-FileHash (Join-Path $Root 'references/lua/ltests.h')).Hash.ToLowerInvariant()}}
            $cases+=@{id=$id;protocol='paired-header-profile-v1';contexts=@($context);mode=$mode.id;language=$mode.language;
                source=@{path=$source;sha256=$hash};source_bindings=$sourceBindings;profile_fields=$fields;
                profile_assertions=@{LUA_VERSION_NUM=505;LUA_VERSION_RELEASE_NUM=50501;
                    'sizeof.lua_Integer'=8;'sizeof.lua_Unsigned'=8;'sizeof.lua_Number'=8;LUA_VERSION='Lua 5.5';LUA_RELEASE='Lua 5.5.1'};
                required_stdout_line='HEADER-PROFILE-V1';sides=$sides;global_classification_review_status='pending';
                runtime_acceptance=$false;coverage_authority=$false}
        }
    }
    return @{schema_version=1;kind='target-compiled-witness-mapping';target='remaining-upstream-compatibility';
        reference_revision=$suite.reference_revision;author='Codex /root/validation_delivery';
        independent_review_status='pending';runtime_acceptance=$false;coverage_authority=$false;execution_evidence=@();
        api_anchors=$anchors;applicability_anchors=$applicability;cases=$cases;review=@{status='pending';author='Codex /root/validation_delivery';reviewer=$null;artifact=$null;artifact_sha256=$null};
        boundaries=@('Declaration/type/header observations only; no Lua implementation is linked and no Lua API executes.',
            'Public C/C++ consumers, DLL import/export declarations and private T callers are distinct modes.',
            'Private T extraspace and buffer declarations do not certify ordinary SDK extraspace mutation or runtime representation.',
            'All function/data entries and behavioral macros retain independently reviewed actual runtime routes.',
            'All 473 global semantic classifications and coverage ledger entries remain pending.')}
}

function Invoke-HeaderDeclarationPair {
    param([Parameter(Mandatory)][string] $Root,[Parameter(Mandatory)][string] $Compiler,
          [Parameter(Mandatory)][Collections.IDictionary] $Case)
    $compilerPath=(Resolve-Path -LiteralPath $Compiler).Path
    foreach($binding in $Case.source_bindings){[void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)}
    $records=@{}
    # GCC's driver digest alone does not identify its C++ parser. Resolve the
    # real selected frontend through that same driver, retain its bytes/hash
    # identity and capture the query for the frozen-image consumer to replay.
    $queryName=if($Case.language -ceq 'c++'){'cc1plus'}else{'cc1'}
    $firstOutput=[IO.Path]::GetFullPath($Case.sides.sdk.output.Replace('{root}',$Root))
    $queryDirectory=Split-Path -Parent $firstOutput
    [void][IO.Directory]::CreateDirectory($queryDirectory)
    $query=Invoke-ConformanceProcess -Executable $compilerPath -Arguments @('-print-prog-name='+$queryName) -Directory $Root `
        -OutputPrefix (Join-Path $queryDirectory 'frontend-query') -TimeoutSeconds 30 `
        -Environment @{PATH=((Split-Path -Parent $compilerPath)+[IO.Path]::PathSeparator+$env:PATH)}
    if($query.exit_code -ne 0 -or $query.timed_out -or $query.stderr_bytes -ne 0){throw 'Cannot identify actual header probe compiler frontend'}
    $reportedFrontend=[IO.File]::ReadAllText($query.stdout_path).Trim()
    if(-not [IO.Path]::IsPathRooted($reportedFrontend) -or -not (Test-Path -LiteralPath $reportedFrontend -PathType Leaf)){
        throw 'Selected C/C++ header probe frontend is unavailable'
    }
    $frontend=@{path=[IO.Path]::GetFullPath($reportedFrontend);reported_path=$reportedFrontend;
        sha256=(Get-FileHash $reportedFrontend).Hash.ToLowerInvariant();query=$query}
    foreach($side in @('sdk','native')){
        $spec=$Case.sides[$side];$artifact=[IO.Path]::GetFullPath($spec.output.Replace('{root}',$Root))
        $relative=[IO.Path]::GetRelativePath($Root,$artifact).Replace('\','/')
        if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or (Test-Path -LiteralPath $artifact)){throw 'Header probe output must be a new reports executable'}
        $directory=Split-Path -Parent $artifact;[void][IO.Directory]::CreateDirectory($directory)
        $processes=@{}
        foreach($operation in @('preprocessing','final_macros','compile')){
            $arguments=@($spec[$operation+'_arguments']|ForEach-Object{$_.Replace('{root}',$Root)})
            $p=Invoke-ConformanceProcess -Executable $compilerPath -Arguments $arguments -Directory $Root `
                -OutputPrefix (Join-Path $directory ($side+'-'+$operation)) -TimeoutSeconds 120 `
                -Environment @{PATH=((Split-Path -Parent $compilerPath)+[IO.Path]::PathSeparator+$env:PATH)}
            if($p.exit_code -ne 0 -or $p.timed_out -or $p.capture_exceeded -or $p.pipe_drain_failed -or $p.process_tree_kill_error -or
                $p.abnormal_exit_kind -or $p.stderr_bytes -ne 0){throw "Header probe compiler failed: $($p.stderr_path)"}
            $processes[$operation]=$p
        }
        if(-not (Test-Path -LiteralPath $artifact)){throw 'Header compiler did not produce its executable'}
        $p=Invoke-ConformanceProcess -Executable $artifact -Arguments @($spec.execution_arguments) -Directory $Root `
            -OutputPrefix (Join-Path $directory ($side+'-execution')) -TimeoutSeconds 30 `
            -Environment @{PATH=((Split-Path -Parent $compilerPath)+[IO.Path]::PathSeparator+$env:PATH)}
        $processes.execution=$p
        $records[$side]=@{artifact=@{path=$artifact;sha256=(Get-FileHash $artifact).Hash.ToLowerInvariant()};
            processes=$processes;runtime_acceptance=$false;coverage_authority=$false}
    }
    return @{id=$Case.id;protocol=$Case.protocol;source_bindings=$Case.source_bindings;sides=$records;frontend=$frontend;
        runtime_acceptance=$false;coverage_authority=$false}
}

function Read-HeaderDefinitionProfile {
    param([Parameter(Mandatory)][string] $Path,[Parameter(Mandatory)][string] $SourceRoot,
          [Parameter(Mandatory)][ValidateSet('sdk','native')][string] $Side,
          [Parameter(Mandatory)][object[]] $Anchors)
    # C identifiers are case sensitive: LUA_INTEGER and lua_Integer must not
    # collapse into PowerShell's ordinary case-insensitive Hashtable lookup.
    $wanted=[Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::Ordinal)
    foreach($anchor in $Anchors|Where-Object kind -CEQ macro){$wanted[$anchor.name]=$true}
    $history=@();$line=0;$file='';$sdk=$SourceRoot.Replace('\','/').TrimEnd('/')+'/c_api/include/api/'
    $native=$SourceRoot.Replace('\','/').TrimEnd('/')+'/references/lua/'
    foreach($text in [IO.File]::ReadAllLines($Path)){
        if($text -cmatch '^#\s+([0-9]+)\s+"((?:\\.|[^"\\])*)"(?:\s+[0-9 ]+)?$'){
            $line=[int]$Matches[1]
            $file=('"'+$Matches[2]+'"'|ConvertFrom-Json).Replace('\','/')
            continue
        }
        if($text -cmatch '^#(define|undef)\s+([A-Za-z_][A-Za-z0-9_]*)(.*)$'){
            $action=$Matches[1];$name=$Matches[2];$tail=$Matches[3]
            if($wanted.ContainsKey($name)){
                $origin=if($file.StartsWith($sdk,[StringComparison]::Ordinal)){'sdk/'+$file.Substring($sdk.Length)}
                    elseif($file.StartsWith($native,[StringComparison]::Ordinal)){'native/'+$file.Substring($native.Length)}else{$file}
                # Do not let an SDK compile silently use the oracle's public
                # header (or the reverse) because an include guard masked it.
                $header=[IO.Path]::GetFileName($file)
                if($header -cin @('lua.h','lauxlib.h','lualib.h','luaconf.h') -and -not $origin.StartsWith($Side+'/',[StringComparison]::Ordinal)){
                    throw 'Header probe used the other counterpart public header tree'
                }
                if($origin -ceq 'native/ltests.h'){$origin='private/ltests.h'}
                elseif($origin.StartsWith($Side+'/',[StringComparison]::Ordinal)){$origin='public/'+$origin.Substring($Side.Length+1)}
                $history+=@{action=$action;name=$name;origin=$origin;line=$line;body=$tail.Trim()}
            }
        }
        $line++
    }
    if($history.Count -eq 0){throw 'Header preprocessing capture contains no original declaration definitions'}
    return ,$history
}

function Get-HeaderDirectiveTokens([string] $Text) {
    $logical=[regex]::Replace($Text,'\\\r?\n','')
    $tokens=@([regex]::Matches($logical,'/\*.*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|##|<<|>>|<=|>=|==|!=|&&|\|\||\+\+|--|->|\.\.\.|[^\s]',[Text.RegularExpressions.RegexOptions]::Singleline)|
        ForEach-Object Value|Where-Object{ -not $_.StartsWith('/*') -and -not $_.StartsWith('//') })
    return ($tokens -join [char]0)
}

function Assert-HeaderDefinitionOrigins {
    param([string] $Root,[string] $Side,[object[]] $History)
    $sources=@{}
    foreach($event in $History){
        $relative=if($event.origin.StartsWith('public/')){
            $(if($Side -ceq 'sdk'){'c_api/include/api/'}else{'references/lua/'})+$event.origin.Substring(7)
        }elseif($event.origin -ceq 'private/ltests.h'){'references/lua/ltests.h'}else{throw 'Header declaration has an unbound definition origin'}
        if(-not $sources.ContainsKey($relative)){$sources[$relative]=[IO.File]::ReadAllLines((Join-Path $Root $relative))}
        $lines=$sources[$relative];$index=[int]$event.line-1
        if($index -lt 0 -or $index -ge $lines.Count){throw 'Header definition origin line is outside its bound source'}
        $directive=$lines[$index]
        while($directive.EndsWith('\',[StringComparison]::Ordinal)){
            $index++;if($index -ge $lines.Count){throw 'Header continued definition origin is truncated'}
            $directive+="`n"+$lines[$index]
        }
        $observed='#'+$event.action+' '+$event.name+$(if($event.body -ne ''){' '+$event.body}else{''})
        if((Get-HeaderDirectiveTokens $directive) -cne (Get-HeaderDirectiveTokens $observed)){
            throw "Header definition origin does not reproduce its exact source directive: $relative`:$($event.line) $($event.name)"
        }
    }
}

function Get-HeaderProbePayloadHash([object] $Value) {
    function Canonical([object] $Item){
        if($Item -is [Collections.IDictionary]){$result=[ordered]@{};$keys=[string[]]@($Item.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal);foreach($key in $keys){$result[$key]=Canonical $Item[$key]};return $result}
        if($Item -is [Collections.IList]){return ,@($Item|ForEach-Object{Canonical $_})}
        return $Item
    }
    return Get-ConformanceHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject (Canonical $Value) -Compress -Depth 64)))
}

function Assert-HeaderDeclarationMapping {
    param([string] $Root,[Collections.IDictionary] $Mapping)
    if($Mapping.schema_version -ne 1 -or $Mapping.kind -cne 'target-compiled-witness-mapping' -or
        $Mapping.target -cne 'remaining-upstream-compatibility' -or $Mapping.runtime_acceptance -isnot [bool] -or $Mapping.runtime_acceptance -or
        $Mapping.coverage_authority -isnot [bool] -or $Mapping.coverage_authority){throw 'Paired header mapping identity or authority differs'}
    $actual=New-HeaderDeclarationMapping -Root $Root
    # The generated schedule is closed over every real context/language/mode.
    # A caller cannot drop the C++ or DLL observation which selects a branch
    # while retaining an easier counterpart where that branch is inactive.
    foreach($field in @('api_anchors','applicability_anchors','cases')){
        if((Get-HeaderProbePayloadHash $Mapping[$field]) -cne (Get-HeaderProbePayloadHash $actual[$field])){
            throw "Paired header source or complete probe schedule differs: $field"
        }
    }
}

function Get-HeaderDeclarationReviewClaims([Collections.IDictionary] $Mapping) {
    # The approval binds executable source, every input hash and the full
    # configuration/argument schedule. Exclude only the approval's own link
    # so that its content-addressed identity does not become circular.
    return [ordered]@{scope='header-probe-source-and-configuration';target=$Mapping.target;
        reference_revision=$Mapping.reference_revision;api_anchors=$Mapping.api_anchors;
        applicability_anchors=$Mapping.applicability_anchors;cases=$Mapping.cases;
        global_api_classifications_accepted=$false;runtime_acceptance=$false}
}

function Assert-HeaderDeclarationSourceReview {
    param([string] $Root,[Collections.IDictionary] $Mapping,[switch] $AllowSynthetic)
    $review=$Mapping.review
    if($review.status -cne 'accepted' -or [string]::IsNullOrWhiteSpace([string]$review.author) -or
        [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or $review.author -ceq $review.reviewer){
        throw 'Paired header source/configuration requires accepted independent review'
    }
    $path=Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    if($approval.schema_version -ne 1 -or $approval.kind -cne 'header-declaration-probe-source-approval' -or
        $approval.scope -cne 'header-probe-source-and-configuration' -or $approval.decision -cne 'accepted' -or
        $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
        $approval.synthetic_fixture -isnot [bool] -or ($approval.synthetic_fixture -and -not $AllowSynthetic) -or
        $approval.global_api_classifications_accepted -isnot [bool] -or $approval.global_api_classifications_accepted -or
        $approval.runtime_acceptance -isnot [bool] -or $approval.runtime_acceptance -or
        $approval.claims_sha256 -cne (Get-HeaderProbePayloadHash (Get-HeaderDeclarationReviewClaims $Mapping))){
        throw 'Paired header source approval scope original bytes configuration or authority differs'
    }
    $expected=@{type_layout='eligible-compiled-candidate';object_macro='eligible-compiled-candidate';
        callable_function='runtime-required';behavioral_macro='runtime-required';conditional_behavioral_applicability='not-runtime-evidence'}
    foreach($name in $expected.Keys){if($approval.category_decisions[$name] -cne $expected[$name]){throw 'Paired header review reclassified callable behavior as a declaration'}}
    $evidence=Resolve-ReviewedFile -Root $Root -Path $approval.review_evidence.path -Sha256 $approval.review_evidence.sha256
    $narrative=Get-Content $evidence -Raw|ConvertFrom-Json -AsHashtable -Depth 64
    if($narrative.reviewer -cne $review.reviewer -or $narrative.decision -cne 'accepted' -or
        $narrative.claims_sha256 -cne $approval.claims_sha256 -or $narrative.synthetic_fixture -isnot [bool] -or
        ($narrative.synthetic_fixture -and -not $AllowSynthetic) -or
        [string]::IsNullOrWhiteSpace([string]$narrative.source_and_configuration_findings) -or
        [string]::IsNullOrWhiteSpace([string]$narrative.behavioral_and_runtime_boundaries)){
        throw 'Paired header actual independent source review narrative differs'
    }
    return @{source_reviewed=$true;scope=$approval.scope;global_api_classifications_accepted=$false;runtime_acceptance=$false}
}

function Resolve-HeaderProbeArtifact([string] $Root,[string] $Original,[string] $Hash) {
    $text=$Original.Replace('\','/');$offset=$text.LastIndexOf('/reports/',[StringComparison]::Ordinal)
    if($offset -lt 0 -or $Hash -cnotmatch '^[0-9a-f]{64}$'){throw 'Header probe artifact is outside reports or lacks its hash'}
    $path=[IO.Path]::GetFullPath((Join-Path $Root $text.Substring($offset+1)))
    $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$path).Replace('\','/')
    if(-not $relative.StartsWith('reports/',[StringComparison]::Ordinal) -or (Get-FileHash $path).Hash.ToLowerInvariant() -cne $Hash){
        throw 'Header probe artifact bytes or path differ'
    }
    return $path
}

function Assert-HeaderProbeProcess {
    param([Collections.IDictionary] $Process,[string[]] $Arguments,[string] $SourceRoot,[string] $ArtifactRoot,[string] $ExecutableSha256)
    if($Process.executable_sha256 -cne $ExecutableSha256 -or $ExecutableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $Process.exit_code -ne 0 -or $Process.timed_out -ne $false -or $Process.capture_exceeded -ne $false -or
        $Process.pipe_drain_failed -ne $false -or $Process.process_tree_kill_error -or $Process.abnormal_exit_kind -or
        $Process.stderr_bytes -ne 0 -or $Process.arguments -isnot [Array] -or
        $Process.working_directory.Replace('\','/') -cne $SourceRoot.Replace('\','/')){
        throw 'Paired header compiler/execution identity or completion differs'
    }
    $observed=@($Process.arguments|ForEach-Object{$_.Replace('\','/').Replace($SourceRoot.Replace('\','/'),'{root}')})
    if($observed.Count -ne $Arguments.Count -or ($observed -join [char]0) -cne ($Arguments -join [char]0)){
        throw 'Paired header exact compiler/execution arguments differ'
    }
    $paths=@{}
    foreach($stream in @('stdout','stderr')){
        $paths[$stream]=Resolve-HeaderProbeArtifact -Root $ArtifactRoot -Original $Process["${stream}_path"] -Hash $Process["${stream}_sha256"]
        if((Get-Item $paths[$stream]).Length -ne $Process["${stream}_bytes"]){throw 'Paired header capture byte count differs'}
    }
    return $paths
}

function Read-HeaderProfileValues([string] $Path,[Collections.IDictionary] $Case) {
    $text=[IO.File]::ReadAllText($Path)
    if($text -cnotmatch '^HEADER-PROFILE-V1 (\{[^\r\n]+\})\r?\n$'){throw 'Paired header measurement protocol is missing or contains extra records'}
    $json=$Matches[1];$document=[Text.Json.JsonDocument]::Parse($json)
    try{
        $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $document.RootElement.EnumerateObject()){
            if(-not $keys.Add($property.Name) -or $property.Value.ValueKind.ToString() -cnotin @('String','Number')){
                throw 'Paired header measurement contains duplicate or non-scalar fields'
            }
        }
        if(-not $keys.SetEquals([string[]]$Case.profile_fields)){throw 'Paired header measured field set differs'}
    }finally{$document.Dispose()}
    $values=$json|ConvertFrom-Json -AsHashtable -Depth 8
    foreach($name in $Case.profile_assertions.Keys){if($values[$name] -cne $Case.profile_assertions[$name]){throw 'Paired header fixed public ABI/version assertion differs'}}
    if($values.cplusplus -ne $(if($Case.language -ceq 'c++'){201703}else{0}) -or
        $values.stdc_version -ne $(if($Case.language -ceq 'c'){201112}else{0}) -or
        $values.user_header -ne $(if($Case.mode.StartsWith('private-t-')){1}else{0}) -or
        ($Case.mode.StartsWith('private-t-') -and $values.LUAL_BUFFERSIZE -ne 23)){
        throw 'Paired header actual language or private/public role differs'
    }
    return $values
}

function Test-HeaderDeclarationPair {
    param([string] $Root,[string] $ArtifactRoot,[string] $SourceRoot,[string] $CompilerSha256,
          [Collections.IDictionary] $Mapping,[Collections.IDictionary] $Case,[Collections.IDictionary] $Record)
    if($Case.protocol -cne 'paired-header-profile-v1' -or $Record.protocol -cne $Case.protocol -or
        $Record.id -cne $Case.id -or @($Record.source_bindings).Count -ne @($Case.source_bindings).Count){throw 'Paired header record identity or source bindings differ'}
    if($Record.runtime_acceptance -isnot [bool] -or $Record.runtime_acceptance -or
        $Record.coverage_authority -isnot [bool] -or $Record.coverage_authority){throw 'Paired header observation cannot claim API or target acceptance'}
    if($Record.sides -isnot [Collections.IDictionary] -or $Record.sides.Count -ne 2 -or
        -not $Record.sides.Contains('sdk') -or -not $Record.sides.Contains('native')){throw 'Paired header SDK/native counterpart is missing or duplicated'}
    foreach($binding in $Case.source_bindings){
        [void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)
        if(@($Record.source_bindings|Where-Object{ $_.path -ceq $binding.path -and $_.sha256 -ceq $binding.sha256 }).Count -ne 1){throw 'Paired header actual source bindings differ'}
    }
    $queryName=if($Case.language -ceq 'c++'){'cc1plus'}else{'cc1'}
    $queryPaths=Assert-HeaderProbeProcess -Process $Record.frontend.query -Arguments @('-print-prog-name='+$queryName) `
        -SourceRoot $SourceRoot -ArtifactRoot $ArtifactRoot -ExecutableSha256 $CompilerSha256
    $reportedFrontend=[IO.File]::ReadAllText($queryPaths.stdout).Trim()
    if($Record.frontend.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $Record.frontend.reported_path -cne $reportedFrontend -or
        [IO.Path]::GetFileName($Record.frontend.path.Replace('\','/')) -cnotin @($queryName,($queryName+'.exe'))){
        throw 'Paired header actual frontend identity or query differs'
    }
    $histories=@{};$macros=@{};$profiles=@{}
    $allAnchors=@($Mapping.api_anchors)+@($Mapping.applicability_anchors)
    $macroNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($anchor in $allAnchors|Where-Object kind -CEQ macro){[void]$macroNames.Add($anchor.name)}
    foreach($side in @('sdk','native')){
        $value=$Record.sides[$side];$spec=$Case.sides[$side]
        $artifact=Resolve-HeaderProbeArtifact -Root $ArtifactRoot -Original $value.artifact.path -Hash $value.artifact.sha256
        if($value.artifact.path.Replace('\','/').Replace($SourceRoot.Replace('\','/'),'{root}') -cne $spec.output){throw 'Paired header executable output path differs'}
        $paths=@{}
        foreach($operation in @('preprocessing','final_macros','compile','execution')){
            $toolHash=if($operation -ceq 'execution'){$value.artifact.sha256}else{$CompilerSha256}
            $paths[$operation]=Assert-HeaderProbeProcess -Process $value.processes[$operation] -Arguments @($spec[$operation+'_arguments']) `
                -SourceRoot $SourceRoot -ArtifactRoot $ArtifactRoot -ExecutableSha256 $toolHash
        }
        if($value.processes.execution.executable.Replace('\','/') -cne $value.artifact.path.Replace('\','/')){throw 'Paired header process ran another executable'}
        $profiles[$side]=Read-HeaderProfileValues -Path $paths.execution.stdout -Case $Case
        $histories[$side]=Read-HeaderDefinitionProfile -Path $paths.preprocessing.stdout -SourceRoot $SourceRoot -Side $side -Anchors $allAnchors
        Assert-HeaderDefinitionOrigins -Root $Root -Side $side -History $histories[$side]
        $final=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
        foreach($line in [IO.File]::ReadAllLines($paths.final_macros.stdout)){
            if($line -cmatch '^#define\s+([A-Za-z_][A-Za-z0-9_]*)(.*)$'){
                $name=$Matches[1];if($macroNames.Contains($name)){
                    if($final.ContainsKey($name)){throw 'Paired header final macro dump contains duplicate names'}
                    $final[$name]=$Matches[2].Trim()
                }
            }
        }
        if($final.Count -eq 0){throw 'Paired header final macro dump is empty'}
        foreach($name in $macroNames){
            $events=@($histories[$side]|Where-Object name -CEQ $name)
            if($events.Count){
                $last=$events[-1]
                if(($last.action -ceq 'define' -and (-not $final.ContainsKey($name) -or $final[$name] -cne $last.body)) -or
                    ($last.action -ceq 'undef' -and $final.ContainsKey($name))){throw 'Paired header final macro values disagree with definition history'}
            }elseif($final.ContainsKey($name)){throw "Paired header final declaration lacks its source definition history: $name"}
        }
        $macros[$side]=$final
    }
    if($Record.sides.sdk.processes.execution.stdout_sha256 -cne $Record.sides.native.processes.execution.stdout_sha256 -or
        (Get-HeaderProbePayloadHash $histories.sdk) -cne (Get-HeaderProbePayloadHash $histories.native) -or
        (Get-HeaderProbePayloadHash $macros.sdk) -cne (Get-HeaderProbePayloadHash $macros.native)){
        throw 'Paired SDK/native actual layout profile or original/final macro definitions differ'
    }
    $states=@{}
    foreach($anchor in $allAnchors){
        if($anchor.kind -ceq 'type'){$state='measured-type'}else{
            $events=@($histories.native|Where-Object{ $_.name -ceq $anchor.name -and $_.origin -ceq ('public/'+$anchor.header) -and $_.line -eq $anchor.line -and $_.action -ceq 'define' })
            if($events.Count -gt 1){throw 'Paired header original definition origin is ambiguous'}
            $state=if($events.Count){
                $last=@($histories.native|Where-Object name -CEQ $anchor.name)[-1]
                if($last.origin -ceq $events[0].origin -and $last.line -eq $events[0].line -and $last.action -ceq 'define'){'processed-effective'}else{'processed-overridden'}
            }else{'not-selected'}
        }
        $states[$anchor.id]=@{state=$state;declaration_only=($anchor.id -cin @($Mapping.api_anchors.id));anchor_sha256=$anchor.anchor_sha256}
    }
    return @{protocol='paired-header-profile-v1';actual_evidence=$true;runtime_observed=$true;
        validation_kind='verified-compiled-context-witness';mode=$Case.mode;language=$Case.language;
        measured_fields=$profiles.native.Count;api_anchor_states=$states;runtime_acceptance=$false;coverage_authority=$false}
}

Export-ModuleMember -Function New-HeaderDeclarationMapping, Invoke-HeaderDeclarationPair, Read-HeaderDefinitionProfile,
    Get-HeaderProbePayloadHash, Assert-HeaderDeclarationMapping, Test-HeaderDeclarationPair,
    Get-HeaderDeclarationReviewClaims, Assert-HeaderDeclarationSourceReview
