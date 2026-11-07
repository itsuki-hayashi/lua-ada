# Debug metadata checkpoint

Date: 2026-11-07, Asia/Tokyo. Status: locally verified component checkpoint;
remaining upstream coverage and platform acceptance are still open.

The remaining-upstream delivery adds real `debug.getinfo(..., "t").extraargs`
metadata and corrects active-line observations. The private activation owns the
number of receivers inserted by its entry `__call` chain. Frame caching resets
the scalar, coroutine suspension retains it, and Lua-to-Lua tail replacement
preserves the original logical frame's value. A native tail call receives its
new chain's value. This distinction follows the pinned `luaD_pretailcall` in
`ldo.c`; an initial interpretation that every tail replacement should report
the new chain was rejected by the native C observations before Ada testing.

Native functions now have no `activelines` field. Lua functions stripped of
line information retain an empty active-line table and report current line
`-1`, rather than the decoder's internal zero sentinel. Canonical vararg entry
setup is excluded from active source lines, following `collectvalidlines` in
pinned `ldebug.c`. Nine separately named AUnit cases cover these observations.
The deterministic `tests/lua/debug_metadata.lua` probe records the same public
results against both runtimes. Reference bytes and pins remain unchanged.

## Verification

Alire 2.1.1 and native GNAT 16.1.0 were used without changing global toolchain
selection. Required warning/style flags and runtime checks remain enabled.

```text
alr -n build --validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=false
alr -n -C tests build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=true
tests/bin/static/test_runner.exe
tests/bin/static/conformance_runner.exe tests/lua/debug_metadata.lua
```

Both builds passed. The AUnit runner reports 1,399 successful cases, zero failed
assertions and zero unexpected errors, including all nine added cases. The
native default C Lua and Ada probe processes both exit successfully with empty
stderr and byte-identical stdout. The instrumented native C oracle also passes
the probe. Local logs are under ignored `reports/debug-metadata`.

Before the fix, the existing root binary independently reported missing
`extraargs`, an invented native active-line table, the vararg declaration line
as active, and current line zero in stripped code. Its complete probe fails on
the missing count; these observations establish the concrete regressions.

## Remaining boundary

Direct execution of unchanged `db.lua` reaches its source metadata assertion
at line 42 and fails because the current CLI/loadfile route supplies a bare
filename as a snippet source rather than an `@` file source. That separate
loading boundary is not repaired by this checkpoint. No whole-file `db.lua`
pass, full T completion, C debug API completion or final matrix pass is claimed.

## Canonical return and closure line follow-up

The explicit `@db.lua` diagnostic route isolates source classification from
inspection. Its first line-hook test exposed a root implicit return attributed
to the last lowered else assignment rather than the final consumed end token.
The shared frontend now retains its existing consumed-token line on the root
node. A short vector reference updates that scalar in place, without copying
the input-sized child list, allocating, or rescanning source. Nested functions
retain their existing closing end line. Canonical final returns use this owned
metadata, following `lparser.c:close_func` and `lcode.c:luaK_code`.

The next trace exposed multiline closure creation on its opening token rather
than the consumed end token. The canonical closure instruction and its explicit
recursive-local nil initialization now share that end line. The initialization
remains in place for root/capture safety; the child's definition range is
unchanged. The first attempt corrected only the closure word and failed the new
test because the initialization still emitted an extra opening-line event.
That failure was inspected and repaired rather than omitted.

Five new named AUnit cases cover the root if/else trace, closure creation,
trailing comments/newlines, an empty root, and a nested function's own end.
The deterministic `tests/lua/debug_return_lines.lua` probe passes native C in
both configurations. Final default Windows validation/static verification is:

- Both strict root and nested-test builds pass.
- All 1,404 AUnit cases pass, with zero assertion failures or unexpected errors.
- C/Ada probe stdout is byte-identical; both processes exit zero with empty
  stderr.
- The official 36-case four-way canonical compiler/runtime campaign passes.
- The official frontend/opcode campaign passes 10,000 arbitrary-byte cases,
  2,000 generated grammar cases, 2,000 mutations, all 34 pinned lex/parse
  inputs, and the 85-opcode/4,096-word comparison.

The pinned reference submodule was initialized for those campaign guards and
remains clean at its original revision. The first canonical campaign attempt
was blocked by that unpopulated checkout; the first direct frontend attempt was
blocked by missing `gprbuild` on PATH. Neither was counted as passing. After
initialization, the frontend campaign ran through `alr exec` with the selected
toolchain environment and both official campaigns passed.

The remaining `db.lua` diagnostic now passes its first four line traces before
an explicit `return` reports the following end token's line (three) instead of
the return token's line (two). The parser currently creates that statement node
after consuming the keyword. This subsequent defect, full file execution and
all other acceptance contexts remain open.

## Return, parameter and iterator transfer checkpoint

The next checkpoint preserves the explicit return keyword site before parser
lookahead advances, and retains its final result token before an optional
semicolon. Fixed parameter debug lifetimes begin at PC zero before VARARGPREP;
the named/hidden vararg table begins after that instruction. Break uses its
keyword rather than the following end token. Numeric/generic loop control words
use the pinned forbody source sites, with separate consumed do and end token
metadata retained in the shared frontend. Those scalar updates use guarded
references rather than copying node child vectors.

A multiline generic header exposed a real dispatch discrepancy: pinned
TFORPREP immediately fetches its TFORCALL companion, and TFORCALL consumes its
TFORLOOP after the iterator returns. The Ada VM now follows those dispatch
phases through its existing explicit call continuation. It validates each real
companion and register base, publishes the same rooted argument/function state,
and resumes the loop branch only after results are stored, including after a
yield. Companion words remain charged to the common host work budget. No hook
is suppressed and no executor is recursively invoked. The actual implicit
generic closer is attributed to its consumed end token.

Fifteen newly named regressions cover returns, fixed parameter names, break,
numeric/generic loop sites, count-hook dispatch boundaries, iterator suspension,
error object and closer identity, hard-quota recovery, and persistent allocator
refusal during an iterator's native-operation call path. Initial verification
passed 1,413 of 1,414 cases before actual iterator companion dispatch was added.
The next verification passed 1,418 of 1,419: the remaining count witness exposed
the compiler's generic closer still using the iterator line. Its end-token
attribution was corrected. Final default Windows validation/static evidence:

- Both strict builds pass; 1,419 AUnit cases pass with zero failed assertions
  and zero unexpected errors.
- `debug_return_lines.lua` and `debug_iterator_transfer.lua` have byte-identical
  C/Ada stdout, successful exits and empty stderr. Native C also passes the
  transfer probe in the instrumented configuration and the separate real
  allocator-refusal/recovery witness.
- All 36 four-way canonical compiler/runtime cases pass.
- Existing frontend/opcode oracles replay successfully against the fresh Ada
  probes: 10,000 arbitrary-byte inputs, 2,000 grammar cases, 2,000 mutations,
  all 34 unchanged lex/parse inputs, and 85 opcodes/4,096 words. No oracle
  rebuild was needed for this execution-only replay.

Two capped read-only Claude Haiku investigations were inspected. Its source
analysis identified deferred target/index materialization as the next real
assignment and line-hook issue. Its fusion review alleged missing count ticks
for companion words. That finding was rejected after reviewing the pinned
direct-fetch/goto paths and running identical C-produced bytecode graphs on
both runtimes: the empty iterator emits six count events, and the two-value
iterator emits thirteen in both. `debug_iterator_counts.lua` is the source for
that imported-bytecode witness; raw source compilers can emit different counts.
The review did not replace execution evidence or independent PR review.

The unmodified `db.lua` diagnostic now reaches its large-gap expression trace.
The next discrepancy is eager indexed/global target materialization and the
assignment store's opening-line attribution. Native probes also show actual
RHS mutation differences for local/upvalue environments and table operands.
Deferred operand/conflict handling is authorized follow-up work; it is not
claimed implemented here. Full debug-file and platform acceptance remain open.

## Deferred operand and assignment checkpoint

Shared prefix/expression/list nodes now retain their final consumed token using
a brief in-place metadata borrow. Canonical indexed descriptors distinguish
live local/upvalue table operands from computed register snapshots, and keys
distinguish register, short constant and immediate integer operands. Small
short-string upvalue accesses use actual GETTABUP/SETTABUP words. Nonconstant
keys force an upvalue table after key evaluation; computed bases remain
captured before their key/RHS. Later conflicting local/upvalue LHS targets
explicitly snapshot earlier receivers/keys before reverse-order assignment.
Ordinary RHS callbacks alone do not create those conflict snapshots.

The same distinction preserves live local arithmetic operands while indexed
operands are discharged before the RHS. Concatenation retains its separate
left-value snapshot. Indexed materialization uses actual consumer token lines,
and stores use the final RHS token. No hook is hidden or replaced with an
expected trace. The existing compiler environment test was updated to inspect
the real GETTABUP upvalue zero and owned key `x`, preserving its ownership and
resolution invariant instead of requiring the former eager helper sequence.

Sixteen separately named public-session regressions and their native fixture
cover local/upvalue environment changes, local table/key mutation, integer vs.
short-string upvalue capture, key callback timing, parallel conflicts, computed
base/key effects and GC roots, arithmetic/concat distinctions, large-gap trace
phases and store current-line inspection. Initial execution passed all sixteen
new cases and 1,434 of 1,435 total cases; the remaining failure was the old
helper-sequence structural assertion described above. Final local evidence:

- Strict default Windows validation/static root and test builds pass.
- All 1,435 AUnit cases pass with zero failed assertions or unexpected errors.
- `canonical_assignment_phases.lua` matches native C stdout byte-for-byte;
  both runtimes exit zero with empty stderr. Instrumented native C also passes.
- The fixture passes all four producer/runtime combinations: both C and Ada
  execute both producers' chunks with the same reference output and empty
  stderr. The retained 36-case four-way campaign passes too.
- Fresh existing frontend/opcode oracles match all 34 lexer/parser inputs,
  10,000 arbitrary-byte inputs, 2,000 grammar cases, 2,000 mutations, the
  allocation-pressure diagnostic, and 85 opcodes/4,096 words.

The unchanged-source `@db.lua` diagnostic now completes every generated
large-gap expression trace and reaches the hook callback inspection at line
312. Its hook frame does not yet report `namewhat == "hook"`. Hook/traceback
metadata is the next debug task. These component results do not establish a
whole-file debug pass, final instrumented Ada/platform acceptance, or a full
upstream completion claim.

## Hook origin and traceback checkpoint

Hook callbacks now carry their real `hook '?'` call origin across the explicit
hook continuation, following `ldebug.c:funcnamefromcall`. Ordinary descendant
calls retain their own names, and Lua tail replacement loses the callback's
name while retaining its real tail flag. Both getinfo and traceback share the
same lazy call-site inference; the interrupted opcode cannot supply the hook
callback's name.

Traceback now describes actual logical frames using `lauxlib.c:pushfuncname`
and `luaL_traceback`: inferred/stored names, main chunks, raw function identity
in the actual loaded-module registry, anonymous definition locations, unknown
native functions, unavailable-line omission, tail markers and the pinned
ten/eleven deep-stack split and skip count. Negative levels select no frame.
The temporary borrowed-frame snapshots use context-owned storage and preserve
the existing scheduler/error-owner exclusions. Table searches are bounded to
two levels, charge the shared work budget, ignore non-string keys and execute
no Lua callbacks. Empty string fields remain valid identities.

Fifteen separately named AUnit cases and `debug_traceback_phases.lua` protect
these behaviors. All thirteen initial probes failed with assertion diagnostics
against the pre-fix Ada binary, and the full fixture passes pinned native C in
both default and instrumented configurations. The initial strict build caught
an incorrect owner argument type in the new snapshots; using the existing
context owner fixed it without suppression. Final local evidence:

- Strict default Windows validation/static root and test builds pass with
  GNAT 16.1.0 and the retained required compiler switches/checks.
- All 1,450 AUnit cases pass, with zero failed assertions or unexpected errors.
- The fixture's C/Ada source executions have byte-identical stdout, successful
  exits and empty stderr.
- Both producers' chunks pass on both C and Ada, with the same native fixture
  output and empty stderr in all four combinations.
- `git diff --check` reports no whitespace errors.

The unchanged-source `@db.lua` diagnostic now passes the hook-origin,
traceback and exact four-event checks through line 322. It stops at line 328
because the real registry `_HOOKKEY` table is not yet implemented. The next
checkpoint must implement its actual weak-key callback storage, including
public registry mutation and coroutine lifetime semantics; an unused shape
placeholder would not establish that behavior. This is component evidence,
not full debug-file or final instrumented Ada/platform acceptance.
