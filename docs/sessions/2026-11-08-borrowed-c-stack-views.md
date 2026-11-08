# Borrowed C stack views

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

The implementation separates actual C guard ownership from the real
borrowed scalar window. Custom C hooks consume their event/line transport
before borrowing interrupted Lua/native cells. Warning and external-release
callbacks use the live Lua range. Nested entries save/restore the physical
view independently of their continuation/error guard. Embedded leases and
existing capacities make acknowledgement cleanup allocation-free.

Nine named regressions exercise real local mutation, nested calls and hook
origin, protected and unprotected errors, yield boundaries, stale weak packet
roots, and external release with a Lua CI/concat operand mutation. Eight hook
cases pass unchanged against pinned native default and T. The external
allocator-reentry case passes native default but aborts the pinned USER_H
plock assertion in ldebug.c:166 under native T. That process is not passing
evidence; the explicit narrower oracle invocation omits only that case.

All six final serialized strict root/tests/C builds pass for default and T
with Alire 2.1.1 and GNAT 16.1.0. Runtime checks and all required Ada warning,
validation and style flags remain enabled. One initial compile detected a
still-needed Warnings Stacks import; restoring it resolved that failure.
Both local configurations pass all 2,103 AUnit cases, including nine new
separately named regressions. This is isolated checkpoint evidence on base
44bf623, rather than a claim about the parent's later integrated source.

The full foreign C consumer passes both Ada configurations with all nine
new cases. The native-default consumer has identical raw stdout SHA256
9D6714B7DAB59BA952DC46569C136A615A77598DF3E44002516E0371975011FC.
The explicit narrower native-T consumer also passes its eight new hook cases;
its allocator reentry omission is not a passing counterpart. Native C
compilation uses GCC 13.2.0, C99 and strict warnings. All twenty-six ordinary
standalone C processes pass each Ada configuration; the T private buffer
caller also passes. The existing T external-string ownership-only and reset
without-warning-reentry variants remain explicit. The native-module host/
import campaign was not rerun in this component.

A bounded read-only Haiku audit reached its eight-turn cap, then returned a
no-tools final report with no established bug (reported session cost
USD 0.04452711). Three uncertain leads were checked: C dispatch raises before
entering a hook on failed setup; retained packet capacity and intrusive root
barriers allocate nothing during restoration; a direct hook yield returns
through End_Hook_View before suspension. The native/Ada yield case protects
that last ordering. This local audit is not GitHub Codex review.

The independent return-hook result mutation witness remains open: native
debug.setlocal changes return 11 to 37; the prior Ada artifact returns 11.
No reference or conformance-ledger entry changes in this component.

See [ADR 0034](../decisions/0034-borrowed-c-stack-views.md) for ownership and
callback boundary invariants. Full upstream, aggregate and final platform
acceptance remain open; no source exclusion is installed by this component.

All six changed Markdown documents pass UTF-8/LF, local-link and aligned-table
checks. The full documentation checker stops at the uninitialized fixture
link tests/modules/busted/busted-scm-1.rockspec in this isolated checkout; it
is not reported as passing. git diff --check passes. Reference trees and
fixture pins are unchanged.
