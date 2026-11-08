# Owning activation release for resetCI

Date: 2026-11-08, Asia/Tokyo. Component follow-up on bd04911.

Integration review found that the test adapter's resetCI operation physically
freed its validated unused frame cache with a local unchecked deallocator.
That bypassed the runtime's actual Frame_Capacity decrement and C call-record
trim, leaving inflated reservations after the frames themselves were gone.
The cache inspector remains an observer; no repair was added to inspection.

The adapter now delegates each already-unlinked cache owner to the existing
checked Lua.Engine.Free_Frame routine. Its declaration and lifetime contract
are available only in the private engine unit: the caller must detach every
list/borrow/execution ownership before physical release, with the context and
selected memory still alive. The implementation continues to decrement real
capacity, trim unused metadata and retain outstanding C records until their
actual guard acknowledgement. Its release algorithm is unchanged. The adapter's
unchecked deallocator/import are removed; no embedding or C interface grows.

Three separately named regressions cover actual recursively warmed VM depth,
exact remaining frame-owner capacity, selected raw-byte release and healthy
recovery; resetCI inside an outstanding T.testC numeric-error guard; and resetCI
after the actual provider refuses all growth. The two public Lua controls pass
unchanged native T. The physical capacity test independently accounts active,
cached, reset and base owners after the real T command, rather than asserting
an invented native backing size.

All six serialized strict default/T runtime, nested-test and C-consumer builds
pass under Alire 2.1.1 and GNAT 16.1.0, with retained warning/style/runtime
checks. Both configurations pass all 2,507 AUnit cases. All 26 ordinary default
and 27 instrumented C consumers pass without flags; the separate native-module
host campaign was not rerun. The full metadata fixture now has twenty-one
Lua cases. Both binary producers execute all cases under both T VMs with empty
stderr and raw stdout SHA256
DAE4A9CEBBB10FE87E0746501D6F3EF8B07914184716301A78C2D3ACDCFD3D75.
Ada telemetry finishes with zero outstanding bytes/blocks and no accounting
fault. Default AUnit explicitly installs T; an ordinary T-absent run receives
no command-coverage credit.

Changed-document encoding/link/table checks and git diff whitespace checks
pass. The isolated full documentation check remains blocked by the missing
busted fixture already recorded in the parent component. No reference source,
pin, source decision or original warmup/refusal/assertion changed. The prior
unreduced memory diagnostic still stops at the exact vararg-table allocation
count; this correction supplies no whole-file or final platform acceptance.
