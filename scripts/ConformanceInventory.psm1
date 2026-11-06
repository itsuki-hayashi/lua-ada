Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ReferenceRevision = '7579fc9d7ed90240487251dfb69168f8e64e9294'
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)

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

function Test-ConformanceResolvedRecord {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Record,
          [Parameter(Mandatory)][string[]] $Contexts,
          [switch] $Api, [switch] $RequireComplete)
    if ($Record.status -notin @('pending', 'passed')) { throw "Invalid status: $($Record.id)" }
    if ($Record.status -eq 'pending') {
        if ($RequireComplete) { throw "Unresolved coverage: $($Record.id)" }
        if (-not $Api -and $Record.disposition -ne 'pending') {
            throw "Pending coverage has completed disposition: $($Record.id)"
        }
        if (@($Record.evidence).Count -ne 0) { throw "Pending coverage has pass evidence: $($Record.id)" }
        return
    }
    if (-not $Api) {
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
        if ($Record.disposition -in @('ada-internal-equivalent', 'native-platform-equivalent') -and
            [string]::IsNullOrWhiteSpace($Record.review.original_c_evidence)) {
            throw "Equivalent lacks original C evidence: $($Record.id)"
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

function Test-ConformanceInventory {
    param([Parameter(Mandatory)][string] $Root,
          [string] $InventoryDirectory = '', [switch] $RequireComplete)
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
            Test-ConformanceResolvedRecord -Record $record -Contexts $contexts -RequireComplete:$RequireComplete
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
    }
    if ($seenFiles.Count -ne 34) { throw 'Missing suite files' }
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
        ApiEntries=$api.Count; Complete=[bool]$RequireComplete }
}

Export-ModuleMember -Function Get-ConformanceHash, Get-ConformanceTokens,
    Get-ConformanceCoverageUnits, Get-ConformanceApiInventory,
    Read-ConformanceJsonLines, Write-ConformanceJsonLines,
    Test-ConformanceReferenceTree, Test-ConformanceResolvedRecord, Test-ConformanceInventory
