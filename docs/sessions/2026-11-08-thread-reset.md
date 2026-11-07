# Public thread reset and guarded self-close

Date: 2026-11-08, Asia/Tokyo. Component checkpoint within the approved remaining
upstream delivery; this is not complete-suite or final matrix acceptance.

## Objective and implementation

Implement the real `lua_closethread` public contract using pinned `lstate.c`
`luaE_resetthread`/`lua_closethread`, `ldo.c` protected closing, and the public
manual's self-close rule. Preserve one universe, allocator, grammar, driver,
set of actual scalar slots and host budget. No reference source or pin changes.

Non-self reset borrows context-reserved scalar driver/transport owners. It
restores any published yield view, adopts held scopes only after actual C
acknowledgement, freezes closing cells and retires old execution in physical
reverse order. The existing iterative closer consumes genuine Lua/C closing
entries with a saved prefix floor. Reset clears old recovery continuations;
completion leaves no stack values, or one original final error and normal
thread status. A failed thread's incoming error is passed to real closers.

Self-close is a separate typed boundary action. Every nearest live C guard
runs its own cleanup before forwarding it, including reader/parser ownership,
dump snapshots and format owners. Callback guards acknowledge their exact
activation/serial. The terminal guard then resets through the existing driver;
no nonlocal jump crosses suspended Ada, no executor is called recursively and
no abandoned C body or old Lua PC resumes. Warning and release ownership are
acknowledged before starting the walk. Reentrant self-close during a closer
preserves the true outer native-depth base. Actual close results and failure
objects remain rooted through final publication.

C surfaces reserve eight reset continuation frames plus one idle driver and
transport record. The bounded pool is exclusive to reset; simple C closers can
run after permanent allocator refusal even while failed scope records remain
owned. Ignored C return values stay in their scalar window, preserving actual
return metadata without allocating an unused result packet. Per-controller
argument/result/error capacities survive reuse. Arbitrary Lua closer work and
hooks still use the same allocator/budget; this is not a blanket allocation
parity claim. [ADR 0026](../decisions/0026-base-c-closing-ownership.md) owns the
extended ownership decision.

## Verification

Windows x86-64 strict validation/static root, nested tests and C-consumer builds
pass with Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.1. Ada 2022 warning/style
checks and runtime checks remain enabled. All 1,737 local AUnit cases pass,
including fifteen separately named additions. Twelve wrap independently named
counted-provider C cases. Three use a genuinely Ada-owned driver and real C
callbacks: a self-close on the reader's second refill, queued warning reset
with a pending Lua closer, and an uncatchable original host quota exhausted by
a closer followed by same-world recovery. Each completes with zero live owned
blocks. The retained persistent-refusal iterator assertion is unchanged.

The public `thread_reset_api_contract.c` has 24 cases covering fresh stacks,
suspended Lua/C, incoming and replacement errors, reuse, actual weak-prefix
lifetime, no-closer refusal, nested C and Lua-resume self-close, idle base C
slots, reader/writer/warning/hook self-close, self-close error publication,
simple and multiple C closers under permanent refusal, twelve ignored C return
values, a failing closer followed by another closer under refusal, recursive
self-close, and 24 growth-position failures in an allocating Lua closer with
older C cleanup and same-thread recovery. Counted provider bytes/blocks reach
zero at state closure. Native default and Ada raw stdout SHA256 is
2557BAD26D906DDC41385FA9A31BF86F21BCAEB24DAD31E245A600038B37F9B8.

Native T rejects warning callback API reentry at its test lock in `lstate.c`.
The explicit `--without-warning-reentry` counterpart runs the other 23 cases
and records one SKIP; Ada's same-argument default counterpart matches raw
stdout SHA256
2BEC89EABBD0E210D80EB331DB0789F9D274D7F47935B2BA629DD8EDCDA1AAAB.
The warning case is required and passes in ordinary C/Ada; the T skip is not
a passing test. The script records matching/skipped counts separately.

The same-source oracle uses isolated reference libraries and GCC 13.2.0 with
`-std=c99 -Wall -Wextra -Werror -pedantic`. The fixture source SHA256 is
CBDDA7B7F115DF21E09BF0D3820966487A0FF9408145B2DD282FE8E92FD910AF.
All sixteen standalone C contracts pass after the production changes, including
protected close-yield, load/dump, debug, foreign continuations, external strings,
formatting, value/auxiliary, operators, conversion, GC, IO, indices and base
closing. Local logs are under reports/thread-reset. The new core-image driver
entries parse successfully; a fresh complete core-image campaign was not run
in this isolated checkout and is not claimed passing here.
The six changed guides/records pass scoped LF/link/table checks. The full
documentation checker stops at the preexisting uninitialized busted fixture's
missing rockspec in this isolated checkout; that run is not called passing.

## Native partial-reader cleanup observation

The immediate reader self-close is balanced in both native configurations and
belongs to the paired protocol. If the first read returns `return 37, ` and
the second read self-closes, native semantics complete the self-transfer but
the jump skips parser scratch cleanup. Default C fails the final counted
provider balance assertion; native T aborts its internal total-byte invariant
during `lua_close`. This is a diagnostic failure, not passing ownership evidence.
The standalone reproducible source is
[thread-reset-partial-reader.c](../../experiments/conformance/thread-reset-partial-reader.c).
Compile it separately against the isolated selected reference library using
the same public header flags. The additional Ada-owned reader AUnit case
requires two refills and zero owned blocks instead of copying that leak.

A bounded read-only Claude Haiku guard audit cost $0.0175593 for fifteen turns.
It mapped cleanup/typed-transfer sites but did not inspect every completion
handler; its unverified observations were checked against source. Later reset
pool/refusal refinements were outside that audit. This is not final GitHub
review approval.

## Remaining work

Fresh Lua-created coroutine initial function slots still need their separate
public stack witness and implementation. Relevant T api.lua/memerr.lua command
drivers, complete allocator parity, integrated Ada T/shared/platform matrices,
unchanged full-target execution, reviewed scope evidence and final PR review
remain open. No reference test, conformance ledger obligation or public
requirement is excluded by this component checkpoint.
External-release self-close has no dedicated public fixture in this checkpoint;
its typed completion path is implemented but not certified by warning tests.
