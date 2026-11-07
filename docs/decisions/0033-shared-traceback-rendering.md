# ADR 0033: Shared owned traceback rendering

Date: 2026-11-08. Status: accepted implementation direction; full upstream
acceptance remains subject to the remaining-suite contract.

## Context

Lua debug.traceback already traverses the runtime's real logical frames.
The public luaL_traceback function needs the same metadata, name inference,
source formatting, tail markers and deep-stack shortening. A second debug
implementation would create divergent frame visibility and ownership rules.
The previous renderer also used unmanaged growing text and stack-sized
temporary frame vectors, which are unsuitable for allocation-failure paths.

## Decision

Place rendering in the existing private Inspection package and share its
logical-frame predicates and borrowed Call_Identity query. Both the Lua
debug operation and the C auxiliary export invoke that renderer. The C
wrapper measures its borrowed message in charged groups and returns through
the established dispatcher; it contains no frame traversal or interpreter
algorithm. No nonlocal transfer crosses an active Ada frame.

The destination's selected provider owns every growing builder and the
published string. The source context retains its actual frames during the
callback-free operation, including when it belongs to an independent state.
Two metered walks count and render frames without allocating frame snapshots.
When pending cleanup requires filtering, each comparison is charged through
the existing Failed_Owner query. Output scanning, copying and registry walks
also consume the destination's execution budget.

Names borrow actual module keys until a match is found. A matched joined
name uses owned temporary storage and retains the pinned C-prefix and `_G.`
handling. Scalar conversion has bounded scratch. Source display scans only
the prefix that can contribute to a bounded chunk identifier. Lua levels
undergo the pinned wrapper's C-int conversion before frame selection.

## Evidence and limits

The component session records actual native-paired C witnesses and separately
named AUnit policy checks. Source contexts are borrowed, never resumed or
closed by the renderer. Successful stack inspection is distinct from full
debug or C-surface acceptance.

Registry `_LOADED` metamethod continuation still needs its own retained
behavioral evidence. This component's synchronous lookup does not discharge
that callback path. It adds no exclusion, adaptation, final matrix result or
global conformance acceptance. The independent code review found and led to
removal of unmetered filtering and stack-sized snapshot allocation; its
possible hook-PC concern is ruled out by the frame's Positive PC type.
