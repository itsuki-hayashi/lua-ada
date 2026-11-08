# Parser stack limits and host quotas

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; delivery continues.

The unchanged errors.lua generated nesting checks exposed an uncatchable
host-limit failure in compatible execution. Pinned lparser.c enters the
shared C-stack counter and lstate.c raises the original C stack overflow
runtime error. Actual native buffer and streaming C consumers confirmed
LUA_ERRRUN and the unprefixed error string, distinct from malformed grammar.

The shared private frontend now carries that overflow fact to compatible
execution callers. Both compiler paths preserve Language_Failure; public
streamed loading returns status two and ordinary load preserves the original
error text. The frontend's default checking behavior and bounded Ada host
limits retain Resource_Error and cannot be caught with Lua pcall. No other
resource, storage or allocation failure is reclassified. Compatible function
parsing charges its body block without a duplicate function-boundary charge;
the original bounded accounting is preserved.

Sixteen separately named AUnit cases cover the thirteen upstream 100/500
generators, ordinary and saved-builtin readers, and bounded host abort/retry.
The initial regression caught rejection of native's valid hundred nested
function statements; that duplicate charge was corrected before final checks.
Both configurations now pass all 2,384 AUnit cases and the fifteen-case public
Lua fixture. All eight native/Ada compiler/VM roles match stdout SHA-256
c93a6dc74c38666693298bb953edf26dadd7cc8d5272cd5ef7efdfd5fa9f02eb.
Two new native-paired C cases preserve the existing stack, verify exact load
status/text and compile/execute a new chunk on the same state afterward.

Six strict tests/C/CLI builds pass serially with Alire 2.1.1 and GNAT 16.1.0,
retaining Ada 2022, warning/style policy and runtime checks. All twenty-six
default and twenty-seven instrumented standalone C executables pass. Evidence
is under reports/compiler-limits. The code has independent peer inspection;
the follow-up comment placement change alters no runtime behavior.

Fresh unchanged errors.lua passes all generated nesting checks and reaches
the upvalue-limit diagnostic assertion at original line768 in both modes;
both native runs complete. That function-line context remains required work.
This checkpoint supplies no passing whole-file, source-ledger or final-head
certificate. Reference/module trees and pins remain unchanged.
