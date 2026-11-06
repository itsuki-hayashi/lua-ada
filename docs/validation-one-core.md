# Unified Ada/C Core Validation

Date: 2026-11-06, Asia/Tokyo. Scope: local Windows validation evidence for
[ADR 0014](decisions/0014-one-core-library.md). These checks use the production
root library, rather than the earlier reports-only observation prototype.

## Verified configurations

The selected GNAT 16.1.0 and GPRbuild 26.0.1 compiled the ordinary default
configuration with validation checks and all required strict compiler switches.

| Configuration               | C API consumer | Mixed Ada/C consumer | C-only startup |
| --------------------------- | -------------- | -------------------- | -------------- |
| Windows validation static   | pass           | pass                 | pass           |
| Windows validation shared   | pass           | pass                 | pass           |
| Other profiles and systems  | pending        | pending              | pending        |
| Instrumented upstream-test  | pending        | pending              | pending        |

Each C API consumer passed its eighteen named cases, including the measured
21-point cold constructor refusal sweep. The mixed consumer executes an Ada
session, constructs a separate real C state, reads its stack/main-thread through
the Ada dispatcher, writes a stack value from Ada, and observes that value in C.
Both interfaces return the same actual stored allocator callback. The actual
Storage.Pool symbol address matches its Ada object address, and GNAT's actual
package-elaboration counter is one before and after construction/closure.
The separate C-only executable repeats construction without an Ada main binder.

The pool/counter assertions intentionally depend on the selected GNAT symbol
convention. They are test-only observations of the actual production image;
the library contains no extra probe unit or fabricated observer counter.

The final static child-test build/run also passed **851/851 AUnit cases** with
zero failed assertions and zero unexpected errors. This includes the three new
host-arithmetic tests. Existing private child tests remain usable against the
standard standalone library through its explicit interface list.

## Commands and reports

```powershell
pwsh -File scripts/check-core-image.ps1 -Profile validation -LibraryType static
pwsh -File scripts/check-core-image.ps1 -Profile validation -LibraryType relocatable
alr -C tests build --validation --profiles=lua_ada=validation -- `
  -XLUA_ADA_LIBRARY_TYPE=static
alr -C tests exec -- bin/static/test_runner
alr exec -- gprbuild -P c_api/lua_c_api.gpr -XLUA_ADA_LIBRARY_TYPE=static
```

The passing logs are reports/m3-one-core-production-static-check3.log,
reports/m3-one-core-production-shared-check2.log,
reports/m3-one-core-aunit-build2.log, reports/m3-one-core-aunit.log, and
reports/m3-one-core-legacy-forwarding.log. Per-process output and structured
results live under reports/core-image. A timed-out, nonzero or stderr-producing
consumer fails the driver. The compatibility aggregate compiled no separate
C-facade core; its dependency is the root project alone.

The first strict consumer build needed the same separate Ada main declaration
as existing private-unit probes. Three newly added math-test registrations also
needed wrapping to meet 79 columns. The first shared mixed assertion compared a
host import-thunk address with an actual DLL callback address. The corrected
assertion compares the world's actual callback returned independently through
both interfaces. This is a test correction, not a runtime identity workaround.
All named passing logs are later runs after these failures were corrected.

## Remaining acceptance

scripts/check.ps1 now runs core-image consumers for its selected profile/kind,
and includes the separate binary CLI campaign. Their inclusion is an executable
workflow, not evidence that unrun jobs passed. The complete platform/profile/
linking matrix, upstream-test Ada configuration, static-PIC, dynamic native
modules, concurrent first entry, full C exports and full upstream suite remain
separate acceptance obligations. Ordinary Lua Ada and C consumers now share one
compiled core; that architectural property does not imply complete C ABI parity.
