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

## 2026-11-08 hook registry and inherited controls checkpoint

Lua hooks now use the actual weak-key `registry._HOOKKEY` callback mapping,
lazily created with its own `__mode='k'` self-metatable. The context records the
installed dispatcher controls independently and holds no hidden strong copy of
a Lua callback. Event dispatch and gethook raw-read the actual entry, including
replacement, removal and non-function entries. Lookup allocates no temporary
key string. A running callback becomes a rooted activation before constructing
event arguments, so replacing its own registry entry cannot collect it early.
Invalid replacement arguments and failed mapping growth precede installation
control changes. Valid disabled installations still store their callback as
the pinned debug library does.

New threads inherit their addressed parent's hook dispatcher, mask and base
count, with a reset countdown and no Lua callback mapping. The private
New_Thread optional Parent argument defaults to State.Current; the dependent C
boundary checkpoint supplies its addressed context explicitly. The actual low
byte mask is retained for both C and Lua installations. The original C int
mask controls removal, preserving a hook pointer for a nonzero mask whose
stored low byte is zero. The coordinated C boundary protocol exposes the real
callable Lua dispatcher and recognizes its restoration without replacing the
callback table; that new C glue is a separate dependent checkpoint.

An immutable marker identifies each actual C hook transport activation,
including after a hook replaces or removes itself. Frame enumeration and lazy
caller inference exclude that scheduler transport by its origin, rather than
comparing against the mutable current callback. Cached frame reuse clears the
marker. Calls from the actual C hook to Lua carry `hook '?'` across the explicit
C-owned boundary, as observed by the C boundary agent's pinned native probe;
nested ordinary C calls carry their own origin. Explicit origin names also
receive a frame-owned NUL-terminated buffer at activation construction for
allocation-free C debug borrowing. The dependent C consumer validates these
new C-facing paths after integration; they are not called passing here.

Inspection additionally accepts an optional already-validated borrowed target
frame, letting the C get/setlocal path reuse the actual Lua debug algorithms
without creating a synthetic runtime activation. The caller must validate its
frame token in the addressed context before using this private query path.

Thirteen newly named public-session regressions and `hook_registry_phases.lua`
cover actual registry identity, callback replacement/removal, non-functions,
disabled storage, replaced-closure collection, thread/callback ephemeron
cycles, active-frame rooting, inherited controls/mappings, invalid replacement
and independent thread entries. Final local evidence:

- Strict default Windows validation/static root and test builds pass on their
  first attempt with GNAT 16.1.0 and required switches/checks.
- All 1,463 AUnit cases pass with zero failed assertions or unexpected errors.
- The fixture passes pinned native default and instrumented C configurations.
- C/Ada source executions have byte-identical stdout and empty stderr; both
  producers' chunks also pass on both runtimes with that same output.
- `git diff --check` reports no whitespace errors.

A capped read-only Haiku review alleged that Pin accumulates hook callbacks
for an entire run. Source inspection rejects that finding: Machine.Step wraps
each individual scheduler phase in Begin_Operation/End_Operation, clearing the
temporary roots after the rooted activation is published. The focused active
and replaced callback collection tests pass. That review is not independent PR
approval and does not replace the pending real C consumer checks.

The unchanged-source `@db.lua` diagnostic now passes registry mode, collecting
hooks, source names and live-local mutation checks through line 414. Its next
failure is line 416: a function reads its caller's pending `(a+1)+f()` temporary
register, which must contain one. Compiler temporary placement and frame live
extent are the next measured debug task. Full db.lua, instrumented Ada and
platform/upstream acceptance remain open.

## 2026-11-08 caller temporary checkpoint

Unary/binary lowering now reuses an eventual result span while it is still
empty above the active bindings and no other live temporary follows it. The
capacity reservation remains, but it no longer invents a nil temporary before
a computed left operand. Actual callbacks and debug.setlocal therefore read
and edit the same pending register that the eventual opcode consumes. Earlier
return-list results, direct live locals, indexed scalars and vararg-adjusted
windows retain their separate ownership and evaluation rules.

The private allocation-free Inspection.Visible_Local_Top query follows actual
Previous_Stack_Window links. Caller temporaries stop before the immediate
child's function slot, whereas the collector intentionally roots that slot.
It ignores actual C hook transport and preserves current-frame bounds. Both
Lua getlocal/setlocal paths use this query; it is available for the dependent
C boundary to consume the same policy without duplicating it.

Eleven separately named public regressions and `debug_temporary_phases.lua`
cover pending reads/writes, callee/argument exclusion, nested arithmetic,
direct-local and unary calls, indexed operands, earlier results, suspension,
vararg base adjustment and managed operand rooting across collection. All
eleven fail at their intended assertions on the pre-fix Ada binary and pass
both pinned native C configurations. The first new strict build passes all
eleven but exposes five retained integer-provenance regressions: in-place
results now reveal that the reaching-write resolver counted the preceding
failed arithmetic word as a write at an MMBIN fallback. Applying the exact
`ldebug.c:findsetreg` testMMMode adjustment excludes that unexecuted write and
restores real field/global/upvalue provenance. No assertion was weakened.

Final default Windows validation/static evidence:

- Both strict root and test builds pass; all 1,474 AUnit cases pass, with zero
  failed assertions or unexpected errors.
- Native and Ada source fixture stdout hashes match and stderr is empty.
- Both producers' chunks pass on both runtimes with the same fixture output;
  all 36 retained four-way canonical compiler/runtime cases pass too.
- `git diff --check` reports no whitespace errors.

The unchanged-source `@db.lua` diagnostic advances from line 416 to line 526,
having passed the pending-operand read/write, temporary-bound and intervening
hook checks. The next checkpoint will synchronize this isolated checkout with
the main integration, including its already-verified transfer-offset fixes,
before diagnosing further debug/close metadata. These results do not establish
full db.lua, final instrumented Ada or full-upstream acceptance.

A separate bounded remaining-file census used identical native/Ada wrappers.
Its T-absent and soft-return results are diagnostics only. A later full-size
run used a disposable complete test-tree copy verified byte-for-byte. Native
big.lua passes with the exact all.lua coroutine wrapper; Ada exceeds that
diagnostic's ten-second observation window, with no cause established. The
Constant_Index quadratic attribution initially sent during investigation was
incorrect and withdrawn after reading its actual append-only implementation.
Native and Ada verybig.lua both encounter a host permission failure when the
native temporary-name result addresses the drive root. No full-size pass is
claimed. Any files generated by the earlier attrib diagnostic were relocated
as ignored artifacts, and the pinned reference tree remains clean.

## 2026-11-08 C caller-temporary regression fixture

After synchronizing the clean isolated checkout to the integrated 25bbf00
checkpoint, its strict root/test builds pass all 1,518 AUnit cases. Two
separately reported cases were added to the existing public-header
debug_api_contract.c consumer while preserving its eighteen existing cases.
They read/edit a Lua caller's pending operand from an active C callback and
from a suspended coroutine, exclude the child's function/argument slots,
preserve a rejected setter's pushed value and consume the edited value after
resume/collection.

The same twenty-case source passes pinned native default and instrumented C,
with zero counted blocks/bytes at close. Those direct native probes use GCC
13.2.0 (MinGW-W64 x86_64-ucrt); the Ada-linked consumer compiles through the
resolved GNAT 16.1.0 toolchain using strict C99 warnings. Its current execution
passes the original eighteen cases and fails the first new assertion that the
child's callee slot is excluded. This is intentional pre-fix regression
evidence: the separate C boundary checkpoint owns integration of the shared
Visible_Local_Top query into its two positive-index branches. Neither this
consumer run nor that pending integration is called passing Ada evidence.

The fresh unchanged db.lua diagnostic also confirms that transfer lengths now
pass but returned builtin values are absent from their real scalar C window.
A pinned math.sin(3) observation reports first slot 2, count 1 and the actual
result; Ada reports slot 1 and the original argument 3. The builtin boundary
agent owns actual result-publication integration, including operations that
reuse argument ranges. This agent owns focused native observations/regressions
and subsequent debug/close metadata. No synthetic hook result is accepted.

## 2026-11-08 native return-window regression checkpoint

A 51-case native observation records actual first/count/result cells and the
visible local top for representative builtin operations. It distinguishes
appending a new result, reusing an argument suffix, replacing consumed keys or
arguments, and protected status/result prefixes. Equal output/input values do
not imply reuse: math.abs(4) still appends its result. Numeric tonumber reuses
its argument while text conversion appends. Default Lua 5.5 pairs returns four
values, retaining both nil results. The visible top during a Lua return hook
also includes the real debug hook's table workspace; that private extra row
must not be fabricated as an implementation result.

Thirteen separately named AUnit wrappers and native_return_windows.lua turn
the meaningful append/reuse/replace/protected/iterator cases into public Lua
regressions. Their capture helper reads getinfo('fr') and actual getlocal
cells, retains explicit nil counts and compares the captured packet with the
independently received function results. Both pinned native default and
instrumented configurations pass the fixture. The current Ada binary fails
the unpublished result cases; these failures are retained as regression
evidence under ignored reports/debug-metadata/return-baseline-* artifacts.

This source-only regression checkpoint is an input to the coordinated builtin
publication implementation. The new Ada wrappers have not yet been compiled
or called passing during that agent's reserved window. That agent owns real
scalar result publication, prefix/argument normalization, obsolete packet-root
release and return-phase continuation handling. The completed implementation
must compile and pass these cases before final acceptance; this checkpoint
does not establish that result.

## 2026-11-08 metamethod, close and finalizer call origins

The shared name resolver now implements the actual calling-opcode cases in
pinned ldebug.c:funcnamefromcode (lines 615-652): indexed reads/stores, all
MMBIN forms with typed TMS event names, unary/concatenation/comparison calls,
and CLOSE/RETURN. Static NUL-terminated identities support both Lua debug
materialization and allocation-free C borrows. No opcode trace or hook result
is fabricated. The real finalizer activation carries a resettable entry
marker, preserving descendants and tail replacement as independent origins.
Pinned funcnamefromcall (lines 659-672) gives an actual hooked caller priority
over its finalizer flag; GCTM in lgc.c disables hooks around the real callback.

Lua getinfo/traceback and public C getstack/getinfo now share one budgeted,
allocation-free traversal. It omits actual scheduler transports and failed
owners retained only to close cells after error/coroutine unwinding. Normal
scope/return owners remain visible, as do genuine protected C callers. This
removes misleading error()/yield() names without changing their lifetimes or
closing transfers. Forty-four separately named AUnit cases and the complete
metamethod_name_phases.lua fixture cover opcode variants, normal/error/return/
coroutine closing, descendants, tail replacement, traceback and frame reuse.
The old component binary failed forty of those source cases and passed four.

Eight new named public-header C cases preserve the existing twenty. They
exercise arithmetic/index/normal/error/coroutine/finalizer origins while
refusing allocation for the actual n query, plus direct collection from a C
hook and direct API collection with call/return hooks installed. The latter
edge revealed the real private drain_collector guard wrapper as an extra
public C frame. A private getter returns that exact callback address through
a checked function-pointer byte copy. Dispatch classifies its activation
before entry hooks; frame queries, physical local boundaries and call/return
eligibility treat this known implementation transport consistently. The
protected C pump, physical windows, rooting and native charging remain intact.
A distinct marker avoids confusing collector transport with hook origin.
The native hook fixture also clears stale host temporary slots explicitly,
so an interrupted activation cannot accidentally retain its userdata target.

Strict default Windows validation/static results at component base efa9368:

- Root, test and C consumer builds pass under GNAT 16.1.0 with all required
  warning/style/check flags. All 1,577 AUnit cases pass, with zero failed
  assertions or unexpected errors. This isolated base excludes newer parser
  tests already present in the parent integration; its count is not a claim
  about that integrated head.
- All twenty-eight public debug C cases pass with zero counted allocations
  outstanding at close. The identical source passes pinned native default
  and instrumented C builds using GCC 13.2.0 MinGW-W64 x86_64-ucrt.
- Both producers' complete metamethod fixture chunks pass on both runtimes;
  source and all four outputs have SHA256
  6D52BF6EA18D6C7CE18CFC9FBFB25EA3EF542619BA7D50ED82F1A92603A1E386,
  with empty stderr. All thirty-six retained four-way compiler/runtime cases
  pass as well. These chunk cross-checks use the default configuration.
- Earlier strict attempts found unused positional enum literals, corrected
  with a named aggregate, and a new test convenience call to the still-missing
  luaL_checklstring, replaced with core lua_tostring plus a non-null assertion.
  Neither failed attempt is counted as passing; the metadata checks remain.
- Reference files and pins are unchanged; git diff --check is clean.

The unchanged-source disposable-tree diagnostics advance db.lua from line
528 to 603 (empty numeric-loop count-hook instruction shape) and soft locals.lua
from line 544 to 562 (removed __close call-error provenance). Neither full file,
T-enabled Ada execution nor full-upstream acceptance is established. A separate
T.listcode inspection of a default-produced chunk hits the native test build's
MAXIWTHABS=3 assumption versus the default compiler interval 128; configuration
line-anchor validation remains separate from these default cross-checks.

## 2026-11-08 iteration cells and suppressed count periods

A measured empty numeric loop reported 2,006 count callbacks against native
1,005: the compiler emitted CLOSE on every iteration even when no child
captured its visible control. Binding descriptors now record real stack
upvalue captures while compiling the child. Matching both symbol and slot
avoids marking hidden loop state that shares a debug lifetime symbol. The
loop emits its actual iteration CLOSE only for captured visible controls;
body-owned closers and generic iterator exit closing keep their existing
operations. Shadowing, transitive captures, slot reuse and collection preserve
separate iteration cells, following pinned lparser.c:forbody/leaveblock.

The first strict attempt passed its eight AUnit cases, but the new cross-check
correctly failed on C executing Ada's period-four fixture. Investigation found
a separate execution bug: luaG_traceexec decrements/resets the real counter
while luaD_hook prevents callback reentry. Before_Step had skipped both.
Suppressed hook/finalizer bodies now consume their real executed words while
call/line/count callback entry remains disabled. Dedicated five/eight-word Lua
hook bodies protect the resulting period shifts without recursive callbacks.
Canonical addition also uses the real ADDI/MMBINI pair for a side-effect-free
integer RHS in -127..128, preserving fallback operands/event and removing the
unexecuted constant load that changed the hook body's word count. Named tests
cover both signed endpoints, a value outside that range, fallback operands,
integer wrapping, float results and numeric-string conversion.

Final default validation/static builds pass under the unchanged strict GNAT
16.1.0 flags. All 1,591 AUnit cases pass with zero failed assertions/errors.
The fourteen-case loop_close_phases.lua fixture passes native default and T
source execution. Both producers' complete chunks pass on both default
runtimes, with empty stderr and shared stdout SHA256
4A53F3B4CF8BE86026CBE373B5AD5B178F3B9A6145B5E904C4BE05F59BF513BD.
All thirty-six retained four-way cases also pass after the final changes.
The C consumer was not relinked/re-executed for this compiler/hook followup;
its earlier checkpoint result is not newly attributed to this source head.

The unchanged db.lua diagnostic still stops at line603: the second comparison
in its live-hook assertion executes additional boolean materialization words
before reading the counter. Conditional lowering remains a separate measured
followup. No assertion was relaxed, no hook was selectively suppressed, no
reference was changed, and no full db.lua or upstream pass is claimed here.

## 2026-11-08 invalid call and replaced-close diagnostics

Dispatch now diagnoses an invalid callee from its actual surviving logical
caller before constructing any callee activation. It borrows the calling
opcode's name, retains explicit hook origins, recognizes a real pending
finalizer invocation, and adds a Lua source location only when that caller is
Lua. This follows pinned ldebug.c:luaG_callerror/formatvarinfo. Stripped source
and line markers remain ?:?; native protection does not receive an invented
Lua prefix. The invalid value's raw __name still supplies its diagnostic type.

Closing re-reads and protected-dispatches the actual current __close handler,
including nil/number/false replacements. The old @invalid.close error stub is
removed. A normal close reports metamethod 'close' at its actual caller; error
and coroutine closing have already unwound to protection/the coroutine base.
Outer closers receive that actual replacement error through the existing
continuation, with no new recursive execution path or ownership shortcut.

Sixteen named AUnit/source cases cover local/global/field/method/upvalue names,
custom types, removed and invalid close handlers, error/coroutine closing,
protected nil calls, invalid __call handlers, stripped locations and outer
error replacement. Native default and instrumented C pass all sixteen; the
prior Ada binary passed two and failed fourteen. Three new public C cases
protect a direct protected nil call, a removed marked C-slot handler and a
noncallable finalizer's full warning text. All prior C cases are preserved.

Strict default root/test/C consumer builds pass under GNAT 16.1.0. All 1,607
AUnit cases pass, with zero failed assertions/errors. All 31 debug C cases and
the six other retained C consumers pass the rebuilt Ada library. The identical
31-case debug source passes native default/T with GCC 13.2.0 and zero counted
blocks/bytes remaining at close. Both producers' full call_error_phases.lua
chunks pass on both default runtimes, with empty stderr and stdout SHA256
0E785674CD082B6C1E5C144864FB29AA20F72DF915A43D394A15629AA374279B.
All 36 retained four-way cases pass after the final change; whitespace is clean.

The unchanged copied locals.lua soft diagnostic advances line 562 to 1015. It
now passes replaced-handler error wording and the subsequent close-error
checks, then finds a yieldability mismatch after a normal closer raises an
error and a remaining closer tries to yield. This remains the next real
lifecycle issue; neither the complete file nor full-upstream acceptance is
claimed. Pinned reference bytes and revisions remain unchanged.
