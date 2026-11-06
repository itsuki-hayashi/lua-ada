# C ABI Implementation Checkpoint

The root Lua_Ada project builds one real standalone library named liblua for
both Ada hosts and this directory's plain C consumers against the pinned public
Lua 5.5.1 headers. The legacy lua_c_api.gpr only forwards its build to that root;
it compiles no independent copy of the interpreter. It links no reference
interpreter object. This is an implementation checkpoint, not a complete public
C API/ABI or full upstream acceptance claim.

The installable headers under include/api are unchanged pinned copies with
per-file hashes and retained notices; production include paths do not enter
the reference-only tree.

The implemented surface covers seeded state construction, default construction,
closure, thread surfaces, allocator selection, stack movement/indexing,
primitive values/conversions, stable NUL-terminated byte strings, raw tables,
registry roots, light/full userdata addresses, identity and exact extra-space
prefix access. Real C functions/closures, fixed and multiple call results, protected
errors, nested C calls, and text/native-binary buffer loading now use the shared
iterative driver. Zero-upvalue C functions retain function-pointer identity;
other C closures retain actual mutable upvalue cells. The standard Ada universe
descriptor and still-unmigrated container or
temporary allocations remain outside full callback-allocator coverage. Every
managed block passed to the callback is released at state closure. Input seed
is retained; seed-dependent hash behavior remains part of the canonical/storage
integration audit. C table capacity arguments remain hints, pending wiring.
Both constructors leave standard libraries closed, as C Lua does; Ada embedding
retains its separate eager default environment.

The call portal accepts null continuations and real Lua/C message handlers.
Handlers run before failed frames and closing declarations unwind; recursive
handler errors reuse the same protected boundary. Non-null continuations return
explicit unsupported errors before execution.
Continuation/yield/resume support, reader-based loading,
dumping, full auxiliaries, debug APIs, warnings, builtin C trampolines and
remaining exports are pending. In particular, `lua_tocfunction` currently exposes
real foreign callbacks; Ada native-library functions need their own stable C
trampolines before complete `luaL_openlibs`/C-function inspection parity.
Missing APIs are missing symbols, never successful stubs. The separately named
lua_ada_guard_probe remains a bootstrap boundary fixture; real lua_pcall is
exercised independently by the consumer.

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
Each callback receives a base-relative stack window. A reentrant C API call
adds an explicit protected boundary to the same driver; it never invokes a
second executor recursively. Returned/error packets remain traced until the C
stack owns them. See [ADR 0013](../docs/decisions/0013-c-owned-call-boundary.md).
Protected holders reserve their two-value error packet before user code begins.
Failure delivery moves owned packets or borrows them for canonical scalar writes;
the C pump uses traced context storage until its stack owns the results. Permanent
refusal introduced inside a real callback is tested through protected return and
subsequent host recovery. Complete Lua memory-error parity still depends on
shared stack capacity and complete allocation-path verification. Context-owned
activation caching is implemented and tested separately.
Automatic initialization happens through the standalone-library binder and C
constructor entrypoints, including when a static archive is linked. The C
consumer never calls an Ada initialization function. Concurrent first-use
initialization remains an explicit production-boundary review obligation.

## Build and verification

Use the already selected Alire toolchain and serialize profile configuration:

```text
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=static
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=relocatable
pwsh -File scripts/check-core-image.ps1 -Profile validation -LibraryType static
pwsh -File scripts/check-core-image.ps1 -Profile validation -LibraryType relocatable
```

Consumer build paths are under ignored build/c-api. The sole library lives under
lib/PROFILE/KIND, with the existing upstream-test configuration subdirectory.
Select the root Alire profile first;
the project reuses its generated compiler configuration without editing it.
Static, shared and Windows static-PIC verification must be recorded separately.
The core-image driver discovers both selected GNAT archives on macOS:
LUA_ADA_TASKING_RUNTIME_ARCHIVE for libgnarl and LUA_ADA_ABI_RUNTIME_ARCHIVE for
libgnat. The C final link retains the required tasking-init symbol and orders
GNARL before GNAT; standalone C builds must provide the same runtime closure.
Windows x86-64 standalone-library partial links select BigObj for the merged
intermediate object because the full Ada closure exceeds ordinary COFF's section
limit. The final executable/DLL format and strict compiler checks stay enabled.
The [one-core decision](../docs/decisions/0014-one-core-library.md) explains
Windows shared exports and why static archive options contain no final-link
math option. Both C and Ada consumers import the root project.

The core-image campaign additionally runs a mixed Ada/C client and a C-only
startup client against the actual production library. They verify the same
C-created state and main thread through the Ada dispatcher, opposite-language
stack mutation, default allocator-function identity, actual Storage.Pool address
and one elaboration across repeated construction. Pool/counter symbol assertions
are explicitly GNAT-specific test observations, not public Lua interfaces.
scripts/check.ps1 runs this campaign for its requested profile/library kind;
other platform/configuration combinations require separate passing evidence.

The consumer has thirty independently named, commented behavior cases:
allocator lifetime, refusal/recovery, every cold construction growth refusal,
a protected live allocation failure, closed-library initialization, stack
operations, numeric conversion, stable binary strings, raw table/pointer identity,
thread/registry/extra-space movement, and
an actual exported-operation failure crossing only the C-owned guard, function
pointer identity, callback stack windows/result adjustment, mutable C upvalues,
protected table errors/recovery, nested C calls, canonical Lua calling C and the
text-only luaL_loadstring convenience entry, Lua/C handlers, recursive handler
errors, inherited-handler transport through a C guard, permanent callback
allocation refusal, panic recovery, reentry into another universe and four
userdata cases. Those cover actual C alignment/stable payload bytes, uservalue
result/pop rules, raw metatable identity/protection bypass and the last valid
uservalue slot. See [stable userdata](../docs/userdata.md) for traced ownership
and the still-pending finalizer/resource-lifecycle integration.
The Windows validation/static run passed all thirty cases and exited
normally in reports/m3-userdata-c-consumer1.log. Constructor refusal
sweeps all 25 measured growth points in that build. The earlier COFF link failure
and callback-phase fallthrough were repaired before that accepted run. This is
local checkpoint evidence; shared/platform/continuation/allocator-parity gates
remain required by the parent M3 acceptance contract.
