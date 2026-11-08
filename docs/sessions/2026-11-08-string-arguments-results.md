# String argument and scalar-result checkpoint (2026-11-08)

This component continues the remaining upstream delivery. It does not close
errors.lua, memerr.lua, relevant T facilities or the full acceptance matrix.
Reference Lua remains unchanged at
`7579fc9d7ed90240487251dfb69168f8e64e9294`.

String subject, position, pattern, replacement and format checks now use the
shared auxiliary argument diagnostic, including actual method self/index
adjustment, missing versus nil values and raw auxiliary type names. Sub's
start is required; byte's start remains optional. Gmatch checks its pattern
before the optional position, and gsub checks the limit before replacement
category. Char preserves integer-representation versus range errors. Dump
requires a Lua function, matching pinned lstrlib.c:str_dump's special check;
the retained native-dump test was corrected to that native-observed message.
Values are copied out of vector indexing references before a diagnostic can
transfer or retire the failing builtin phase. Borrow checks remain enabled.

Scalar string operations fill the actual activation's owned output arena.
A waiting native receiver first reuses sufficient existing result capacity,
or adopts a sufficient empty argument arena. The producer remains traced
through Copy_Roots; its old value edges clear immediately after publication.
The allocation-free owning move remains available when no receiver capacity
exists. This preserves warmed storage without creating a shadow value root.
Pcall/xpcall success publication reserves the complete status prefix before
changing protection, prefixes in place exactly once and then uses normal
completion. Error recovery and the existing error packets are unchanged.
The procedure overload is private; the existing function form remains for
internal callers. This establishes selected warmed scalar behavior, not an
allocation-free guarantee for every string output or public C operation.

## Verification

GNAT 16.1.0 strict Ada 2022 static runtime, tests and C consumers built serially
in both default and upstream-test configurations under the root's exclusive
build lease. A first generated-test compile rejected comment spacing; the
spacing was fixed and the complete test build rerun without flag changes.
After the final test-only refresh, all **2,146 AUnit cases pass** in each
configuration, including 32 new separately named argument checks and fifteen
cold/warm/status/yield/error/weak-lifetime/refusal cases. The retained provider
fault sweep also passes. All twenty-six ordinary standalone C consumers pass
in both configurations; the additional private T buffer caller passes in T.
Native modules require configured images and were not run bare in this check.

The 32-case argument fixture, its direct-code compiler companion and the
eleven-case scalar/status/lifetime fixture pass native default and T. All
three also pass all four C/Ada producer/VM paths in the default configuration,
with equal stdout and empty stderr. The first argument fixture passes all four
paths in T. Four strict refusal cases require an actual T allocator driver;
they pass native T and the fresh Ada T conformance runner. They cover a plain
two-index find, one-integer length, zero-result byte and an arbitrary table
error through the directly called C error builtin. The real control surface
is initialized before producer warming: a first Ada-host C entry prepares
reset metadata and may consume ordinary cached frames. The configured T
launcher already performs that setup while installing its warning callback.
No test bypasses refusal or treats absent T as passing these cases.

A tool-free one-turn supplied-source Claude Haiku review reported no
high-confidence actionable bug (reported cost USD 0.00751015). Its conditional
questions were checked against Complete's protection guard, Values.Move's
actual finalizing transfer semantics and pinned str_dump. This review did not
execute tests and is not GitHub/final approval.

## Measured remaining failures

The exact direct-code argument fixture compiled by Ada aborts on native T at
ldebug.c:getbaseline's absolute-line estimate assertion. The native-produced
chunk and both Ada VM paths pass. Pinned ltests.h sets MAXIWTHABS to 3, while
the compiler currently writes periodic absolute lines every 128 words for
both configurations. That selected debug-writer interval is a separate next
checkpoint; this record does not call the failed T producer/VM path passing.

Unchanged errors.lua through the fresh default conformance runner, in a
disposable original-byte test tree, passes the three sub/self assertions and
next fails table.sort({1,2,3}, table.sort): expected `table.sort`, observed
`bad argument to sort (table expected)`. No soft flags or upstream edits were
used. Full unchanged T memerr.lua has not been certified by these focused
refusal results. Borrowed Lua CI windows/hooks, remaining original sources,
shared/platform campaigns and immutable final-head acceptance remain open.
