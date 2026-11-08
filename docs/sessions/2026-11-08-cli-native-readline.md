# Native CLI readline and fallback input

Date: 2026-11-08, Asia/Tokyo. Author: Codex /root, working from 2f0c115.
This is a component checkpoint; Unix, TTY and final-context acceptance remain
pending. No source adaptation, exclusion, PR or merge is supplied here.

[ADR 0044](../decisions/0044-cli-native-readline.md) records platform selection,
the optional host dependency, alternatives, licensing and ownership. Native
input now runs while the real prompt remains rooted. Linux dynamically selects
the same optional readline library/environment override as C Lua; macOS uses
the system API; Windows retains fixed-size native text stdio. Ada owns prompt
callbacks, expression/statement selection, multiline assembly and execution.
The old unbounded byte loop no longer substitutes for the pinned fgets limit.

Complete nonempty commands enter history once. The history transport borrows
a selected-owner NUL-terminated buffer, releases it before returning and reports
actual allocation refusal through the session. Three independently named AUnit
tests verify no work for empty history, a real synchronous C-prefix observation
and actual selected-provider refusal/retry followed by healthy Lua execution.
The deterministic observer is compiled only in the test crate, never into the
product CLI or runtime SAL. Both strict local CLI/test builds succeeded and
both full AUnit suites pass 2,665 cases without failures/errors.

The new paired process script runs thirteen cases on Unix and fourteen on
Windows. It freezes executable/library files and preserves exact input and raw
streams before comparing the same-host native CLI with Ada. Local Windows
default and T each pass all fourteen pairs: normal/empty/final input, fallback
boundary, embedded NUL, multiline, dynamic prompts, CRLF, invalid UTF-8,
library override/warnings/-E and native Ctrl-Z. Captures are under
reports/cli-readline/b1b194eba3944536b78d20a571ca378f and
reports/cli-readline/858bfe828cb346738ce2fcf53d609171. These are precommit local
component observations with dirty-source metadata, not final frozen contexts.
The existing default CLI suite also passes all 112 operations. Fresh final-head
routine execution and Unix backend observations remain required.

The pair script is integrated after the debug-console operation in ordinary
and instrumented builds. Its report explicitly denies runtime/coverage
authority and measured Ada allocator evidence; product CLI processes do not
acquire such telemetry merely from requested environment variables. Final
image collection/receiver reconciliation must include this report separately
from allocator, console and typed-argument witnesses. Existing strict native
prompt expectations are not weakened to claim the pending Unix selection gate.

Earlier new-script diagnostics failed before producing a complete report due
to PowerShell enumeration of an empty byte array. Direct typed assignment now
preserves that actual zero-byte input. The failed capture remains diagnostic.
The first test compile exposed a missing visibility clause for C.int equality;
that cause is fixed without changing flags or suppressing diagnostics.

Follow-up source inspection of Apple's published header found its integer
add_history return differs from GNU's void return. The macOS branch now uses
a declared-call wrapper instead of assigning an incompatible function pointer.
Four actual strict GCC compile-only cases pass with deliberately synthetic
int/void headers and both product/test macro selections. This verifies the
transport's type handling, not an Apple SDK build or Unix runtime observation.

At committed 4ca6280, both CLI executables were strictly rebuilt and both full
112-operation suites passed. Fresh fourteen-pair results are under
reports/cli-readline/ef73de50211b4aca9c9075cec03f5f90 and
reports/cli-readline/1dd35caf8ab8446499a3851b99333b79. Suite independently read
the prompt/input/history lifetime changes while integrating its separate
message-handler work and reported no high-confidence ownership finding.
