# M2a: Frontend and Opcode Definition Parity

Accepted: 2026-11-06, Asia/Tokyo. Status: **in progress**.

## Contract

Target pinned Lua 5.5.1 commit
`7579fc9d7ed90240487251dfb69168f8e64e9294`: int64, binary64,
ASCII classification, and default LUA_COMPAT_GLOBAL=1.

Deliver complete lexical and grammar/static-semantic coverage, a shared
owned syntax representation and VM lowering pass, a side-effect-free
Lua.Syntax.Check API, CLI --check, and all 85 canonical opcode definitions.

Diagnostics match failure category and reported line; wording remains Ada's.
Resource exhaustion is separate from syntax failure. C register allocation,
instruction-size limits, optimization decisions, and platform-dependent
C-stack exhaustion are outside this frontend contract and must be inventoried.

## Delivery gates

- FRONT-001: shared frontend design, behavior inventory, baseline evidence.
- ORACLE-002: isolated protected C lex/parse and opcode inspection adapters.
- LEX-002: incremental tokens, payloads, malformed input, locations, budgets.
- PARSE-002: complete grammar/resolution, labels/gotos, const/close, scopes.
- OPCODE-001: IDs, metadata, six formats, checked bit encoding and decoding.
- CHECK-001: shared lowering, Ada checking, CLI checking, unsupported status.
- ACCEPT-002: all 18 OS/profile/link jobs; oracle campaigns on each OS;
  ABI probes and Windows static-PIC; final verified pull request.

Each item needs recorded evidence before completion. Implementation order may
exercise the independent opcode gate before the parser refactor.

## Verification

Use focused, individually named, commented AUnit cases. Compare at least
10,000 bounded byte inputs, 2,000 valid grammar inputs and 2,000 mutations,
and 4,096 instruction words against the isolated pinned oracle. Retain seeds
and mismatch regressions. Compare all 34 unchanged upstream files in
parse-only mode; source acceptance is not execution-suite conformance.

Checking supports files, stdin, repeated snippets, arguments, and --.
Valid goto/label/close chunks check successfully; execution returns a distinct
Unsupported_Feature before any side effects. Syntax errors take precedence.

## Boundaries

The current M1 VM remains the execution backend. Canonical code generation,
full opcode execution, binary chunks, metamethods, close execution, libraries,
C ABI, and ecosystem fixtures are later work. No runtime dependency is added.
The [session](../sessions/2026-11-06-m2a-frontend.md) owns current evidence.

