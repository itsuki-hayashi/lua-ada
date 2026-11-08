# Return windows through close handlers

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

Two independent probes expose the pre-close snapshot problem without hooks.
A closer changes its parent's real outgoing 11 to 37: both native
configurations return 37, while the preceding Ada artifact returns 11. A
closer replacing every matching publicly exposed result temporary with nil
can collect the original weak value under native Lua; Ada's retained packet
keeps it alive.

The implementation makes the real scalar range/count authoritative before normal
return closing begins. The existing publication bit is generalized to
Return_Window_Published, without growing the private frame layout. Native,
canonical and retained-native-tail publishers establish the same fact.
Return_Exit retains/reuses owned packet capacity but removes copied roots
before entering a closer. Only successful completion reconstructs delivery
from edited cells; error/scope/coroutine exits and the packet migration
backend retain their existing protocols. Internal protection prefixes remain
separate from the actual source span and appear once.

Eight named Lua cases pass both native configurations: scalar result, tuple
with nils, weak result, a subsequent return hook, close error, reverse closer
order, yielding closer, and vararg return range. Three public C cases also
pass both native configurations: a C-slot result edit, tuple/count retention,
and a warmed provider frozen inside the C body before return. That last case
requires zero attempted allocation growth after freezing and balanced bytes/
blocks after physical close. It does not infer ownership from net byte cost.

All six final centrally serialized strict root/tests/C builds pass for both
configurations with Alire 2.1.1 and GNAT 16.1.0, retaining every required
warning, style, validation and runtime check. Final logs contain no
diagnostics. Both isolated local configurations pass all 2,216 AUnit cases,
including eleven new named cases. Both full Ada foreign consumers pass all
three new C cases, including the unchanged zero-growth/provider-balance case.
The eight-case Lua fixture matches source execution and all four native/Ada
producer/VM combinations in both configurations, raw stdout SHA256
C437B0EADF3AF29B86F44E0D52D44E1DB3B798D64258E92258A4ECBC7E13993B.

The first replay passed 2,215/2,216: the warmed refusal case exposed a fresh
Wrap allocation in @foreign.entry after successful closing. GDB identified
the exact path; reusing the existing protected-return packet removed it.
The next replay exposed a controlled Control_Transfer record copy at final
handoff. The scheduler now snapshots its scalar kind, retains the original
result packet until its real recipient owns it, and directly completes a
root transfer without another copy. Actual parent pin/packet/receiver passes
are metered before consuming that transfer; yield, C-resume and error/status
recipients retain their existing protocols. Neither failure was reclassified
or masked by weakening the allocator assertion.

This isolated component is based on 2eda8d7, rather than the parent's later
integrated compiler/diagnostic source. Full-target acceptance remains open.
The following coroutine result-portal capacity checkpoint must preserve
native false/error behavior when the parent cannot reserve a child's wide
result tuple; that separate CI observation is not claimed fixed here. See
[ADR 0034](../decisions/0034-borrowed-c-stack-views.md). No reference tree,
fixture pin, source adaptation, or conformance-ledger entry changes.

All twenty-six ordinary standalone C consumers pass per configuration, plus
the T private buffer caller. Existing T external-string ownership-only and
reset without-warning-reentry variants remain explicit; Ada foreign includes
its full allocator-reentry case, while the native-T counterpart retains the
earlier documented private-lock omission. Native-default/Ada-default foreign
stdout matches SHA256
7E52D5BECE43B6D3B35AE0453060639D5AC054043AA247898F7D24ADA46147F2.
The native-module host/import campaign was not rerun. Changed-document
UTF-8/LF, local-link and table checks and git diff --check pass; the full
documentation check retains the isolated uninitialized busted fixture limit.
