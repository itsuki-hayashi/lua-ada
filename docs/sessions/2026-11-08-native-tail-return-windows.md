# Native tail return publication

Date: 2026-11-08, Asia/Tokyo. Corrective component; full delivery continues.

The preceding actual return-hook checkpoint exposed a missing publication:
a Lua frame retained while its native tail callee runs receives results only
in Native_Results. Its real CALL A range still contains no result. Native
return hooks observe 11 for return math.abs(-11), while Ada exposes nil.
Rereading that source after an observing hook can consequently regress the
caller's delivered value to nil. The earlier seventeen cases did not cover
this retained-native-tail path.

The correction publishes the rooted raw packet into the retained Lua
frame's actual source range, sets its live GC extent and transfer offset/
count, then performs existing completion. Reservation precedes any physical
write; publication work uses the shared budget. The private packet backend
continues its previous path. Three separately named cases cover observation
without mutation, edited results with parameters, and a zero-result native
tail call. All three pass both native configurations unchanged.

All six centrally serialized strict root/tests/C builds pass for default and
T, using Alire 2.1.1 and GNAT 16.1.0 with all required checks and no final-log
diagnostics. Both configurations pass all 2,205 AUnit cases on the isolated
preceding return-window checkpoint, including the three new named cases.
The complete eighteen-case Lua fixture passes source execution and all four
native/Ada producer/VM combinations in both configurations, with raw stdout
SHA256 B029A8E81185EECF75CE901130DE82A31CC11307AE2B92AD693594DE6584FD62.
An independent trace now reads 11 from the real tail return cell and delivers
37 after mutation, matching native Lua. This corrects the earlier scope gap;
the seventeen-case historical session remains its original dated evidence.

Close-callback result mutation remains a separate open checkpoint.

All twenty-six ordinary standalone C consumers pass each configuration, plus
the T private buffer caller. Existing T external-string ownership-only and
reset without-warning-reentry variants remain explicit; the native-module
host/import campaign was not rerun. All five changed Markdown files pass
UTF-8/LF, local-link and table checks, and git diff --check passes. The full
documentation checker retains the preceding isolated-checkout limitation
from the uninitialized busted fixture link; it is not reported passing here.
See [ADR 0034](../decisions/0034-borrowed-c-stack-views.md). No reference tree,
fixture pin, source adaptation or conformance-ledger entry changes.
