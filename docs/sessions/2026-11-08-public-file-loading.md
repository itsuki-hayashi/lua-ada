# Public file loading checkpoint

Date: 2026-11-08, Asia/Tokyo. This continues the approved remaining-upstream
delivery. Full-target implementation, review and merge remain outstanding.

`luaL_loadfilex` now delegates to the actual Ada parser/decoder through owned
file input; its public macro uses that same export. The Lua file/stdin/module
loaders share the native stream and preamble helper. All input-sized retained
bytes use the selected owner. Every owned FILE closes before parsing or any
error/host action can return to C. Source diagnostics use the existing debug
formatter, removing the incorrect raw @ marker from C load syntax errors.
See [ADR 0029](../decisions/0029-owned-file-input.md).

A Haiku draft supplied eighteen focused cases. Primary inspection strengthened
exact syntax and memory error classes, activated refusal inside the actual
callback, and added a binary-prefix witness, an actual-growth failure sweep
and a lone-CR shebang witness. Each sweep attempt owns a fresh identically
configured state; each failed state must recover and close without live bytes
or blocks. Counts are measured separately per runtime, never asserted equal.

A bounded independent Sonnet review found the shared lone-CR preamble bug.
The implementation now ignores it through LF while preserving terminal CRLF
bytes in the pure preparation API. Two separately named pure cases and the
native-paired case protect the distinction. Two additional C/Ada embedding
cases enforce source/work quotas and immediate teardown without another Lua
operation. The review inspected implementation source, ran no tests, and its
other bounded-work observations are recorded in ADR 0029. It grants no source
exclusion or full-target acceptance. Raw review:
`reports/remaining-loadfile-sonnet-review.json`.

Local tools remain Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1
(executable 26.0.0), with strict flags and runtime checks. Windows validation
static runtime/tests/C builds run serially in default and T configurations.
Both configurations pass all 1,898 combined AUnit cases. The twenty-one public
C cases match native default and native T, including exact deterministic
output SHA256
`5c72f179d02e46b9c87f9bc8b4f41c8da35398fd5fbe56faddbd80ee5fd126b0`.

The named stdin modes preserve the actual child byte streams. Sixteen real
children cover text stdin in four images, four binary producers, and all
four C/Ada producer/consumer pairs within each configuration. Result checks
include three returns, an embedded NUL payload, source metadata and balanced
state closure. Windows binary stdin/stdout is explicitly selected in both
oracle and implementation probe roles. The local diagnostic record binds
source, executable, native library, arguments, input/output hashes and byte
counts; authority is explicitly false. It is not the final sealed runner.

Logs: `reports/remaining-loadfile-{default,tests,consumer,T,T-tests,T-consumer}-build.log`,
`remaining-loadfile-{AUnit,T-AUnit}.log`,
`remaining-loadfile-{C-default,C-upstream-test,Ada-validation-static,Ada-upstream-test-validation-static}.log` and
`remaining-loadfile-stdin/observations.json` with its raw inputs/outputs.
The earlier failed source-marker probe and invalid fixed-file B experiment
are not passing tests. Temporary artifacts from those failed experiments
were removed; their raw failed B observation/executable remain in reports.

Shared/POSIX/final-head context evidence, complete primary/aggregate/heavy/T
drivers, source/API reconciliation and independent certificate remain open.
The remaining auxiliary traceback helper still needs implementation. Native
pointer/undefined-lifetime experiments do not authorize any ledger exclusion.
