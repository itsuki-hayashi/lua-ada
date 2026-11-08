# Original main.lua and CLI prompt diagnostics

Date: 2026-11-08, Asia/Tokyo. Local diagnostics at source snapshot 0f3c780.

The [author observation](../../tests/conformance/targets/remaining-upstream-compatibility/main-cli-native-platform.author-observation.json)
records native default/T baselines before Ada default/T execution of original
main.lua. Its source SHA-256 is
`844d13f96bdbf03a554b8b466fdf21aeac2bcddb907ad2b971814c994898d457`
at reference pin `7579fc9d7ed90240487251dfb69168f8e64e9294`. Each primary gets
a separate full original-byte test tree, immutable selected executable named
lua.exe, matching native DLL copy where applicable, 900-second timeout and
2,147,483,648-byte allocator ceiling. No port/soft flag or source adaptation is
used. The actual parent, bare-lua child and arg-selected child configuration
probes each pass with separate 30-second deadlines and balanced PID sidecars.
Closed-input -E/-W/-i preflights also succeed without stderr in every role.

All four original main.lua processes fail original RUN line67, from line81's
second version command redirected to out. cmd.exe reports Access is denied.
The native default/T processes take 69/41 ms; Ada takes 47/67 ms. Each has two
actual allocator records: its parent and the first successful version child.
Every record ends with zero selected outstanding bytes and blocks. Ada also
reports completed shutdown and no accounting fault. No timeout, capture limit,
pipe-drain or tree-kill failure occurs. All original fixture hashes remain
unchanged; no native-module block is reached or module fixture built for this
first-failure campaign.

Separate read-only line-hook diagnostics capture the actual prog/otherprog/out
locals immediately before original line81. All have a leading backslash and
no drive, such as native out `\s1t3k.2` and Ada out `\s1fvk.2`. Pinned C Lua and
the existing Ada platform bridge both use native Windows tmpnam. The shell's
drive-root redirection is denied on this host. This shared native failure
cannot justify changing only Ada's production os.tmpname semantics to conceal
it. The original final temporary-file cleanup is not reached. Instrumented
captures remain distinct from the four original primary processes.

Raw stdout is retained without normalization: the source prints each actual
role-specific progname path. No full-output equality or completed source is
claimed. The existing main completion proposal expects all.lua's dump/load
entry, a final zero-value result tuple, warning assertions, both real interrupt
blocks and final OK. These raw CLI runs stop before those phases; they neither
capture that result tuple nor establish any final protocol. Primary children
share the parent's 900-second deadline and tree cleanup policy. Individual
primary-child durations/deadlines are not measured here. Future protocol review
must reconcile actual child identities, statuses, warnings, pipes and cleanup.

Eighteen separate 30-second interactive probes inspect three public boundaries
from main.lua in both configurations and three image kinds: native C, actual
Ada conformance runner, and actual product CLI. They expose a concrete Ada
gap despite exit zero and empty stderr in all eighteen processes:

- Setting _PROMPT to alo yields native aloaloalo but Ada's fixed prompts.
- Empty _PROMPT/_PROMPT2 suppress native prompts around expression and
  continuation results; Ada still emits its fixed primary/continuation text.
- A table prompt's __tostring yields native XX, XXX and XXXX; Ada never calls
  it and emits fixed prompts.

The conformance runners instantiate the same Lua_CLI generic as the product
CLI and additionally provide actual selected allocator telemetry/T support.
All twelve measured C/Ada conformance prompt probes balance their selected
owners. The six ordinary product CLI probes confirm the public mismatch but
provide neither measured allocator ceilings nor cleanup sidecars. Product CLI
configuration has no T adapter and supplies no instrumented-body credit.
Prompt conversion/error/nil semantics need further native measurement before
the authorized bounded repair chooses its policy.

The committed observation binds all six executable identities. Native hashes
remain `098b0348...`/`2bb0d62f...`; current Ada conformance hashes are
`6d3627d6...`/`01058417...`; product CLI hashes are
`d5efeb7d...`/`6c0a279d...`, with complete SHA-256 values in the JSON. The
snapshots reside under
`reports/debug-metadata/main-original-8dc1ce1d728c446fa5f01c261847f335`.
Further probes use these frozen copies rather than mutable Root build paths.

A native Windows platform proposal remains a separate review task. The source
explicitly assumes a Unix-like shell and later uses echo quoting, env/env -i,
/dev/null, background PID capture, kill -INT and sleep. Any future equivalent
must preserve the corresponding CLI/package/environment/warning/finalization
operations, real matching Lua children, actual native modules, both interrupt
obligations and result/cleanup protocol. No exact Windows replacement, source
exclusion, adapted program or fabricated output is installed by these findings.

The initial report writer nested an already-returned empty change array.
Per-run metadata now has a flat empty list after rechecking every original
fixture; initial metadata and aggregation records remain retained separately.
The process/output/allocator captures were not changed. No production, reference,
selector, review or build input changes and no Alire/GPR command are included.
Main.lua remains failed in every original role; final acceptance stays open.

All 179 bound source/image/capture identities and six exact source regions
were rechecked. Diagnostic labels and process counts, the four changed
Markdown files' UTF-8/LF/links and git whitespace checks pass. No new full
documentation, build, AUnit or acceptance run is claimed by this record.
