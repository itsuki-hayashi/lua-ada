# ADR 0048: Maintainer-authorized interim compatibility checkpoint

Date: 2026-11-08. Status: accepted delivery-scope change.

The maintainer asked to end the session early, stop progressing toward complete
upstream compatibility, keep the progress, verify it in CI and merge it. This
supersedes the earlier all-or-nothing delivery/merge timing. It does not weaken
Lua behavior, public ABI, ownership, source review or conformance requirements.

Deliver the coherent runtime, public C API, library and verification progress
already on the remaining-compatibility branch. Exclude the unfinished CLI
message-handler/persistent-main/interrupt implementation and host receiver
schema replacement. Preserve them on named remote branches with dated source
and observation handoffs. No unfinished production draft is made acceptable
by calling it a checkpoint.

Use a separately named automatic checkpoint workflow with twelve validation
contexts: each supported OS, both runtime configurations and static/shared
linkage. Run strict builds, full AUnit, actual C/Ada/native-fixture consumers
and the checkpoint's explicit CLI/frontend/binary/library regressions. Keep
batch CLI evidence separate from the full 112-operation protocol and actual
paired native readline/console operations. Do not disable the selected native
backend to satisfy fallback-only expectations.

The complete 26-context upstream workflow becomes an explicit manual campaign
while the target is deferred. Its acceptance contract, validators, pending
source/API ledgers, source-only exclusions and stale-review failures remain
intact. A successful checkpoint workflow is not a full-target certificate.
Document results and limitations in the session handoff and PR. Open one ready
PR, let its configured review run automatically, fix actionable findings and
merge with a merge commit after successful checkpoint checks. Verify post-merge
checks before reporting the requested checkpoint complete.
