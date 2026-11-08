# Intern-index refusal and collection witnesses

Date: 2026-11-08, Asia/Tokyo. Component observations; delivery continues.

Three separately named AUnit cases exercise actual selected-provider ownership
behind the independently reviewed private string-table feature. They do not
implement querystr, adapt api.lua, install exclusions or resolve original source
anchors. Production behavior is unchanged by this checkpoint. The distinct
remaining-suite reviewer inspected epoch roots, refusal ordering, real heap
membership and cleanup and found no actionable source defect. That review
supplies no exact source-equivalent approval.

The live-root case creates a thousand dynamic discarded short strings and a
retained table containing an embedded-zero string key/value. A real provider
refuses all growth during full collection. The key keeps its actual identity,
the value keeps every byte, and the index remains valid without a growth
request. The dead-header case records a thousand actual heap slots, retires
their operation roots, collects with growth disabled, verifies each slot is
empty and the remaining index is valid, then recreates a retired string.

The replacement case fills the actual current intern bucket capacity with
operation-rooted strings. The next string requests real replacement storage;
the selected provider refuses it, including emergency retry. The test checks
unchanged capacity/population, valid old chains and every retained identity.
Restoring the provider permits actual index growth and string creation.
The shared inspector establishes heap membership before dereferencing chain
pointers, checks header kinds and bucket ownership, bounds cycle walks and
reconciles the real population count. Each fixture checks both raw-provider
bytes and managed blocks are zero after finalization.

All eight serialized default/instrumented runtime, test, C-consumer and CLI
builds pass with Alire 2.1.1, GNAT 16.1.0, Ada 2022 and the retained strict flags
and runtime checks. An initial unused-use warning in the new test unit was
removed; warnings were not suppressed. Both combined configurations pass all
2,510 AUnit cases. All 26 default and 27 instrumented ordinary C consumers pass.
The argument-taking native-module host campaign was not rerun here.

Both actual configured fixture campaigns pass, including the complete real-T
21-case metadata fixture and the Ada-only table-storage inspector. Their
negative observation campaigns pass 25 default and 46 instrumented cases;
the existing source-only exclusion verifier passes 45 cases. Immutable image
membership replay was explicitly not run because these are combined working
tree observations. It remains required with fresh final-head reports.

Raw build logs are under reports/intern-index-faults/
build-2b30275be94a4612b2a3390b167cfb02; AUnit, C-consumer and configured logs
share that parent report directory. Configured observations are under
reports/core-image/configured-eee171b4f47044de859f626fabe41c77 and
reports/core-image/configured-2b07de0d8d654396979199bdc910af0c.
These observations do not establish the original generated child workload,
matching native refused-shrink execution, whole-file or final matrix acceptance.
