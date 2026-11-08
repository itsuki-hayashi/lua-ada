# Safe real CLI interrupt component

Date: 2026-11-08, Asia/Tokyo. Author: Codex /root/runtime_gaps.

[ADR 0045](../decisions/0045-cli-interrupt-lease.md) records the private lease,
C11 lock-free signal controller, fixed target context and safe iterative
delivery. Pinned lua.c:70-87 and 161-172 establish first/default-second signal
and Docall policy. ldo.c:444-465 and collection's allowhook suppression establish
the active-hook/finalizer boundary. No reference file changes.

The author draft combines this core with the peer's explicitly temporary CLI
message-handler helper. The four peer files, its sole lease insertion and the
AUnit runner registration are outside this dependency commit. The new test
unit calls that private helper API; its fourteen separately named bodies need
the peer API and registration to compile/execute. This is a dormant core/test
source dependency until actual Docall integration, not a standalone full CLI
behavior claim. The peer measured extra per-Docall C hook events in the temporary
transport and owns a persistent host-main replacement. No hook suppression or
source exclusion hides that remaining obligation.

All eight strict runtime/test/CLI/consumer builds pass on the combined dirty
author draft with cb9241f's frame reduction and 30c6185's C argument correction.
Both full AUnit configurations pass 2,678 cases before the separately added
finalizer case; two subsequent strict nested test builds add that case.
Fourteen real-signal cases cover protected and unhandled
interrupts, close-error delivery, count/line/return-hook completion and removal,
finalizer completion, fixed coroutine target, repeated operations, no arming
for syntax/argument lookup errors, both exit modes and uncatchable host quota.
Each uses actual raise(SIGINT), checks the preceding handler is restored by
raising it after the lease, and requires zero selected-provider bytes/blocks.
The test callback refuses to raise if no lease is armed, preventing an ordering
regression from killing the test process. Test-only probes do not inject a
pending interrupt or become public product APIs.

The new shared protected-call transport exposed a retained M0 selected-script
test failure in Foreign.Begin_Call: it copied already rooted arguments into a
cold scratch vector. That separate public C correction is 30c6185, with three
new unchanged C-oracle/Ada cases. All thirty-three builtin cases and all retained
C consumers pass in both configurations, with existing T callback-lock options
preserved. Native modules use fresh actual-image import fixtures; a first
argument-free usage failure is not passing evidence.

Actual Windows protected/search probes use immutable copied conformance CLI
images, confirmed default/T configurations and a real 2 GiB allocator. All four
Ada processes satisfy the existing broker's exact protocol. Protected prints
12 then 42, catches one real CTRL_C_EVENT, exits zero with empty stderr and one
complete zero-bytes/blocks sidecar. Search retains string.find(string.rep('a',
100000),'.*b'), prints 15, receives two real requests and dies with exactly
0xC000013A and empty stderr. Its absent abrupt sidecar is not balanced shutdown
evidence. Console membership, PID, actual wait, request results, timestamps and
handle cleanup are retained by the unchanged broker. A first author replay
had malformed PowerShell argument construction; the broker returned usage
status before creating any child. Only the corrected fresh directories count.

Raw combined build/execution records are reports/cli-interrupt-build/
ef0a24e1e0d640cf82e8e53cb046f8b1. production-signal-observations.json binds the
corrected immutable images, source bytes, configuration probes, actual events
and sidecars. author-source-proof.json records every runtime/test/helper hash
and explicitly identifies the dirty peer-owned helper inputs. The actual
toolchain is Alire 2.1.1 and native GNAT/GCC 16.1.0; all required warnings,
style, validity and runtime-check switches remain enabled. The standalone
controller proof under reports/
cli-interrupt-control/eddf06739efe406daf4d2c37a98b0670 uses a real signal and
checks overlap refusal, one-shot consumption and preceding-disposition restore.
Native direct C callback, Lua wrapper, pure loop and finalizer observations are
reports/cli-interrupt-native-callback/7e06120177e141218b67d99c9ad589bd; both
native configurations pass these bounded observations. They establish actual
bare-versus-caller-prefixed interruption and suppressed finalizer completion.

The earlier native Windows broker record remains reports/windows-main-signals/
6b2d43bcc8904d50a5b22a66f84ff9ed. Default protected/search and T protected
complete, but native T search has the existing ltests.c:2226 abrupt atexit
assertion on stderr. That native baseline remains a failure, with no changed
criterion, teardown exemption or coverage credit. No main.lua transformed
execution, source adaptation or whole-file acceptance is introduced here.
POSIX source is implemented but has not been executed in this local Windows
component; CI/native same-platform signal observation remains required.
