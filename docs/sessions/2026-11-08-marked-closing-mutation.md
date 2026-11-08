# Marked closing-value mutation (2026-11-08)

A read-only native/Ada public probe after the scalar-link checkpoint found an
older semantic gap: when an upper closer uses debug.setlocal to replace a
lower slot marked with a truthy value with nil or false, native still attempts that
slot's current close operation. With no type closer it raises the real closing
call error; Ada's shared unwind loop instead skipped every falsy current value.
The initial marking rule and the later closing obligation are distinct.

The narrow @unwind correction captures whether the selected entry came from
the actual scalar chain before popping its head. Linked slots dispatch their
current value even when nil/false; raw type-metatable lookup and the existing
closing continuation handle success/error normally. Initial nil/false never
enter the chain. The legacy packet list retains its separate inactive filter.
No storage, binary format, callback ABI, grammar or executor changes are added.

Four separately named ordinary AUnit/Lua bodies cover nil replacement, false
replacement, false with a real type __close, and outer replacement-error/weak
collection/healthy recovery. The type-closer control checks genuine one/self
normal and two/self+error argument counts and confirms initially false remains
unmarked even while that type metatable exists. Its error case mutates during
a normal inner-scope close before error(17): native hides an already abandoned
owner from numeric debug lookup. All global type metadata is restored afterward.
The weak case drops the original object before the lower closing call and
requires collection while outer cleanup still runs. No T helper is installed
or consulted by these four ordinary bodies.

The source-final default/T runtime, test and C-consumer builds all pass with
Alire 2.1.1, GNAT 16.1.0, Ada 2022 and retained warning/style/runtime checks.
Both full suites pass 2,549/2,549 AUnit cases, including Root's IO regressions
and the earlier scalar-owner negatives. All 26 ordinary default and 27 T C
consumers pass without flags; the separate native-module host campaign is not
rerun. No materialized-vararg WIP was registered or compiled in this replay.

All four bodies pass pinned native default and T. The eight default/T native/
Ada binary producer/VM roles have identical raw stdout SHA256
761655BB33A12DA75E19B73B24D61263781DB0A1183CB6AFBB4EB76B7DACE9D3,
empty stderr and balanced Ada shutdown/accounting. Raw build, case, consumer,
process and telemetry evidence is retained under reports/hook-top/marked-close-*.

Fresh unchanged errors.lua/coroutine.lua are also replayed in all native/Ada
configurations under their actual 2-GiB ceilings, no soft flags and 900-second
timeout. All eight exit 0 with empty stderr. Coroutine raw stdout matches
native exactly in each mode; errors retains only its documented printed
recursion-depth differences, with no output normalization. Ada errors peaks
are 1,870,423,829/default and 144,938,624/T; coroutine peaks are
1,960,496,074/default and 134,606,693/T. Every Ada telemetry record has the actual
2,147,483,648-byte limit, zero outstanding bytes/blocks, completed shutdown
and no accounting fault. The raw large campaign is
reports/hook-top/marked-close-campaign-743d9808374f4fbc8606884e3c176f12. Whole locals
source/runtime/checker bindings still need renewal before reviewed whole-source
acceptance; no source adaptation or original assertion is changed here.

Changed-document encoding/link/table and git diff whitespace checks pass.
The full isolated documentation fixture blocker is unchanged; it is not called
a passing full documentation check.
