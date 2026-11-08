# Debug console implementation and actual C calls (2026-11-08)

Implemented debug.debug through a private Ada continuation driver and the
existing dynamic compiler/protected scheduler. The extracted Compile_Chunk
body was checked byte-for-byte after deterministic indentation, name and
parameter adjustment against the previous nested implementation. Existing
builtin IDs remain unchanged; the new callable C trampoline is appended.
[ADR 0043](../decisions/0043-debug-console-continuations.md) owns the design.

Independent source review by validation_delivery identified two real issues
in the draft. Initial arguments remained rooted after a successful command;
the paired two-command weak-reference regression reproduced that failure.
Direct C calls also require real stack normalization and closing, rather
than clearing only private packet copies. The correction drives actual C
slots through the existing close continuation, clears working/public windows,
and publishes a context-bound per-call cursor before returning. A failing
closer escapes command protection and reaches the real outer C lua_pcall.

Validation on the combined local Windows validation/static source:

- Eight strict runtime/C-consumer/CLI/test builds pass in default and T modes.
  Both full AUnit runs pass 2,629 cases, including the newly integrated 17
  Nextvar counterparts. All 26 default and 27 T standalone C consumers pass;
  the argument-requiring native-module consumer is not included in that count.
- Both existing product CLI campaigns pass all 112 named operations.
- Sixteen paired console process cases pass in each mode: fourteen common
  cases plus Windows CRLF/Ctrl-Z controls. They include exact raw invalid-UTF8
  error bytes, initial-argument release, NUL, EOF, bounded read chunks,
  environment, errors/conversion, recovery and non-yieldability. Raw byte
  comparison replaces the initial draft's decoded/newline-normalized view.
- Four same-source public C consumer modes pass against separate native/Ada
  images in both configurations: direct host, host closing slot, callback
  closing slot and callback closer error. Frozen sources/headers, executable
  and library bytes, compiler, stdin and raw outputs are recorded. Console
  modes use luaL_newstate, including native T's actual required debug allocator;
  their unused custom counter is not reported as measured cleanup evidence.

Final component captures are console f2d058cc7512464aa2ae07156f9f751b/default
and 97bdfa034b85405f9ef1121269085790/T under reports/debug-console; C campaigns
are 25fb951433304f7c978be10231ea77ed/default and
f9c4ba8726f8426795c0ff7daceebd70/T under reports/debug-console-c. The standalone
C campaign is table-error-consumers-556ba54bec644540bf3fb0ad191b2436 under
reports/exact-equivalent-review. Earlier failing drafts remain raw diagnostics.

No reference source, source-exclusion policy or final certificate changed.
These observations do not complete main.lua, signals/readline, native
applicability or the immutable 26-context target. The next combined source
must refresh affected source bindings and rerun final observations.
