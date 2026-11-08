# Preserve lifecycle watchdog failures

Date: 2026-11-08, Asia/Tokyo. Author: Codex /root, from 4ca6280.

The fa6d99c diagnostic run
[42473877709](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42473877709)
failed the macOS default lifecycle campaign after unchanged goto.lua completed.
The Ada coroutine child exceeded the existing 2 GiB sampled resident watchdog.
The old helper threw before writing its in-memory stdout/stderr, losing the
actual workload's last output and measured peak. This remains an unresolved
runtime/platform failure, not an exclusion or passing acceptance result.
Linux default in that run instead failed downloading AUnit with HTTP 504;
Windows T still rejected the dated GC/verifier source bindings. Those failures
are distinct and receive no runtime credit.

The helper now streams to fresh campaign files, writes a process record with
actual arguments, executable hash, PID, status, sampled peak, limits and raw
stream identities, then throws on watchdog failure. It retains the same
50 ms sample interval, memory/time thresholds and owned-child termination.
Normal exact-output/omission checks are unchanged. A sampled value of zero
means no non-exited poll observed the process; it is not a measured peak.
This legacy watchdog is resident memory, not the separate managed allocation
limit required by final target acceptance.

Local unchanged goto/coroutine pairs complete against C in the normal campaign
reports/lifecycle/bf36ece58d684c24a73caf0e42a39171. An intentional one-byte
resident threshold then actually terminates the Ada goto child and returns a
failed campaign. Its 8,933,376-byte sample, 122 stdout bytes, zero stderr bytes,
actual PID/executable/arguments and both original C streams remain available
in reports/lifecycle/f861bc5fc46c4a629547611c6135c4db. This negative probe is a
watchdog-evidence regression, never a passing Lua result. Failed setup or pipe
operations outside this watchdog path are not claimed covered by that probe.

The development workflow also observes readline as a separately named
operation after an incomplete campaign, if an Ada CLI actually exists. It
builds the separate C oracle and runs the unchanged paired process script.
This does not repair the previous failed step, bypass source acceptance or
claim complete context acceptance. It allows native backend investigation
while retaining the unrelated lifecycle/source failures and all raw artifacts.
The new macOS coroutine capture and Unix backend results remain pending.
