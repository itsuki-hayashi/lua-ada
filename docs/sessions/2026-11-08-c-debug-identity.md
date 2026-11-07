# Public C debug identity checkpoint

Date: 2026-11-08, Asia/Tokyo.

## Objective and implementation

Continue the remaining upstream delivery after the demand-driven input
checkpoint. The root integrated source and the independently verified
traceback/hook-registry checkpoints are this component's base. This checkpoint
does not replace final whole-delivery or platform acceptance.

The C facade implements every public `lua_getinfo` selector, inactive/active
`lua_getlocal`, `lua_setlocal`, `lua_getupvalue`, `lua_setupvalue`,
`lua_upvalueid` and `lua_upvaluejoin`. An ordinary C/Ada transport record carries
scalars and borrowed bytes; the public `lua_Debug` layout stays on the C side.
Frame tokens are validated against the addressed context before use. Queries
read actual canonical metadata, registers, hidden vararg slots and stable
capture cells. Setters mutate those real slots/cells with existing barriers;
joining redirects a closure's actual cell edge. Failed setters preserve their
stack value, and inactive parameter queries do not push a value.

Frozen canonical strings now expose a documented managed, preterminated byte
view. Empty intern entries reserve their terminator during construction. Source
and debug-name lengths remain byte lengths, including embedded NULs. The shared
canonical name selection and reaching-definition resolver can return borrowed
views for C without allocating temporary runtime strings; existing Lua inspection
wrappers still materialize their Lua values. Borrowed inferred names/source live
with their actual prototype/constant owner. Explicit hook/metamethod origin
names use the actual activation's owned byte buffer from the hook checkpoint.
Simple `getinfo` selectors require no new allocation once stack capacity exists;
`L` creates the real result table, skips VARARGPREP and returns nil for C functions.

A real C Lua-hook dispatcher uses the public API to retrieve the registry's
thread callback, pass the event/line and call through the same driver. Its
address is callable and save/restorable by C clients. The hook-registry
checkpoint's typed identity/restore flags retain the weak mapping and original
mask/count controls. `lua_newthread` passes its actual addressed parent for hook
inheritance. Immutable C-hook transport origins keep helper frames hidden after
the hook removes/replaces itself, and preserve the hook/? origin for Lua called
from that C hook.

Native testing exposed two related existing transfer-metadata faults. A return
hook's first slot is the actual RETURN register or C result range, rather than
always one. The runtime now retains `Transfer_First` before packet movement.
Return-event construction explicitly selects the departing activation instead
of the already scheduled `@return.hook` helper. Both Lua and C inspection read
those actual fields. Entry calls continue to start at slot one.

## Validation

Tools remain Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (executable
banner 26.0.0, 2026-04-15-gpr2), Windows x86-64. No global compiler selection,
machine pin, generated configuration, reference source or reference revision was
changed. Strict Ada 2022 warning/style/runtime-check policies remain enabled.

The serialized default/validation/static window ran the strict root build,
`gprbuild -P c_api/consumer.gpr` with `LUA_ADA_PREBUILT=true`, and the nested
validation test build with the same prebuilt root. All 1,489 AUnit cases pass,
with zero assertion failures and unexpected errors. The full retained C consumer
and foreign consumer pass. Initial strict attempts identified missing operator
visibility, a redundant use clause, a missing prior subunit specification and
one long line; these were repaired without weakening checks. Their failed logs
remain under ignored `reports/debug-c-boundary/` alongside successful runs.

`debug_api_contract.c` is one unchanged public-header C99 consumer compiled
separately against the Ada image and pinned native default/T images. Its
eighteen named cases exercise function/native metadata; selector/pop/push
protocols; borrowed metadata and allocation-refused queries; inactive parameter
names; active Lua/C locals; Lua/C upvalue values and identity; cell joining after
collection; callable Lua-hook identity; hook mutation and logical frames;
`__call` receiver metadata; Lua/C hook transfer ranges; active-line-table
refusal/recovery; stripped metadata; and mutation of a suspended captured local.
All three outputs match byte for byte, and each counted allocator has zero
outstanding blocks/bytes at close. The consumer is registered in
`check-core-image.ps1`, including source hashes and native comparison, for later
integrated matrix execution.

## Limits and handoff

These are local default/static Ada results. Native T success is oracle evidence,
not integrated Ada T acceptance. Shared libraries, all platform/configuration
contexts and full Lua-file execution remain final-delivery gates. The private
packet backend remains a migration path; this new C inspection implementation
uses the canonical production substrate and does not establish separate packet
backend debug parity. Complete auxiliaries, callable builtin Ada library
identities and external-string lifetime callbacks remain later checkpoints.
The parent delivery owns current status/backlog and the final PR/review/merge
workflow. Only this component's implementation commit needs integration; its
locally cherry-picked base commits must not be duplicated.
