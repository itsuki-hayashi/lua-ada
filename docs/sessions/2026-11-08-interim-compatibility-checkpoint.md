# Interim compatibility checkpoint

Date: 2026-11-08, Asia/Tokyo. Delivery owner: Codex /root.

The maintainer changed the active request to end this session early: stop the
full-target implementation, preserve progress, obtain CI verification and merge
a coherent checkpoint. [ADR 0048](../decisions/0048-interim-compatibility-checkpoint.md)
records that delivery authorization. The original M3 acceptance goal remains
unfinished; this checkpoint does not close its ledgers or certify all upstream
assertions, public headers or 26 contexts.

The cut keeps completed owned-runtime/C-boundary, library, loading, debug,
compiler/binary and test-driver work, plus source-bound conformance tooling and
explicit pending author proposals. Recent component checkpoints include native
string locale behavior, external-string lifetime drivers, actual table storage
inspection, typed CLI arguments, debug.debug through protected continuations,
native readline/fallback input, C-call argument-arena reuse and the smaller
canonical frame. Strict flags, runtime checks, pinned references and eight
consumer-module fixture pins are preserved. Ecosystem/LuaRocks acceptance
remains outside this delivery.

The following unfinished production work is excluded from this PR. Remote
backup heads contain skip-CI preservation commits; they are not ready PRs.

| Backup branch                          | Remote head                              | Preserved draft                          |
| -------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| codex/wip-m3-cli-host-main-20261108    | ccc4a83482bc4de3d10a6f4938d6ddd68d657aa2 | 1d6a29ea42fe141cb75b68b915a431ec7f7b0af4 |
| codex/wip-m3-interrupt-helper-20261108 | 72ca670b680dc58f040f01a79e7ddf9cecc3023d | f45f6422b0833aa97123842f811bc0445f26ef0e |
| codex/wip-m3-host-receivers-20261108   | db22804a66bea9661d009d678f9eec73308cb002 | decfa4e7c5c6f32ceb7bfdec901013465c1becab |

The CLI backup has a confirmed public call/return-hook mismatch in its temporary
per-docall transport. Its persistent host-main replacement and thirty named
tests are unfinished/uncompiled, and the measured nonstring l_print correction
is unapplied. The interrupt stash preserves the dormant core 3624a6d and its
temporary helper/fourteen tests; its third parent retains untracked source
files. Inspect that stash graph in an isolated worktree when resuming. The
host-receiver backup preserves schema2 extraction/replay and an unfinished
warning-scope adjustment. Binary snapshots remain local with hashes; the CLI
backup also preserves 433 verified raw report blobs. Local worktrees are kept.

The independently useful C-call arena change 30c6185 is included as 6d52343.
Its author's 2,679-case combined-draft runs include excluded interrupt tests
and must not be reported as the checkpoint's AUnit count. The clean cut has
2,665 AUnit cases before CI, plus three appended public C cases (33 builtin
cases). Root independently read the lending/return paths and regressions;
current-head checkpoint CI must validate the integrated cut.

Verification and PR/merge identities will be recorded after the new checkpoint
campaign completes. At this handoff's initial revision they remain pending.
The full-target workflow remains manually available and its validators reject
incomplete receipts, stale approvals and missing global reconciliation. All
remaining work is retained in the owning backlog and M3 contract.
