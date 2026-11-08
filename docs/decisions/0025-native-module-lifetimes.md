# ADR 0025: Native module images and cleanup

- Date: 2026-11-08, Asia/Tokyo.
- Status: implemented locally; complete platform acceptance remains pending.
- Scope: package native searchers, loader handles and environment paths.

## Context

Native modules need the actual exported Lua surface and must use the same
runtime image as their caller. Linking the static interpreter archive into
each module creates independent runtime state. Module functions, finalizers,
external-string deallocators and selected allocation functions can remain
live until state disposal. An OS handle therefore cannot follow the lifetime
of the last Lua-visible module table alone.

## Decision

The Ada world owns an intrusive, provider-allocated cache keyed by the exact
C-string path. Construct its record and path before opening a library; publish
the acquired handle without allocation. Cache successful opens even when a
symbol lookup fails. Resolve foreign function addresses for the existing
iterative C portal; never invoke them from the loader's active Ada frames.
Retain handles through object, callback, stack and program disposal. Release
records and handles in reverse opening order. Hold the selected allocator's
code image across the final cache-record frees and the storage owner's final
raw-block cleanup. Its controlled lease precedes the owner in the world, so
reverse component finalization establishes that order even after physical
engine cleanup returns.

The C platform file performs only OS operations: open, symbol lookup, close,
borrowed diagnostics, pinned SDK default paths and executable-directory
lookup. Ada owns path expansion, environment selection, symbol-name policy
and storage. No interpreter logic or C-reference object enters this glue.

Both native searchers capture their package table. `require` captures the
searcher table for its search and preserves loader arguments and data. The
registry's real `LUA_NOENV` marker controls native environment paths. An idle
host operation lets the CLI apply `-E` before initialization without running
a Lua setup chunk. Bounded Ada sessions retain their local search defaults
and existing ambient-environment isolation.

Windows static executables export the implemented public C functions, so a
module import library can bind to the actual final executable basename.
Shared modules use the runtime DLL's import library. The fixture producer
must verify and record this linkage; an archive link is insufficient.
POSIX static launchers likewise export host symbols. The POSIX allocator-code
lease uses `RTLD_NOLOAD` to avoid loading a different file through a relative
reported image name. These build and
immutable-image checks remain separate from the runtime loader itself.

## Alternatives and consequences

Unloading on module-table collection would invalidate retained callbacks.
Never unloading would hide lifetime bugs and leak OS references. A global
process cache would mix separate owned sessions. The per-world cache avoids
these choices while retaining each acquired OS reference explicitly.

Exact source review and native platform observations remain necessary for
upstream assumptions about path spelling and module suffixes. Changing a
disposable test copy is not acceptance until its transformation is approved.
This decision grants no private-T exclusion and closes no global ledger.

## Verification implications

Verify default and instrumented native fixtures against static and shared
images, including inter-module symbols, errors, allocation refusal and
cleanup with retained external strings and finalizers. Reject modules linked
to another runtime, stale executable names or stale image receipts. Local
checkpoint results and remaining limits are recorded in the
[session](../sessions/2026-11-08-native-module-loading.md).
