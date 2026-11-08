# Self-valued C table assignments (2026-11-08)

The separately reviewed API fixed-buffer adaptation let the instrumented file
reach api.lua:664. Its `seti -1 200` command uses the same top table as both
destination and consumed value. The public wrapper made the target absolute,
but inserting the integer key shifted that actual target cell upward. It
then indexed the integer instead. lua_setfield had the same stack-bookkeeping
error. Both wrappers now follow that original cell after inserting the key.
The change stays in essential C API stack glue; Ada still implements lookup,
mutation, callbacks, collection and error propagation through its existing
iterative public portal.

Three separately named C cases check integer self assignment, string-field
self assignment and a collecting __newindex callback receiving identical
self/value operands. Each checks consumed stack extent and actual table
identity. Three named AUnit cases repeat those operations through the real T
public-API command driver, with owned session cleanup checked by its harness.
The complete 30-case index/type consumer matches native/Ada default/T stdout:
`996d5cb429de4d18dd130b375e4580372e9a6dec4400bbee57ce85204aaadf20`.

All eight strict static runtime/tests/C/CLI builds passed. The integrated
vararg, setmetatable, return-hook and native-tail implementation passes 2,232
AUnit cases in each local configuration. The complete foreign consumer,
including actual return-hook cases25/26 and the Ada T release-reentry case24,
passes in both configurations. The source-bound AUnit launch also passes
all2,232 cases after selecting Alire in tests/ and starting the actual child
from the repository root. The first manual launch used an uppercase expected
hash; the strict byte-identity guard rejected it before execution. Supplying
the prescribed lowercase digest produced the successful launch receipt.

The approved API adaptation still removes only the18-byte private400-byte
conjunct. Native T completes it; Ada now reaches line941, a byte-count bound
after finalization. A separate diagnostic observes exactly1,000 finalizers
and1,000 live userdata after the first collection, then zero remaining userdata
after the second, in both native and Ada T. Ada retains more private storage
capacity. That observation is not an approved adaptation, exclusion or passing
file result. Its ownership/footprint distinction requires independent review.

The subsequently integrated function-definition source checkpoint was tested
in its author worktree; a fresh Root combined build remains required after
that integration. The 26-context target, source/public-API reconciliation,
aggregate/heavy execution, complete fault campaigns and GitHub review remain
open. Mutable reports/api-self-value and reports/api-reviewed-transform are
component diagnostics, not final-head acceptance artifacts.
