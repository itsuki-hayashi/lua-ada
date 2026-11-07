# Actual scalar prefixes during abandoned execution

Date: 2026-11-08, Asia/Tokyo. Base: host C closing `1ccd512` plus the tested
execution-retirement dependency `429addc`, applied locally as `3d45c1c`.
This is an implementation prerequisite for error/reset callers, not a
`lua_closethread` or close-yield acceptance claim.

Canonical closing entries now retain their actual absolute stack level.
`Machine.Pending_Closing_Level` reads the highest Lua/C closing slot without
allocation. `Machine.Set_Closing_Stack_Prefix` publishes a context-owned real
scalar interval and recomputes public/physical bounds while preserving any
surviving actual window. Ordinary retirement clears only above this prefix;
the collector's existing ordered union trace includes that prefix and all
remaining real windows. Restoring a lower floor does not blindly clear bytes
that an outer close handler can still own. No shadow values, alternate stack
or new executor is introduced. [ADR 0026](../decisions/0026-base-c-closing-ownership.md)
records the ownership requirement for future callers.

Five independently named AUnit cases use a genuinely compiled canonical scope
and the existing iterative driver. They verify the exact TBC slot level,
collection of an otherwise unreferenced local only after restoring its floor,
collection of the abandoned tail above a pending closing slot, survival of
a real active window when the floor decreases, and zero allocator growth
while publishing/retiring/restoring under persistent refusal. Fixtures finish
with zero managed blocks. These tests exercise actual heap and scalar owners;
they do not certify automatic reset/error transitions that have not called
the primitive yet.

Strict local Windows/default/static root, C consumer and nested test builds
pass with Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (banner
26.0.0, 2026-04-15-gpr2). All 1,705 AUnit cases pass, zero failures/errors.
Thirteen retained C consumers pass: base closing, foreign, debug, external,
reader/dump, builtin, arithmetic/comparison, conversion, value, auxiliary,
formatting, collector and IO. Ignored logs are in `reports/closing-prefix/`:
`root-build.log`, `consumer-build.log`, `tests-build-3.log`, `aunit.log` and
the named consumer logs. Initial test compilation correctly rejected a
private-child import and an 80-column line; the test uses the existing Engine
lookup interface and complies with the unchanged strict compiler settings.

No reference source or revision changed. Automatic error cleanup, the C guard
deferred-scope protocol, reset/self-close, fresh coroutine function-stack
semantics, integrated Ada T/shared/platform and complete suite acceptance
remain unfinished. Native reset fixtures are still separate oracle evidence,
not passing Ada reset coverage. The next checkpoints wire real prefix floors
to those actual cleanup drivers and test their public behavior.
