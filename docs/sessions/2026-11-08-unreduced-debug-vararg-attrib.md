# Unreduced debug, vararg and package observations

Date: 2026-11-08, Asia/Tokyo. Local diagnostic observations only.

The [author observation](../../tests/conformance/targets/remaining-upstream-compatibility/unreduced-debug-vararg-attrib.author-observation.json)
records twelve complete original-file processes: db.lua, vararg.lua and
attrib.lua, each in separate native C and Ada processes in both default and
upstream-test configurations. Every process used a separate original-byte
full test-tree copy, a 900-second timeout and a 2,147,483,648-byte allocator
limit. No soft/port flags or adapted upstream sources were used. Original
fixture hashes remain unchanged after every process. Configuration probes
confirm the actual selected configuration, including the T adapter in the
upstream-test images. The pinned reference revision is
`7579fc9d7ed90240487251dfb69168f8e64e9294`.

Root released the immutable images after its strict builds and reported Ada
runtime source revision fce313c, plus three test-only string-index cases. This
work neither built those images nor treats its older local worktree images as
current. SHA-256 identifies the four executables used:

| Image                | Executable SHA-256                                                 |
| ---                  | ---                                                                |
| Native default       | `098b0348da5eb4ab581d0579d503662d383827e66ffb15d35f248a138b55d7fd` |
| Native upstream-test | `2bb0d62ff7ae53415bf4e8633cc31faf1d558e418dc8e965a4a48913f3e56eaa` |
| Ada default          | `e4b2ecd0958ded1221d2a5cff0c916e853d41fa88e5be389766e9732ee6d183b` |
| Ada upstream-test    | `188bc394d1150452ecfb6f444fd9c73e4f6eb584d96efd0ecdc2de1936825ba6` |

Both db.lua and vararg.lua complete with exit zero and empty stderr in all
four roles. Their terminal OK markers are present and stdout is identical
across roles. The db.lua source SHA-256 is
`82ed710f0aa5ab23eb86fc0ad73705e6d8f8b0cd9c8a3d1b4da31623c3e40f10`;
its stdout SHA-256 is
`61d58565c89cd99626c0a10641e6e8a14303a560258ef302fc6b9915e7724897`.
The vararg.lua source SHA-256 is
`46405b18946c40a9c092cc63216df9a3944562ce222acfd5e63ae78f19f356be`;
its stdout SHA-256 is
`b9c8e5332926fab75c3325c589f99aae07d27314573fe55bdc8a83a449d84e06`.
Native/Ada default durations are 40/758 ms for db.lua and 13/28 ms for
vararg.lua. Upstream-test durations are 39/542 ms and 10/29 ms respectively.
These short local durations are observations, not benchmark claims.

The original internal db.lua coroutine yield/resume and parameter/result
inspection assertions execute before its terminal marker. The original vararg
value, nil/cardinality and final named-vararg no-allocation assertions likewise
execute before its marker. Both main chunks end with an implicit zero-value
return. These runs use direct file CLI entry and do not capture that returned
tuple separately or exercise all.lua's dump/load entry. The existing file
completion wrapper/proposal remains pending independent review and was not
executed here. Empty stderr observes no warnings in these eight successful
processes; it does not establish the aggregate warning protocol. No completion
protocol, original source parent or conformance ledger entry is accepted here.

Original attrib.lua, source SHA-256
`dd2eb13be29628ac0268cddfafdc6a816edcba6552ae15e8637afc6a79742e52`,
fails at original line154 in all four roles, from the call at line169. Stdout
matches across all roles, SHA-256
`40cfec709b65c6224a5322dbb3421d58e61c6641a3c9a60717f467263c779d7a`.
Separate instrumented diagnostic processes leave the file bytes unchanged and
install a command-line line hook only to read the actual local values before
the assertion. All four report expected ext bytes `libs/B.lua` and actual x
bytes `libs\B.lua`. The shared native Windows failure is an expected-path
literal mismatch, not an observed Ada-specific difference. The original final
OK marker and one-integer-27 return are never reached and remain mandatory.

The existing validation-authored
[Windows equivalent proposal](../../tests/conformance/targets/remaining-upstream-compatibility/attrib-windows-equivalence.author-proposal.json)
already proposes ten exact expected-path literal changes using the original D
helper. Its intentionally mixed subpackage template retains the literal slash
after the platform-dependent prefix. The D/DC/try helpers, all original package
operations, native module openers, T checks and assertions remain required.
That proposal is pending independent exact review. This checkpoint emits and
executes no adapted attrib.lua and grants no approval to the proposal.

The existing standalone
[Windows package-path counterpart](../../tests/conformance/platform/windows-package-paths.lua),
SHA-256 `d3700e1babb78724741101d2a2ce66a0add4525455ff40d6bc9047d5fd0337f4`,
passes all ten separately reported operations in all four images. Stdout is
identical, SHA-256
`4d3af7f25039b2b9fd7dae65e6ea5a33caf1f5f3ec4e9b5e861bd19751a3f5cc`,
and stderr is empty. It checks exact require/searchpath loader data, cached and
false-result reload behavior, the mixed-separator template, and actual C-module
opener arguments for lib2-v2 and lib1.sub. This is a public counterpart
observation, not execution or coverage of the remaining attrib.lua body.

For each attrib role, the existing builder compiled all five original C
fixture sources with native GNAT 16.1.0's gcc, then audited PE imports against
the actual selected host executable or native DLL. The Ada modules import the
actual static conformance-runner executable; no reference C interpreter is
linked into Ada. Separate linkage records bind the owner image, compiler,
sources and resulting modules. Original attrib stops before executing them;
the standalone counterpart executes its two named modules. The fixture tree
remains disposable and original reference bytes and pins remain unchanged.

All twelve original processes and four counterpart processes end with zero
selected outstanding bytes and blocks. Ada additionally reports completed
shutdown and no accounting fault. No process timed out, exceeded the capture
limit or failed pipe draining. Native telemetry does not expose Ada's shutdown
or accounting-fault fields, so those fields are not inferred for C. The
instrumented path-value diagnostics are retained separately from the original
primary runs and carry no primary-execution authority.

Raw process JSON, stdout/stderr, selected allocator sidecars, configuration
probes and same-image module linkage records remain in
`reports/debug-metadata/unreduced-fce-08cc76c936aa4802b23dd8d1b9be9444`.
The committed observation binds those artifacts and source/proposal identities.
No Alire/GPR command, production change, source exclusion, adapted-source
execution or final-context acceptance is part of this checkpoint. Root then
reserved these image paths for a rebuild; no further execution used them.

All 78 bound artifact hashes and the recorded process/fixture/cleanup fields
were rechecked before committing this record. The four changed Markdown files
pass the repository checker's UTF-8/LF, links and aligned-table rules. The full
documentation check stops at an existing unavailable future module fixture,
tests/modules/busted/busted-scm-1.rockspec; it is not recorded as passing and no
fixture dependency or pin was changed to complete this diagnostic record.
