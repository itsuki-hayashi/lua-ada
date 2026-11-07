# Allocation-free public C numeric conversion

Date: 2026-11-08, Asia/Tokyo. Base `d627a0c` on integrated `6e166ea`.
Scope: `lua_stringtonumber`, exported `lua_ident`, and fixed exact runtime
numeric-string conversions. This is a component checkpoint within the
remaining-suite delivery, not complete C ABI/upstream/platform acceptance.

The new public C entry borrows the original `strlen` extent and calls the
existing exact parser through [ADR 0024](../decisions/0024-fixed-numeric-scratch.md)'s
fixed local arena. No input-sized returned Ada string is created. Success
pushes the actual integer/float variant and returns byte length plus NUL;
malformed input returns zero without changing the stack. NUL terminates this
C interface, while whitespace belongs to the original consumed length.

Runtime state conversions now forward through that same fixed exact path,
retaining the native decimal-point byte and existing linear host work charge.
This includes `lua_tonumberx`, `lua_tointegerx` and `lua_isnumber` on strings.
Explicit-owner parser overloads and frontend callers remain unchanged. No
second grammar, native numeric primitive or rounded intermediate is added.
The `lua_ident` data definition uses the pinned copyright/authors macro format.
Its Windows DLL branch explicitly exports that data because the pinned header
declares it without `LUA_API`. An isolated GCC 13.2 object compile verifies the
actual COFF directive `-export:"lua_ident",data`; this is not a linked-DLL
acceptance claim. That compiler's C99 stdio path was selected with
`__USE_MINGW_ANSI_STDIO=1` for the existing `%zu` diagnostic; its initial default
MSVCRT attribute check rejected `%zu` before the C99 path was selected.

Serialized strict Windows/default/static root, C consumer and nested test
builds pass using Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1
(banner 26.0.0, 2026-04-15-gpr2). Commands are the same root/consumer/tests
validation commands in the preceding external-string session. The first
root attempt found a changed numeric helper's old body profile; it was fixed
without suppressions. Final logs are in ignored `reports/numeric-conversion/`:
`runtime-build-2.log`, `consumer-build-1.log`, `tests-build-1.log`, `aunit-1.log`.

All 1,641 AUnit cases pass, zero failures/errors. The new named case uses an
actual C callback to request parsing of a preinstalled ten-thousand-digit
string, verifies the original uncatchable host scan quota, recovers on the
same universe and closes with zero managed blocks.

The same `conversion_api_contract.c` C99 consumer passes eleven named cases
against Ada default/static and isolated pinned default and T C builds.
It verifies exact exported metadata, integer boundaries/wrapping, decimal/
hex float syntax, signed zero/extreme exponents/subnormals, malformed-input
stack preservation, C NUL extent, existing numeric-string conversions,
ten-thousand-digit cancellation, remote halfway tails, and two thousand
seeded finite bit round trips. Under provider refusal, the successful/failed
conversions make exactly zero counted allocator calls after stack reservation.
All three stdout files have SHA-256
`9344f78ded2fb9355c6f26f70ec1fffdac9de33756f2c01dd280d32003373587`.
Both native configurations run all eleven cases without skips. Counted
providers close with zero bytes and blocks. Native oracle compilation uses
the separate pinned libraries, never links reference code into Ada.

All nine retained C consumers pass locally: bootstrap, GC, IO/OS, foreign,
reader/writer, debug, builtin, formatting and external strings. The core-image
script registers the new identical-source oracle, comparison and source hashes;
PowerShell parsing passes. Its full pipeline was not run in this checkpoint.
Integrated Ada instrumented/shared/platform builds and complete suite gates
remain pending. Arithmetic/comparison/thread-close exports remain next work.
