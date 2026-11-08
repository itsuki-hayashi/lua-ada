# Sort argument phases (2026-11-08)

Unchanged errors.lua reached table.sort({1,2,3}, table.sort), where the inner
sort is invoked as a C comparator. Ada reported `bad argument to sort (table
expected)`; pinned native Lua reports an auxiliary error naming `table.sort`.
The retained parent executable also fails the new same-source fixture at its
first generic receiver error.

Sorting now uses the shared argument diagnostic for a missing/invalid
receiver, an oversized first length and a nonfunction second comparator.
The actual call origin supplies the name, method self adjustment and argument
index; absent values differ from nil and raw auxiliary type names survive.
Pinned ltablib.c:checktab forces luaL_checktype after its raw capability checks
fail. Sort first obtains length, checks oversized arrays before comparator
type and ignores an unused comparator for lengths zero or one. Those phase
decisions remain intact. The sorting algorithm and successful iteration/
comparison continuations are unchanged. No public interface was added.

An independently native-paired registry callback clears the actual invalid
comparator C slot and collects its sole weak edge before returning modules
for the error name. Once oversized length or comparator type has definitively
failed, obsolete sort algorithm captures retire before diagnostic callbacks.
The real C window and caller still own all actual live arguments. Comparator
values are copied out of indexing references before capture retirement; the
checked borrow invariant remains enabled. This avoids retaining an operand
that no actual C slot owns anymore, without changing visible logical frames.

The fifteen separately named AUnit cases and two paired Lua fixtures cover
missing/nil/numeric/named receivers, invalid/named/callable comparators, nested
C comparator naming, oversized length, bad method self, trivial intervals,
optional nil, a throwing length callback and failed-root retirement. Both
fixtures pass all four fresh C/Ada producer/VM paths separately in default
and upstream-test configurations, with matched stdout and empty stderr.
Both configurations pass **2,176 AUnit cases**, including the retained return
window and provider fault regressions. All twenty-six ordinary standalone C
consumers pass in both configurations; the additional private T buffer caller
passes too. Configured native-module images were not rerun in this component.

All six static runtime/tests/C-consumer strict builds passed first try,
serially under the root's exclusive build lease, with GNAT 16.1.0, Ada 2022
and all required warning/style/runtime-check policies retained.

Unchanged default errors.lua through the fresh 2-GiB conformance runner in a
disposable original-byte test tree now passes the nested-sort assertion. A
separate diagnostic line hook identifies the next failure as
string.gsub('s', 's', setmetatable): expected `setmetatable`, observed `table
expected`. The original source remains unchanged, no soft flag is used and
neither run passes the whole file. Reference Lua remains pinned unchanged at
`7579fc9d7ed90240487251dfb69168f8e64e9294`. The cold scalar-output refusal
still measured in full T memerr.lua, borrowed Lua CI windows/hooks and all
remaining source/T/shared/platform/final-head obligations remain open.
