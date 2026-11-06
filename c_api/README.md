# C ABI Implementation Checkpoint

This directory builds a real standalone Ada library named liblua and a plain C
consumer against the pinned public Lua 5.5.1 headers. It links no reference
interpreter object. This is an implementation checkpoint, not a complete public
C API/ABI or full upstream acceptance claim.

The installable headers under include/api are unchanged pinned copies with
per-file hashes and retained notices; production include paths do not enter
the reference-only tree.

The implemented surface covers seeded state construction, default construction,
closure, thread surfaces, allocator selection, stack movement/indexing,
primitive values/conversions, stable NUL-terminated byte strings, raw tables,
registry roots, light-userdata addresses, identity and exact extra-space prefix
access. The standard Ada universe descriptor and still-unmigrated container or
temporary allocations remain outside full callback-allocator coverage. Every
managed block passed to the callback is released at state closure. Input seed
is retained; seed-dependent hash behavior remains part of the canonical/storage
integration audit. Table capacity arguments are hints, pending capacity wiring.
Both constructors leave standard libraries closed, as C Lua does; Ada embedding
retains its separate eager default environment.

The public C callback execution portal, callable C closures, continuations,
load/dump, full auxiliaries, debug APIs, warnings and remaining exports are not
implemented by this checkpoint. Missing APIs are missing symbols, never stub
functions that report success. lua_ada_guard_probe is a separately named test
fixture for the C-owned error boundary; it does not stand in for lua_pcall.

## Ownership and errors

C sees a stable opaque surface whose prefix matches configured LUA_EXTRASPACE.
Its control block and surface block use the owning universe's storage provider.
Thread contexts own traced C stacks; registry entries refer to the actual globals
and main-thread objects. Context reclamation releases its two raw C blocks.
String pointers refer to real immutable byte storage and remain valid while the
Lua string is reachable. A null light-userdata address remains distinct from nil.

The C wrapper receives an action after the Ada dispatcher returns. It then
returns normally, raises through a live C guard, or invokes the C panic path.
No C longjmp crosses active internal Ada frames. Physical Ada failures remain
host aborts; callback allocation refusal is a semantic Lua memory failure.
Automatic initialization happens through the standalone-library binder and C
constructor entrypoints, including when a static archive is linked. The C
consumer never calls an Ada initialization function. Concurrent first-use
initialization remains an explicit production-boundary review obligation.

## Build and verification

Use the already selected Alire toolchain and serialize profile configuration:

```text
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=static
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=relocatable
```

Build paths are under ignored build/c-api. Select the root Alire profile first;
the project reuses its generated compiler configuration without editing it.
Static, shared and Windows static-PIC verification must be recorded separately.
macOS may require the selected GNAT runtime archive path through
LUA_ADA_ABI_RUNTIME_ARCHIVE, following the existing ABI probe convention.

The consumer has eleven independently named, commented behavior cases: allocator
lifetime, refusal/recovery, every cold construction growth refusal, a protected
live allocation failure, closed-library initialization, stack operations,
numeric conversion, stable binary
strings, raw table/pointer identity, thread/registry/extra-space movement, and
an actual exported-operation failure crossing only the C-owned guard. Builds
and results must be inspected before any target is called passing. Full callback
unwinding, allocator failure sweeps and instrumented ABI tests remain required
by the parent M3 acceptance contract.
