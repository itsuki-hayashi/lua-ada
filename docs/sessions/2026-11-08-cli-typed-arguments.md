# Selected CLI scripts use actual Lua arguments

Date: 2026-11-08, Asia/Tokyo. Component on 5ac08df plus separate lifecycle and
length-result checkpoints. [ADR 0042](../decisions/0042-cli-typed-arguments.md)
records the ownership and callback design; full upstream acceptance is open.

The CLI formerly rebuilt script varargs from host strings, ignoring changes to
global arg. Native default/T satisfied 21 frozen controls while four Ada images
satisfied only3. The existing
[dated diagnostic](2026-11-08-cli-dynamic-arg-diagnostics.md) and its raw captures
are preserved, with source bindings intentionally stale after later changes.

The CLI-only session child now compiles and creates the selected callable
before real getglobal/length callbacks. It preserves the initial environment,
actual object values, raw integer entries and nil holes. The full context
packet roots callable/table/all values until existing Function_Value Start
publishes the callee; a second owned arena supplies only script arguments.
Its scope ends before close=true can free the world. The public SDK string
argument API, implicit stdin, initialization, snippets, REPL and checker keep
their existing contracts. No Machine/Foreign change implements this feature.

Twenty-eight separately named AUnit cases execute the native-paired setup
bodies. They cover replacements/types/identities, raw indexing, holes/trailing
nil, numeric length conversion, callback errors/yield, GC/global replacement,
real anonymous C ancestry, compiled closure lifetime, syntax precedence,
typed close exit and two real T fault modes. Missing-file precedence is tested
at the actual CLI process layer. A separate four-case core correction removes
a cold length-result copy found by the unchanged M0 entry test.

All source-final six strict runtime/tests/CLI builds pass, with Ada 2022 warning,
style and runtime checks retained. One initial missing Integer_Value operator
visibility was fixed with a narrow use-type clause and all six builds repeated.
Initial AUnit runs were 2639/2640 because M0 exposed that core copy; after the
separately reviewed length fix, both full suites pass 2644/2644. Both C-consumer
projects relink cleanly, all 26 default/27 instrumented standalone contracts pass
without flags/with empty stderr, and both full product CLI suites pass 112/112.
The argument-driven native-module campaign was not rerun here.

The [fresh observation](../../tests/conformance/targets/remaining-upstream-compatibility/cli-typed-arguments.current.author-observation.json)
contains actual newly frozen campaigns, not updated hashes on old results:
all 21 argument controls satisfy native contracts in native default/T, Ada
conformance default/T and both product build variants. All40 selected lifecycle
processes satisfy their six ordinary plus two real-T contracts. Both native
configuration probes and actual Ada probes identify the correct adapter/ABI.
Product images identify no T adapter and provide no selected allocator measure.
Native typed exits bypass main-return telemetry and have no fabricated
sidecars or inferred balance. Measured normal-return workloads balance actual
PID/run/configuration/2GiB selected owners; no capture/deadline failure occurs.

Fresh raw roots are reports/cli-dynamic-arg/044f4b712a944d00a8f75a00123026bc and
reports/cli-arg-lifecycle/debb53436ab54329badc8234768da0a3. Combined build/AUnit,
CLI and 53 standalone C records are in
reports/cli-argument-build-2d4294d243404cc7b49ce7abcef1948c. The fresh packet
binds actual source and images; earlier dated packets remain unchanged and
must not be presented as current-source acceptance. No original main.lua run,
source equivalent, exclusion or final target authority is granted by this work.

A peer independently read the two critical handoffs: context roots persist
through Start/pin/new-frame publication, and local vector finalization precedes
Apply_Exit on normal, exceptional and early typed-exit paths. That source-only
check found no high-confidence issue; Root's independent code review remains
required. General CLI message handling, Windows source transport, readline,
signals/true-terminal evidence and the final immutable upstream matrix remain
separate obligations. The Root-owned debug console work is a separate component.
