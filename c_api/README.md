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

The [public value/auxiliary checkpoint](../docs/sessions/2026-11-08-public-value-auxiliary.md)
adds lua_len, lua_concat and lua_numbertocstring, plus 28 argument, option,
metatable, userdata, reference, registration and error/result helpers. All
value operations execute in Ada; the auxiliary C layer composes public calls
and handles native varargs. Scalar output uses the shared exact renderer and
parser with bounded fixed scratch, making no Lua allocator request. Seven
value cases (including 20,000 seeded binary64 spellings) and 76 auxiliary cases
match both separately built C configurations locally. Native-platform/shared
and whole-target gates remain open. Public buffer, file, traceback and further
core exports still require completion; see [ADR 0023](../docs/decisions/0023-public-value-auxiliary-operations.md).

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

External `lua_pushexternalstring` payloads preserve their original buffer even
at short/zero lengths. Their original allocator/userdata receives the exact
pointer and length-plus-one once, including header-refusal cleanup. Collection
queues existing headers without allocation; a guarded C portal runs release
callbacks after Ada steps return. Callback Lua reentry shares the actual driver,
roots, allocator and work budget. State teardown drains releases before deleting
globals/code. Ordinary short strings use a weak per-universe intern index;
external short keys normalize only when inserted as new table keys.
String `lua_topointer` identifies the actual header while `lua_tolstring`
borrows the original payload. See [ADR 0021](../docs/decisions/0021-external-string-ownership.md).
The focused external consumer passes eighteen cases against default C/Ada.
Its native T ownership-only mode passes thirteen and explicitly skips five
reentry cases rejected by the reference lock instrumentation; these skips are
not passing tests. Integrated Ada T and loader/unload/platform gates remain open.

The call portal accepts null continuations and real Lua/C message handlers.
Handlers run before failed frames and closing declarations unwind; recursive
handler errors reuse the same protected boundary. A non-yieldable call accepts
an unused continuation and returns synchronously to its original C body, as
pinned Lua does. Main/secondary-thread `lua_isyieldable` reports the actual
execution barrier. The expanded-T draft extends this portal with explicit
yieldable continuations, public resume windows and C hooks; its
[session record](../docs/sessions/2026-11-07-expanded-t-conformance.md) owns
actual verification and remaining failures. These additions are not accepted
full C API evidence. See [ADR 0017](../docs/decisions/0017-c-continuations-and-resume.md).
Reader-based `lua_load` and canonical `lua_dump` use real public callbacks.
The protected reader region preserves callback stack values between reads,
rejects yielding, returns the real error object, and restores the caller's
stack with one closure or error. Source buffers use the selected universe
allocator and are released on every callback/error/refusal path. Binary
reading stops at the decoded graph without an extra EOF read; documented
whole-buffer `B` inputs are copied into owned canonical storage. The Lua
library's `load` continues to reject `B`, as pinned C Lua does.
The shared scanner/parser and binary decoder now drive acquisition on actual
byte demand, including native current-byte prefetch before token delivery.
They consume one frontend pass, without gathering text to EOF first or
reconstructing binary prefixes. A C-owned refill checkpoint above suspended
Ada returns actual errors/yields as typed outcomes; explicit user API reentry
retains the same driver, roots, allocator and work budget. See
[ADR 0019](../docs/decisions/0019-demand-driven-input.md).

Dumping serializes the selected actual canonical subtree and preserves the
writer's stack between callbacks. It sends Lua 5.5's terminal NULL/zero call,
returns a nonzero writer status unchanged, and releases its owned snapshot
before propagating a writer error through the caller's C guard. The shared
reader/writer consumer has twenty-eight separately named cases;
`check-core-image.ps1` runs and compares that same source against both images.
The demand-driven checkpoint passes the full local Windows/default/static
consumer and 1,412 AUnit cases. Its standalone output matches the pinned native
default and instrumented C runs; integrated Ada instrumented and complete
platform acceptance remain separate final-delivery evidence.
The public C debug surface now describes real active frames or a popped
function through all `lua_getinfo` selectors, including source/name lifetimes,
parameter/upvalue metadata, tail/`__call` data, transfer ranges and active lines.
Inactive parameter names, active Lua/C locals, hidden varargs and captured
locals share real canonical registers/cells; public upvalue get/set/id/join
operate on the actual traced cells. Immutable graph names/source retain their
NUL-terminated bytes without query allocations; simple selectors remain usable
under provider refusal after stack reservation. `L` allocates its required
result table and has separately exercised refusal/recovery behavior.
`lua_gethook` returns an actual callable C dispatcher for Lua-installed hooks;
C can save, directly invoke and restore it while the weak registry remains the
callback owner. Hook transport stays hidden even after a hook replaces itself.
The Windows/default/static checkpoint passes 1,489 AUnit cases and eighteen
separately named C debug cases, with identical standalone output against pinned
native default and T configurations. See its dated
[session](../docs/sessions/2026-11-08-c-debug-identity.md) for exact checks and
remaining integration limits. Complete platform/configuration acceptance is
still required.

Known stateless Ada builtins now use strong scalar identities with actual C
trampolines; they allocate no closure/cache. C push/tocfunction roundtrips retain
their identity and callability, while captured library functions retain distinct
closures and real mutable cells. Direct C pointer calls share the current
driver, allocator, registry, budget and capture owner through a hidden phase and
a real C continuation, including yielding callbacks. Strict/lax UTF-8 iterators
retain distinct stateless function identities. See
[ADR 0020](../docs/decisions/0020-callable-builtin-identities.md).
The local default/static checkpoint passes 1,515 AUnit cases, fifteen native-
matched C builtin cases and the twenty-case C debug consumer. Return hooks read
real result slots, with append/reuse/trim protocols independently observed;
fifty-one native operation labels match first-transfer/count ranges. Complete
matrix/full-upstream evidence remains with the parent delivery, as recorded in
the dated [session](../docs/sessions/2026-11-08-callable-builtins.md).

Full auxiliaries, external strings and remaining exports are pending.
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
Each C guard echoes its callback's opaque activation address and request serial.
Completion checks both before changing state, so a nested guard or an earlier
use of a cached frame cannot acknowledge another pending callback. Four focused
driver cases cover valid completion, invalid addresses, invalid serials and real
frame-cache reuse; the strict validation/static checkpoint passes 1,042 AUnit
cases and retains all 35 C consumer cases.
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
Windows x64 C compilation uses unique function sections to preserve unwind
relocations through that partial link. The core-image driver checks final PE
exception ranges for overlap before executing consumers and shared callbacks;
it retains the actual exception tracebacks and protected-refusal tests.
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

`lua_setwarnf` and `lua_warning` now provide real custom callbacks, data pointers,
literal control messages and fragments. Delivery takes place in C after the Ada
dispatcher returns, including nested API use and protected callback errors.
Bare construction leaves the handler absent; auxiliary construction enables the
pinned default stderr handler. See [warning delivery](../docs/warnings.md) for
allocation-free event ownership and the 1,067 AUnit/39 C-case local checkpoint.

The later shared-window, registry and output checkpoint retains those cases and
adds actual initial free-stack capacity and failed-checkstack recovery. The
continuation checkpoint then passes 35 named C cases in the Windows
validation/static consumer (reports/m3-k-nonyieldable-consumer1.log), including
three separately oracle-checked cases for thread yieldability and the
non-yieldable callk/pcallk branch. Yieldable continuations and public C coroutine
resumption remain pending; these synchronous cases do not establish them.

The four-file follow-up shares three public IO/OS cases in `io_contract.h`
between the ordinary C consumer and `io_api_contract.c`. The latter is built
independently against Ada and the pinned C oracle by `check-core-image.ps1`.
It compares FILE pointer/closer layout, metatable identity after reopening io,
the os opener without global publication, and real native closure through the
public callback. Both runtimes must free all counted allocator storage at close
and produce identical output. This comparison does not expand the public API
boundary or establish complete C ABI coverage.
