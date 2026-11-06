# ADR 0014: One Library Image for Ada and C Hosts

Date: 2026-11-06. Status: accepted; platform acceptance remains separate.

## Context

The Ada library and the initial C-facade standalone library compiled independent
copies of the same interpreter units. That arrangement could give one process
two storage pools, elaboration closures and runtime identities when an Ada host
also called a C module. A C API that happens to work in a separate executable
does not prove that the module and Ada host share the same interpreter image.

The [isolated experiment](../validation-one-core-experiment.md) built the actual
interpreter and facade together and passed mixed Ada/C and C-only consumers in
Windows static and shared configurations. It also identified the required
Windows exports, BigObj partial link and final-consumer math-library linkage.

## Decision

The root Lua_Ada GPR project is the sole standard GNAT standalone library. Its
library name is lua, providing the usual liblua archive/shared-library naming;
the Alire crate and Ada project names remain lua_ada. Its source closure includes
the Ada core, isolated C facade and narrow platform helpers. Production builds
never include reference-interpreter source or a second compiled core project.

Ada sessions, the CLI, tests and C consumers import that same root project.
The former C-library project becomes an aggregate compatibility build entry
point that forwards to the root project. It owns no object or library directory.
The existing static, static-PIC and relocatable scenario values remain valid.

The standard SAL interface explicitly lists first-party Ada specifications and
its C translation units. The private specifications remain private under Ada
visibility rules; their inclusion permits existing child AUnit packages to
inspect real internals without compiling another copy. Adding an implementation
specification used by such a consumer requires maintaining this interface list.

The [GNAT project-manager guide](https://docs.adacore.com/gprbuild-docs/html/gprbuild_ug/gnat_project_manager.html#stand-alone-library-projects)
defines standalone interfaces and automatic initialization. The shared library
uses automatic binder initialization. The C constructor entrypoints also invoke
the same idempotent binder entry, ensuring a static C main pulls its initialization
closure from the archive. A C host never has to call an Ada initialization API.

On Windows, shared builds explicitly export their symbols because C dllexport
declarations prevent MinGW's implicit export-all policy from exposing the Ada
interface. The x86-64 partial link uses BigObj to accommodate the complete Ada
closure; the final executable or DLL retains its ordinary format. Static archive
options contain no -lm: Ada link pragmas and C consumers provide final-link
dependencies. This deliberately broad shared-symbol policy is an implementation
boundary, not a promise that private symbols are public stable APIs.

Darwin C clients need the selected compiler's complete runtime closure. The
root binder requires real tasking initialization, so C final links include
libgnarl before libgnat and retain that entry for shared-library flat lookup.
The [GPRbuild runtime-link construction](https://github.com/AdaCore/gprbuild/blob/master/src/gprlib.adb)
also orders tasking support before the core runtime. Toolchain paths are queried
at build time; no machine-specific archive path enters a project file. Failed
consumer captures are printed and uploaded so a loader error remains observable.

## Alternatives

Keeping two libraries retains duplicated ownership. Linking a thin facade SAL
to a normal static core can still embed that core twice when an Ada consumer
also links it. Either alternative needs extra ownership and linker contracts
without an advantage over a single mixed-source image for the current project.
An encapsulated SAL would change runtime-closure and platform support decisions;
it is unnecessary for the verified standard-SAL arrangement.

## Verification and consequences

The permanent core-image consumers link the actual production root library.
A C-created state is inspected and mutated by the real Ada dispatcher; C checks
the resulting stack, main-thread identity and default allocator-function identity.
The test also compares the actual Storage.Pool linker-symbol address with Ada's
object address and checks GNAT's actual package-elaboration counter remains one.
These last two assertions are explicitly GNAT-specific test observations. They
introduce no production probe function or test-modified interpreter library.
A separate C-only main repeats construction without explicit Ada startup calls;
GPRbuild may still supply generated binder glue for that executable.

Each build profile, library kind and operating system needs its own consumer
evidence. Local experiment results do not establish those matrix results.
Native-module loading, process-wide symbol resolution, concurrent first entry,
installation/runtime search paths and complete public C exports retain separate
acceptance obligations. This decision claims neither complete C ABI parity nor
successful execution of the full upstream suite.

## Windows partial-link unwind metadata

Adding another narrow C platform unit exposed a GNU x64 BigObj partial-link
defect. Its merged ordinary .pdata rows referenced the first .text/.xdata
section symbols with zero offsets, even though the later C functions occupied
different merged offsets. The final executable contained overlapping runtime
function ranges. An allocator-refusal test then faulted in RtlVirtualUnwind2
while GNAT recorded its exception traceback, before Ada recovery or GC ran.

Windows x64 first-party C compilation now uses -ffunction-sections. Unique
function section names preserve the relocation targets through the same BigObj
partial link. Ada already emits such function sections. The final PE format,
strict warnings, runtime checks and the binder's -Es exception tracebacks remain
enabled. No interpreter path, allocator policy or failure assertion is bypassed.

The core-image driver validates the final executable exception tables and the
shared lua DLL when applicable, using a small first-party PE reader. It checks
mapped bytes, complete table rows, sorted nonempty ranges and absence of
overlap. Eleven synthetic boundary cases exercise the reader on any host.
Actual C guard/refusal/error tests remain necessary: structural validity alone
cannot prove every unwind opcode describes its machine instructions correctly.
