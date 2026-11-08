# ADR 0047: Remove unused canonical frame arenas

Status: implemented and locally validated; macOS/final-context results pending.

The unchanged coroutine.lua deep-recursion test approaches the existing 2 GiB
limit. Its default Ada managed peak was 1,968,500,975 bytes on Windows; the
macOS legacy resident watchdog had already failed. Do not lower the semantic
stack limit, enable reduced-suite flags or discharge this useful lifetime
stress as a private C representation test.

Canonical registers and captured-cell associations already reside in the
context's shared scalar stack. Frame.Canonical_Registers and Canonical_Cells
are unused remnants: the complete first-party source search finds only their
declarations, allocation-free owner binding in New_Frame and clearing in
Clear_Frame. No execution, collector, inspection, closing or foreign code
reads/writes their contents. Remove those two controlled vector fields and
their binding/clearing. Keep the actual context arenas, private packet backend,
frame lifetimes, callback/closing storage and allocation-refusal behavior.

On the measured GNAT 16.1 Windows build, Frame'Object_Size decreases from
1,304 to 1,232 bytes. The actual record reduction is 72 bytes; do not infer it
solely from two independently measured 32-byte vector headers. A retained
1,003-active-frame probe loses 72,432 raw bytes across its 1,006 allocated
frames, retains the same block count and finalizes to zero bytes. This is a
private diagnostic, not a public representation promise or acceptance receipt.

Fresh unchanged coroutine default/T native and Ada processes still complete
under the actual 2 GiB managed ceiling with zero ownership at shutdown. Ada
default peak falls to 1,896,476,423 bytes; T falls from 135,157,641 to
130,237,089. No refusal, source adaptation or reduced flag is involved. Keep
raw memory observations separate from C's implementation-dependent costs.
The macOS resident watchdog result must still be reproduced; a smaller Windows
managed peak alone does not resolve that platform gate.
