# C/Ada ABI Feasibility Experiments

These isolated fixtures link pinned **C Lua**, never the production Ada runtime.
They establish reference behavior and a limited Ada callback boundary. Build
output stays under ignored `build/`; reference submodules are not modified.

From the repository root, after `alr build` has generated configuration:

```text
alr exec -- gprbuild -P experiments/abi/abi_probe.gpr
alr exec -- build/abi/bin/abi_probe
```

On Windows the executable ends in `.exe`. The C-only main explicitly invokes
the standalone Ada library's generated initialization/finalization procedures.
The probe checks a null C callback, C-to-Ada-to-C status return, `va_list`
formatting, failed state creation, protected allocation failure, extra-space
access, protected Lua errors after Ada returns, state reuse, and allocator
balance after close. A second prototype calls a guarded C helper while Ada is
active below it: the helper catches a foreign nonlocal jump entirely within C
and returns status through Ada normally. Nested C/Ada/C reentry restores the
outer guard. It prints public size/layout facts for the host ABI.

## What this does not prove

Returning a status from Ada before C raises an error, and guarding every foreign
callback in C below its caller's Ada frames, are promising boundary mechanisms.
The guarded prototype uses its own test error function, not Lua's exported
`lua_error`. Integrating the mechanism into all Lua API error paths and yields
is **unresolved**. This experiment does not establish arbitrary ABI compatibility,
continuations, full allocator compatibility, stable Ada heap addresses, or a
drop-in library. No general unwinding mechanism has been approved.

Before fixing heap/frame representation, extend ABI-001 with reentry/yield
experiments and a reviewed mechanism that preserves Ada resource cleanup. Do
not infer that wrapping a call in a C function makes longjmp across Ada safe.
