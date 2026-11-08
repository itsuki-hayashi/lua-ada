# Native Windows real-signal broker observation

Date: 2026-11-08, Asia/Tokyo. Author checkpoint based on
`7a987882dfe73f0d4b5b793e5de46025345177b0`. Root authorized this test-only OS
broker and a bounded correction after the initial attachment failure. Source,
platform applicability, teardown and runtime reviews remain pending. The
complete native-positive gate is false. No Ada signal implementation, source
adaptation, policy installation, source exclusion or whole main execution is
included.

The [author observation](../../tests/conformance/targets/remaining-upstream-compatibility/main-windows-signals.author-observation.json)
retains both raw campaigns, source identities, exact original anchors and all
four corrected observations. It records three authored native controls passing
and the native T search failing. It does not reinterpret the failure or import
the separate os.exit no-close protocol's authority.

Test-only implementation
------------------------

[The C broker](../../experiments/conformance/c/windows_signal_broker.c) links
only standard C and Windows OS facilities. It neither links Lua nor interprets
source. The two [protected-loop](../../tests/conformance/platform/windows-main-sigint-protected.lua)
and [native-search](../../tests/conformance/platform/windows-main-sigint-search.lua)
fixtures contain the exact original main.lua workload statements. They are
passed as opaque -e arguments to the actual native executable. No helper Lua
error, shorter search, signal emulation, extra readiness marker or replacement
interpreter is involved. The actual first print supplies readiness. The search
retains string.rep('a', 100000), pattern '.*b' and the original one-second delay
after the observed 15.

Each invocation creates one child with CreateProcessW, CREATE_NEW_CONSOLE,
STARTF_USESHOWWINDOW/SW_HIDE and explicit inherited stdin/stdout/stderr pipes.
A STARTUPINFOEX handle list contains only those three handles. The command line
is a writable bounded buffer with ordinary Windows CRT argument quoting; no
shell is involved. Input source is bounded to 4 KiB, each raw captured stream
to 1 MiB, the child deadline to 25 seconds, attachment retries to two seconds,
pipe drain after exit to one second and failed-child cleanup wait to two seconds.
The observer imposes a separate thirty-second broker deadline.

The broker alone detaches from its inherited console and attaches to the actual
child PID's new console after observed workload output. Only documented
ERROR_INVALID_HANDLE attachment failures may retry. Every attempt is timestamped
and the child must remain alive. The broker installs an ignore handler for
itself, then requires GetConsoleProcessList to contain exactly its own PID and
the selected child's PID. It repeats that full check immediately before every
GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0). It never targets a parent console or
uses a nonzero process group. All request results, elapsed timestamps, process
IDs, output and actual wait/exit results are retained.

This follows Microsoft's restrictions: Ctrl-C cannot be limited to a nonzero
process group, and attachment error 6 means the selected process does not yet
have a console. See [GenerateConsoleCtrlEvent](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent)
and [AttachConsole](https://learn.microsoft.com/en-us/windows/console/attachconsole).
The selected native executables' actual PE headers are AMD64, PE32+, subsystem
3 (Windows CUI), so a GUI subsystem silently ignoring console flags is not the
observed input. The source guard checks those measured headers and actual
configuration-child receipts, rather than inferring them from file names.

TerminateProcess is only failed-probe cleanup. Any use forces the result to
failure and records its actual wait. A normal probe drains both pipes, waits for
the real child exit, closes all owned handles/files, frees its attribute list
and detaches. The four corrected probes used no cleanup termination.

Actual observations
-------------------

Initial raw campaign:
`reports/windows-main-signals/297f1e506c1b439b85d7aa2797c618f5`.
CreateProcess succeeded, but attachment at elapsed zero failed with error 6.
No signal was requested. Failed-probe cleanup terminated the child with 125 and
waited successfully; the broker exited one. The exact initial C and observer
bytes are preserved beside that campaign, matching its recorded source hashes.
This observation remains a failure. Root authorized the same-path correction
to wait for real readiness and bound only error-6 retries. Successful later
attachment supports the initialization-race hypothesis without rewriting the
initial evidence.

Corrected raw campaign:
`reports/windows-main-signals/b133f7c63fe248a8856db55452482dc4`.
The four probes have the following actual results:

| Native configuration | Workload  | Requests | Child exit | Broker exit | Strict result |
| -------------------- | --------- | -------- | ---------- | ----------- | ------------- |
| default              | protected | 1        | 0          | 0           | PASS          |
| default              | search    | 2        | 3221225786 | 0           | PASS          |
| T                    | protected | 1        | 0          | 0           | PASS          |
| T                    | search    | 5        | 3221225786 | 1           | FAIL          |

Each protected workload prints exactly 12 followed by 42, with empty stderr.
Both normal closures have actual PID/run/configuration-bound sidecars at the
2 GiB limit and zero outstanding bytes/blocks. Raw stdout SHA-256 is
`58e790f8d98cfc2e5ce82582946d817d294375805b4445e79c322ed0ccf020fd`.

Both searches print exactly 15, receive the recorded successful real Ctrl-C
requests and actually die with Windows status 0xC000013A. Raw stdout SHA-256
is `e2bb232cac786f7284bb237d193407e94f32ee0fbf64d27d0ae8b1642de44923`.
Default search stderr is empty. T search stderr contains the actual assertion
`l_memcontrol.numblocks == 0` at ltests.c line 2226; its raw hash is
`3502938af48118d9164dd36c60d9d761721edc05c8ac9f3dfecc68ae347a7bff`.
Native ltests.c registers that final-memory check with atexit at line 2239.
The source packet anchors both the check and registration. The broker's strict
criterion requires empty search stderr, so T search remains failed even though
its actual OS-signal delivery/death trace is available for independent review.

Neither abrupt search produces normal-return allocator telemetry. Those missing
sidecars are explicitly unavailable, never synthesized or called balanced
shutdown. The measured normal count is two and the unmeasured abrupt count is
two. Request counts are retained observations, not refreshed expected values.
Every child completed within 1.6 seconds in this campaign, with no forced
cleanup or outer capture/pipe failure.

Validation and next review
--------------------------

[The observer](../../scripts/observe-windows-main-signals.ps1) ran standalone
GNAT GCC 16.1.0 directly, with -std=c11 -Wall -Wextra -Werror -pedantic -municode.
It freezes the exact C input and records compiler/executable hashes, command,
clean compile output, native EXE/DLL hashes, actual config-child output, fixture
bytes, environment and raw process receipts. PowerShell is 7.6.9. No Alire/GPR
configuration or generated project file was touched.

[The integrity guard](../../scripts/test-windows-main-signals.ps1) passes 217
positive checks and sixteen rejection controls. It executes no signal, process,
compiler or Lua code. It checks eight current source bindings and eight exact
original main/lua.c/ltests.c byte anchors; initial failure retention; the frozen
build; all four raw event/output/status records; monotonic timestamps and actual
PIDs; exact console membership immediately before requests; the two balanced
normal closures and two explicitly absent abrupt sidecars. It rejects a passing
native gate, relabelled T success, nonzero signal group, cleanup-as-pass,
invented accounting, changed source/payload/count and source/policy authority.
These are evidence integrity results, not a complete native-positive result.

Root must independently review source, real delivery and abrupt native T
teardown as separate questions. Any scoped feature/protocol decision needs this
actual default partner and preserved T failure; it cannot silently mark the
native allocator check clean, exclude public signal behavior, import another
protocol's authority, change the search or fabricate shutdown evidence. Only
after the required native gate and source review may an Ada signal design or
main source mapping proceed. Work stopped bounded after this author commit.
