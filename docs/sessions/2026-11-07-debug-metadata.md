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
