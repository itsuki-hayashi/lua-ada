# Public API command driver and cross-context C calls

Date: 2026-11-08, Asia/Tokyo. Component checkpoint within the approved complete
remaining upstream delivery. Source base f043dbc; final target acceptance open.

## Actual baseline and implementation

The freshly rebuilt main upstream-test launcher at f043dbc had SHA256
967BB83E6434768E6DC589F0499FB14CD66323E451AC65421E50B0A3BDB1C555.
Its measured configuration had T enabled, maximum stack 68,000, maximum C calls
180, auxiliary buffer 23 and actual/expected extra space 8. This is an observed
SDK configuration, not a private USER_H extra-space claim. Unchanged api.lua
failed at line 33 on missing absindex; memerr.lua failed at line 28 on missing
checkpanic. An older T artifact reproduced those gaps too but was not counted
as current-head evidence.

The first-party public C driver implements 94 of the pinned runC's 98 nonempty
command names, up from 27. Every new ordinary operation calls the actual export;
there is no value/table/arithmetic implementation in the command interpreter.
The four remaining names are alloccount, loadfile, traceback and private
printstack. Ten public helpers now expose real references, capture cells,
addresses, double bytes, new-thread protected calls and external payload
ownership. Provenance and deliberate safety extensions belong in the owning
[source manifest](../../tests/c/conformance_adapter.sources.md).

Public C helpers now install as genuine light function values. The operation
and world address remain captures only for Ada inspection callbacks which need
them. This preserves testC's missing U1, registry U0 and actual C pointer
round-trip identity. U256 is an acceptable absent-upvalue query. Registry roots
keep the real status strings alive before refusal tests, as pinned regcodes does.

The new doonnewstack helper exposed a production gap: a protected call on a
different same-world context incorrectly borrowed a nonexistent C callback.
It now owns a real entry drive while scalar metadata preserves/restores the
outer driver, context, call records and native depth. A typed Abort_State names
the genuine saved C caller for a host stop on a context with no local guard.
The exact instruction-limit failure survives restoration, and pcall cannot catch
it. [ADR 0030](../decisions/0030-cross-context-c-entry.md) records this decision.

## Verification

Windows x86-64 Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.1 strict validation
builds pass for default/upstream-test static root and nested test crates.
Upstream-test C consumers also compile/relink against the new checked response
layout. Ada 2022 warning/style flags and runtime checks remain enabled. All
1,896 AUnit cases pass in each configuration, including 23 separately named
new cases. Twenty cover public command/helper behavior and safety; three prove
the shared host budget with a main C caller, a coroutine caller with no main
guard, and two nested entry switches. Each recovers in the same world and
finalizes with zero owned blocks. Before typed routing, the first budget case
aborted its host process with exit 3; that failure is retained in local logs.

Nineteen public Lua cases in tests/lua/public_api_commands.lua pass unchanged
against the original native T driver and the Ada T driver. An independently
compiled oracle-only module also links the identical first-party C driver
against the native T shared library and passes those same nineteen cases.
All three raw stdout streams have SHA256
B12F60B67E7A9DBDD79F16F6615A2964265E655E52459208751C9D0B05414FCE.
The module entry is experiments/conformance/c/public_api_driver_probe.c; compile
it with the public include directory, strict C99 flags, the selected reference
library and a shared-module export. No reference object enters the Ada library.

The same driver module on native default passes eighteen non-warning witnesses
in separate processes. The warning-store protocol requires native T's installed
test warning handler; default's ordinary warning handler does not implement it.
This is a scoped default probe, not a passing nineteen-case campaign. The Ada
default AUnit case installs the real first-party callback and checks its actual
fragments. The additional invalid-operand safety case is not a native oracle
because the pinned source does not reject overflowing ints or unknown comparison
options safely. Host quotas are Ada policy tests, not native matching claims.

The new reservation witness first requested 1,000,023 slots in both profiles.
After a failed raw check, native default can retain an overflow reserve large
enough for a later request of that same size, depending on live stack depth;
the combined first-party assertion therefore failed natively. The witness now
uses INT_MAX, which exceeds normal and overflow capacities and preserves its
actual purpose: nonthrowing false, auxiliary error message, and recovery. No
upstream source or previously accepted assertion was changed. Incidental native
overflow-reserve geometry is not certified by this corrected witness.

All twenty executed retained upstream-test C consumer processes pass after the
response change, including buffer, allocator, substitution, reset/close-yield,
debug, reader/writer, operators, values and bootstrap. External strings use the
existing ownership-only T counterpart; reset uses its existing explicit warning
lock skip. The native-module host/import campaign was not rerun in this checkout.
Local logs and compiled diagnostic probes are under reports/api-driver.
Changed records pass scoped LF/link/table checks. The full documentation checker
stops at the existing uninitialized busted fixture's missing rockspec in this
isolated checkout; that run is not passing. An overwide existing session-index
link label was shortened to fit its unchanged table column.

## Remaining work

Unchanged T api.lua now passes its ordinary initial API sections and reaches
line 415, where checkpanic is still missing. Memerr.lua still stops at line 28.
Implement the C-owned panic fixture, shared refusal-control command and remaining
public drivers, then investigate the actual next failures. Fresh Lua-created
coroutine function slots and full allocator parity remain open. Querystr,
stacklevel, trick and printstack require source-specific eligibility review;
this component grants no exclusion and edits no conformance obligation.
Integrated current-head matrices, complete unchanged target execution, source
review/ledger binding, automatic GitHub review and final merge remain pending.
