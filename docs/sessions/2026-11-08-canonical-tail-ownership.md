# Owned arguments across canonical Lua tail calls

Date: 2026-11-08, Asia/Tokyo. Component checkpoint on fce313c.

The pinned manual describes direct access to hidden varargs for the read-only, uncaptured named
vararg indexing case. The original memory
source's sel(2.0,20,30) must return 32 with no new allocations or extra bytes.
A focused native control passes; Ada's first genuine refusal was Dispatch's
fresh Expanded_Args copy before the direct Lua tail f-to-sel, not table
materialization or GETVARG. This public obligation remains required, separate
from the pending review of materialized-table exact allocation count 3.

For a direct canonical Lua tail, the canonical bridge now validates its actual
current frame, precharges clear work and moves its argument arena into a local
independent owner before calling Dispatch. No argument borrow refers to the
retiring frame. Dispatch validates the private opt-in, pins the independent
values before retirement and borrows them only until actual callee scalar
publication. Push_Frame returns the real created owner explicitly; a hook
activation above a callee cannot become an assumed donation target.

After successful publication, the bridge clears duplicate argument edges and
returns reusable empty capacity to that callee, preserving a larger existing
arena. Partial construction/error paths retain ordinary operation pins and
the local owning vector until unwinding completes. No waiting Ada activation
crosses a foreign transfer. Native, metamethod and migration tail paths retain
their previous independent-copy/continuation protocols; no executor recurses.

Eleven separately named AUnit cases cover the original optimized vararg result
under count/byte refusal, nil tuples, recursive tail arena reuse, retired weak
arguments, actual tail-hook mutation and raised errors, yielding callees,
outer close/error roots, genuine larger-callee allocation refusal with healthy
retry, and bounded host-budget recovery. The larger-callee AUnit case requires
an actual selected-owner refusal, not only an enabled control. Ten public Lua
cases pass native T and match all four native/Ada binary producer/VM roles:
raw stdout SHA256
79C9EE4585C1EAEFAE653317B6B82EA140FB96F1F0987EFE35B8883F0A08B62D,
empty stderr, balanced Ada shutdown and no accounting faults.

All six final serialized strict default/T runtime, test and C-consumer builds
pass with Alire 2.1.1, GNAT 16.1.0 and retained warning/style/runtime checks.
The initial build caught one 80-column line, corrected before the final replay.
Both configurations pass all 2,518 AUnit cases. All 26 ordinary default and 27
instrumented C consumers pass without flags; no separate native-module host
campaign was rerun. Default fixtures explicitly install T for these cases.

Original errors.lua and coroutine.lua were copied unchanged and run in all
native/Ada default/T roles, without soft flags, timeout 900 seconds and actual
2-GiB selected limits. All eight processes exit 0 with empty stderr. Coroutine
stdout matches native exactly in each configuration, hashes
1BA864A5A1252E99B555709EAC4300F63574B0769EF02C1FCCBB319DD6EEB85D
(default) and 67684281E453D226EFF6C1AA9E9DCFFDEC4F631B170E6716D1CA1CD8896DF204
(T). Ada peaks are 1,960,502,197/default and 134,612,816/T for coroutine;
1,870,423,829/default and 144,938,624/T for errors. All finish with zero
outstanding bytes/blocks, shutdown_complete=true and accounting_fault=false.
Errors retains only the previously recorded printed implementation-depth
difference; its output is not claimed byte-identical. Raw process/telemetry
records are reports/hook-top/tail-campaign-f28617fa65244df08d82bdce7b173e2f.

A fresh whole memory diagnostic using the exact approved 17-byte verifier
copy still fails adapted 134/original 133's materialized-vararg allocation-count
assertion: Ada now observes 5 allocations versus native 3 after removing the
unnecessary tail copy. The optimized result 32/count 0/extra-byte 0 obligation is
retained and component-verified, not silently waived with that private count.
Native still fails at 205's Windows temporary-name Permission denied. This
records two failing whole-file observations, not source or final acceptance.

Changed-document encoding/link/table and git diff whitespace checks pass.
The full isolated documentation checker remains blocked by the known missing
busted fixture. No upstream bytes, reference pins, source decisions, allocator
limits or original assertions changed. Final whole-source/platform/matrix and
GitHub review obligations remain open.
