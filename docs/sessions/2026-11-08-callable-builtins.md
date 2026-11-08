# Callable builtin and result-window checkpoint

Date: 2026-11-08, Asia/Tokyo.

## Objective and implementation

Continue the authorized remaining upstream delivery after the C debug checkpoint.
This component uses the integrated shared-input/debug base plus the independently
native-verified caller-temporary and return-window regression checkpoints. Only
the subsequent implementation commit needs integration; local cherry-pick IDs
for those preceding checkpoints must not be duplicated.

ADR [0020](../decisions/0020-callable-builtin-identities.md) records the strong
scalar registry, 161 actual C wrapper addresses, captured-cell ownership,
direct-call hidden phase and C continuation. Stateless functions allocate no
closure/cache, survive push/tocfunction roundtrips with real callable identity,
and keep distinct strict/lax UTF-8 iterators. Pointer formatting includes actual
scalar/foreign C function identity and the previously omitted thread/userdata
kinds. The C debug bridge uses the shared actual visible-local bound.

Visible Ada builtin returns now publish values in their actual scalar window.
Explicit per-operation stack transformations preserve append, argument reuse,
suffix selection and top normalization without using value equality to guess a
position. The original raw result borrow survives until its continuation owns
it. Protected failures retain the public pcall/xpcall activation through its
return phase; reserved packets move into the caller before owner retirement.
Consumed shadow packets no longer retain discarded values during return hooks.

Two old component fixtures assumed every native callable had a heap reference.
The formatter fixture now checks the requested actual callable identity. The
finalizer ownership fixture explicitly chooses a captured, collectable handler
so it still exercises independent root ownership after its metatable edge is
removed. Their original behavioral assertions remain.

## Commands and results

Tools: Alire 2.1.1; GNAT 16.1.0; GPRbuild package 26.0.1 (executable banner
26.0.0, 2026-04-15-gpr2), Windows x86-64. No compiler pin, global selection,
generated configuration, reference source or reference revision was changed.

The serialized default/validation/static build window ran:

```text
alr -n build --validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
alr -n -C tests build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
alr exec -- tests/bin/static/test_runner.exe
```

Strict builds pass. All 1,515 AUnit cases pass, with zero assertion failures or
unexpected errors. This includes thirteen independently native-backed return
window cases and two new separately named C-pointer host cases: a Lua callback
must consume the original bounded work counter despite pcall, and an arbitrary
callback table error must remain catchable with its identity intact. Both host
cases close with zero live managed blocks.

The final standalone `builtin_api_contract.c` has fifteen named cases. It checks
actual C types/metadata and inverse identity, reopening, direct host/C calls,
hidden callback frames, captured generator cells, stateless iterator identity,
pointer formatting, arbitrary errors, direct protected results, real yields and
yielding callbacks, scalar refusal and captured-closure refusal/recovery. The
same public-header C99 source passes Ada default and pinned native default/T;
all three outputs have SHA-256
`ce10b9316ac48b13097c9f28935a49d077509a48ab2091afb064a6db7dd712db`.
Each counted allocator has zero outstanding bytes/blocks at close.

The twenty-case C debug consumer and complete retained C/foreign consumers pass
against this image. Execution-only replay of fifty-one native observations
matches all first-transfer/count ranges; native GC byte counts, clock values
and private extra hook-table workspace are separate observations, not asserted
parity. The shared core-image script registers the new consumer, source hashes
and same-source native comparison for the later matrix.

Initial strict drafts rejected a C macro escape, an omitted stack-window
argument, indentation and an Unbounded_String membership expression. Runtime
drafts exposed attempts to publish an internal phase with no physical window,
loss of the raw pcall packet borrow and retirement before an owned error packet
was delivered. The original failed logs remain under ignored
`reports/builtin-c-boundary/`; the passing final AUnit run is `aunit-5.log`.
No warning, style, validity or runtime check was disabled to repair these causes.

## Remaining work

These are local default/static Ada results; native T output is oracle evidence,
not Ada instrumented acceptance. The full shared/platform/configuration matrix,
all remaining Lua-file runtime execution and reviewed conformance reconciliation
remain final-delivery gates. Private C workspace/allocation-layout parity is not
claimed. Universe-wide short-string interning, external-string lifetime
callbacks, remaining core exports/formatting ABI and auxiliaries remain later
checkpoints. The parent delivery owns current status/backlog and final PR,
automatic review, review fixes and merge workflow.
