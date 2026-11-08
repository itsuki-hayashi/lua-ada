# Coroutine result capacity and recipients

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

Remote default CI reached unchanged coroutine.lua:844 and let a parent-side
stack overflow escape coroutine.resume near one million returned values.
The pinned auxresume checks the resumer's nres+1 room before moving results;
failure returns false and "too many results to resume". Child-side overflow
was already a permitted false/error outcome of the original test.

The scheduler now preflights the real resumer C window, including direct
builtin calls on borrowed/host views. Successful delivery writes into the
actual receiver's retained packet without another temporary vector. A
capacity rejection discards the child delivery, preserves its completed or
yielded lifecycle, and publishes the native false/error result. Explicit
child failure metadata lets wrapped coroutines distinguish this rejection
from a real body error: a healthy yielded body remains suspended, while a
failed body still closes and preserves replacement errors. Actual packet
passes are budgeted; no broad exception catch turns a host stop into false.

Five named Lua cases pass both native configurations at their actual limits:
completed/yielded overflow, wrapped yield with pending close state, a large
fitting nil tuple and genuine wrapped-body error replacement. A sixth AUnit
case checks uncatchable shared-budget exhaustion and same-session recovery.
The fixture collects between overflow cases because native error-stack
reserve persists until shrink; each named AUnit case owns an independent
session. It uses live named locals, not a private compiler-layout match.

All six final serialized strict default/T root/tests/C builds pass with
Alire 2.1.1 and GNAT 16.1.0, retaining required warning/style/runtime checks.
All 2,298 AUnit cases pass each isolated configuration on base b3f2b8a.
The five-case fixture passes source and all four native/Ada producer/VM
combinations per configuration, stdout SHA256
E92507224E8E8CD650C32E7ACAD4CB1B8C35238B5B32EF041595B815AD5BF00E.

Original unchanged coroutine.lua passes with no _soft in both configurations.
Default naturally skips its T-absent blocks; T executes both coroutine API
sections. Ada/native raw stdout matches independently per configuration:
default SHA256
1BA864A5A1252E99B555709EAC4300F63574B0769EF02C1FCCBB319DD6EEB85D;
T SHA256
67684281E453D226EFF6C1AA9E9DCFFDEC4F631B170E6716D1CA1CD8896DF204.
These are local Windows observations; fresh remote platform evidence remains
required after integration. The native-module campaign was not rerun.

All twenty-six ordinary standalone C consumers pass per configuration, plus
the T private buffer caller. Existing T external-string ownership-only and
reset without-warning-reentry variants remain explicit. Changed-document
UTF-8/LF, local-link and table checks and git diff --check pass. The full
documentation checker retains the isolated uninitialized busted fixture
link limitation; no passing full-doc claim is inferred from scoped checks.

No Failure_Text representation/getter/setter changes are part of this
component. No references, fixture pins, source adaptations or conformance
ledger entries change. Full-target acceptance remains open. See
[ADR 0034](../decisions/0034-borrowed-c-stack-views.md).
