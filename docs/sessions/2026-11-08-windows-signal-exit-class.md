# Windows signal exit-class correction

Date: 2026-11-08, Asia/Tokyo. Follow-up to
[the real-signal author checkpoint](2026-11-08-windows-real-signals.md) at
`1c4c92af27956288b27406fc8254ffd4854c320f`. Root's independent source review
found that the search broker accepted any nonzero child status after successful
requests. That could misclassify an unrelated crash as a signal result. No
passing native T search or complete native gate was claimed by that checkpoint.

The broker now names EXPECTED_CONTROL_C_EXIT as Windows status 0xC000013A and
requires exact equality. The observer and source guard use the same named
UInt32 value. An access-violation status such as 0xC0000005 is rejected even
with the expected output and successful request count. The underlying
workloads, signal delivery, strict empty-stderr requirement and T failure
classification are unchanged.

The cleanup audit also found that CloseHandle, final FreeConsole and HeapFree
errors were ignored. They now set a cleanup-failure flag, emit an error event
and prevent success. The final cleanup-complete event records the actual
successful handle-close count. The source-file handle, six pipe handles and
two process/thread handles account for the nine observed closures. Attribute
list destruction has no return value and remains guarded by successful
initialization. File close failures already prevented success; event-stream
errors also prevent success. These checks concern the OS broker's resources;
they do not invent normal Lua shutdown telemetry for abrupt children.

Fresh actual campaign:
`reports/windows-main-signals/6b2d43bcc8904d50a5b22a66f84ff9ed`.
The corrected source compiled cleanly with standalone GNAT GCC 16.1.0 using
-std=c11 -Wall -Wextra -Werror -pedantic -municode. No Alire/GPR ran.
All four original-workload probes were repeated with frozen native EXE/DLL
copies and actual CUI/configuration identities. Their results remain:

| Configuration | Workload  | Requests | Child exit | Strict result |
| ------------- | --------- | -------- | ---------- | ------------- |
| default       | protected | 1        | 0          | PASS          |
| default       | search    | 2        | 3221225786 | PASS          |
| T             | protected | 1        | 0          | PASS          |
| T             | search    | 5        | 3221225786 | FAIL          |

Every corrected broker records successful checked cleanup and nine closed
owned handles. No probe needed forced termination. Both protected loops retain
exact 12/42 output, empty stderr and actual balanced normal-return sidecars at
2 GiB. Default search retains exact 15 output and empty stderr. T search retains
exact 15 output and the ltests.c:2226 final-memory assertion. Both searches have
the exact expected Windows control-C exit status, but neither has normal-return
telemetry. The latter remains explicitly unavailable, not balanced closure.
The complete native-positive gate remains false.

The [current author packet](../../tests/conformance/targets/remaining-upstream-compatibility/main-windows-signals.author-observation.json)
records the fresh campaign and retains the entire prior packet at
reports/windows-main-signals/b133f7c63fe248a8856db55452482dc4/prior-author-packet.json.
That prior packet's raw observation and compiled C input remain unchanged, and
its exact observer is preserved alongside them. The first error-6 attachment
failure remains preserved separately. The dated original session's four
observations are historical evidence, not overwritten by this replay.

[The updated source guard](../../scripts/test-windows-main-signals.ps1) passes
228 integrity checks and nineteen rejection controls. New controls reject an
unexpected access violation, a loose exit-class contract and unchecked cleanup.
It also validates all four checked cleanup records and the prior source/raw
snapshots. The rejection control changes a recorded status; it does not crash
a native process or count a synthetic child as a real signal positive. The
guard executes no Lua, compiler or signal. Both modified PowerShell files parse,
the two touched Markdown files pass documentation checks and git diff checks
pass. No criterion, exclusion, source mapping or Ada implementation changed.

Root's independent delivery and abrupt native T teardown reviews remain
pending. This correction removes an overbroad success condition; it does not
clear the retained T failure or authorize a whole-main/Ada signal claim.
