# ADR 0043: Debug console through owned continuations

Status: implemented; complete upstream/context acceptance remains pending.

The pinned debug library exposes debug.debug to native modules and ordinary
Lua code. Its console reads native stdin, compiles commands in the global
environment, executes each under protection and reports errors to native
stderr. It cannot enter another executor from an active Ada frame or delegate
interpretation to C.

Use a private Engine.Debug_Console continuation driver. Read at most 249 bytes
per command, matching the pinned fgets buffer size. A counted read retains
embedded NUL bytes while compilation uses its C-string prefix. Recognize the
exact cont/newline command and EOF. Preserve native stdio state and write the
prompt directly to stderr, independently of replaceable Lua IO fields.

Lift the existing loader's Compile_Source implementation into the shared
Loaders.Compile_Chunk operation. The dynamic-loader wrapper and console use
the same compiler, diagnostics, allocation policy, budget and saved-error
ownership. Apart from its explicit State/Activation parameters, name and
indentation, that implementation is unchanged. No second parser is introduced.

The real console activation owns its compiled closure and error packets.
Commands dispatch through the existing Native_Action and scheduler. The same
activation becomes a protected holder with a reserved error packet; recovery
closes and unwinds the real failing frames before resuming it. Successful
command results are discarded. Error conversion invokes an actual __tostring
directly outside command protection; conversion errors escape the console.
All retained error/closure values stay in traced captures or results.

After every command, close actual C to-be-closed slots through the existing
foreign.close/unwind continuation before clearing the window and its copied
arguments. A saved builtin pointer has both a private working window and an
actual public caller/host prefix. Clear both, and publish the normalized cursor
in that one live direct-builtin call record, checked against its context,
universe and original base. Completion uses that explicitly published cursor;
other builtin calls retain their existing entry-base behavior. This prevents
return from resurrecting an old prefix. Immediate EOF keeps the untouched
original arguments, matching the pinned console's return-before-settop path.

Register debug.debug as an appended stable builtin identity with its actual
C trampoline, preserving existing builtin ordinals. Add its non-yieldable
charge through the central activation initializer, so entry and retirement
balance the same counter. Setting only Blocks_Yield inside the driver would
break that invariant; actual EOF/return probes rejected the initial draft,
which was corrected before delivery.

The process regression compares isolated C/Ada console runs, preserving raw
stdin/stdout/stderr. It covers command/environment semantics, conversion and
recovery, partial input, NUL, fixed-buffer boundaries and non-yieldability;
Windows additionally observes native CRLF and Ctrl-Z handling. Product CLI
observations have no measured allocator sidecar and supply no final
conformance authority. Allocation campaigns, public C consumers, existing
AUnit suites and immutable context reconciliation remain required.
