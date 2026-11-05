# Frontend Compatibility

The [M2a contract](milestones/m2a.md) targets pinned default Lua 5.5.1.
Current validation is recorded in the [session](sessions/2026-11-06-m2a-frontend.md).

## Checking and execution

Lua.Syntax.Check accepts source bytes, an owned diagnostic source label, and
source/token/node/nesting limits. It returns Success, Syntax_Error, or
Resource_Error. Lexical and static-semantic rejection are syntax failures.
It exposes no trees or runtime objects and has no Lua side effects.

The CLI accepts --check with files, stdin, repeated -e, and --. Each source is
a separate chunk. It stops on the first failure, prints errors on stderr, and
emits no normal output. Script arguments are accepted but unused. File inputs
retain BOM/shebang loader behavior; raw source and -e do not acquire it.

Lua.Sessions.Execute shares this parser. Valid goto/label/close chunks return
Unsupported_Feature before executing any part, including nested/unreachable
constructs. Invalid source still returns Syntax_Error before this feature gate.
Execution_Status has this additional literal; exhaustive consumers must handle
it. Diagnostic is now an alias of Lua.Diagnostics.Diagnostic with the same
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

C stack exhaustion, bytecode register allocation/limits, code-size limits,
constant folding/optimization, and exact instruction streams are excluded.
C's 200 stack-local/255-upvalue representational constraints are not reproduced
as grammar restrictions; Ada can accept source that fits its configured limits.
No excluded implementation limit is counted as matching parser rejection.
Diagnostics compare syntax/resource category and reported line, not wording.

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
