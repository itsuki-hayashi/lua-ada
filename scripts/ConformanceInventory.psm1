Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ReferenceRevision = '7579fc9d7ed90240487251dfb69168f8e64e9294'
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
Import-Module (Join-Path $PSScriptRoot 'ConformanceReview.psm1')
Import-Module (Join-Path $PSScriptRoot 'ConformanceExclusionEligibility.psm1')
$script:ExclusionBaselines = @(
    @{id='gc-io-events';path='tests/conformance/scopes/gc-io-events.json';
        sha256='79fa732f60f380c93be190f43640acf0b2ac595bdf9196d2fc8fd0a7ee62eae7'},
    @{id='expanded-t-conformance';path='tests/conformance/scopes/expanded-t-conformance.json';
        sha256='9df8642d10238abaa48c97184ed2345be7106d4c2c74668954e43bc0cb6ecdc1'})

# This byte-oriented scanner is an inventory aid, not a second Lua parser.
# It masks comments and quoted/long strings before looking for source anchors.
# Keeping a byte offset for every token makes hashes independent of UTF-8
# decoding and prevents an 'assert' inside a comment from becoming coverage.
if (-not ('LuaAda.ConformanceAnchorsV1' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
namespace LuaAda {
  public sealed class AnchorToken {
    public string Text;
    public int Offset, Length, Line, EndLine;
    public bool IsString;
  }
  public static class ConformanceAnchorsV1 {
    static int LongOpen(byte[] s, int p) {
      if (p >= s.Length || s[p] != 91) return -1;
      int q = p + 1;
      while (q < s.Length && s[q] == 61) q++;
      return q < s.Length && s[q] == 91 ? q - p - 1 : -1;
    }
    static bool NewLine(byte[] s, ref int p, ref int line) {
      if (s[p] != 10 && s[p] != 13) return false;
      byte first = s[p++];
      if (p < s.Length && (s[p] == 10 || s[p] == 13) && s[p] != first) p++;
      line++; return true;
    }
    static void LongBody(byte[] s, ref int p, ref int line, int level) {
      p += level + 2;
      while (p < s.Length) {
        if (NewLine(s, ref p, ref line)) continue;
        if (s[p] == 93) {
          int q = p + 1, n = 0;
          while (q < s.Length && s[q] == 61) { q++; n++; }
          if (n == level && q < s.Length && s[q] == 93) { p = q + 1; return; }
        }
        p++;
      }
      throw new FormatException("Unterminated long string/comment in inventory input");
    }
    public static AnchorToken[] Scan(byte[] source) {
      var tokens = new List<AnchorToken>();
      int p = 0, line = 1;
      while (p < source.Length) {
        if (NewLine(source, ref p, ref line)) continue;
        byte c = source[p];
        if (c == 32 || c == 9 || c == 11 || c == 12) { p++; continue; }
        if (p == 0 && c == 35) {
          while (p < source.Length && source[p] != 10 && source[p] != 13) p++;
          continue;
        }
        if (c == 45 && p + 1 < source.Length && source[p + 1] == 45) {
          p += 2; int level = LongOpen(source, p);
          if (level >= 0) LongBody(source, ref p, ref line, level);
          else while (p < source.Length && source[p] != 10 && source[p] != 13) p++;
          continue;
        }
        int start = p, firstLine = line;
        bool quoted = c == 34 || c == 39;
        int longLevel = LongOpen(source, p);
        if (quoted) {
          p++; bool closed = false;
          while (p < source.Length) {
            if (source[p] == c) { p++; closed = true; break; }
            if (source[p] == 92) {
              p++;
              if (p < source.Length && !NewLine(source, ref p, ref line)) p++;
            } else if (!NewLine(source, ref p, ref line)) p++;
          }
          if (!closed) throw new FormatException("Unterminated quoted string in inventory input");
        } else if (longLevel >= 0) {
          LongBody(source, ref p, ref line, longLevel);
          quoted = true;
        } else if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95) {
          p++;
          while (p < source.Length) {
            byte v = source[p];
            if (!((v >= 65 && v <= 90) || (v >= 97 && v <= 122) ||
                  (v >= 48 && v <= 57) || v == 95)) break;
            p++;
          }
        } else p++;
        tokens.Add(new AnchorToken { Offset = start, Length = p - start,
          Line = firstLine, EndLine = line, IsString = quoted,
          Text = Encoding.Latin1.GetString(source, start, p - start) });
      }
      return tokens.ToArray();
    }
  }
}
'@
}

function Get-ConformanceHash {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Bytes)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-ConformanceTokens {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Bytes)
    return [LuaAda.ConformanceAnchorsV1]::Scan($Bytes)
}

function Get-ConformanceCoverageUnits {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][byte[]] $Bytes)
    $tokens = @(Get-ConformanceTokens -Bytes $Bytes)
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path).ToUpperInvariant()
    $counts = @{}
    $anchors = [Collections.Generic.List[object]]::new()
    # A compulsory manual audit remains pending for every file. Static sites
    # cannot prove that generated source, aliases, data-driven assertions, or
    # platform guards have been semantically inventoried.
    $anchors.Add(@{ kind='manual-audit'; offset=0; length=$Bytes.Length; line=1;
        end_line=1 + [regex]::Matches([Text.Encoding]::Latin1.GetString($Bytes),
            '\r\n|\n\r|\n|\r').Count })
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        $kind = $null
        $length = $token.Length
        $endLine = $token.EndLine
        if ($token.IsString) {
            if ($token.Text -match '\bassert\s*\(') { $kind = 'generated-template' }
        }
        elseif ($token.Text -eq 'if') { $kind = 'conditional-guard' }
        elseif ($token.Text -eq 'assert' -and $i + 1 -lt $tokens.Count -and
                $tokens[$i + 1].Text -eq '(') { $kind = 'assert-call' }
        elseif ($token.Text -eq 'T' -and $i + 2 -lt $tokens.Count -and
                $tokens[$i + 1].Text -eq '.') {
            $kind = 'internal-reference'
            $length = $tokens[$i + 2].Offset + $tokens[$i + 2].Length - $token.Offset
            $endLine = $tokens[$i + 2].EndLine
        }
        elseif ($token.Text -eq 'Message') { $kind = 'skip-report' }
        if ($null -ne $kind) {
            $anchors.Add(@{ kind=$kind; offset=$token.Offset; length=$length;
                line=$token.Line; end_line=$endLine })
        }
    }
    foreach ($anchor in $anchors) {
        $kind = $anchor.kind
        if (-not $counts.ContainsKey($kind)) { $counts[$kind] = 0 }
        $counts[$kind]++
        $span = [byte[]]::new($anchor.length)
        if ($span.Length -gt 0) { [Array]::Copy($Bytes, $anchor.offset, $span, 0, $span.Length) }
        [ordered]@{
            id = 'LUA-' + $stem + '-' + $kind.ToUpperInvariant() + '-' + $counts[$kind].ToString('0000')
            kind = $kind
            byte_offset = $anchor.offset
            byte_length = $anchor.length
            line = $anchor.line
            end_line = $anchor.end_line
            anchor_sha256 = Get-ConformanceHash -Bytes $span
            status = 'pending'
            disposition = 'pending'
            invariant = $null
            configurations = @()
            evidence = @()
            review = $null
        }
    }
}

function Get-ConformanceApiInventory {
    param([Parameter(Mandatory)][string] $Root)
    foreach ($header in @('lua.h', 'lauxlib.h', 'lualib.h', 'luaconf.h')) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $Root "references/lua/$header"))
        $text = [Text.Encoding]::Latin1.GetString($bytes)
        # Spaces replace comments without moving offsets/newlines. This is
        # declaration discovery, not preprocessing: conditional definitions
        # remain distinct entries so neither ABI configuration disappears.
        $masked = [regex]::Replace($text, '(?s)/\*.*?\*/', {
            param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ')
        })
        $entries = [Collections.Generic.List[object]]::new()
        foreach ($m in [regex]::Matches($masked, '(?m)^[ \t]*(?:LUA_API|LUALIB_API|LUAMOD_API)\b[^;]+;')) {
            if ($m.Value -match '\(\s*(lua[A-Za-z_0-9]+)\s*\)') {
                $entries.Add(@{offset=$m.Index;length=$m.Length;kind='function';name=$Matches[1]})
            }
        }
        foreach ($m in [regex]::Matches($masked, '(?m)^[ \t]*extern\b[^;]+;')) {
            if ($m.Value -match '\b(lua[A-Za-z_0-9]+)\s*(?:\[[^\]]*\])?\s*;') {
                $entries.Add(@{offset=$m.Index;length=$m.Length;kind='data';name=$Matches[1]})
            }
        }
        foreach ($m in [regex]::Matches($masked, '(?m)^[ \t]*#[ \t]*define[ \t]+([A-Za-z_][A-Za-z_0-9]*)(?:[^\r\n]*\\\r?\n)*[^\r\n]*')) {
            $entries.Add(@{offset=$m.Index;length=$m.Length;kind='macro';name=$m.Groups[1].Value})
        }
        foreach ($m in [regex]::Matches($masked, '(?m)^[ \t]*typedef\b|^[ \t]*struct[ \t]+([A-Za-z_][A-Za-z_0-9]*)[ \t]*\{')) {
            $start = $m.Index
            $cursor = $start
            $depth = 0
            while ($cursor -lt $masked.Length) {
                $c = $masked[$cursor]
                if ($c -eq '{') { $depth++ }
                elseif ($c -eq '}') { $depth-- }
                elseif ($c -eq ';' -and $depth -eq 0) { $cursor++; break }
                $cursor++
            }
            if ($cursor -gt $start) {
                $declaration = $masked.Substring($start, $cursor - $start)
                $name = $null
                if ($declaration -match '\(\s*\*\s*([A-Za-z_][A-Za-z_0-9]*)\s*\)') { $name = $Matches[1] }
                elseif ($declaration -match '([A-Za-z_][A-Za-z_0-9]*)\s*;\s*$') { $name = $Matches[1] }
                elseif ($declaration -match '^\s*struct\s+([A-Za-z_][A-Za-z_0-9]*)') { $name = $Matches[1] }
                if ($null -ne $name) {
                    $entries.Add(@{offset=$start;length=$cursor-$start;kind='type';name=$name})
                }
            }
        }
        foreach ($entry in @($entries | Sort-Object offset, kind, name)) {
            $span = $bytes[$entry.offset .. ($entry.offset + $entry.length - 1)]
            $line = 1 + [regex]::Matches($text.Substring(0, $entry.offset), '\r\n|\n\r|\n|\r').Count
            $conditionStack = [Collections.Generic.List[string]]::new()
            foreach ($directive in [regex]::Matches($masked.Substring(0, $entry.offset),
                '(?m)^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)\b[^\r\n]*')) {
                $name = $directive.Groups[1].Value
                $value = [regex]::Replace($directive.Value.Trim(), '[ \t]+', ' ')
                if ($name -in @('if','ifdef','ifndef')) { $conditionStack.Add($value) }
                elseif ($name -eq 'endif') {
                    if ($conditionStack.Count -eq 0) { throw 'Unbalanced C header conditions' }
                    $conditionStack.RemoveAt($conditionStack.Count - 1)
                }
                else {
                    if ($conditionStack.Count -eq 0) { throw 'Unbalanced C header alternatives' }
                    $last = $conditionStack.Count - 1
                    $conditionStack[$last] += ' -> ' + $value
                }
            }
            # Header guards are universal include mechanics, not a reason to
            # waive an otherwise unconditional public ABI obligation.
            $guard = '#ifndef ' + $header.Replace('.', '_')
            $conditions = @($conditionStack | Where-Object { $_ -cne $guard })
            [ordered]@{
                id = ('CAPI-' + $header.Replace('.', '-').ToUpperInvariant() + '-' +
                    $entry.kind.ToUpperInvariant() + '-' + $entry.name.ToUpperInvariant() + '-' + $line)
                header = $header
                kind = $entry.kind
                name = $entry.name
                line = $line
                byte_offset = $entry.offset
                byte_length = $entry.length
                anchor_sha256 = Get-ConformanceHash -Bytes $span
                declaration = [regex]::Replace($text.Substring($entry.offset, $entry.length).Trim(), '\s+', ' ')
                conditions = $conditions
                applicability_review = $null
                status = 'pending'
                evidence = @()
            }
        }
    }
}

function Test-ConformanceReferenceTree {
    param([Parameter(Mandatory)][string] $Root,
          [string] $ExpectedRevision = $script:ReferenceRevision)
    $reference = Join-Path $Root 'references/lua'
    $head = @(& git -c core.fsmonitor=false -C $reference rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or ($head -join '').Trim() -cne $ExpectedRevision) {
        throw 'Reference checkout is not the pinned Lua commit'
    }
    # HEAD comparison includes BOTH staged and unstaged edits. Checking only
    # manifest hashes would let regenerated metadata bless a modified source
    # tree while continuing to label it with the old pinned commit.
    & git -c core.fsmonitor=false -C $reference diff --quiet HEAD --
    if ($LASTEXITCODE -eq 1) { throw 'Tracked reference tree differs from pinned HEAD' }
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked reference tree' }
    # The runner copies the complete test directory, including native modules
    # and extensionless data. Any extra path there could affect the observed
    # execution. Let Git select the subtree so even quoted unusual filenames
    # are rejected; omitting --exclude-standard deliberately includes ignores.
    $untrackedFixtures = @(& git -c core.fsmonitor=false -C $reference ls-files --others -- testes/)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect untracked reference fixtures' }
    if ($untrackedFixtures.Count -gt 0) {
        throw "Untracked reference fixture input: $($untrackedFixtures -join ', ')"
    }
    $untracked = @(& git -c core.fsmonitor=false -C $reference ls-files --others --)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect untracked reference sources' }
    foreach ($path in $untracked) {
        if ([IO.Path]::GetExtension($path).ToLowerInvariant() -in
            @('.c','.h','.lua','.ads','.adb','.gpr','.inc')) {
            throw "Untracked reference source input: $path"
        }
    }
}

function Read-ConformanceJsonLines {
    param([Parameter(Mandatory)][string] $Path)
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($Path, $script:Utf8)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { throw "Empty JSONL record: ${Path}:$lineNumber" }
        try { ConvertFrom-Json -InputObject $line -AsHashtable -Depth 32 }
        catch { throw "Invalid JSONL record: ${Path}:$lineNumber ($_)" }
    }
}

function Write-ConformanceJsonLines {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][object[]] $Records)
    # WriteAllLines uses the host newline, which would make regenerated
    # inventory bytes differ between Windows and Unix. Keep each JSON record
    # on one LF-terminated line and retain the shared BOM-free UTF-8 encoding.
    $lines = [string[]]@($Records | ForEach-Object {
        ConvertTo-Json -InputObject $_ -Compress -Depth 24
    })
    $contents = if ($lines.Count -eq 0) { '' } else { ($lines -join "`n") + "`n" }
    [IO.File]::WriteAllText($Path, $contents, $script:Utf8)
}

function Get-ConformanceExclusionBaseline {
    param([Parameter(Mandatory)][string] $Root)
    # Freeze the accepted partition selection independently of mutable ledger
    # statuses. Downgrading an accepted pass to pending must not make it newly
    # eligible for exclusion. Descriptor hashes belong to this target's fixed
    # baseline, not to whatever scope file a caller happens to supply later.
    $sources = @{}
    foreach ($identity in $script:ExclusionBaselines) {
        try { $path = Resolve-ReviewedFile -Root $Root -Path $identity.path -Sha256 $identity.sha256 }
        catch { throw "Protected acceptance descriptor missing or changed: $($identity.id): $($_.Exception.Message)" }
        $descriptor = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
        if ($descriptor.schema_version -ne 1 -or $descriptor.id -cne $identity.id -or
            $descriptor.reference_revision -cne $script:ReferenceRevision) {
            throw 'Protected acceptance descriptor identity differs'
        }
        $helpers = if ($descriptor.Contains('helpers')) { @($descriptor.helpers) } else { @() }
        foreach ($file in (@($descriptor.files) + $helpers)) { $sources[$file.path] = $true }
    }
    return @{identities=$script:ExclusionBaselines;sources=$sources}
}

function Assert-ConformanceExclusionBaselineBinding {
    param([AllowEmptyCollection()][object[]] $Bindings)
    if (@($Bindings).Count -ne $script:ExclusionBaselines.Count) {
        throw 'Exclusion protected descriptor bindings differ'
    }
    $seen = @{}
    foreach ($identity in $Bindings) {
        $expected = @($script:ExclusionBaselines | Where-Object { $_.id -ceq $identity.id })
        if ($expected.Count -ne 1 -or $seen.ContainsKey($identity.id) -or
            @($identity.Keys).Count -ne 3 -or $identity.path -cne $expected[0].path -or
            $identity.sha256 -cne $expected[0].sha256) {
            throw 'Exclusion protected descriptor bindings differ'
        }
        $seen[$identity.id] = $true
    }
}

function Assert-ConformancePrivateBoundSource {
    param([string] $Source,[byte[]] $Bytes,[Collections.IDictionary] $Record,[Collections.IDictionary] $Exclusion)
    # V2 is a deliberately narrow source rule: a pure implementation bound
    # can be a derived conjunct, while the original assertion remains a
    # distinct required obligation. It cannot consume a call or statement.
    $parent=$Exclusion.retained_parent
    $original=@(Get-ConformanceCoverageUnits -Path $Source -Bytes $Bytes|Where-Object id -CEQ $parent.id)
    if($Record.kind -cne 'reviewed-block' -or $parent.id -ceq $Record.id -or
        $original.Count -ne 1 -or $original[0].kind -cne 'assert-call' -or $original[0].byte_offset -ne $parent.byte_offset -or
        $parent.byte_offset -gt $Bytes.Length -or $parent.byte_length -gt $Bytes.Length-$parent.byte_offset -or
        $Record.byte_offset -le $parent.byte_offset -or
        $Record.byte_offset+$Record.byte_length -ge $parent.byte_offset+$parent.byte_length){
        throw 'V2 private bound must be a derived child inside its retained original assertion'
    }
    $parentBytes=[byte[]]::new($parent.byte_length);[Array]::Copy($Bytes,$parent.byte_offset,$parentBytes,0,$parent.byte_length)
    if((Get-ConformanceHash $parentBytes) -cne $parent.anchor_sha256){throw 'V2 retained parent source hash differs'}
    $tokens=@(Get-ConformanceTokens $parentBytes)
    if($tokens.Count -lt 5 -or $tokens[0].Text -cne 'assert' -or $tokens[1].Text -cne '(' -or $tokens[-1].Text -cne ')'){
        throw 'V2 retained parent is not an exact assertion expression'
    }
    $depth=0
    for($index=1;$index -lt $tokens.Count;$index++){
        if($tokens[$index].IsString){continue}
        if($tokens[$index].Text -ceq '('){$depth++}
        elseif($tokens[$index].Text -ceq ')'){$depth--}
        if($depth -lt 0 -or ($depth -eq 0 -and $index -ne $tokens.Count-1)){throw 'V2 retained parent crosses its assertion boundary'}
    }
    if($depth -ne 0){throw 'V2 retained parent assertion is unbalanced'}
    $privateBytes=[byte[]]::new($Record.byte_length);[Array]::Copy($Bytes,$Record.byte_offset,$privateBytes,0,$privateBytes.Length)
    $private=@(Get-ConformanceTokens $privateBytes)
    if($private.Count -lt 4 -or $private[0].Text -cne 'and' -or
        @($private|Where-Object{$_.IsString -or $_.Text -cin @('assert','function','return','if','then','else','elseif','for','while','do','repeat','until','end','local','goto','break','T',';','{','}')}).Count -ne 0 -or
        @($private|Select-Object -Skip 1|Where-Object{$_.Text -cin @('and','or')}).Count -ne 0 -or
        @($private|Where-Object{$_.Text -cmatch '^[0-9]'}).Count -eq 0 -or
        @($private|Where-Object{$_.Text -cin @('<','>','=')}).Count -eq 0){
        throw 'V2 private bound must be a pure comparison conjunct without public operations'
    }
    $privateDepth=0
    for($index=1;$index -lt $private.Count;$index++){
        if($private[$index].Text -ceq '('){$privateDepth++}
        elseif($private[$index].Text -ceq ')'){$privateDepth--}
        if($privateDepth -lt 0){throw 'V2 private bound crosses a retained expression delimiter'}
        if($private[$index].Text -ceq '(' -and $private[$index-1].Text -cmatch '^[A-Za-z_]' -and
            $private[$index-1].Text -cnotin @('and','or','not')){throw 'V2 private bound cannot remove a public or application call'}
        if($private[$index].Text -ceq '=' -and
            -not (($index -gt 0 -and $private[$index-1].Text -cin @('=','<','>','~')) -or
                ($index+1 -lt $private.Count -and $private[$index+1].Text -ceq '='))){throw 'V2 private bound cannot contain an assignment'}
    }
    if($privateDepth -ne 0){throw 'V2 private bound crosses a retained expression delimiter'}
}

function Assert-ConformancePrivateBoundFeatureReview {
    param([string] $Root,[Collections.IDictionary] $Exclusion,[Collections.IDictionary] $Decision)
    if(@(@('schema_version','kind','feature_review')|Where-Object{-not $Decision.Contains($_)}).Count -ne 0){
        throw 'V2 observable private bound lacks explicit independent feature review'
    }
    $feature=$Decision.feature_review
    if($Decision.schema_version -ne 2 -or $Decision.kind -cne 't-private-bound-feature-review' -or
        $feature -isnot [Collections.IDictionary] -or
        @(@('module_observable','module_compatibility_obligation','observation_kind','retained_parent_id','no_public_bound_guarantee','rationale',
            'retained_behaviors','public_contract_source','counterpart_source_bindings')|Where-Object{-not $feature.Contains($_)}).Count -ne 0 -or
        $feature.module_observable -isnot [bool] -or $feature.module_observable -ne $Exclusion.module_observable -or
        $feature.module_compatibility_obligation -isnot [bool] -or $feature.module_compatibility_obligation -or
        $feature.observation_kind -cne $Exclusion.observation_kind -or $feature.retained_parent_id -cne $Exclusion.retained_parent.id -or
        $feature.no_public_bound_guarantee -isnot [bool] -or -not $feature.no_public_bound_guarantee -or
        [string]::IsNullOrWhiteSpace([string]$feature.rationale) -or $feature.retained_behaviors -isnot [Array] -or
        $feature.retained_behaviors.Count -eq 0 -or @($feature.retained_behaviors|Where-Object{[string]::IsNullOrWhiteSpace([string]$_)}).Count -ne 0 -or
        @($feature.retained_behaviors|Sort-Object -Unique).Count -ne $feature.retained_behaviors.Count){
        throw 'V2 observable private bound lacks explicit independent feature relevance and retained-behavior review'
    }
    $contract=$feature.public_contract_source
    if($contract -isnot [Collections.IDictionary] -or $contract.path -cne 'references/lua/manual/manual.of' -or
        ($contract.byte_offset -isnot [int] -and $contract.byte_offset -isnot [long]) -or $contract.byte_offset -lt 0 -or
        ($contract.byte_length -isnot [int] -and $contract.byte_length -isnot [long]) -or $contract.byte_length -le 0 -or
        $contract.anchor_sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'V2 feature review lacks pinned public contract source'}
    $path=Resolve-ReviewedFile -Root $Root -Path $contract.path -Sha256 $contract.source_sha256
    $bytes=[IO.File]::ReadAllBytes($path)
    if($contract.byte_offset -gt $bytes.Length -or $contract.byte_length -gt $bytes.Length-$contract.byte_offset){throw 'V2 public contract source span is outside its file'}
    $span=[byte[]]::new($contract.byte_length);[Array]::Copy($bytes,$contract.byte_offset,$span,0,$span.Length)
    if((Get-ConformanceHash $span) -cne $contract.anchor_sha256){throw 'V2 public contract source span hash differs'}
    if($feature.counterpart_source_bindings -isnot [Array] -or $feature.counterpart_source_bindings.Count -eq 0){throw 'V2 feature review lacks retained counterpart source bindings'}
    $seen=@{};$testSource=$false
    foreach($binding in $feature.counterpart_source_bindings){
        if($binding.path -cnotmatch '^(?:src|c_api/tests|tests/(?:c|lua|src|conformance/targets/remaining-upstream-compatibility))/[a-zA-Z0-9_-]+\.(?:c|h|lua|adb|ads)$' -or
            $seen.ContainsKey($binding.path)){throw 'V2 feature review counterpart source binding is invalid or duplicate'}
        $seen[$binding.path]=$true
        if($binding.path -cmatch '^(?:c_api/tests|tests)/'){$testSource=$true}
        [void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)
    }
    if(-not $testSource){throw 'V2 feature review requires retained test counterpart source, not implementation claims alone'}
}

function Assert-ConformancePrivateBoundParentRecord {
    param([Collections.IDictionary] $Exclusion,[Collections.IDictionary] $Records,[Collections.IDictionary] $Exclusions)
    $id=$Exclusion.retained_parent.id
    if(-not $Records.Contains($id) -or $Exclusions.Contains($id)){throw 'V2 retained original parent cannot be absent or excluded'}
    $parent=$Records[$id]
    if($parent.status -ceq 'pending'){return}
    if($parent.status -ceq 'passed'){
        if($parent.disposition -cne 'ada-internal-equivalent' -or -not $parent.Contains('source_exclusion_ids') -or
            $parent.source_exclusion_ids -isnot [Array] -or $Exclusion.id -cnotin $parent.source_exclusion_ids){
            throw 'V2 retained original assertion needs its own executed reviewed-equivalent evidence and exact child linkage'
        }
        return
    }
    # A source-reference classification needs a separate retained runtime
    # child. A link solely to the excluded private observation cannot discharge
    # a mixed assertion's public part, even after all other records pass.
    $public=@($parent.obligations|Where-Object{$_ -cne $Exclusion.id -and -not $Exclusions.Contains($_) -and $Records.Contains($_)})
    if($parent.status -cne 'reviewed' -or $parent.classification -cne 'reference' -or
        $Exclusion.id -cnotin $parent.obligations -or $public.Count -eq 0){throw 'V2 mixed parent requires a separately retained public runtime obligation'}
    foreach($publicId in $public){
        $child=$Records[$publicId]
        if($child.kind -cin @('assert-call','reviewed-block') -and $child.byte_length -gt 0 -and
            $child.byte_offset -ge $Exclusion.retained_parent.byte_offset -and
            $child.byte_offset+$child.byte_length -le $Exclusion.retained_parent.byte_offset+$Exclusion.retained_parent.byte_length -and
            ($child.byte_offset+$child.byte_length -le $Exclusion.byte_offset -or
                $child.byte_offset -ge $Exclusion.byte_offset+$Exclusion.byte_length)){return}
    }
    throw 'V2 retained public runtime child must cite preserved parent bytes outside the private bound'
}

function Assert-ConformanceOptimizerSource {
    param([byte[]]$Bytes,[Collections.IDictionary]$Exclusion)
    # A fixed full-source hash and closed registry bind the private inspection
    # context, including public helper calls that merely reduce its data.
    # This is not a token-based exemption for arbitrary optimizer/debug code.
    if($Exclusion.t_guard.mode -cne 'absent-return' -or $Exclusion.t_guard.byte_offset -ne 83 -or
        $Exclusion.t_guard.byte_length -ne 104 -or
        $Exclusion.t_guard.sha256 -cne '6cbc2276f7214ec212214a3f5dbf2f48914a46ab90adebe20f15d6c38f631050'){
        throw 'V3 optimizer must retain its exact pinned top-level T guard'
    }
    $original=@(Get-ConformanceCoverageUnits -Path code.lua -Bytes $Bytes)
    if($original.Count -ne 51){throw 'V3 optimizer original51 anchor set differs'}
    $inside=@($original|Where-Object{$_.byte_offset -ge $Exclusion.byte_offset -and
        $_.byte_offset+$_.byte_length -le $Exclusion.byte_offset+$Exclusion.byte_length})
    if($Exclusion.original_anchor_links.Count -ne $inside.Count){throw 'V3 optimizer original-anchor decomposition is incomplete'}
    foreach($anchor in $inside){
        $link=@($Exclusion.original_anchor_links|Where-Object id -CEQ $anchor.id)
        if($link.Count -ne 1 -or (($link[0].Keys|Sort-Object)-join '|') -cne
            'anchor_sha256|byte_length|byte_offset|id|kind'){throw 'V3 optimizer original-anchor link differs'}
        foreach($key in @('id','kind','byte_offset','byte_length','anchor_sha256')){
            if($link[0][$key] -cne $anchor[$key]){throw 'V3 optimizer original-anchor identity differs'}
        }
    }
    $checkR=[byte[]]::new(127);[Array]::Copy($Bytes,2079,$checkR,0,127)
    if((Get-ConformanceHash $checkR) -cne '324530f639ef49280bcc33a77b56351c3369cdfd13290c63934071985bb880dc'){
        throw 'V3 optimizer must retain exact checkR execution/type bytes'
    }
}

function Assert-ConformanceOptimizerReviews {
    param([string]$Root,[Collections.IDictionary]$Exclusion,[Collections.IDictionary]$Decision,
        [Collections.IDictionary]$Approval,[switch]$AllowSyntheticReview)
    function Source-Only($value){
        foreach($flag in @('runtime_acceptance','coverage_authority')){
            if($value[$flag] -isnot [bool] -or $value[$flag]){throw 'V3 source review cannot grant runtime authority'}
        }
        if($value.Contains('synthetic_fixture') -and
            ($value.synthetic_fixture -isnot [bool] -or ($value.synthetic_fixture -and -not $AllowSyntheticReview))){
            throw 'V3 actual source authority cannot use a synthetic review'
        }
        if($value.execution_evidence -isnot [Array] -or $value.execution_evidence.Count){throw 'V3 source review cannot invent execution evidence'}
        if($value.Contains('source_exclusions') -and
            ($value.source_exclusions -isnot [Array] -or $value.source_exclusions.Count)){throw 'V3 source review cannot introduce another source waiver'}
    }
    Source-Only $Approval;Source-Only $Decision
    if($Decision.schema_version -ne 3 -or $Decision.kind -cne 't-private-optimizer-exclusion-review'){
        throw 'V3 optimizer lacks its independent exact source narrative'
    }
    $feature=Get-Content (Resolve-ReviewedFile -Root $Root -Path $Exclusion.feature_review.path -Sha256 $Exclusion.feature_review.sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    $retention=Get-Content (Resolve-ReviewedFile -Root $Root -Path $Exclusion.semantic_retention_review.path -Sha256 $Exclusion.semantic_retention_review.sha256) -Raw|ConvertFrom-Json -AsHashtable -Depth 48
    foreach($review in @($feature,$retention)){
        Source-Only $review
        if([string]::IsNullOrWhiteSpace($review.author) -or [string]::IsNullOrWhiteSpace($review.reviewer) -or
            $review.author -ceq $review.reviewer -or $review.reviewer -ceq $Exclusion.review.author -or
            $review.source.path -cne 'references/lua/testes/code.lua' -or $review.source.sha256 -cne $Exclusion.source_sha256){
            throw 'V3 optimizer feature/retention review identity or independence differs'
        }
    }
    if($feature.kind -cne 't-private-optimizer-feature-review' -or $feature.candidate_id -cne 'code-private-optimizer' -or
        $feature.decision -cnotin @('accepted-feature-only','accepted-feature-only-with-required-revisions') -or
        $feature.configuration -cne 'upstream-test' -or $feature.candidates.Count -ne 8){
        throw 'V3 optimizer lacks bounded independent feature relevance'
    }
    $registry=@(Get-ConformanceOptimizerRegistry)
    foreach($row in $registry){
        $candidate=@($feature.candidates|Where-Object id -CEQ $row.id)
        if($candidate.Count -ne 1 -or $candidate[0].decision -cne 'accepted-feature-only' -or
            $candidate[0].module_observable -isnot [bool] -or -not $candidate[0].module_observable -or
            $candidate[0].module_compatibility_obligation -isnot [bool] -or $candidate[0].module_compatibility_obligation){
            throw 'V3 optimizer feature cannot hide visibility or waive public compatibility'
        }
        foreach($key in @('byte_offset','byte_length','anchor_sha256')){
            if($candidate[0][$key] -cne $row[$key]){throw 'V3 optimizer feature candidate widened or changed'}
        }
    }
    $featurePaths=@('references/lua/manual/manual.of','references/lua/ltests.c','src/lua-canonical_compiler.adb',
        'src/lua-canonical_compiler.ads','src/lua-opcodes.ads','src/lua-chunks.ads',
        'scripts/ConformanceExclusionEligibility.psm1','scripts/ConformanceInventory.psm1','scripts/ConformanceTransforms.psm1')
    if($feature.source_bindings -isnot [Array] -or (($feature.source_bindings.path|Sort-Object)-join '|') -cne (($featurePaths|Sort-Object)-join '|')){
        throw 'V3 feature lacks current implementation/source bindings'
    }
    foreach($binding in $feature.source_bindings){[void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)}
    if($retention.schema_version -ne 1 -or $retention.kind -cne 'code-optimizer-semantic-retention-review' -or
        $retention.decision -cne 'accepted-source-retention-contract-only' -or
        $retention.schema_implementation_scope.version -ne 3 -or
        $retention.schema_implementation_scope.target -cne 'remaining-upstream-compatibility' -or
        $retention.schema_implementation_scope.permitted_candidates.Count -ne 8 -or
        $retention.protected_checkR.byte_offset -ne 2079 -or $retention.protected_checkR.byte_length -ne 127 -or
        $retention.protected_checkR.sha256 -cne '324530f639ef49280bcc33a77b56351c3369cdfd13290c63934071985bb880dc' -or
        $retention.retained_contracts -isnot [Array] -or $retention.retained_contracts.Count -lt 7 -or
        @($retention.retained_contracts|Where-Object{[string]::IsNullOrWhiteSpace($_)}).Count){
        throw 'V3 optimizer requires separately reviewed public semantic retention and exact checkR'
    }
    foreach($row in $registry){
        $candidate=@($retention.schema_implementation_scope.permitted_candidates|Where-Object id -CEQ $row.id)
        if($candidate.Count -ne 1){throw 'V3 retention candidate set differs'}
        foreach($key in @('byte_offset','byte_length','anchor_sha256')){
            if($candidate[0][$key] -cne $row[$key]){throw 'V3 retention candidate widened or changed'}
        }
    }
    $sources=@('tests/lua/code_public_semantics.lua','tests/src/code_public_semantic_tests.adb','tests/src/code_public_semantic_tests.ads')
    if($retention.witness_sources -isnot [Array] -or (($retention.witness_sources.path|Sort-Object)-join '|') -cne (($sources|Sort-Object)-join '|')){
        throw 'V3 optimizer lacks the exact public semantic source set'
    }
    foreach($binding in $retention.witness_sources){[void](Resolve-ReviewedFile -Root $Root -Path $binding.path -Sha256 $binding.sha256)}
    [void](Resolve-ReviewedFile -Root $Root -Path $retention.witness.path -Sha256 $retention.witness.sha256)
}

function Assert-ConformanceOptimizerParentRecords {
    param([byte[]]$Bytes,[Collections.IDictionary]$Exclusion,[Collections.IDictionary]$Records,[Collections.IDictionary]$Exclusions)
    # An excluded derived child cannot overwrite even one original identity.
    # Pending originals remain pending; resolved references need their own
    # independent classification and a separately retained runtime obligation.
    $original=@(Get-ConformanceCoverageUnits -Path code.lua -Bytes $Bytes)
    foreach($anchor in $original){
        if(-not $Records.Contains($anchor.id) -or $Exclusions.Contains($anchor.id)){throw 'V3 optimizer must preserve every original51 anchor and parent'}
        foreach($key in @('kind','byte_offset','byte_length','anchor_sha256')){
            if($Records[$anchor.id][$key] -cne $anchor[$key]){throw 'V3 optimizer original identity changed'}
        }
    }
    foreach($link in $Exclusion.original_anchor_links){
        $record=$Records[$link.id]
        if($record.status -ceq 'passed' -or @($record.evidence).Count){throw 'V3 previously passing original obligations cannot become private exclusions'}
        if($record.status -ceq 'pending'){continue}
        $retained=@($record.obligations|Where-Object{$_ -cne $Exclusion.id -and -not $Exclusions.Contains($_) -and $Records.Contains($_) -and
            $Records[$_].kind -cin @('assert-call','reviewed-block')})
        if($record.status -cne 'reviewed' -or $record.classification -cne 'reference' -or
            $Exclusion.id -cnotin $record.obligations -or $retained.Count -eq 0){
            throw 'V3 original reference requires explicit private-child and retained-runtime decomposition'
        }
    }
}

function Test-ConformanceTargetExclusion {
    param([Parameter(Mandatory)][string] $Root,
          [Parameter(Mandatory)][string] $Source,
          [Parameter(Mandatory)][byte[]] $SourceBytes,
          [Parameter(Mandatory)][Collections.IDictionary] $Record,
          [Parameter(Mandatory)][Collections.IDictionary] $Exclusion,
          [switch]$AllowSyntheticReview)
    # Exclusions belong to a separately authorized target, never to the pass
    # ledger. Bind the review to the original bytes and the pending obligation
    # before allowing it to discharge that target's coverage requirement.
    if ($Record.kind -notin @('assert-call','reviewed-block') -or
        $Record.id -cnotmatch '^LUA-[A-Z0-9]+-(ASSERT-CALL|REVIEWED-BLOCK)-[0-9]{4}$' -or
        $Record.status -cne 'pending' -or $Record.disposition -cne 'pending') {
        throw 'Only pending source runtime obligations can be excluded'
    }
    if (@($Record.evidence).Count -ne 0 -or @($Exclusion.evidence).Count -ne 0) {
        throw 'An exclusion cannot contain execution or pass evidence'
    }
    $baseline = Get-ConformanceExclusionBaseline -Root $Root
    if ($baseline.sources.ContainsKey($Source)) {
        throw 'Previously accepted source partitions cannot be excluded'
    }
    foreach ($field in @('id','byte_offset','byte_length','anchor_sha256')) {
        if ($Exclusion[$field] -cne $Record[$field]) { throw "Exclusion anchor differs: $field" }
    }
    $stem = [IO.Path]::GetFileNameWithoutExtension($Source).ToUpperInvariant()
    if ($Source -cnotmatch '^[a-z0-9]+\.lua$' -or
        $Record.id -cnotmatch ('^LUA-' + $stem + '-') -or
        $Exclusion.source -cne $Source -or
        $Exclusion.source_sha256 -cne (Get-ConformanceHash -Bytes $SourceBytes) -or
        $Exclusion.status -cne 'excluded' -or
        $Exclusion.disposition -cne 'reviewed-t-internal-exclusion') {
        throw 'Exclusion source or disposition differs'
    }
    if ($Record.byte_offset -isnot [int] -and $Record.byte_offset -isnot [long]) {
        throw 'Exclusion source span is not integral'
    }
    if ($Record.byte_length -isnot [int] -and $Record.byte_length -isnot [long]) {
        throw 'Exclusion source span is not integral'
    }
    if ($Record.byte_offset -lt 0 -or $Record.byte_length -le 0 -or
        $Record.byte_offset -gt $SourceBytes.Length -or
        $Record.byte_length -gt $SourceBytes.Length - $Record.byte_offset) {
        throw 'Exclusion source span is outside the source'
    }
    $span = [byte[]]::new($Record.byte_length)
    [Array]::Copy($SourceBytes, $Record.byte_offset, $span, 0, $span.Length)
    if ($Record.anchor_sha256 -cne (Get-ConformanceHash -Bytes $span)) {
        throw 'Exclusion original span hash differs'
    }
    if (@($Exclusion.configurations).Count -ne 1 -or
        $Exclusion.configurations[0] -cne 'upstream-test' -or
        $Exclusion.eligibility -cne 't-only-private-invariant' -or
        -not (Test-ConformanceExclusionCompatibilityShape $Exclusion) -or
        [string]::IsNullOrWhiteSpace([string]$Exclusion.invariant) -or
        [string]::IsNullOrWhiteSpace([string]$Exclusion.third_party_irrelevance)) {
        throw 'Exclusion must identify a T-only private invariant without public or mixed behavior'
    }
    $eligibilityVersion=Get-ConformanceExclusionEligibilityVersion $Exclusion
    if($eligibilityVersion -eq 2){Assert-ConformancePrivateBoundSource -Source $Source -Bytes $SourceBytes -Record $Record -Exclusion $Exclusion}
    if($eligibilityVersion -eq 3){
        if($Record.kind -cne 'reviewed-block'){throw 'V3 optimizer must use an exact derived reviewed block'}
        Assert-ConformanceOptimizerSource -Bytes $SourceBytes -Exclusion $Exclusion
    }
    $guard = $Exclusion.t_guard
    if ($null -eq $guard -or $guard.mode -cnotin @('positive-guard','absent-return') -or
        ($guard.byte_offset -isnot [int] -and $guard.byte_offset -isnot [long]) -or
        ($guard.byte_length -isnot [int] -and $guard.byte_length -isnot [long]) -or
        $guard.byte_offset -lt 0 -or $guard.byte_length -le 0 -or
        $guard.byte_offset -gt $SourceBytes.Length -or
        $guard.byte_length -gt $SourceBytes.Length - $guard.byte_offset) {
        throw 'Exclusion T guard span is invalid'
    }
    $guardBytes = [byte[]]::new($guard.byte_length)
    [Array]::Copy($SourceBytes, $guard.byte_offset, $guardBytes, 0, $guardBytes.Length)
    if ($guard.sha256 -cne (Get-ConformanceHash -Bytes $guardBytes)) {
        throw 'Exclusion T guard hash differs'
    }
    $tokens = @(Get-ConformanceTokens -Bytes $guardBytes)
    $sourceTokens = @(Get-ConformanceTokens -Bytes $SourceBytes)
    $originalGuardTokens = @($sourceTokens | Where-Object {
        $_.Offset -ge $guard.byte_offset -and $_.Offset + $_.Length -le $guard.byte_offset + $guard.byte_length
    })
    if ($tokens.Count -ne $originalGuardTokens.Count) { throw 'Exclusion T guard is not a source token span' }
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i].Offset + $guard.byte_offset -ne $originalGuardTokens[$i].Offset -or
            $tokens[$i].Length -ne $originalGuardTokens[$i].Length -or
            $tokens[$i].IsString -ne $originalGuardTokens[$i].IsString) {
            throw 'Exclusion T guard is not a source token span'
        }
    }
    $words = @($tokens | ForEach-Object { if ($_.IsString) { '<string>' } else { $_.Text } })
    $guardEnd = $guard.byte_offset + $guard.byte_length
    if ($guard.mode -ceq 'positive-guard') {
        if ($words.Count -lt 4 -or ($words[0..2] -join ' ') -cne 'if T then' -or
            $words[-1] -cne 'end' -or
            $Record.byte_offset -lt $guard.byte_offset + $tokens[2].Offset + $tokens[2].Length -or
            $Record.byte_offset + $Record.byte_length -gt $guard.byte_offset + $tokens[-1].Offset) {
            throw 'Exclusion is not inside its positive T guard'
        }
        # A caller cannot extend the cited guard past its first matching end
        # to swallow an adjacent public assertion. This is lexical block
        # matching over the existing inventory tokens, not another Lua parser.
        $blocks = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $words.Count; $i++) {
            $word = $words[$i]
            if ($word -cin @('if','function','do','repeat')) { $blocks.Add($word) }
            elseif ($word -cin @('else','elseif') -and $blocks.Count -eq 1) {
                # Only the initial then arm is guarded by a truthy T. An
                # alternative belongs to T absence (or another predicate),
                # even though it shares the enclosing if/end byte span.
                throw 'Exclusion positive T guard cannot include outer alternatives'
            }
            elseif ($word -cin @('end','until')) {
                if ($blocks.Count -eq 0 -or (($word -ceq 'until') -ne ($blocks[-1] -ceq 'repeat'))) {
                    throw 'Exclusion T guard block nesting differs'
                }
                $blocks.RemoveAt($blocks.Count - 1)
                if ($blocks.Count -eq 0 -and $i -ne $words.Count - 1) {
                    throw 'Exclusion T guard extends into unguarded behavior'
                }
            }
        }
        if ($blocks.Count -ne 0) { throw 'Exclusion T guard block nesting differs' }
    } else {
        # The pinned T-only files use an unconditional return on T absence.
        # Accept only the literal forms used for that check, with no nested
        # block or early transfer in its reporting prefix. Semantic dominance
        # and private/public separation still require the bound source review.
        $prefix = if ($words.Count -ge 6 -and ($words[0..5] -join ' ') -ceq 'if T = = nil then') { 6 }
            elseif ($words.Count -ge 4 -and ($words[0..3] -join ' ') -ceq 'if not T then') { 4 }
            else { 0 }
        $reportWords = if ($words.Count -gt $prefix + 2) { @($words[$prefix..($words.Count - 3)]) } else { @() }
        if ($prefix -eq 0 -or $words.Count -lt $prefix + 2 -or
            ($words[-2..-1] -join ' ') -cne 'return end' -or
            $Record.byte_offset -lt $guardEnd -or
            @($reportWords | Where-Object {
                $_ -cin @('if','then','else','elseif','end','function','for','while','do','repeat','until','return','goto','break')
            }).Count -ne 0) {
            throw 'Exclusion lacks a literal T-absent unconditional return'
        }
        $depth = 0
        foreach ($token in $sourceTokens) {
            if ($token.Offset -ge $guard.byte_offset) { break }
            if ($token.IsString) { continue }
            if ($token.Text -cin @('if','function','do','repeat')) { $depth++ }
            elseif ($token.Text -cin @('end','until')) { $depth-- }
            if ($depth -lt 0) { throw 'Exclusion T-absent return has invalid enclosing blocks' }
        }
        if ($depth -ne 0) { throw 'Exclusion T-absent return must be at source top level' }
    }
    $review = $Exclusion.review
    if ($null -eq $review -or $review.status -cne 'accepted' -or
        [string]::IsNullOrWhiteSpace([string]$review.author) -or
        [string]::IsNullOrWhiteSpace([string]$review.reviewer) -or
        $review.author -ceq $review.reviewer) {
        throw 'Exclusion requires accepted independent review'
    }
    $approvalPath = Resolve-ReviewedFile -Root $Root -Path $review.artifact -Sha256 $review.artifact_sha256
    $approval = Get-Content -LiteralPath $approvalPath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    if ($approval.schema_version -ne $eligibilityVersion -or $approval.kind -cne 't-exclusion-approval' -or
        $approval.target -cne 'remaining-upstream-compatibility' -or
        $approval.reference_revision -cne $script:ReferenceRevision -or
        $approval.author -cne $review.author -or $approval.reviewer -cne $review.reviewer -or
        $approval.decision -cne 'accepted') { throw 'Exclusion approval identity or decision differs' }
    Assert-ConformanceExclusionBaselineBinding -Bindings @($approval.protected_scopes)
    # Bind every semantic field, including false eligibility booleans. The
    # approval omits only its own referring review metadata, avoiding a hash
    # cycle while preventing an old approval from blessing a broadened span.
    $fields = @(Get-ConformanceExclusionSemanticFields $Exclusion)
    if (@($Exclusion.Keys | Where-Object { $_ -cnotin ($fields + @('review')) }).Count -ne 0 -or
        $null -eq $approval.exclusion -or @($approval.exclusion.Keys).Count -ne $fields.Count) {
        throw 'Exclusion approval field set differs'
    }
    foreach ($field in $fields) {
        # JSON object key order is irrelevant, including the nested guard.
        $actual = $Exclusion[$field]; $approved = $approval.exclusion[$field]
        if ($field -cin @('t_guard','retained_parent')) {
            if ((@($actual.Keys | Sort-Object) -join '|') -cne (@($approved.Keys | Sort-Object) -join '|')) {
                throw 'Exclusion approved T guard fields differ'
            }
            foreach ($key in $actual.Keys) {
                if ($actual[$key] -cne $approved[$key]) { throw 'Exclusion approved T guard differs' }
            }
        } elseif ((ConvertTo-Json -InputObject $actual -Depth 8 -Compress) -cne
            (ConvertTo-Json -InputObject $approved -Depth 8 -Compress)) {
            throw "Exclusion approved semantics differ: $field"
        }
    }
    $narrative = $approval.review_evidence
    if ($null -eq $narrative) { throw 'Exclusion lacks independent review evidence' }
    $narrativePath = Resolve-ReviewedFile -Root $Root -Path $narrative.path -Sha256 $narrative.sha256
    $decision = Get-Content -LiteralPath $narrativePath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    if ($decision.reviewer -cne $review.reviewer -or $decision.exclusion_id -cne $Exclusion.id -or
        $decision.decision -cne 'accepted' -or
        [string]::IsNullOrWhiteSpace([string]$decision.t_dominance) -or
        [string]::IsNullOrWhiteSpace([string]$decision.private_invariant) -or
        [string]::IsNullOrWhiteSpace([string]$decision.third_party_irrelevance)) {
        throw 'Exclusion independent source decision differs or lacks rationale'
    }
    if($eligibilityVersion -eq 2){Assert-ConformancePrivateBoundFeatureReview -Root $Root -Exclusion $Exclusion -Decision $decision}
    if($eligibilityVersion -eq 3){Assert-ConformanceOptimizerReviews -Root $Root -Exclusion $Exclusion -Decision $decision -Approval $approval -AllowSyntheticReview:$AllowSyntheticReview}
    return $Exclusion
}

function Test-ConformanceResolvedRecord {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Record,
          [Parameter(Mandatory)][string[]] $Contexts,
          [switch] $Api, [switch] $RequireComplete)
    # A lexical candidate can be reviewed without having executed anything.
    # Keep that state separate from a runtime pass: a guard or a string which
    # merely contains 'assert' must never acquire fabricated process evidence.
    $statuses = if ($Api) { @('pending', 'passed') } else { @('pending', 'reviewed', 'passed') }
    if ($Record.status -notin $statuses) { throw "Invalid status: $($Record.id)" }
    if ($Record.status -eq 'pending') {
        if ($RequireComplete) { throw "Unresolved coverage: $($Record.id)" }
        if (-not $Api -and $Record.disposition -ne 'pending') {
            throw "Pending coverage has completed disposition: $($Record.id)"
        }
        if (@($Record.evidence).Count -ne 0) { throw "Pending coverage has pass evidence: $($Record.id)" }
        if (-not $Api -and (($Record.Contains('classification') -and $null -ne $Record.classification) -or
            ($Record.Contains('obligations') -and @($Record.obligations).Count -gt 0))) {
            throw "Pending coverage has unreviewed classification: $($Record.id)"
        }
        return
    }
    if (-not $Api -and $Record.status -eq 'reviewed') {
        $classifications = switch ($Record.kind) {
            'conditional-guard' { @('guard') }
            'skip-report' { @('report') }
            'generated-template' { @('template', 'data') }
            'internal-reference' { @('reference') }
            'assert-call' { @('reference') }
            default { @() }
        }
        if ($Record.disposition -ne 'candidate-reviewed' -or
            $Record.classification -notin $classifications) {
            throw "Invalid non-runtime classification: $($Record.id)"
        }
        if ([string]::IsNullOrWhiteSpace($Record.invariant) -or
            @($Record.configurations).Count -eq 0 -or
            @($Record.configurations | Where-Object { $_ -notin @('default','upstream-test') }).Count -gt 0) {
            throw "Missing classified applicability/invariant: $($Record.id)"
        }
        if ($null -eq $Record.review -or [string]::IsNullOrWhiteSpace($Record.review.reviewer) -or
            [string]::IsNullOrWhiteSpace($Record.review.author) -or
            $Record.review.reviewer -ceq $Record.review.author -or
            [string]::IsNullOrWhiteSpace($Record.review.rationale) -or
            [string]::IsNullOrWhiteSpace($Record.review.artifact)) {
            throw "Missing independent classification review: $($Record.id)"
        }
        if (@($Record.evidence).Count -ne 0) {
            throw "Non-runtime candidate has execution evidence: $($Record.id)"
        }
        $links = @($Record.obligations)
        if ($Record.classification -eq 'data') {
            # Only an independently reviewed quoted template can be classified
            # as inert data. A guard, T reference or real call cannot use this
            # escape hatch to erase the block it controls or tests.
            if ($links.Count -ne 0) { throw "Data candidate has runtime links: $($Record.id)" }
        }
        elseif ($links.Count -eq 0 -or
            @($links | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
            @($links | Select-Object -Unique).Count -ne $links.Count) {
            throw "Missing/duplicate runtime obligation links: $($Record.id)"
        }
        return
    }
    if (-not $Api) {
        if ($Record.kind -in @('conditional-guard', 'skip-report', 'generated-template', 'internal-reference')) {
            throw "Lexical candidate cannot claim runtime pass: $($Record.id)"
        }
        $allowed = if ($Record.kind -eq 'manual-audit') { @('inventory-reviewed') }
            else { @('unchanged', 'ada-internal-equivalent', 'native-platform-equivalent') }
        if ($Record.disposition -notin $allowed) { throw "Invalid pass disposition: $($Record.id)" }
        if ([string]::IsNullOrWhiteSpace($Record.invariant)) { throw "Missing invariant: $($Record.id)" }
        if (@($Record.configurations).Count -eq 0 -or
            @($Record.configurations | Where-Object { $_ -notin @('default','upstream-test') }).Count -gt 0) {
            throw "Missing/invalid applicability: $($Record.id)"
        }
        if ($null -eq $Record.review -or [string]::IsNullOrWhiteSpace($Record.review.reviewer) -or
            [string]::IsNullOrWhiteSpace($Record.review.author) -or
            $Record.review.reviewer -ceq $Record.review.author -or
            [string]::IsNullOrWhiteSpace($Record.review.rationale) -or
            [string]::IsNullOrWhiteSpace($Record.review.artifact)) {
            throw "Missing independent review: $($Record.id)"
        }
        # Every runtime obligation needs the original C observation, including
        # unchanged tests. Otherwise an Ada-only pass could silently stand in
        # for the reference result. A whole-file inventory audit reviews what
        # must be tested; it is not itself an executed runtime obligation.
        if ($Record.kind -ne 'manual-audit' -and
            [string]::IsNullOrWhiteSpace($Record.review.original_c_evidence)) {
            throw "Runtime source lacks original C evidence: $($Record.id)"
        }
    }
    $evidence = @($Record.evidence)
    if ($evidence.Count -eq 0) { throw "Pass lacks evidence: $($Record.id)" }
    $seen = @{}
    foreach ($item in $evidence) {
        $validResult = $item.result -eq 'passed'
        if ($Api -and $item.result -eq 'not-applicable') {
            # Conditional *macro definitions* can be inactive in one ABI.
            # Exported functions, data and types still need real test proof.
            # Source-derived conditions are regenerated by the outer validator;
            # a definition-specific compiler artifact and independent review
            # are mandatory before accepting any inactive branch.
            $validResult = $Record.kind -eq 'macro' -and
                @($Record.conditions).Count -gt 0 -and
                $item.kind -eq 'preprocessor' -and
                $item.definition_id -ceq $Record.id -and
                $item.active -is [bool] -and -not $item.active -and
                -not [string]::IsNullOrWhiteSpace($item.reason) -and
                $null -ne $Record.applicability_review -and
                -not [string]::IsNullOrWhiteSpace($Record.applicability_review.reviewer) -and
                -not [string]::IsNullOrWhiteSpace($Record.applicability_review.author) -and
                $Record.applicability_review.reviewer -cne $Record.applicability_review.author -and
                -not [string]::IsNullOrWhiteSpace($Record.applicability_review.rationale) -and
                -not [string]::IsNullOrWhiteSpace($Record.applicability_review.artifact) -and
                ($Record.applicability_review.conditions -join "`n") -ceq ($Record.conditions -join "`n")
        }
        if ($item.context -notin $Contexts -or $seen.ContainsKey($item.context) -or
            -not $validResult -or $item.revision -notmatch '^[0-9a-f]{40}$' -or
            [string]::IsNullOrWhiteSpace($item.artifact) -or
            [string]::IsNullOrWhiteSpace($item.case_id)) {
            throw "Invalid/duplicate pass evidence: $($Record.id)"
        }
        $seen[$item.context] = $true
    }
    if ($RequireComplete) {
        $required = if ($Api) { $Contexts } else {
            @($Contexts | Where-Object { ($_ -split '/')[0] -in $Record.configurations })
        }
        foreach ($context in $required) {
            if (-not $seen.ContainsKey($context)) { throw "Missing $context evidence: $($Record.id)" }
        }
    }
}

function Test-ConformanceSourceLinks {
    param([Parameter(Mandatory)][object[]] $Records, [switch] $RequireComplete,
          [ValidateSet('strict-upstream','remaining-upstream-compatibility')]
          [string] $TargetPolicy = 'strict-upstream',
          [Collections.IDictionary] $ResolvedExclusions = @{})
    if ($TargetPolicy -ceq 'strict-upstream' -and $ResolvedExclusions.Count -ne 0) {
        throw 'Strict upstream coverage cannot use exclusions'
    }
    # Resolve links only after all records in one pinned file are known.
    # Requiring direct edges to runtime obligations avoids reference cycles,
    # whole-file pass stamping and links into another file's successful suite.
    $indexed = @{}
    foreach ($record in $Records) {
        if ($indexed.ContainsKey($record.id)) { throw "Duplicate linked unit ID: $($record.id)" }
        $indexed[$record.id] = $record
    }
    foreach ($record in $Records) {
        if ($record.status -ne 'reviewed' -or $record.classification -eq 'data') { continue }
        $covered = @{}
        foreach ($id in $record.obligations) {
            if (-not $indexed.ContainsKey($id) -or $id -ceq $record.id) {
                throw "Missing/self runtime obligation link: $($record.id)/$id"
            }
            $target = $indexed[$id]
            $excluded = $TargetPolicy -ceq 'remaining-upstream-compatibility' -and $ResolvedExclusions.Contains($id)
            if (($record.id -split '-', 3)[1] -cne ($id -split '-', 3)[1]) {
                throw "Runtime obligation link crosses source file: $($record.id)/$id"
            }
            if ($target.kind -notin @('assert-call', 'reviewed-block') -or
                $target.status -notin @('pending', 'passed') -or
                ($record.classification -eq 'template' -and $target.kind -ne 'reviewed-block')) {
                throw "Link is not a direct runtime obligation: $($record.id)/$id"
            }
            # Foundation mode may record that review discovered still-pending
            # tests. Completion cannot count that discovery as their execution.
            if ($RequireComplete -and $target.status -ne 'passed' -and -not $excluded) {
                throw "Linked runtime obligation remains pending: $($record.id)/$id"
            }
            $applicable = if ($excluded) { $ResolvedExclusions[$id].configurations } else { $target.configurations }
            foreach ($configuration in $applicable) { $covered[$configuration] = $true }
        }
        foreach ($configuration in $record.configurations) {
            if (-not $covered.ContainsKey($configuration)) {
                throw "Linked obligation applicability gap: $($record.id)/$configuration"
            }
        }
    }
}

function Test-ConformanceInventory {
    param([Parameter(Mandatory)][string] $Root,
          [string] $InventoryDirectory = '', [switch] $RequireComplete,
          [ValidateSet('strict-upstream','remaining-upstream-compatibility')]
          [string] $TargetPolicy = 'strict-upstream')
    if ($InventoryDirectory -eq '') { $InventoryDirectory = Join-Path $Root 'tests/conformance' }
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $InventoryDirectory 'suite.json') |
        ConvertFrom-Json -AsHashtable -Depth 32
    if ($manifest.schema_version -ne 1 -or $manifest.reference_revision -ne $script:ReferenceRevision -or
        $manifest.source_root -ne 'references/lua/testes') { throw 'Invalid pinned suite manifest' }
    Test-ConformanceReferenceTree -Root $Root
    $expectedNames = @('all.lua','api.lua','attrib.lua','big.lua','bitwise.lua','bwcoercion.lua',
        'calls.lua','closure.lua','code.lua','constructs.lua','coroutine.lua','cstack.lua','db.lua',
        'errors.lua','events.lua','files.lua','gc.lua','gengc.lua','goto.lua','heavy.lua','literals.lua',
        'locals.lua','main.lua','math.lua','memerr.lua','nextvar.lua','pm.lua','sort.lua','strings.lua',
        'tpack.lua','tracegc.lua','utf8.lua','vararg.lua','verybig.lua')
    $actualNames = @(Get-ChildItem -LiteralPath (Join-Path $Root $manifest.source_root) -Filter '*.lua' |
        ForEach-Object Name | Sort-Object)
    if (($actualNames -join '|') -cne ($expectedNames -join '|')) { throw 'Pinned suite file set changed' }
    $contexts = @($manifest.acceptance_contexts)
    if ($contexts.Count -ne 26 -or @($contexts | Select-Object -Unique).Count -ne 26) {
        throw 'Expected 26 distinct acceptance contexts (18 default, 6 test, 2 static-PIC)'
    }
    foreach ($context in $contexts) {
        if ($context -notmatch '^(default|upstream-test)/(windows|linux|macos)/(development|validation|release)/(static|shared|static-pic)$') {
            throw "Invalid acceptance context: $context"
        }
    }
    $expectedContexts = [Collections.Generic.List[string]]::new()
    foreach ($os in @('windows','linux','macos')) {
        foreach ($profile in @('development','validation','release')) {
            foreach ($link in @('static','shared')) { $expectedContexts.Add("default/$os/$profile/$link") }
        }
        foreach ($link in @('static','shared')) { $expectedContexts.Add("upstream-test/$os/validation/$link") }
    }
    $expectedContexts.Add('default/windows/validation/static-pic')
    $expectedContexts.Add('upstream-test/windows/validation/static-pic')
    if ((@($contexts | Sort-Object) -join '|') -cne (@($expectedContexts | Sort-Object) -join '|')) {
        throw 'Acceptance context set changed'
    }
    if (@($manifest.configurations).Count -ne 2) { throw 'Expected two isolated configurations' }
    $configurationIds = @{}
    foreach ($configuration in $manifest.configurations) {
        if ($configurationIds.ContainsKey($configuration.id)) { throw 'Duplicate configuration' }
        $configurationIds[$configuration.id] = $true
        $expectedSettings = switch ($configuration.id) {
            'default' { @{lua_compat_global=1;lua_compat_mathlib=$false;lua_rand32=$false;
                extra_space='sizeof(void*)';max_stack=1000000;max_ccalls=200} }
            'upstream-test' { @{lua_compat_global=0;lua_compat_mathlib=$true;lua_rand32=$true;
                extra_space='sizeof(struct L_EXTRA)';max_stack=68000;max_ccalls=180;lual_buffersize=23} }
            default { throw 'Unknown conformance configuration' }
        }
        foreach ($key in $expectedSettings.Keys) {
            if ($configuration[$key] -cne $expectedSettings[$key]) { throw "Configuration drift: $($configuration.id)/$key" }
        }
    }
    $exclusions = @{}; $resolvedExclusions = @{}
    if ($TargetPolicy -ceq 'remaining-upstream-compatibility') {
        # The selected target has an explicit, separately reviewed overlay.
        # Old callers never read it and retain their strict completion rule.
        $policyPath = Join-Path $InventoryDirectory 'targets/remaining-upstream-compatibility.exclusions.json'
        $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
        if ($policy.schema_version -ne 1 -or $policy.target -cne $TargetPolicy -or
            $policy.reference_revision -cne $script:ReferenceRevision -or
            -not $policy.Contains('exclusions')) { throw 'Invalid target exclusion policy identity' }
        $null = Get-ConformanceExclusionBaseline -Root $Root
        Assert-ConformanceExclusionBaselineBinding -Bindings @($policy.protected_scopes)
        foreach ($exclusion in $policy.exclusions) {
            if ($exclusion.source -cnotin $expectedNames -or
                $exclusion.id -cnotmatch '^LUA-[A-Z0-9]+-(ASSERT-CALL|REVIEWED-BLOCK)-[0-9]{4}$' -or
                $exclusions.ContainsKey($exclusion.id)) { throw 'Unknown or duplicate source exclusion' }
            $exclusions[$exclusion.id] = $exclusion
        }
        foreach($exclusion in $exclusions.Values){
            if((Get-ConformanceExclusionEligibilityVersion $exclusion) -eq 2 -and
                $exclusions.ContainsKey($exclusion.retained_parent.id)){throw 'V2 retained original parent cannot itself be excluded'}
        }
    }
    $seenFiles = @{}; $seenUnits = @{}; $unitCount = 0; $pending = 0
    foreach ($file in $manifest.files) {
        if ($file.path -notin $expectedNames -or $seenFiles.ContainsKey($file.path)) { throw 'Unknown/duplicate suite file' }
        if ($file.id -cne ('LUA-' + $file.path.Replace('.lua','').ToUpperInvariant())) { throw 'Invalid suite file ID' }
        $seenFiles[$file.path] = $true
        $role = switch ($file.path) {
            'all.lua' { 'orchestrator' } 'heavy.lua' { 'stress' }
            { $_ -in @('tracegc.lua','bwcoercion.lua') } { 'helper' }
            default { 'primary' }
        }
        if ($file.role -ne $role) { throw "Wrong suite role: $($file.path)" }
        if ($file.path -in @('tpack.lua','utf8.lua','bitwise.lua')) {
            if ($null -eq $file.m2b_execution -or
                $file.m2b_execution.revision -cne '52e8eb62466c5852b3995dc99b751c1d477dc9c2' -or
                $file.m2b_execution.evidence -cne 'https://github.com/itsuki-hayashi/lua-ada/actions/runs/42090465632' -or
                $file.m2b_execution.status -cne 'historical-m2b-execution-pass' -or
                $file.m2b_execution.configuration -cne 'default' -or $file.m2b_execution.T -cne 'absent') {
                throw "Invalid historical M2b evidence: $($file.path)"
            }
        }
        elseif ($null -ne $file.m2b_execution) { throw "Invented M2b pass: $($file.path)" }
        $bytes = [IO.File]::ReadAllBytes((Join-Path $Root "$($manifest.source_root)/$($file.path)"))
        if ($file.sha256 -cne (Get-ConformanceHash -Bytes $bytes)) { throw "Source hash drift: $($file.path)" }
        if ($file.coverage_file -cne ('coverage/' + $file.path.Replace('.lua','.jsonl'))) { throw 'Unsafe coverage path' }
        $expected = @(Get-ConformanceCoverageUnits -Path $file.path -Bytes $bytes)
        $records = @(Read-ConformanceJsonLines -Path (Join-Path $InventoryDirectory $file.coverage_file))
        $indexed = @{}
        foreach ($record in $records) {
            if ($record.id -notmatch '^LUA-[A-Z0-9]+-[A-Z-]+-[0-9]{4}$' -or $seenUnits.ContainsKey($record.id)) {
                throw "Invalid/duplicate unit ID: $($record.id)"
            }
            $seenUnits[$record.id] = $true; $indexed[$record.id] = $record
            $unitCount++
            if ($record.status -eq 'pending') { $pending++ }
            $excluded = $exclusions.ContainsKey($record.id)
            Test-ConformanceResolvedRecord -Record $record -Contexts $contexts `
                -RequireComplete:($RequireComplete -and -not $excluded)
            if ($excluded) {
                $resolvedExclusions[$record.id] = Test-ConformanceTargetExclusion -Root $Root `
                    -Source $file.path -SourceBytes $bytes -Record $record -Exclusion $exclusions[$record.id]
            }
        }
        # Comparing regenerated sites prevents deletion of an inconvenient
        # assertion from converting an incomplete ledger into a passing one.
        if ($records.Count -lt $expected.Count) { throw "Coverage anchor set changed: $($file.path)" }
        foreach ($anchor in $expected) {
            if (-not $indexed.ContainsKey($anchor.id)) { throw "Missing source anchor: $($anchor.id)" }
            foreach ($field in @('kind','byte_offset','byte_length','line','end_line','anchor_sha256')) {
                if ($indexed[$anchor.id][$field] -cne $anchor[$field]) { throw "Anchor drift: $($anchor.id)/$field" }
            }
        }
        $expectedIds = @{}; foreach ($anchor in $expected) { $expectedIds[$anchor.id] = $true }
        foreach ($record in $records) {
            if ($expectedIds.ContainsKey($record.id)) { continue }
            $stem = $file.path.Replace('.lua','').ToUpperInvariant()
            if ($record.kind -ne 'reviewed-block' -or
                $record.id -cnotmatch ('^LUA-' + $stem + '-REVIEWED-BLOCK-[0-9]{4}$') -or $record.byte_offset -lt 0 -or
                $record.byte_length -le 0 -or $record.byte_offset -gt $bytes.Length -or
                $record.byte_length -gt $bytes.Length - $record.byte_offset) {
                throw "Invalid manually expanded source block: $($record.id)"
            }
            $span = [byte[]]::new($record.byte_length)
            [Array]::Copy($bytes, $record.byte_offset, $span, 0, $span.Length)
            if ($record.anchor_sha256 -cne (Get-ConformanceHash -Bytes $span)) {
                throw "Manual block hash drift: $($record.id)"
            }
            $text = [Text.Encoding]::Latin1.GetString($bytes)
            $startLine = 1 + [regex]::Matches($text.Substring(0, $record.byte_offset), '\r\n|\n\r|\n|\r').Count
            $endLine = 1 + [regex]::Matches($text.Substring(0, $record.byte_offset + $record.byte_length), '\r\n|\n\r|\n|\r').Count
            if ($record.line -ne $startLine -or $record.end_line -ne $endLine) {
                throw "Manual block source line drift: $($record.id)"
            }
        }
        foreach($exclusion in $resolvedExclusions.Values){
            if($exclusion.source -ceq $file.path -and (Get-ConformanceExclusionEligibilityVersion $exclusion) -eq 2){
                Assert-ConformancePrivateBoundParentRecord -Exclusion $exclusion -Records $indexed -Exclusions $exclusions
            }
            if($exclusion.source -ceq $file.path -and (Get-ConformanceExclusionEligibilityVersion $exclusion) -eq 3){
                Assert-ConformanceOptimizerParentRecords -Bytes $bytes -Exclusion $exclusion -Records $indexed -Exclusions $exclusions
            }
        }
        Test-ConformanceSourceLinks -Records $records -RequireComplete:$RequireComplete `
            -TargetPolicy $TargetPolicy -ResolvedExclusions $resolvedExclusions
    }
    if ($seenFiles.Count -ne 34) { throw 'Missing suite files' }
    if ($resolvedExclusions.Count -ne $exclusions.Count) { throw 'Exclusion names a missing source obligation' }
    foreach ($header in $manifest.headers) {
        if ($header.path -notin @('lua.h','lauxlib.h','lualib.h','luaconf.h','ltests.h')) { throw 'Unknown header path' }
        $bytes = [IO.File]::ReadAllBytes((Join-Path $Root "references/lua/$($header.path)"))
        if ($header.sha256 -cne (Get-ConformanceHash -Bytes $bytes)) { throw "Header hash drift: $($header.path)" }
    }
    $headerNames = @('lua.h','lauxlib.h','lualib.h','luaconf.h','ltests.h')
    if ((@($manifest.headers.path | Sort-Object) -join '|') -cne (@($headerNames | Sort-Object) -join '|')) {
        throw 'Missing/duplicate header inventory'
    }
    $expectedApi = @(Get-ConformanceApiInventory -Root $Root)
    $api = @(Read-ConformanceJsonLines -Path (Join-Path $InventoryDirectory 'c-api.jsonl'))
    if ($api.Count -ne $expectedApi.Count) { throw 'C API anchor set changed' }
    $seenApi = @{}
    foreach ($entry in $api) {
        if ($seenApi.ContainsKey($entry.id)) { throw "Duplicate C API ID: $($entry.id)" }
        $seenApi[$entry.id] = $entry
        Test-ConformanceResolvedRecord -Record $entry -Contexts $contexts -Api -RequireComplete:$RequireComplete
    }
    foreach ($entry in $expectedApi) {
        if (-not $seenApi.ContainsKey($entry.id)) { throw "Missing C API entry: $($entry.id)" }
        foreach ($field in @('header','kind','name','line','byte_offset','byte_length','anchor_sha256','declaration')) {
            if ($seenApi[$entry.id][$field] -cne $entry[$field]) { throw "C API anchor drift: $($entry.id)/$field" }
        }
        if (($seenApi[$entry.id].conditions -join "`n") -cne ($entry.conditions -join "`n")) {
            throw "C API condition drift: $($entry.id)"
        }
    }
    [pscustomobject]@{ Files=34; SourceAnchors=$unitCount; PendingSourceAnchors=$pending;
        ApiEntries=$api.Count; PendingApiEntries=@($api | Where-Object status -CEQ 'pending').Count;
        Complete=([bool]$RequireComplete -and $resolvedExclusions.Count -eq 0);
        TargetPolicy=$TargetPolicy; TargetComplete=[bool]$RequireComplete;
        ExcludedSourceObligations=$resolvedExclusions.Count;
        RequiredPendingSourceAnchors=($pending - $resolvedExclusions.Count);
        Exclusions=@($resolvedExclusions.Values | Sort-Object id) }
}

Export-ModuleMember -Function Get-ConformanceHash, Get-ConformanceTokens,
    Get-ConformanceCoverageUnits, Get-ConformanceApiInventory,
    Read-ConformanceJsonLines, Write-ConformanceJsonLines,
    Test-ConformanceReferenceTree, Test-ConformanceResolvedRecord,
    Test-ConformanceSourceLinks, Test-ConformanceTargetExclusion, Test-ConformanceInventory
