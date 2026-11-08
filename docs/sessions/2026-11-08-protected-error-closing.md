# Protected error closing checkpoint

Date: 2026-11-08, Asia/Tokyo. Scope: regular callback error closing, following
the real execution-retirement and closing-prefix prerequisites. This is a
component checkpoint in the approved major delivery, not its completion.

## Implemented ownership and behavior

Error closers through Lua pcall can suspend after genuinely abandoned native
and Lua execution has relinquished its real charges and windows. Private close
holders no longer invent another protected floor for ordinary/error closing;
explicit coroutine reset keeps its nonyieldable protection. Shared inspection
sees the surviving real caller. Message handlers still observe intact failing
frames before retirement. [ADR 0027](../decisions/0027-protected-error-closing.md)
records the phases, native sources, alternatives and remaining guard scope.

An unprotected regular C call now defers scopes until its actual callback guard
acknowledges the error. Intrusive scope ownership remains traced; metadata
capacity reserves allocation-free restoration. A physical one-value error
view above the retained scalar prefix prevents publication from overwriting
pending locals. Exact frame/serial tokens distinguish that regular guard from
ownerless or borrowed warning/reader/release guards. Adoption restores scopes
without executing their old PCs. A private shared adoption operation also
supports coordinated thread reset after actual typed C transfer.

Acknowledgement schedules recovery on the same context/driver. Initial testing
exposed that calling recovery directly bypassed root lua_resume finalization;
the continuation preserves its existing failure protocol. Debugger inspection
also found a new query borrowing a root driver after publication had freed it.
The final code captures the error-view boolean before finishing/freeing the
driver and uses that scalar during result publication.

Unhandled coroutine errors preserve the original failed local/call graph and
pending closers until reset. A suspended unprotected callk boundary has already
left its C guard and supplies no error protection. Its K is skipped for an
escaping error, while a caught inner pcall leaves an unrelated outer K intact.

Actual close invocation uses retained frame-owned arguments. Ordinary callable
non-tail dispatch borrows rooted input until the new activation owns its slots
and packet. Tail replacement and __call receiver insertion retain owned copies.
This removes fresh argument-vector allocation during a permanently refusing
error transfer. Only explicit reset needs the per-closer false/error holder.

## Verification

Strict root, test and C-consumer builds pass with Alire GNAT 16.1.0 and the
retained Ada 2022 warning/style/runtime-check policy. All 1,713 AUnit cases pass.
Eight separately named new cases cover replacement errors across yields, an
abandoned tostring barrier and caller, pre-TBC ordinary-local roots, dead
post-TBC locals, obsolete return-packet release, nested closing floors, and
false results discarded by normal/error closers. The original six cases each
failed the prior Ada executable before implementation. The final eight-case
Lua fixture passes both native configurations.

The public close_yield_contract source has thirteen named cases: the nine
call/pcall/pcallk × normal/body-error/close-error combinations, unhandled failed
traceback locals, two suspended-unprotected-callk boundaries, and persistent
refusal after a C error object is ready. That last setup first warms real
scope/call ownership, then refuses all growth until the first real closer runs
after acknowledgement. It preserves error 17 with zero attempted growth in
that interval. Native default and T run the identical source; both and Ada have
stdout SHA256
0827ECE114C41F2EF8CF277131788EFBF412D7678B780475CF024A169468AC9E,
empty stderr, and zero counted blocks/bytes after state closure. The T run
initially caught missing public stack reservation before getlocal pushes in
the new traceback fixture; lua_checkstack now satisfies that actual API
precondition, with all assertions retained.

All fifteen retained standalone C consumers pass after the shared dispatch
change. The eight-case fixture passes both producers on both default runtimes
with empty stderr and stdout SHA256
6337861BEE93FC474D19BA39CA841327CF180FCC1E5D8D3212F38C27FB53A861.
All thirty-six retained four-way compiler/runtime cases pass too.

The unchanged locals.lua copy now reaches OK in default source C/Ada runs with
no _soft setting. Its source SHA256 is
56B5126C40F48BB1A701F041AF28CD72A3A7D50B3DB9B05DA5659F2485F740C1.
Both runs have stdout SHA256
1092E05E70A6DBA1AFDECAE3A03CED806D4DB5A1804EF1C5DD6D1E183AB6483B
and stderr SHA256
272B660CC18BCD3289A0C88A76BFB45F2A12AB76A1571F0118D5A074A5E59751
(two tracegc progress dots and CRLF). Full default four-way chunks also pass
all assertions with that stdout. Their raw stderr differs: both C executions
have two progress dots, both private Ada runtime-probe executions one. This is
recorded as a collection-progress observation, not a raw four-way pass. The
final source db.lua replay retains stdout SHA256
61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897
and empty stderr. Runs use a disposable full original-byte test-tree copy;
reference sources and pins remain unchanged.

A bounded tool-free one-turn Claude Haiku review of the earlier ownership
draft reported no high-confidence findings ($0.0127). Its two questions concern
existing idempotent window retirement and real guard-token initialization;
both were inspected. Later traceback/callk/refusal refinements were outside
that draft review, so it is not final-head or GitHub review approval.

## Handoff and limits

Ownerless warning, reader, writer and external-release guards remain real
barriers. Broader deferred abandonment needs independent native policy cases
and actual typed guard ownership; these regular callback cases do not certify
it. Full allocator parity, integrated thread reset/self-close, T-enabled
locals.lua obligations, final platform/image matrices and final-head review
remain open in the major delivery. The default T-absent locals.lua return does
not certify omitted C tests. No reference or conformance-ledger scope is edited.
