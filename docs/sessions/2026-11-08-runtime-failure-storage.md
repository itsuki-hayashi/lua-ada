# Runtime failure-storage migration (2026-11-08)

Context.Failure_Text now uses the private selected-owner immutable diagnostic
component from ADR 0035. Existing Lua error values remain authoritative:
capturing their failure clears duplicate reporting text, and publication reuses
the same actual value. Pending diagnostics create a Lua string directly from a
borrowed managed view, then release the pending payload. Cross-context and
saved-state text copies share immutable storage without allocator growth.
Host reports explicitly materialize their final public Ada diagnostic result.
The public Ada session API and pinned public C layouts remain unchanged.

Compile_Source temporarily roots any saved Lua error in its actual loader
activation captures while compilation can replace context failure state and
collect. Normal restore checks the capture invariant and republishes the old
root before releasing that slot. Exceptional guard cleanup cannot replace a
host abort/refusal with a finalizer exception; an unexpected layout remains
owned by the departing frame's cleanup. No foreign jump crosses Ada frames.

Syntax and invalid-mode diagnostics use destination-owned builders, with
borrowed source text and explicit charges for input-sized passes. Mode and
chunk-name C prefixes are scanned and borrowed without ordinary String copies.
The new long-mode regression found that the former implementation accepted a
`t` after an embedded NUL; both recognition and rendering now stop at the same
C prefix. Lua-compatible dynamic compilation also ignores the instruction
quota check consistently while bounded execution retains its host abort.

Eight named AUnit cases exercise selected pending storage, original long-string
identity under permanent refusal, counted NUL bytes, allocation-free context
routing, atomic refusal/memory-error recovery, bounded copy work, compatible
load policy and long C-prefix mode errors. Existing representation-dependent
assertions now inspect the same actual error through Failure_Image; unchanged
behavior expectations and case identities remain. Obsolete unbounded-string
imports were removed to satisfy the existing warnings-as-errors policy.

Both local configurations pass all 2,300 AUnit cases. All final strict static
runtime/tests/C/CLI builds pass with GNAT 16.1.0, Alire 2.1.1 and the existing
Ada 2022 warning/style/runtime-check policies. All 26 ordinary standalone C
consumers pass in default and T, with the separate private T buffer consumer
also passing. Those full Ada runs retain release/warning reentry cases; native
private-lock modes are not labelled passing operations. Native-module images
and the full platform matrix were not rerun in this component checkpoint.

The six-case public Lua fixture checks long/NUL error pointer identity through
pcall, nested xpcall/load diagnostics and collection, table error identity,
closing-error replacement, coroutine failure/close, and long mode options.
Native/Ada default/T and all eight compiler/VM roles match output SHA256
f7318f75227b075d153bcb8e30c6a648c0f6633b1f7e2f5e32742e888a9caf89.
Raw mutable logs are in reports/diagnostic-text and have no final-head
acceptance authority.

A bounded supplied-source Haiku review ran no tools/tests. It identified the
preexisting non-Bounded load check and mode scanning/concatenation paths, which
were corrected and receive focused regressions. Its finalizer concern moved
the ownership assertion to normal restore while preserving exceptional cleanup.
A brief Root/child build overlap was identified; the affected checks were
repeated under explicit serial leases and only the non-overlapping verification
logs own the final component results. No checks or warning flags were disabled.

This closes the specific unbounded Context failure-text storage path, not the
whole allocation audit. Other input-sized legacy formatting/builders, C call
metadata and canonical return packets, registry-callback traceback naming,
linear reader integration, remaining upstream/T/helper/aggregate/heavy files,
all 26 final contexts and independent reconciliation remain required. The
implementation PR, automatic GitHub review and authorized merge are still
future gates.
