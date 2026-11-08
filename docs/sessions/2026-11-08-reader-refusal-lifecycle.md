# Reader refusal and self-close follow-up (2026-11-08)

The [linear reader checkpoint](2026-11-08-linear-lua-readers.md) explicitly
deferred reader-injected permanent refusal and self-close witnesses. A cold
reader which enables actual T.alloccount(0) reproduced a public mismatch:
native pcall(load, reader) returned true, nil, "not enough memory"; Ada
returned false, "not enough memory". The failing assertion was retained.

GDB showed two separate post-callback metadata acquisitions. The first was
the portal's Native_Results reservation after its real C guard returned.
Preflighting that alone exposed Complete's fresh Wrap vector. Both could
turn the parser's already protected memory result into an outer call error.
Loaders now reserves the actual packet for two raw results plus existing
private protection before entering any reader. Only the portal's native
completion prepends its private true statuses in that retained capacity and
passes the owned alias to Complete_Packet. Protection remains intact through
actual return-hook reconstruction and external-release deferral; it is not
removed early or exposed as part of load's public raw transfer range.

Nine separately named AUnit cases cover cold/warm reader refusal, refusal
after a retained source prefix, binary reader refusal, empty/partial/direct
saved-builtin self-close, and protected successful/failed return-hook edits.
The four refusal cases interpose the real selected provider and assert an
actual refusal occurred. They restore the allocator only after the tested
call. The native T fixture and actual Ada T launcher match. The Ada default
tests explicitly install the test adapter on their selected provider; this
does not claim a T-absent native interpreter ran those controls.

Three self-close trials invoke a tiny real C ABI callback from coroutine.resume,
while the ordinary or direct saved-builtin reader and shared parser wait.
Neither C nor Lua code after reset executes; pending closing handlers run
once, the thread is dead, and a later load succeeds. Finalization observes
zero selected raw bytes and blocks in all three Ada cases. No fake transfer,
reference-runtime linkage or source alteration supplies this result.

Both configurations pass **2,363 AUnit cases**. All six static runtime/tests/C
strict builds passed serially with GNAT 16.1.0, Ada 2022, runtime checks and
the complete warning/style policy retained. The original forty-one reader
witnesses plus the two new hook controls still match all four C/Ada producer
and VM roles in each configuration. Both retained 36-case canonical campaigns
pass. All twenty-six ordinary C consumer executables pass in each
configuration, plus the private T buffer caller. Configured native modules
were not rerun here.

The balanced builtin consumer keeps all twenty-nine prior cases and adds a
cold C-reader injected-refusal case. Its thirty cases pass in native and Ada,
default and T, with stdout SHA-256
`f77af97d236e8b5da4faa9ac15ef6ef7f1ccfd3bf0352ba355b28daf5bec1af8`.
Its original final provider-zero assertion remains mandatory. Self-close
trials use explicit --reader-self-close, --reader-partial-self-close and
--reader-direct-self-close arguments, separate from that balanced run. All
three isolated Ada trials pass in both configurations and call lua_close.

The pinned native oracle has an independently observed cleanup defect.
Self-close is supported by lstate.c:lua_closethread. Nevertheless, the counted
native default partial-reader and direct partial-reader trials leave **128
bytes in two provider blocks after lua_close**; the empty-reader trial and
baseline without those cases leave zero. In native T, the corresponding
default-allocator isolated trials observe the expected public semantics,
then abort at lstate.c:273's total-memory assertion during lua_close. These
two T teardown runs are **failed oracle diagnostics**, not passing tests.
No close call or reference assertion is bypassed, and Ada does not emulate
the leak. The non-counted native default semantic trials supply no balanced
cleanup evidence. Ada's selected-byte/block assertions establish its own
cleanup independently.

Local evidence is under reports/debug-metadata: reader-life-final-* contains
the final Ada builds, AUnit and C trials; reader-life-isolated-native-* keeps
the separate native balanced and teardown results; native-self-leak-* keeps
the counted defect isolation; reader-life-c-refusal-gdb.log records the
retained allocation stacks. Reference trees and pins remain unchanged.
This narrow native cleanup defect still needs final acceptance review; it is
not a reason to weaken public self-close behavior or mark an incomplete file
passing. Full upstream/T, platform and final-head acceptance remain open.
