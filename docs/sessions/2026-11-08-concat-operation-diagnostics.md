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

## Primitive arithmetic diagnostic followup

The same borrowed formatter now covers arithmetic/bitwise handler misses,
length failures, ordering and direct integer division-by-zero faults. It
attributes a direct primitive fault to the current actual Lua activation,
or a synthetic operation to its immediate Lua owner. It never searches past
a C activation. `luaG_tointerror` places operand varinfo between `number`
and `has no integer representation`; the previous spelling placed it last
and materialized a Lua string merely to inspect the binding. The new query
borrows immutable metadata. Raw `__name` is now honored only on tables and
userdata, following `ltm.c:luaT_objtypename`; primitive metatable names are
ignored.

Twenty-one more separately named cases cover left/right/first-invalid
selection, named varargs, global/local/upvalue/field origins, nonintegral
conversion, unary operators, comparison/division source and primitive-name
exclusion. Native default and T pass all forty-one combined cases. Strict
root/tests/C builds pass, as do all 1,787 AUnit cases, both complete forty-one
case four-way fixtures, thirty-six retained four-way cases and seventeen
retained C consumers. The first run's division case correctly caught the
direct canonical path lacking a synthetic helper; it passed after that
actual owner was included. No assertion was weakened.

Full unchanged default errors.lua now reaches indexing diagnostics. Its next
failure is `aaa.bbb:ddd(9)`: expected `global 'aaa'`, actual
`attempt to index a nil`. Index operand/source attribution, actual C concat
windows and full-file/T/final-matrix acceptance remain open.

## Indexing and C name-boundary followup

Index failures now identify the actual receiver register or directly indexed
upvalue cell. Redirected noncallable `__index`/`__newindex` chains still report
the final primitive object and cannot borrow the initial receiver's name.
This follows `ldebug.c:varinfo`'s distinction between actual stack/upvalue
addresses and objects stored elsewhere. Get/set operations use their real
opcode operands, including deferred assignment receivers and environments.

Rendered Lua debug/error names now end at the first embedded NUL in a field
key, matching upstream's C name view. The immutable field key keeps every
counted byte. `Name_Image` performs that scan only for rendered text; raw
public C metadata still borrows the original stable pointer without a scan
or allocation. The now-unused operand materializer was removed. Call errors,
Lua getinfo, primitive varinfo and loader call names share the renderer.

The loader regression exposed an existing path which bypassed argument
validation and reported `string expected in base.loadfile`. Optional filename
validation now precedes mode validation and opening, following
`lbaselib.c:luaB_loadfile`; dofile validates its filename and ignores extra
arguments. Nil retains stdin and numbers retain existing string coercion.
The failing assertion was kept and now passes, alongside independent
filename-before-mode, mode-before-open and dofile-name cases.

Twenty-two new named cases pass within all 1,809 AUnit cases. Native default/T
pass both complete sixty-three-case fixtures, and all four default
compiler/runtime combinations pass both fixtures. Strict serial root/tests/C
builds, thirty-six retained four-way cases and seventeen retained C consumers
pass. Unchanged db.lua again has the recorded matching stdout and empty
stderr. Reference sources/pins remain untouched and git diff --check is clean.

Full unchanged default errors.lua now reaches the numeric-for diagnostics:
`for i = {}, 10 do end` expects the offending table type, while the current
message is still `'for' initial value must be a number`. Actual C concat
windows, numeric-for/library diagnostics, T file paths and final matrices
remain unfinished. These focused checkpoints do not close the file ledger.

## Numeric-for diagnostic followup

A small typed VM failure helper now shares raw diagnostic types and actual
Lua source attribution with canonical numeric-for conversion failures. The
existing conversion and control paths retain their ordering: integer loops
test a zero step before converting their limit; float loops validate limit,
step and initial value before testing zero. No loop control is given a
fabricated variable annotation.

Seventeen new cases cover initial/limit/step roles, table/function/FILE* and
raw/NUL `__name` types, both validation orders, zero steps including coerced
strings, multiline FORPREP source, and successful integer/float coercions.
Both native configurations pass both complete eighty-case fixtures; all four
default compiler/runtime combinations pass them too. Strict root/tests/C
serial builds pass, as do all 1,826 AUnit cases, thirty-six retained four-way
cases and seventeen retained C consumers. The initial compile's missed
forward/body parameter type update was corrected; no flags were relaxed.

Full unchanged default errors.lua advances to its light-userdata argument
diagnostic: debug.setuservalue currently reports `full userdata expected`
instead of identifying the rejected light userdata. Separate measured
library gaps concern FILE* numeric arguments, named IO arguments and named
tostring output. Those, actual C concat windows and full file/T/matrix
acceptance remain open.
