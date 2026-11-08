# Current global arg and selected CLI scripts

Date: 2026-11-08, Asia/Tokyo. Native/Ada diagnostic at author base 503549c;
selected artifact repository 5218e38. No runtime implementation or source
equivalent is included. The planned private child integration remains pending
Root review.

The [21 authored cases](../../tests/conformance/targets/remaining-upstream-compatibility/cli-dynamic-arg.author-cases.json)
and [shared selected script](../../tests/conformance/platform/cli-dynamic-arg.lua)
measure main.lua lines 274-277 without running or adapting that upstream file.
The [observation](../../tests/conformance/targets/remaining-upstream-compatibility/cli-dynamic-arg.author-observation.json)
binds source, six actual executable identities, two matching native DLLs and
raw process records. Every mode uses the same literal -e setup and script
bytes in its own directory, with explicit argv and a filename containing a
space. A different sentinel script would fail if arg[0] retargeted execution.
No shell, Lua source forwarding to the C interpreter, T omission or output
normalization supplies a result.

Pinned behavior
---------------

C lua.c lines 264-274 loads the selected file before pushargs. The latter at
lines 251-259 resolves the current global arg using lua_getglobal, requires
a table, calls luaL_len, checks result stack capacity and uses lua_rawgeti
for 1..n on that same retained table. Its n is fixed before raw reads. Changing
the global arg in a length callback does not replace the table already on the
C stack. Missing entries are actual nil values; table __index is bypassed.
The filename was selected from argv and is not reread from arg[0].

Lauxlib lines 923-931 defines luaL_len as lua_len followed by lua_tointegerx.
The native observations confirm an integral real and a numeric string length
are accepted, whereas fractional/table results fail with object length is not
an integer. A real length callback error and main-thread yield abort before
the selected script enters. Negative/huge count and C int narrowing edges are
not exercised or mechanically translated by this plan; safe positive count
and stack admission need a separate native-supported boundary decision.

Actual outcomes
---------------

Both separately frozen native configurations satisfy all 21 contracts,
including the six expected error exits. Each Ada conformance image and each
actual product CLI image satisfies3 and fails18. The three successes are
unchanged string argv and the two controls proving arg[0]/negative indices do
not retarget the already selected script. Current Ada enters the script even
for non-table arg and every failing length callback: each guard checker raises
SCRIPT INCORRECTLY ENTERED rather than the native pre-entry error. This is a
measured public CLI gap, not just a differently formatted error.

| Authored control                 | Native default/T   | Ada conformance default/T | Product default/T  |
| -------------------------------- | ------------------ | ------------------------- | ------------------ |
| unchanged-strings                | contract satisfied | contract satisfied        | contract satisfied |
| numeric-slot                     | contract satisfied | contract fails            | contract fails     |
| boolean-slot                     | contract satisfied | contract fails            | contract fails     |
| replace-table                    | contract satisfied | contract fails            | contract fails     |
| replace-empty                    | contract satisfied | contract fails            | contract fails     |
| mixed-object-identity            | contract satisfied | contract fails            | contract fails     |
| metalen-holes                    | contract satisfied | contract fails            | contract fails     |
| raw-indexing                     | contract satisfied | contract fails            | contract fails     |
| metalen-number-string            | contract satisfied | contract fails            | contract fails     |
| metalen-float-integer            | contract satisfied | contract fails            | contract fails     |
| metalen-mutates-values           | contract satisfied | contract fails            | contract fails     |
| metalen-replaces-global-gc       | contract satisfied | contract fails            | contract fails     |
| global-handler                   | contract satisfied | contract fails            | contract fails     |
| non-table-number                 | contract satisfied | contract fails            | contract fails     |
| non-table-nil                    | contract satisfied | contract fails            | contract fails     |
| metalen-fraction                 | contract satisfied | contract fails            | contract fails     |
| metalen-table-result             | contract satisfied | contract fails            | contract fails     |
| metalen-error                    | contract satisfied | contract fails            | contract fails     |
| metalen-yield                    | contract satisfied | contract fails            | contract fails     |
| arg-zero-does-not-retarget       | contract satisfied | contract satisfied        | contract satisfied |
| negative-index-does-not-retarget | contract satisfied | contract satisfied        | contract satisfied |

The 126 case processes plus six configuration/capability probes have separate
30-second deadlines and 1MiB per-stream capture caps. Native and Ada conformance
workloads use actual 2GiB selected allocator ceilings. All84 workload sidecars
match PID/run/configuration/limit, end with zero bytes and blocks, and Ada
reports completed shutdown without accounting faults. Both measured
instrumented configurations identify actual T adapters. The Lua bodies here
are ordinary public controls, not T-only driver coverage. Product CLI images
actually report Lua 5.5 and T=nil in both build variants; they have no selected
allocator measurement, so no product memory ceiling or sidecar cleanup claim
is made. Native configuration commands return before constructing a Lua state
and therefore have no fabricated shutdown sidecar. Ada probe sidecars are
preserved when present.

Raw evidence is under reports/cli-dynamic-arg/fb359eccf2b54daa937aee4fc76921f2
in the isolated remaining-c-api worktree. Native default executable/DLL hashes
are 098b0348.../6fd51198...; native T uses 5f6df96a.../90cd6bb9....
Measured Ada executable hashes aree4b3f54b.../a157f03e...; product hashes are
ff758dce.../b6d43685.... Full hashes, actual argv, selected fixture hash, setup
UTF-8 hash, raw stdout/stderr hashes and telemetry are retained in the JSON and
per-case records. No compile-command receipt is inferred from source/GPR hashes
or mutable selected paths. Frozen artifacts are checked before and after use.

The first two observer authoring attempts failed before starting Lua because
a line break omitted a Freeze target. Corrected captures are separate; those
failed directories remain diagnostic. An initial completed campaign produced
the same 21 outcomes; after renaming an automatic PowerShell variable to a
task-specific one, the final 132-process campaign was repeated. The final
observer bytes are the ones bound by the committed observation.

Pending narrow design
---------------------

The current failure is explained by Lua_CLI lines 776-784 passing the original
host Arguments_After to Sessions.Execute. Sessions lines 157-168 makes fresh
Lua strings from that host array. It does not query the current Lua table or
run its lookup/length handlers. Keep this documented SDK string-argument
contract unchanged; the CLI needs a private child entry for selected scripts.

A proposed Execute_Selected_Script operation belongs only to the existing
Lua.Sessions.CLI child, built by CLI/test projects. It should compile the chosen
source through the shared Compiler and create its actual loaded closure before
argument callbacks, use sequential
existing drivers and actual anonymous C primitive callbacks like the prompt
transport, and run the already compiled code with actual rooted Lua values.
No new Machine entry, new runtime SAL API, Lua bootstrap chunk, second compile
or C argument-copy loop is currently justified. The planned sequence is:

1. Initialize status and the shared work budget once. Compile the selected
   source first; preserve its actual initial environment and selected name.
   Carry the loaded callable in a traced Current.Arguments prefix.
2. An actual tiny C callback may call only lua_getglobal for arg. Ada validates
   the resulting table. Global environment lookup must retain its real handler
   and callback/error behavior.
3. A second tiny callback may return the original table plus luaL_len result.
   It carries the closure prefix too. The C code performs no argument
   iteration, fallback or policy. Ada keeps
   this same table and the fixed count rooted across reservation and copying.
4. Validate safe count/stack admission, transactionally reserve the selected
   owner arena, and charge the raw index/copy work. Append actual raw values
   without invoking table __index, preserving holes, trailing nil, object
   identity and edits performed by the length handler. Remove only private
   prefix metadata, without callbacks or early close semantics.
5. Dispatch using the existing driver and compiled callable; keep source,
   argument values and callbacks rooted through failures. Report the existing
   typed exit/host-abort outcomes and perform normal CLI cleanup. Do not call
   Sessions.Execute again, since it clears/rebuilds the actual argument root.

Source inspection supports existing sequential drives: Machine.Start_Borrowed
at 6367-6399 and Finish at 7433-7450 do not modify Entry_Code or reset Steps;
Collector at 594 shades Entry_Code. Begin_Operation deliberately ends previous
temporary-root epochs, so Operation_Programs pins alone cannot span a start.
Published Entry_Code and Current.Arguments must own all retained data, and
results must be taken before Finish clears the transfer packet. Reuse the
prompt child's established guard/ACK/error/exit cleanup rather than nest an
executor inside a callback.

There is an open initialization detail before selecting the callback shape.
New_Closure at Engine2039-2078 captures Global_Environment and clears
Entry_Code after the closure owns the code. Running Code after an argument
callback could capture a replacement registry-global environment too late.
Root agreed that the callable must be created before callbacks; additional
native controls should retain this ordering. Creating the
actual callable before lookup and carrying it as a prefix through both C
callbacks may preserve it without another context field. The final prefix
removal and Function_Value start still need an explicit no-GC-gap ownership
argument. A local Value is not a traced root. Exact C ancestry, compilation/load
failure before length, callback exit and actual refusal/recovery controls
remain required before implementation, alongside the unchanged21 controls.

Only Script_Index>0, including explicit stdin, should use this operation.
Implicit stdin via dofile has no pushargs step in C lua.c; initialization files,
snippets, REPL and --check retain their current rules. arg[0] never chooses a
new file. No production code was changed by this diagnostic or proposal.

Evidence validation
-------------------

[The evidence reader](../../scripts/test-cli-dynamic-arg-observation.ps1)
checks629 actual source/image/input/capture/record identities with 1978
integrity checks, including all 126 records and 84 sidecars, and recomputes
each classification from raw captures. It executes no new Lua process. Both
new PowerShell files parse and the session passes UTF-8/LF/link/table checks.
No Alire/GPR, AUnit build, runtime change, original main execution, adaptation
authority or final acceptance is supplied. These dated measurements remain
a failing baseline until an independently reviewed implementation and fresh
current-image replay demonstrate otherwise.
