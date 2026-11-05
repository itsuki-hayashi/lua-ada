# ADR 0006: Shared Frontend and Canonical Opcode Definitions

Date: 2026-11-06, Asia/Tokyo. Status: accepted.

## Context

M1 combined token consumption, name resolution, and VM instruction emission.
Its batch lexer could report a later lexical failure before an earlier grammar
failure. Checking all Lua syntax must be independent of executable VM features.

## Decision

Use one owned incremental scanner and one parser/resolver. A compilation unit
owns indexed discriminated syntax nodes, declarations, resolved names/captures,
and label targets. Private indexed identifiers survive vector reallocation.
The public Lua.Syntax.Check API destroys temporary storage on return and exposes
only structured diagnostics. It creates no runtime session or globals.

The existing VM compiler is a lowering pass over resolved syntax. It retains
packet registers, environment cells, explicit frames, and tracing ownership.
Validate the complete chunk before rejecting goto/labels/close as unsupported.
Execution reports Unsupported_Feature for valid deferred syntax before effects.

Canonical Lua.Opcodes is private and independent of the VM's Operation type.
Explicit enum representations and shifts on unsigned 32-bit words describe
the pinned 85-opcode format without relying on host layout or endianness.
Numeric opcode parity does not imply code generation or execution parity.

## Alternatives and consequences

A second check-only grammar would drift from execution; compiling with emission
disabled would couple checking to runtime limits and representations. Both were
rejected. An owned syntax arena increases temporary memory and requires explicit
node/nesting limits. No syntax pointer or runtime object escapes the check API.

The baseline uses default LUA_COMPAT_GLOBAL=1. Numerals are classified and
validated lexically; unmatched bytes become parser input. C error wording,
register allocation, optimizer choices, instruction-size limits, and C-stack
exhaustion are not frontend compatibility promises. Configured Ada limits
produce resource errors separately from source rejection.

## Verification implications

Require token/payload/line and parse accept/reject/line comparisons with an
isolated pinned C oracle, focused AUnit cases, all-platform regression, and
opcode metadata/bit comparisons. Preserve upstream trees and consumer fixtures.
