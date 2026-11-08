# Scalar closing owner bound (2026-11-08)

Independent integration review of 287ff2b found that Closing_Predecessor
validated initialized context rows and the owner's lower base, but did not
reject a level above its owning frame window. Another live child can own such
an initialized row. Strict descent alone does not establish that ownership.

The private query now rejects Level - Stack_Base > Stack_Window_Length after
its lower-bound check, avoiding overflowing base-plus-length arithmetic.
Public C pushes/checkstack and active borrowed views resize the physical owner
before publishing extra slots; abandoned execution retains the same descriptor.
Current Foreign_Top may belong to a child or a smaller suspended view and is
not this upper bound. A predecessor is above the owner base and below the
validated head, so it also remains inside the owner upper bound. This changes
no scalar allocation, visible top, frame layout, callback or binary protocol.

Two new separately named VM cases publish a real initialized child window and
reject its slot as the parent's head, and separately reject a wholly
uninitialized context index. Both restore/query/collect the original chain
before physical teardown. The existing cycle, liveness-independent root,
actual C views and retired closing cases remain intact.

All six serialized strict default/T runtime, test and C-consumer builds pass
with retained Ada 2022, warning/style and runtime checks. Both full AUnit suites
pass 2,538/2,538. All 26 ordinary default and 27 T C consumers pass without
flags, including borrowed C views, closing prefixes and actual reset/allocator
fault cases. The separate native-module host campaign is not rerun.

Fresh unchanged errors.lua/coroutine.lua copies complete in all eight native/
Ada default/T roles, no soft flags, 900-second timeout and actual 2-GiB ceilings.
All exit 0 with empty stderr and balanced shutdown/accounting. Coroutine raw
stdout matches native exactly in each mode. Errors retains the previously
recorded printed recursion-depth difference; no normalization was performed.
Raw source-final build, process and telemetry evidence is retained under
reports/hook-top/scalar-owner-*. The materialized-vararg fixtures and runner
registration draft are separate uncommitted work and were excluded from these
builds. Whole locals source bindings and final acceptance remain pending.

The fresh large campaign is
reports/hook-top/scalar-owner-campaign-0e010d722a3641e29a788fe4e3e98187.
Ada errors peaks are 1,870,423,829/default and 144,938,624/T; coroutine peaks
are 1,960,496,074/default and 134,606,693/T. All telemetry records the actual
2,147,483,648-byte limit, zero outstanding bytes/blocks, completed shutdown
and no accounting fault. Four changed-document checks and git diff whitespace
checks pass; the full documentation fixture blocker is unchanged.
