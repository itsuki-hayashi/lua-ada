# Bounded Nextvar storage counterparts

Date: 2026-11-08, Asia/Tokyo. Test-only implementation checkpoint; full delivery
continues. The original reference files and all source decisions remain unchanged.

The [feature proposal](../../tests/conformance/targets/remaining-upstream-compatibility/nextvar-sort-table-geometry.author-proposal.md)
separates physical C table geometry and positive two/three-allocation counts
from values, construction, iteration and ownership. The new
[Lua companion](../../tests/lua/nextvar_storage_invariants.lua) exercises those
public operations and reuses the existing actual Ada storage checker from
[ADR 0016](../decisions/0016-gc-adapter-equivalents.md). No querytab facade,
private C capacities, hash-layout clone or production change is introduced.

The companion requires an explicit public or ada-storage mode. Both modes
check real table values, lengths, iteration counts and the ordinary
math.log/ceil/power inequalities. Ada-storage also requires the actual
T.ada_check_table_storage operation at every checkpoint; a missing inspector,
omitted/unknown mode or unknown selected case cannot silently pass. Native
public observations do not claim execution of Ada's inspector or C's private
geometry.

Eleven separately named workloads cover library entries, all 529 generated
constructor size pairs, open constructor results, growing dense/string-key
tables, reverse and sparse fills, both churn shapes, vararg values/cardinality,
and weak object-key/value collection followed by reuse of the same table. The
constructor workload retains source generation, load, a distinct warm call,
GC stop/restart, length, every array/hash value and the mp2 evaluation. Both
churn loops perform exactly 1,024 real fresh-key insert/delete cycles, verify
all surviving original bindings before/after and across real collections, and
never wait for a physical rehash. This counterpart does not replace or reduce
the original separate 100,000-cycle churn.

Four private AUnit cases arm an actual selected provider immediately before a
canonical NEWTABLE instruction. The provider records a real refused growth,
including emergency retries. The first refused instruction must be a real
constructor operation; compilation and unrelated setup failures cannot count.
Each case requires the canonical memory error, verifies the earlier rooted
table/marker and unpublished result binding, then restores the provider and
executes the same source through the normal execution boundary. Every dense
and hash value, length and marker alias is checked after retry. Physical
finalization must return all selected bytes/blocks. The four allowance points
are Ada fault locations, not a promised allocation count or a C cost model.

Seventeen new AUnit cases pass within both complete local 2,629/2,629 suites,
with zero failed assertions or unexpected errors. Two final serial nested
test builds pass with Alire 2.1.1/GNAT 16.1.0 and all required strict flags and
runtime checks. The first default compile rejected missing forward declarations
and an ineffective use-type clause in the new test body; these were corrected
without disabling diagnostics. Production sources match the already built
4c8fb6c static runtimes exactly, so no runtime, C consumer or CLI build was
needed. Existing adapter/checker sources are byte-identical.
All nine changed files pass UTF-8/LF/final-newline checks and the four changed
Markdown files have valid local links. The full documentation checker is
blocked by the uninitialized future Busted fixture link,
tests/modules/busted/busted-scm-1.rockspec; it is not reported passing.

The [source/evidence record](../../tests/conformance/targets/remaining-upstream-compatibility/nextvar-storage.author-observation.json)
owns exact source spans, image hashes, limits, complete output/return protocols,
raw build/execution records and measured inspection cost. All eight public
producer/VM roles (C/Ada in each configuration), direct Ada public observations
and the mandatory Ada-T inspector run complete with empty stderr and exactly
one result 29. Their 352 stdout bytes match SHA256
1bafc24bb4d6258b8fec396f67171bb14b6658c3bec292500f79903692915104.
The complete actual-inspector run takes 11.638 seconds, with peak managed
5,157,942 bytes, inside the real 900-second / 2-GiB process protocol. All 16
campaign processes have balanced PID/run/configuration-bound sidecars; Ada
shutdown completes without accounting fault. The default missing-inspector
process is a separately labeled successful negative, not omitted T coverage.
These are local envelope observations, not comparative performance benchmarks.

This implementation installs no equivalent, exclusion, source approval,
native applicability decision or whole-nextvar/sort acceptance. Exact mixed
source retention, current runtime/checker bindings, independent review and
full-source/final-context execution remain separate gates. In particular,
physical querytab diagnostics are not reported as passing, and successful
counterparts do not grant automatic authority to a future hash update.
