# CLI dynamic prompts

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

The original native/Ada main.lua campaign still stops on the shared Windows
temporary-output redirection. Separate unchanged native prompt probes establish
dynamic _PROMPT/_PROMPT2 lookup, nil defaults, auxiliary conversion, raw fatal
error behavior and one anonymous C caller. The former Ada fixed prompts differed.
The [transport decision](../decisions/0039-cli-prompt-transport.md) records the
private layout/allocation assessment and its retained failed diagnostics.

The CLI-only session child drives actual C public-API lookup/conversion callbacks
with the existing iterative foreign/warning/release pump. It roots results
through write/flush, respects host budgets and recovers after actual provider
refusal. The small C glue contains no interpreter logic. The runtime SAL/public
embedding API do not include the child. Only existing private failure/exit
declarations move into the Session private spec. A narrow borrowed-pump correction
preserves an already completed typed exit instead of replacing it with generic
host abort; the invalidated C caller is neither resumed nor acknowledged.

The first strict default run compiled after three local integration diagnostics
were corrected without relaxing flags. It passed 2,565/2,568 AUnit cases; exact
global temporary equality and both typed-exit controls failed. GDB then proved a
completed Process_Stopped exit was overwritten in the borrowed abort path. The
reviewed correction and actual-temporary contract passed all 2,568 AUnit cases in
both configurations before three additional error-display cases. Twenty-six new
named cases cover nil/custom/empty/numeric/
boolean/NUL prompts, replaced global tostring, numeric handler results, actual
Lua/C callback frames, error/yield handling, dynamic conversion, weak argument
retirement, bounded callback/output recovery, both exit flags and actual refusal.
Table and boolean Lua error objects use native raw-report fallback; a string
error with NUL displays only its C prefix. The original table identity and full
owned string remain intact. Separate native/Ada nil and numeric error probes
also match. No error object's __tostring is called by this host reporting step.

All source-final default/T runtime, C-consumer, CLI and nested test builds passed
strict Ada 2022 checks with Alire 2.1.1 and GNAT 16.1.0. Default full CLI execution
passed 109 cases before the three display additions. The original full T CLI run
found a separate existing -l helper
using reserved local name global; its failure is retained. The authorized local
rename to target preserves action order and argument/module behavior. Final
default/T CLI and test builds pass after that rename and the three display
additions. The first final default test build caught a nonexistent test-only
World.Globals selector; using the actual Global_Environment fixed it, and that
build was repeated with unchanged strict flags. Both final AUnit runs pass
2,571/2,571, both full product CLI suites pass 112/112, and both measured
conformance images pass all 19 prompt process controls plus two existing initial
capture checks. No runtime/consumer source changed after its strict builds.
All seven changed Markdown files pass UTF-8, LF and link checks. The complete
documentation check remains blocked by the uninitialized future Busted fixture
link, tests/modules/busted/busted-scm-1.rockspec; no fixture tree or pin changed.

Four named public getglobal cases extend the retained index/type consumer. They
cover the last guaranteed result slot, strict cached noncallback M0 success,
real handler arguments/stack prefix/temporary access, and provider-refused
metamethod safety with original marker identity and healthy retry. Both native
configurations and both Ada images pass all 34 cases plus balanced physical close.
The final authored metamethod control permits ERRMEM only after actual rejected
provider growth, canonical memory text and intact top/prefix/marker. It does not
claim private native/Ada scratch allocation counts match. All26 ordinary default
and27 instrumented C consumers pass with empty stderr; the argument-taking
native-module campaign was not rerun for this prompt checkpoint.

Native default passes all 19 focused prompt process controls. Instrumented native
passes the first17, then os.exit(37,false) reports a failed ltests.c:2226 atexit
zero-block assertion. Its final separate raw capture exits 37 with 122 stderr
bytes, so it fails the clean process protocol. The separate close=true control
exits 37 with empty stderr in both native
modes. Keep the failed instrumented no-close oracle evidence; no cleanup bypass
or invented main-return telemetry is accepted. Ada managed cases prove zero
selected blocks/bytes for both flags. Earlier failed native expectations for
allocation-free error unwind and exact C temporary spelling remain diagnostic
records, not passing tests or upstream source adaptations.

The [source/evidence record](../../tests/conformance/targets/remaining-upstream-compatibility/cli-prompts.author-observation.json)
binds actual source and artifact hashes without acceptance authority.
Raw build, process, native, AUnit and refusal/GDB evidence is retained under
reports/debug-metadata/prompt-*. The original main/native semantic observations
remain under main-original-8dc1ce1d728c446fa5f01c261847f335. Reference sources,
submodule pins, upstream assertions and source-review mappings are unchanged.
Whole main.lua completion, final immutable images, subprocess/interrupt gates,
source equivalence reviews and full-upstream acceptance remain required.
