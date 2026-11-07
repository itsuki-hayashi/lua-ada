# Concatenation operation checkpoint

Date: 2026-11-08, Asia/Tokyo. Scope: actual concatenation operand evaluation,
source attribution and diagnostic identities. This remains a component of
the approved remaining-upstream delivery.

## Implementation and source evidence

The canonical compiler now captures each left operand into its next real
register before evaluating the right operand. It merges the right-associated
concatenation spine into one contiguous CONCAT run, preserving the innermost
CONCAT source line. A parenthesized left concatenation still finishes first.
The walk is iterative, uses the existing register bound, and publishes the
completed result only after the run. It never reuses an active destination
binding while an RHS callback can still inspect it.

This follows pinned `lcode.c:luaK_infix`, `codeconcat` and `luaK_posfix`.
The former lowering copied operands backwards into the final destination
before CONCAT. Besides fragmenting right folds, those real MOVE instructions
prevented `ldebug.c:basicgetobjname` from recovering their original names.
An Ada-produced chunk on the actual C VM reproduced the missing local name;
the repair changes emitted evaluation rather than inventing debug identities.

Failed concatenation now selects the actual nonconvertible operand and uses
its reaching definition from the currently failing fold. Source belongs to
the immediate Lua caller; a C caller receives no older Lua location. The
borrowed resolver allocates no query cache. Diagnostic string `__name` ends
at its first NUL, matching `luaT_objtypename`'s C string use, while underlying
Lua strings and primitive `type()` results keep their existing meaning.

## Local verification

Strict root, nested test and C consumer builds pass with GNAT 16.1.0 and the
retained Ada 2022 warning/style/runtime-check flags. All 1,766 AUnit cases
pass, including twenty separately named new cases. Both native default and
instrumented C pass the unchanged first-party Lua witnesses.

Two twenty-case fixtures pass all four default compiler/runtime combinations.
The direct-code companion is deliberate: its producer compiles the operation
itself, rather than leaving nested `load` to the runtime compiler. Cases cover
local/global/upvalue/field/integer-index names, stripped data, failed left and
right operands, intermediate handler results, raw/NUL/nonstring `__name`,
multiline merged source, capture before mutation, active destinations and
left-parenthesized/right-associated handler order. All thirty-six retained
four-way cases and seventeen retained C consumers pass. The native-module
consumer requires its separately owned image fixtures and was not run bare.

A one-turn, tool-free Claude Haiku review of the supplied source/diff found
no high-confidence actionable defect (reported cost USD 0.01044). Its scope
excluded definitions not supplied in the patch. This is a local sidekick
review, not the required GitHub review or final acceptance evidence.

Unchanged `db.lua` bytes, loaded from a disposable tree as `@db.lua`, still
match default C stdout SHA256
`61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`
with empty stderr. Full unchanged default `locals.lua` reaches OK on both
runtimes with matching stdout SHA256
`1092E05E70A6DBA1AFDECAE3A03CED806D4DB5A1804EF1C5DD6D1E183AB6483B`.
Its collection-progress stderr differs: native prints two dots and this Ada
probe prints one. That observation is not raw-output parity or a reviewed
collector exclusion, and remains explicit final acceptance work.

## Remaining work

Full unchanged default `errors.lua` advances past concatenation and next
fails the field-name diagnostic for
`local function foo (...t) return t.xx + 1 end; foo()`.
It expects `field 'xx'`; current arithmetic failure is still bare. T-enabled
error-message cases and the final configuration/platform matrix remain open.

Public C `lua_concat` still owns an operand snapshot. Four native-default/T
diagnostic witnesses independently demonstrate that handlers must see the
original actual C window, mutations of an earlier operand must affect later
folds, and overwritten/consumed weak operands must die at the proper fold.
Those witnesses are preparation for a separate actual-window repair, not
passing Ada evidence for that behavior. Reference trees and pins are unchanged.
