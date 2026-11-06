# ADR 0012: Owned Canonical Programs and Native Binary Chunks

Date: 2026-11-06, Asia/Tokyo. Status: implemented standalone; runtime migration
and cross-platform acceptance remain pending.

## Context

The canonical compiler and future binary loader need one representation of
Lua 5.5.1 prototypes independent of the private packet VM. Runtime heap objects
cannot own partially decoded input safely, and recursive ownership would make
cycles or interrupted construction difficult to destroy. The pinned dump
format includes native numeric sentinels, globally reused strings and absolute
array alignment; treating it as a portable record image would be incorrect.

## Decision

Private Lua.Prototypes owns a limited controlled Program. Its flat stable
registry owns every prototype exactly once; children borrow registry nodes.
Managed vectors and interned byte buffers use an explicit Lua.Storage owner.
String identity zero means null and remains distinct from an empty byte string.
Cleanup walks the registry rather than following potentially cyclic children.
The owner must outlive the program and every synchronous borrowed view.

Private Lua.Chunks imports and exports that model without Engine, sessions or
VM values. Decode returns typed format, resource or allocation failure and
releases partial graphs. Encode validates graph ownership and operand bounds
before emitting any output. Neither operation invokes the reference interpreter.
The model and codec use Lua.Opcodes words, explicit byte arithmetic and native
width checks, without native record-layout assumptions.

Private Lua.Canonical_Compiler consumes the same resolved frontend, borrowing
its byte arena synchronously and producing this owned model. Program.Move
transfers graph ownership without allocating/cloning; existing node IDs remain
stable while ownership tokens change to the destination. The runtime bridge
must respect the owner's lifetime and publish wrappers before allocation retry.

Pinned [ldump.c](https://github.com/lua/lua/blob/7579fc9d7ed90240487251dfb69168f8e64e9294/ldump.c)
and [lundump.c](https://github.com/lua/lua/blob/7579fc9d7ed90240487251dfb69168f8e64e9294/lundump.c)
own the format evidence. Imported chunks require matching native integer,
instruction and binary64 sentinels. Debug PC values refer to canonical words.
Strip removes source/debug payloads while retaining capture descriptors.

## Alternatives and consequences

Reusing packet prototypes would couple binary compatibility to an incompatible
instruction representation. Recursive ownership would complicate interruption
and malformed-graph cleanup. Unmanaged containers would bypass allocator
callbacks. The selected model adds a small independent ownership layer and
requires explicit lifetime ordering at its eventual runtime bridge.

## Verification

Named AUnit cases cover values, debug data, every truncated prefix, limits,
cyclic cleanup and moving allocator refusals. A separate codec executable
roundtrips C-produced native chunks and lets C load Ada-produced bytes.
The [codec guide](../binary-chunks.md) owns commands and evidence boundaries.
These checks establish standalone serialization behavior on the measured host,
not canonical Ada execution or an unchanged upstream binary-suite pass.
