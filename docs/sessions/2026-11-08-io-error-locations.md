# Actual IO error caller locations

Date: 2026-11-08, Asia/Tokyo. Component implementation; delivery continues.

A native-paired protected-call probe found that raising io.input/io.output
failures omitted the immediate Lua caller's source and line. An enclosing
command-line chunk could consequently appear in host reporting in place of
the loaded function. Direct pcall calls into the same C functions correctly
require bare error text, so adding the host chunk name unconditionally would
also be incompatible.

The existing private argument-error location formatter now supplies a shared
Append_Location operation. It reads the actual immediate public caller,
canonical source bytes and current instruction line, and uses the existing
bounded Short_Source rules. Public C callers and missing stripped line records
contribute no prefix. The new private Raise_Error builds its charged message
in selected-owned storage before publishing the ordinary managed failure.
Raising file-open failures use it after preserving errno; the failed prefile
remains closed. Returned io.open error tuples retain their original behavior.
There is no new public Ada embedding API or foreign transfer mechanism.

Seven separately named AUnit cases and an ordinary Lua fixture cover named
input/output callers, direct C callers, stripped code, embedded-NUL source
labels and the three-result nonraising file error. The distinct remaining-suite
reviewer inspected the production diff and witnesses and found no actionable
source defect. Both native configurations execute the public fixture unchanged.

All source-final default/instrumented runtime, test, C-consumer and CLI builds
pass with Alire2.1.1, GNAT16.1.0 and retained strict Ada2022 flags/checks.
The final default build was repeated after tightening the stripped-line branch;
the instrumented build already contains that final source. Both complete AUnit
runs pass2,528 cases. All26 default and27 instrumented ordinary C consumers
pass; the argument-taking native-module host campaign was not rerun here.
All eight public fixture producer/VM roles match stdout SHA256
d87f926e799de3fa701e4e4ff35361b8b2c9ef7417b1ca4363ba31e03c50f7d7,
with empty stderr. Raw logs are under reports/io-error-locations; the binary
crossing is binary-9f9c50800f6041bcbc5601393307c06b in that directory.

These are component working-tree observations. Whole-source/CLI acceptance,
native platform adaptations, immutable final images and the26-context matrix
remain required. The separately approved locals equivalent reaches a later
closing/refusal failure; this diagnostic correction neither adapts that test
nor supplies whole-file acceptance.
