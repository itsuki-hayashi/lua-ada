# Actual return-hook result windows

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

The prior Ada artifact exposes real return cells to debug.setlocal but
delivers a copied pre-hook packet afterward. Native returns 37 after editing
return 11; Ada still returns 11. The same copies can keep replaced weak
values alive during callback collection.

The implementation keeps the physical source window until hook completion, reserves
reconstruction capacity first, and removes stale copied packet roots before
running the callback. The explicit continuation reads the edited transfer
range and adds internal protection prefixes once. Public pcall/xpcall status
cells remain part of their actual editable tuple. External-release deferral
preserves a complete packet without wrapping it twice. The private migration
backend retains its existing packet path.

Fifteen named Lua cases pass unchanged native default and T: scalar/tuple,
appended/reused builtin results, pcall success/error status, xpcall status,
weak Lua/builtin results, closer ordering, coroutine resumption, no-yield
boundary, error recovery, zero results, and vararg transfer range. The weak
Lua case clears every matching publicly exposed actual temporary first,
allowing different compiler reservations while isolating copied packet roots.
Two named public C cases also pass both native configurations: raw result-slot
mutation and weak result replacement during a custom C return hook.

All six centrally serialized strict root/tests/C builds pass for default and
T with Alire 2.1.1 and GNAT 16.1.0. Required warning, style, validation and
runtime checks remain enabled; the final logs contain no diagnostics. Both
local configurations pass all 2,202 AUnit cases on isolated base d547666,
including seventeen new named cases. This count is component evidence, not a
claim about later integrated source. All twenty-six ordinary standalone C
processes pass each configuration, plus the T private buffer caller. The
native-module host/import campaign was not rerun. Existing T external-string
ownership-only and reset without-warning-reentry variants remain explicit.

The source fixture and all four native/Ada producer/VM combinations match
raw stdout in both configurations, SHA256
B029A8E81185EECF75CE901130DE82A31CC11307AE2B92AD693594DE6584FD62.
Both native configurations also pass the two new C cases unchanged. The
native-T foreign consumer uses the earlier explicit allocator-reentry
omission; that omitted case is not passing counterpart evidence. Both Ada
foreign consumers include it. The prior Ada artifact fails the first Lua
mutation assertion, while the new artifacts pass the complete fixture.

A bounded no-tools Haiku diff audit reports no established defect (USD
0.00581935). Its conditional C-count concern is resolved by actual callback
completion storing the source offset/count before return processing. The
custom vector Clear retains capacity, Fail raises, complete-packet aliases
are existing in/in borrows, and native upvalues use their actual cells.
This local audit does not replace GitHub review.

An independent execution-only probe confirms another open obligation:
without hooks, a closer changing the departing parent's real result cell
from 11 to 37 yields 37 under both native configurations and 11 under Ada.
That pre-close result snapshot belongs to the subsequent Return_Exit cleanup
checkpoint. This component does not claim to fix it or full-target acceptance.
See [ADR 0034](../decisions/0034-borrowed-c-stack-views.md). No references,
fixture pins, source adaptations, or conformance-ledger entries change.

The five changed Markdown files pass UTF-8/LF, local links and table alignment;
git diff --check passes. The full documentation checker remains blocked by
this isolated checkout's uninitialized busted/busted-scm-1.rockspec fixture
link, rather than being reported as passing.
