# Table Sorting and Capacity Hints

This M3 implementation checkpoint adds table.sort and table.create. It does
not establish a whole sort.lua pass: that file also needs collector memory
reports, OS timing, and the remaining full-M3 runtime/test-adapter work.
Current status owns platform acceptance.

## Resumable sorting

The private Sorting driver uses iterative heapsort, with constant-size traced
continuation state and O(n log n) comparisons. It sorts in place without a
second table-sized value array or recursive Ada calls. Each sift phase retains
its saved value, child candidates and indices before requesting a callback.

Ordinary reads/writes obey __index/__newindex; length obeys __len. Primitive
numeric and byte-string comparisons run directly, while other comparisons use
the VM's existing typed metamethod request. Optional Lua/native comparators run
through the same activation scheduler. The native sorting boundary prevents
yielding through those callbacks, as pinned C Lua does. Host work limits remain
shared across phases, helpers and callbacks.

An adjacent-order verification detects contradictory sorted output, including
always-true comparison functions, as a controlled Lua error. Sorting requires
a strict ordering; comparator invocation counts and equal-item order are not
specified. This backend does not claim C quicksort's comparison stream.

## Actual table reservation

Capacity hints allocate real member/index storage through the session provider.
They create no keys and do not change the sequence border. C-int bounds and the
pinned hash-exponent overflow are checked before embedding allocation quotas.
A failed multi-buffer reservation publishes no new index lengths or entries.

Dense members do not consume chained hash capacity. Recycled rows retain their
storage, and conversion from a deleted dense key to a sparse key reserves the
needed hash before modifying the free list. Recycling a row does not grow a
dense history of all its former keys. Retained tombstones count as real chained
rows until unlinking/rebuilding removes them.

The representation remains Ada-owned dense indexes and chained member rows;
private C layout/allocation-count equality is not claimed. Actual allocation
statistics include reserved capacity, even when the Lua table is empty.

## Verification

Twenty named session cases cover ordering, byte strings, duplicate keys, custom
comparators, metamethods, table-like receivers, callback collection/errors/yield
boundaries, invalid ordering, size checks, capacity arguments and host-limit
recovery. Four private storage cases verify real allocations, full preallocated
dense/hash insertion under continued growth refusal, atomic partial reservation
failure, retry and zero managed blocks after finalization.

The initial 940-case run exposed an existing churn invariant while integrating
reservation: a recycled dense row needed its first sparse bucket. The repair
also preserves bounded dense storage under repeated novel-key churn. The final
strict validation/static run passes all 940 cases without weakening that test.
The deterministic table_sorting_campaign uses seed (927, -1701), checks 384 sorts,
65 capacity cases and protected boundary failures. The complete validation/static pipeline passes its 465 output records against
pinned C Lua, with empty stderr, in reports/m3-table-algorithms-check1.log.
No whole sort.lua or complete upstream-suite pass follows.
