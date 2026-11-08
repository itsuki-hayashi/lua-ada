# Frontend Compatibility

The [M2a contract](milestones/m2a.md) targets pinned default Lua 5.5.1.
Current validation is recorded in the [session](sessions/2026-11-06-m2a-frontend.md).

## Checking and execution

Lua.Syntax.Check accepts source bytes, an owned diagnostic source label, and
source/token/node/nesting limits. It returns Success, Syntax_Error, or
Resource_Error. Lexical and static-semantic rejection are syntax failures.
It exposes no trees or runtime objects and has no Lua side effects.

Syntax diagnostics retain pinned token spellings and near-token context through
allocator-owned buffers. Semantic binding/goto errors retain source-line detail
and omit lexical context. Lua string-load errors share debug's bounded chunk
identifier; reader loads keep their explicit/default labels. The
[diagnostic checkpoint](sessions/2026-11-08-syntax-diagnostic-tokens.md) records
focused native/Ada evidence and the remaining runtime-error obligations.

`Check_Result.Incomplete_Input` reports an unfinished quoted/long token or a
grammar expectation at actual EOF. Interactive hosts can request more input
from this structured fact, without inspecting diagnostic wording or introducing
another grammar. Successful chunks, resource failures, malformed numerals or
escapes, and static-semantic/resolver errors return false. In particular, an
unresolved goto stays a final error even though label resolution happens after
the scanner reaches EOF.

Whole-buffer and foreign-reader loading share the same scanner, parser and
checked binary decoder through the private demand-driven input boundary. See
[ADR 0019](decisions/0019-demand-driven-input.md) for ownership, guarded refill
and work-budget rules; the final delivery's runtime/platform evidence remains
separate from that implementation decision.

The CLI accepts --check with files, stdin, repeated -e, and --. Each source is
a separate chunk. It stops on the first failure, prints errors on stderr, and
emits no normal output. Script arguments are accepted but unused. File inputs
retain BOM/shebang loader behavior; raw source and -e do not acquire it.

Lua.Sessions.Execute shares this parser. Goto/label/close constructs now lower
to executable lifecycle operations. Complete-source syntax validation still
precedes every execution effect, including nested and unreachable constructs.
Invalid source returns Syntax_Error. Execution_Status retains Unsupported_Feature
for future execution boundaries; exhaustive consumers must still handle it. Diagnostic is now an alias of Lua.Diagnostics.Diagnostic with the same
fields. Execution limits add Syntax_Nodes and Syntax_Depth.

## Behavior inventory

- Lexical: every keyword/operator, contextual global, ASCII identifiers,
  fallback byte tokens, int64/binary64 numerals, escapes, extended UTF-8,
  long strings/comments, newline variants, EOF/lookahead, malformed input.
- Expressions: precedence/associativity, calls/methods, table fields,
  assignability, parentheses, scalar/list boundaries, varargs and functions.
- Resolution: source-point bindings, recursive local functions, captures,
  _ENV, explicit/collective global declarations, const and close attributes.
- Statements: blocks, assignments, return placement, all loops, break,
  labels/gotos with visibility, scope-entry and terminal-label checks.
- Opcode format: all 85 IDs/names/metadata, all six formats, checked operands,
  excess-K signed encoding, top predicates, and unrelated-bit preservation.

Lua 5.5 numeric-for and first generic-for control variables are const.
Additional generic-for values remain mutable. This corrects an M1 test that
previously assigned the numeric control variable.

## Limits and comparison domain

Defaults: 1,000,000 source bytes, 100,000 tokens including EOF, 200,000 syntax
nodes/declarations, nesting 200. Runtime register limits remain independent.
These are bounded-work/storage controls, not a hard OS memory quota.

The standalone M2a checking comparison excludes C stack exhaustion, bytecode
register allocation/limits, code-size limits, constant folding/optimization
and exact instruction streams. Its grammar checker does not impose C's
200-local/255-upvalue compiler constraints. That bounded checking domain does
not exclude the separate M3 runtime obligations or certify their acceptance.
M2a diagnostics compare syntax/resource category and reported line, not wording.

Canonical execution enforces its actual local, upvalue and register encoding
limits. Compatible parsing checks explicit local limits as names arrive,
preserving their precedence over later incomplete grammar; compiler-limit
diagnostics retain the actual defining function's line. See the
[context checkpoint](sessions/2026-11-08-compiler-limit-context.md).
Under Lua_Compatible policy, excessive parser nesting is a catchable
runtime stack failure with the original C-stack error text; public lua_load
returns LUA_ERRRUN, preserving its distinction from LUA_ERRSYNTAX. Both
contiguous and streamed input use the same parser. Function bodies charge
their recursive block once. Bounded Ada sessions and standalone checking keep
their configured host-depth accounting and Resource_Error behavior. The
[parser limit checkpoint](sessions/2026-11-08-parser-stack-limits.md) records
focused evidence; full source and final matrix acceptance remain separate.

## Oracle workflow

Build the nested test crate, then run from the root environment:

```powershell
alr exec -- pwsh -NoProfile -File scripts/check-frontend.ps1
```

Pass -Probe and -OpcodeProbe for a different library kind. CI runs this on
each target OS in static-validation. It compares 10,000 seeded byte cases,
2,000 valid grammar cases and 2,000 mutations, all 34 unchanged upstream source
files, and 4,096 instruction words plus all opcode metadata. Reports/corpora
live under ignored reports/. Seed 551 and the generation rules are tracked
in the driver. Failures retain the corpus and identify the mismatching record.

The two upstream files with leading # preambles reject identically in raw
parse mode. CLI file-loader checking additionally accepts those preambles.
These are syntax/token checks, not upstream execution-suite passes.

## Acceptance mapping

Names below identify independently reported cases/families; the opcode mapping
is exhaustive by mnemonic. The generated campaign supplements these focused
cases without replacing their human-readable regression descriptions.

| Behavior                               | First-party evidence                                                     |
| -------------------------------------- | ------------------------------------------------------------------------ |
| Keywords / punctuation / literals      | Lexer_Tests.Keywords, Longest_Operators, string/escape cases             |
| Numeral values / boundaries            | Incremental_Lexer_Tests.Numeric_Payloads, Hex_Exponent_Boundary          |
| Incremental state / diagnostics        | Incremental_Lexer_Tests terminal cases; Syntax_Before_Lexical            |
| Scopes / capture identity              | Session_Tests.Local_Shadowing, Captured_Mutation, For_Iteration_Captures |
| Globals / attributes / const           | Syntax_Tests declaration cases; Session_Tests global cases               |
| Functions / varargs / results          | Syntax_Tests function cases; Session_Tests result/vararg cases           |
| Control flow / labels / gotos          | Syntax_Tests loop and goto families; session loop regressions            |
| Runtime rejection / recovery           | Syntax_Tests.Unsupported_No_Effects, Syntax_Precedes_Unsupported         |
| Ownership / resource bounds            | Syntax_Tests budget cases; existing Lifecycle_Tests                      |
| Each canonical opcode                  | Lua.Opcode_Tests.Test_<mnemonic> (one case for each of 85 entries)       |
| Instruction fields / top / invalid IDs | Lua.Opcode_Tests boundaries, predicates, invalid words, round trips      |
| Generated / upstream comparisons       | scripts/check-frontend.ps1; tests/src/lexer_probe.adb                    |
| Embedding / process interface          | tests/src/syntax_consumer.adb; scripts/check-cli.ps1                     |
