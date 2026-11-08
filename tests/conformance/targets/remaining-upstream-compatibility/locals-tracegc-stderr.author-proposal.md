# Pending locals progress-output contract

Two original native File observations on `ca48d67` completed `locals.lua`,
including the actual dump-entry and exact integer5/function two-result return
protocol. The checker then rejected stderr. These remain `setup-failed`
reports: the default child wrote two dots and the instrumented child nine.
No Ada child or adapted source emission followed that failed setup check.

Pinned `tracegc.lua` describes itself as tracking collections. Its finalizer
writes one literal dot to actual stderr as progress, then marks the object
again when tracking is active. `locals.lua` stops the tracker around its stack
overflow recovery and restarts it afterward. This occurs in ordinary default
semantics too. The pinned manual describes finalizer timing and later-cycle
callbacks for remarked objects; an independent review should determine the
proper informational-output contract and whether at least one dot is required
for this exact completed workload.

The proposal preserves the raw bytes, hash and observed count. It proposes a
`locals.lua`-only language of one or more ASCII dot bytes, with no whitespace,
newlines, warning text, control bytes or other diagnostics. It does not filter
or rewrite output and does not promise equal automatic collection counts
between implementations. The actual finalizer side effect, unchanged source
assertions, complete refusal/closing workload, exact return protocol and
selected-owner cleanup all remain required. It supplies no exclusion or
adaptation, and the source is not classified as T-only.

The source-bound JSON records the exact original progress/start/stop and locals
stop/restart spans, the original failed native reports and their process/raw
identities. They motivate a proposed checker correction; they are not passing
evidence. No checker code or existing completion manifest changed. API warning
fragments, memory-error numbered progress, main subprocess observations and
every other file retain their separate strict protocols.

The newer runtime287 correction changes the locals counterpart snapshot. Its
current source review and fresh images must precede another adapted Ada T
execution. Independent source/output-contract review must also precede any
passing target envelope for this progress output.
