# One Core Image Experiment

Date: 2026-11-06, Asia/Tokyo. Scope: **local Windows prototype evidence**.
This is a reports-only linking experiment, not production consolidation or a
C API/ABI acceptance claim. Production project changes need their own reviewed
decision, full consumers and Windows/Linux/macOS validation.

## Question and construction

Can one standard GNAT stand-alone library contain the actual Ada interpreter
and C facade, while both Ada sessions and C clients operate on that same core?

The disposable projects under reports/one-core compile the existing src and
c_api source trees once. They include the selected runtime configuration, public
Ada interface units and private implementation units needed by a child test
main. A mixed-language Interfaces list includes Ada specifications and C glue.
No reference interpreter source or library enters this target.

The experiment adds only observation glue: a private function returns the
actual Lua.Storage.Pool address, and an independent C counter records library
elaboration. The C startup symbol is renamed at compile time to match the
disposable library name. No production unit is edited for these observations.

The [GPR standalone-library guide](https://docs.adacore.com/gprbuild-docs/html/gprbuild_ug/gnat_project_manager.html#stand-alone-library-projects)
defines interface visibility and generated elaboration entry points. A standard
SAL owns its elaboration closure; implementation units outside its declared
interface cannot be imported directly. Including private units for this test
does not change Ada's package privacy rules. Encapsulated SALs and their separate
runtime-closure policy were not the selected experiment.

## Actual checks and results

GNAT 16.1.0 and GPRbuild 26.0.1 built shared and static variants with strict
first-party Ada flags and runtime checks. Both variants passed these consumers:

| Consumer | Observed result                                                                                                                                           |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ada + C  | Public Ada Session executes; Ada dispatcher recognizes the C-created state/thread; C sees Ada stack write; pool addresses match; elaboration count is one |
| C only   | Ordinary C main constructs, uses and closes a real state without calling Ada startup; elaboration count is one                                            |

The mixed client creates a C state with integer 37 and its actual main-thread
value. Ada reads the stack/thread pointer, pushes integer 42 through the real
Foreign.Dispatch, and C observes both the value and unchanged state identity.
It compares the actual pool object address across the language boundary.
The separate Ada Session has its own world, as required, within the same image.

Exact build commands were:

```powershell
alr exec -- gprbuild -P reports/one-core/consumer.gpr `
  -XONE_CORE_KIND=relocatable -p -j0
alr exec -- gprbuild -P reports/one-core/consumer.gpr `
  -XONE_CORE_KIND=static -p -j0
```

shared-build2.log and static-build2.log record the passing builds. The four
shared/static mixed/C process logs each exited zero and printed their expected
ONE CORE success marker. DLL inspection shows the shared client uses only the
one_core_lua core image; the static mixed executable imports OS DLLs and no
separate interpreter DLL. These artifacts remain ignored local reports.

## Measured integration details

MinGW's explicit C dllexport declarations disabled its ordinary automatic
export-all behavior. The first shared link therefore lacked real Ada interface
symbols, including controlled-type initialization. The prototype's explicit
Windows export-all linker option resolved this; a production symbol policy
still needs deliberate review.

Static archive Library_Options could not contain ordinary executable options
such as -lm in this configuration. Moving those options to the final consumer
linker, while retaining Ada's pragma-based library closure, allowed static
linking. The existing Windows BigObj partial-link handling was retained.

The shared processes also require the exact selected GNAT runtime DLL directory
on PATH. An initial run without it failed loader startup; this was not a passed
consumer. The corrected runs used the selected compiler's runtime directory.

## Consequences and remaining work

One mixed-source SAL is a verified local candidate for eliminating the current
separately compiled Ada/C cores. A thin facade importing a normal static core
does not itself prove one-image ownership when clients also link that core.
The production design must select library naming, exports, internal test
visibility, installation/runtime dependencies and native-module link behavior.
Static clients loading native modules need separate platform-specific evidence.

This experiment does not cover full public C exports, T, allocator exhaustion,
foreign unwinding/yield behavior, all native modules, another OS, or the final
M3 matrix. Existing C-boundary pilots and canonical execution tests retain their
separate scope and evidence.
