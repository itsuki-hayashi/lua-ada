# Owned argument labels and message formatting

Date: 2026-11-08, Asia/Tokyo.

The existing shared argument formatter now builds its label and complete
message in selected-owner buffers. Module-name traversal borrows up to two
actual matching keys before rendering. C-prefix scans and copies share the
execution budget; a NUL in the first key ends the composed name without
materializing either large suffix. `_G.` removal and an empty resulting label
retain pinned behavior. The immediate Lua source prefix uses a borrowed
canonical source view and bounded short-source result.

The formatter no longer grows unmanaged Unbounded_String values or concatenates
input-sized ordinary String intermediates. Its final borrowed view still
enters the existing Fail routine, whose context failure-text store requires
separate migration. This component does not claim the full storage audit is
complete or that every diagnostic copy already uses the selected provider.

Four identical Lua cases pass native default/T and Ada default/T: nested keys,
a first-key NUL before two 30,000-byte suffixes, nested global prefix removal,
and an empty stripped label. All four stdout SHA-256 values are
`b5b15c1de1eb4d4fba2e63d61ae0a6d22774d843afdc83da155248f555a9857e`.
The existing four type-detail and fifteen registry-continuation Lua bodies
also pass in all four processes. Separately named AUnit cases reuse the new
bodies; another case prepares an actual long module key before reducing the
instruction budget, requires a host stop during scanning, and restores the
registry on a healthy subsequent execution.

All eight serialized Windows validation/static root, nested-test, C-consumer
and CLI builds passed in default and upstream-test configurations. The first
compile caught one 80-column line; it was wrapped without changing flags.
Each configuration passed all 2,104 AUnit cases. Six relevant standalone C
consumers also passed in each configuration: builtin, auxiliary, index/type,
foreign, external-string and traceback. Tool versions remain Alire 2.1.1,
GNAT 16.1.0 and GPRbuild 26.0.0, with strict switches and runtime checks.
Logs are under `reports/owned-argument-label` and carry component scope.

Continue final failure-text storage, native hook/C views, binary debug writer
interoperability and remaining file/helper/aggregate/heavy/platform gates.
No reference revision, adaptation, exclusion or global acceptance changed.
