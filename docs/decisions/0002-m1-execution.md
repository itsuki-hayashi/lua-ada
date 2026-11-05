# ADR 0002: Executable M1 and Initial Gates

Date: 2026-11-05. Status: accepted milestone; implementation in progress.

## Context and decision

The user expanded M1 from build infrastructure into a useful core Lua scripting
interpreter, selecting an Ada API plus batch CLI and a small base library.
The [milestone target](../milestones/m1.md) owns the exact scope and exclusions.

Use separate library, CLI, and test crates. The library kind scenario is
LUA_ADA_LIBRARY_TYPE (static default, static-pic, relocatable). Every crate
retains the required compiler flags and runtime checks; object/library paths
include profile and kind. AUnit stays test-only. ABI/reference experiments are
separate GPR closures and never link into production.

The lexer is an owned-result development API under Lua.Lexers, returning tokens
or structured syntax/resource diagnostics. It decodes string bytes and preserves
numeric spellings for a dedicated numeric parser. It does not execute code.
A private register format, resolving compiler, session API, and tracing GC
remain required by M1; no alternative execution backend has been adopted.

## ABI observations and limits

A C helper can establish a checkpoint above its Ada caller, catch a foreign
nonlocal jump entirely in C, and return a status through Ada normally. A probe
demonstrates nesting and restoration. Ada operations can likewise return status
before a C API wrapper raises an error. This is promising, not proof of complete
Lua error/yield compatibility. Do not fix the runtime representation until
ABI-001 evaluates integration, continuation behavior, and ownership consequences.

## Alternatives and consequences

Putting AUnit in production would leak a test dependency. Linking reference Lua
as a backend would violate project goals. Jumping across Ada frames would bypass
defined cleanup and is not an accepted error mechanism.

Cross-platform CI is required but its existence is not passing evidence.
Keep M1 active while parser/runtime/interfaces and platform acceptance are missing.
