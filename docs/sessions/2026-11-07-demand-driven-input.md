# Demand-driven input checkpoint

Date: 2026-11-07, Asia/Tokyo.

## Objective and scope

Complete the public C reader boundary begun in `ab5e482` without text overread
or repeated binary-prefix decoding. This is a component of the authorized
remaining upstream delivery. Integration, complete T-enabled Lua-file execution,
the platform matrix, PR review and final acceptance remain with that delivery.

The shared lexer, resolving parser and binary decoder now consume either a
borrowed whole buffer or a managed growing `Lua.Inputs.Source`. Each foreign
reader piece is copied before another callback may invalidate it. The existing
algorithms demand bytes directly; no second grammar or speculative reparse is
used. The existing static-buffer APIs keep synchronous borrowed input.

A guarded C refill catches reader errors, attempted yields and host aborts above
the suspended Ada frontend, returning typed outcomes so partial syntax/model and
input storage can be finalized. Reentrant reader API calls use the original
universe, allocator, registry, execution driver and bounded work counter. The
empty transient operation lease is renewed after a callback, without restarting
those counters. Native current-byte lexical lookahead and binary fixed-piece
requirements remain observable. ADR [0019](../decisions/0019-demand-driven-input.md)
records ownership, alternatives and limits.

`Lua.Syntax.Check_Result.Incomplete_Input` is additive host metadata. Only
unfinished quoted/long tokens and explicit grammar expectations at actual EOF
set it. Malformed escapes/numerals, static-semantic/resolver failures, resources
and success leave it false. This gives the CLI one shared grammar fact rather
than diagnostic-text matching. The root agent's managed malformed-number
diagnostic patch is included in this checkpoint.

## Tools and commands

Windows x86-64; Alire 2.1.1; GNAT 16.1.0; GPRbuild package 26.0.1 with banner
26.0.0 (2026-04-15-gpr2), target `x86_64-w64-mingw32`. No compiler selection or
manifest pin was changed. All first-party Ada builds retain the required strict
Ada 2022, warning, style and runtime-check policy.

The serialized local build window ran:

```text
alr -n build --validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
alr -n -C tests build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
alr exec -- tests/bin/static/test_runner.exe
alr exec -- build/c-api/bin/validation/static/load_dump_api_contract.exe
alr exec -- build/c-api/bin/validation/static/c_api_consumer.exe
```

The unchanged `scripts/check-canonical-compiler.ps1` then ran execution-only
against the newly built local compiler/runtime probes and the existing pinned
native default interpreter. An execution-only frontend/opcode replay used the
existing seeded corpus and native oracle binaries, capturing full raw outputs
and hashes before comparing them. No additional Alire build ran during another
agent's build window. Local logs are under ignored `reports/demand-input/`.

The same standalone C reader/writer contract source was compiled as a C99
consumer of the separately built pinned native default and `upstream-test`
libraries. Native configuration identities report Lua 5.5.1, default without T
and `upstream-test` with T respectively. The reference submodule was initialized
for the canonical guard and remains unchanged at
`7579fc9d7ed90240487251dfb69168f8e64e9294`.

## Results

- Strict runtime, C consumer and nested test builds pass. The first runtime
  attempt rejected a missing prior local `Peek` specification; that cause was
  repaired before the passing builds, with no warning/style suppression.
- All 1,412 AUnit cases pass: zero assertion failures and unexpected errors.
  Twenty new separately named cases cover three real C-reader bounded-host
  policies and seventeen structured incomplete-input boundaries.
- All twenty-eight standalone reader/writer cases and the complete retained C
  consumer pass. Standalone output is byte-identical to both pinned native
  configurations. New cases cover early error versus reader side effects,
  native punctuation prefetch, split text tokens, recursive Lua/API execution,
  nested guarded readers, every two-piece binary split, B-mode contiguous-block
  requirements, partial-model error cleanup and 16,384 one-byte input pieces.
  Existing cases retain callback stack/error identity, writer terminal/status
  and allocator refusal/recovery coverage. The counted consumer closes with
  zero outstanding allocator blocks or bytes.
- Execution-only frontend comparisons pass 10,000 seeded arbitrary lexer
  inputs, the allocation-pressure diagnostic, 2,000 grammar programs, 2,000
  mutations, all thirty-four upstream source lex/parse pairs and 4,182 opcode
  records. These are frontend/opcode checks, not Lua-file runtime acceptance.
  An initial temporary replay-script invocation selected PowerShell's `Compare`
  alias; the corrected wrapper and all actual comparisons pass.
- The unchanged canonical campaign passes thirty-six four-way C/Ada
  compiler/runtime interoperability cases. `git diff --check` passes.

## Limits and integration handoff

These are local Windows/default/validation/static Ada results. Running this
checkpoint with the integrated Ada `upstream-test` configuration, shared builds,
other platforms and the full remaining Lua-file campaign is still required.
Native T contract output does not establish Ada T acceptance. Source storage
remains linear in all supplied bytes; decoded code/strings retain Ada ownership
even in B mode. No native private allocation-layout equivalence is claimed.

The root integration must preserve independent debug/compiler source metadata
changes while taking this checkpoint's parser overloads and EOF facts. The root
already owns the previous lexer diagnostic checkpoint; only the subsequent
streaming commit is needed. Current status/backlog and the major-delivery
handoff remain owned by that integration, so this dated record does not replace
their current-session pointer or make a complete-conformance claim.
