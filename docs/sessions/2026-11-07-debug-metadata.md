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
