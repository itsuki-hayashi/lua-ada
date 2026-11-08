# Fixed external-string T driver, 2026-11-08

Original instrumented strings advanced through native locale checks to its
missing externKstr wrapper. The new test driver follows the pinned ltests
public API sequence: check the actual string argument, then call exported
lua_pushexternalstring with its pointer/length and null allocator/data. It does
not copy the payload, invent statistics or replace the behavior in Lua. The
caller remains responsible for source storage lifetime. Main T installation
and T.loadlib's separately created-state module register the same real C
function. Existing callback identifiers and inspection paths remain distinct.

Four separately named AUnit cases and a mandatory-T Lua fixture retain a short
binary payload, a dynamically constructed long payload through collection and
table-key lookup, child-state publication before closure, and invalid type
followed by healthy retry. Every borrowed source is actually used after its
collection so its original Lua owner remains rooted. The child result uses
non-NUL bytes because pinned T.doremote publishes through lua_pushstring;
an initial author test incorrectly expected binary-NUL remote publication.
That failing native test was corrected to test the driver's real contract;
the separate short/long cases still retain embedded-NUL behavior.

Both strict test-crate builds pass against the previously verified immutable
fd9041b runtime images, with LUA_ADA_PREBUILT=true. Both full AUnit suites pass
2,574/2,574, zero failed assertions/unexpected errors, and only the expected
named finalizer warning. Runtime, CLI and ordinary C consumers were unchanged
and not rebuilt for this test-driver-only checkpoint.

All four instrumented compiler/VM roles pass with empty stderr and identical
stdout hash `896534ec7ab288ff91f0db34a834b8cbd4b41446366e84a6cfa3a2fc81f44b37`.
Original instrumented strings completes its actual wrapper/zero-return
protocol in both C and Ada with identical stdout hash
`cf7aefc9645e6b785809c8bd78b92f84928a77f6ae3e8aa5eb3ab73c280c590f`.
Its original T guard remains present and actual external-string paths run.
The preceding default complete pair retains matching stdout8e7db5b0 from
the locale checkpoint; a default T omission does not certify this block.

Pinned source, public interfaces and runtime ownership policies are unchanged.
No exclusion/equivalent or acceptance authority is installed. The adapter
registration changes a current exact source dependency, so existing verifier,
API and locals decisions need explicit renewed reviews before adapted replay.
Raw captures remain below reports/exact-equivalent-review. Final whole-target
matrix, aggregate/heavy, review certificate and authorized PR/merge are pending.
