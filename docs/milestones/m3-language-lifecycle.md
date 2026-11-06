# M3 Language Lifecycle Delivery

Approved: 2026-11-06. Branch: codex/m3-language-lifecycle.
Baseline: merged PR #6, master bbc6e230cc1fcf4d20eb3caf02077b6bb0c0f46a.
Status: all six checkpoints have completed runtime acceptance. Final publication
checks are linked from PR #7; the broader M3 milestone remains incomplete.

## Scope and checkpoints

One major PR implements goto/labels, closing, the complete Lua-facing coroutine
library, weak/ephemeron collection, the documented debug subset, collection
controls and compatible CLI execution policy. [ADR 0009](../decisions/0009-language-lifecycle.md)
owns the runtime decisions. Stable implementation tasks are M3-LC-01 through
M3-LC-06, sequentially dependent within this one delivery:

1. M3-LC-01: typed context/transfer lifecycle, iterative scheduling, protected
   boundaries and execution-wide budgets; evidence: focused resume/error cases.
2. M3-LC-02: stable binding cells, jump frontiers and scope cleanup; evidence:
   capture identity cases and unchanged goto.lua.
3. M3-LC-03: closing continuations and all coroutine exports; evidence: every
   scope exit, callback restriction, explicit/self close, replacement errors.
4. M3-LC-04: reachability-owned threads and weak ephemerons; evidence: abandoned
   cycles, surviving captures, mutable weakness and fixed-point regressions.
5. M3-LC-05: debug metadata/hooks, collection controls and execution policy;
   evidence: local/upvalue/frame cases, native boundaries, quota/reset/CLI cases.
6. M3-LC-06: deterministic campaigns, both unchanged new files, retained M2b
   targets, all final platform jobs and one open PR. Missing evidence stays open.

These advance selected portions of M3-02, M3-06, M3-07, M3-08 and M3-11. They do
not complete the original gates. Canonical code execution, allocator callbacks,
public C ABI, binary chunks, userdata, finalizers, native modules and ecosystem
fixtures remain deferred. No dummy io/os/T library is provided.

## Acceptance configuration

scripts/check-lifecycle.ps1 copies goto.lua and coroutine.lua unchanged into
fresh disposable directories and checks SHA-256 after copying. Each file gets
independent C and Ada processes with matching working directory and local Lua
package path. T is absent; no _soft, _port, _U or _nomsg flags are set, and all.lua
is not invoked. Success requires zero exit status, empty stderr, identical raw
same-host stdout and the final OK marker.

The new files use the normal compatible CLI, a 900-second timeout, and an explicit
2 GiB sampled resident-process watchdog. WorkingSet64 is sampled every 50 ms;
it measures process resident memory, not the C oracle's managed Lua allocation
accounting or an exact peak. Crashes, timeouts, watchdog failures and resource
aborts fail acceptance. The three M2b primary files retain their separate bounded
1,000,000-instruction profile and 120-second timeout; bwcoercion.lua is a helper.

Every Windows/Linux/macOS × development/validation/release × static/shared job
runs AUnit, public API/CLI consumers and both new files. Existing ABI, frontend,
opcode, layout, library campaigns and Windows validation/static-PIC remain.
The lifecycle differential campaign additionally exercises generated scope exits,
close/error combinations, nested coroutines and collection, with recorded seed
and source/evidence retained on mismatch.

## T-absent coroutine omissions

Pinned source: Lua commit 7579fc9d7ed90240487251dfb69168f8e64e9294,
references/lua/testes/coroutine.lua. The exact two upstream omission messages are
required and every other skip message fails the runner. These source anchors
inventory the guarded omissions, rather than treating them as executed coverage:

- Line 591, if not T / else, through line 822: C hooks and coroutine API block.
  Lines 595–626 test alternating count-hook yields and traceback during C hooks.
  Lines 629–648 test hook yields with multiple results and perturbed stacks.
  Lines 651–669 test line-hook yields and exact reported lines.
  Lines 671–687 test count-hook yield cadence and results.
  Lines 689–711 inspect/mutate locals and varargs in a hook-suspended thread.
  Lines 714–724 inspect the last native frame of a suspended coroutine.
  Lines 727–750 test reuse, stacks, transfer and protected native API programs.
  Lines 752–777 test resume/result stacks through T.testC bodies.
  Lines 780–820 test independent C states, main-thread yieldability, library
  installation, cross-state execution and context/stack restoration.
- Line 1054, if T==nil, returns at line 1056: all later native continuation tests
  are omitted. Lines 1061–1107 test pcallk error/yield continuations and context
  values. Lines 1110–1121 test yielding C bodies and upvalue continuations.
  Lines 1123–1144 test a C toclose slot spanning pcallk and cleanup.
  Lines 1146–1161 test native-body resume/status/value movement.
  Lines 1164–1191 test chains of suspendable C callk functions.
  Lines 1194 onward test successive yieldk/pcallk continuations and errors.

Report coroutine.lua as default-configuration execution with documented upstream
omissions. It establishes neither complete coroutine nor C-API conformance.

## Evidence and completion

The [session record](../sessions/2026-11-06-m3-language-lifecycle.md) owns exact
local commands and intermediate observations.
[The validation record](../validation-m3-lifecycle.md) records runtime revision
830e0a1a2bad905ef34da3d553b24f8260ef35ff, 587 passing AUnit cases (99 new),
all five selected files, all 18 inspected jobs and Windows static-PIC.
[PR #7](https://github.com/itsuki-hayashi/lua-ada/pull/7) owns the final
publication-head checks; it is not ready until they pass. The broader
[M3 conformance ledger](../../tests/conformance/README.md) remains authoritative
for pending full-suite assertions and separately reviewed C/internal equivalents.
