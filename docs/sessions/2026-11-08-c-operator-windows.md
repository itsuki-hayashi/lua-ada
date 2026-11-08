# Public C arithmetic and comparison windows

Date: 2026-11-08, Asia/Tokyo. Base: integrated `e9ea4ff`. Scope:
`lua_arith`, `lua_compare` and shared primitive/metamethod diagnostics.
This is a component checkpoint in the remaining-suite delivery.

Seventeen static `C_Operators` descriptors map pinned C operation codes
to existing lexer/operator kinds. Primitive arithmetic/comparison acts
directly on the addressed real C stack without allocator growth. Absent
comparison indices return false. Numeric types, modular arithmetic, integral
bitwise conversion and exact mixed numeric comparison retain the shared VM.

Handler calls append a private operation helper and copied operands above
the original C top, then use the same nonyieldable C-owned call pump.
Original slots remain authoritative during Lua inspection/mutation. Unary
arithmetic also publishes the actual duplicate second operand before the
helper function slot. Arithmetic replaces/pops its native operand range;
comparison removes only its private result, preserving real caller writes.
No callback runs inside an Ada value-dispatch activation; no executor,
allocator or work budget is replaced.

Shared no-handler arithmetic selects the first non-number as pinned
`luaG_opinterror` does. A right numeric string without its installed string
handler cannot silently coerce. Bitwise errors use their actual wording.
Order errors distinguish two values with the same diagnostic type from
different types. Yield refusal distinguishes main-thread outside-resume
from a nonyieldable C-call boundary. Handler lookup and raw operations remain
shared; these are not separate C implementations of language operators.

Strict local Windows/default/static root, C consumer and nested test builds
pass using Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (banner
26.0.0, 2026-04-15-gpr2), with required warning/style/runtime checks. All
1,678 AUnit cases pass, zero failures/errors. Two new named cases invoke
actual public C operators and prove Lua arithmetic/comparison handlers
consume the original uncatchable host quota, recover on the same universe,
and close with zero managed blocks.

Identical C99 `operator_api_contract.c` passes seventeen named cases against
Ada default/static and separate pinned default and T C. All stdout files
have SHA-256
`eccc2ad8efb4fa6390c822be2e5546ab3b1ff19c8f64cda0e2fccfc90c9770cc`.
Both native configurations run every case. Coverage includes all arithmetic
codes, typed results/wrapping, comparison precision/embedded NUL/absent
indices, zero-allocation primitive refusal, actual string/numeric handlers,
arbitrary errors, integer/division/type errors, missing-library conversion,
truthy equality/order handlers, actual caller function/slots, unary duplicate
slot, real `debug.setlocal` writes and forbidden yield. Counted providers
close with zero blocks and bytes.

The first Ada consumer run passed fifteen cases and exposed only the old
generic yield-error wording. The final run includes that native diagnostic
and another order-error case. Retained value, auxiliary, debug, external,
numeric-conversion and foreign C consumers pass. Ignored evidence is under
`reports/c-operators/`: `runtime-build-2.log`, `consumer-build-2.log`,
`tests-build-2.log`, `aunit-2.log`, `ada-default-2.log`, and both
`native-*-2.log` files. The core-image script registers the identical-source
oracle, stdout comparison and hashes. Parsing passes; its full pipeline was
not run for this component. No reference tree or revision changed.

Unchanged `errors.lua` passes the table-bitwise wording observation and
still stops at its message-helper assertion. A report-only exploratory copy
printing message pairs identifies concatenation's generic non-string error
as the next mismatch. The reference remains unchanged; the file is not a
pass. Thread reset, host-base C closers, integrated Ada T/shared/platform
builds, full suite and final acceptance remain outstanding work.
