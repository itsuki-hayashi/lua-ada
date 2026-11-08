# Base setmetatable argument phases (2026-11-08)

Unchanged errors.lua reached string.gsub('s', 's', setmetatable). The real C
replacement callback failed with Ada's generic `table expected`; the pinned
native error names `setmetatable` and its actual argument. The retained parent
executable also fails the new paired fixture at its first generic error.

The base.setmetatable continuation now uses shared auxiliary type diagnostics
for both argument gates. Its already copied Left/Right values end all vector
indexing borrows before error formatting can transfer a failed builtin phase
or invoke registry callbacks. An absent second argument is rejected, while an
explicit nil removes the metatable. Receiver validation still precedes the
second argument, and that argument still precedes protected-metatable lookup.
Actual call origin supplies method self/index adjustment, C callback names,
source prefixes, named types and missing-versus-nil spelling.

Pinned evidence is unchanged Lua revision
`7579fc9d7ed90240487251dfb69168f8e64e9294`, lbaselib.c:luaB_setmetatable.
The only production edit is this argument-gate branch in Native_Step. Return
handling, the actual metatable update and protected-metatable behavior are
unchanged; no interface or second execution path was added.

Fifteen separately named AUnit cases and primary/direct-code Lua fixtures
cover absent/nil/invalid/named receivers, absent/invalid/named metatables,
validation order, colon self/regular argument indices, the actual gsub C
callback, explicit nil removal, real metatable identity/lookup and a registry
callback that clears the invalid second C slot and collects its sole weak
edge. Both fixtures pass all four fresh C/Ada producer/VM paths separately
in default and T configurations, with matched stdout and empty stderr.

Both configurations pass **2,200 AUnit cases**, including retained return
window/provider fault regressions. All twenty-six ordinary standalone C
consumers pass in both configurations; the separate private T buffer caller
passes too. Configured native-module images were not rerun in this component.
All six static runtime/tests/C-consumer strict builds passed first try,
serially under the root's exclusive build lease, with GNAT 16.1.0, Ada 2022
and every required warning/style/runtime-check policy retained.

Fresh unchanged default errors.lua through the 2-GiB conformance runner in a
disposable original-byte test tree passes the gsub, coroutine-error and source
size checks, then fails its lineerror assertion at line 427. A separate
diagnostic line hook identifies function a.x.y () followed by a=a+1 and end:
the final definition store reports line 3, while native expects line 1. The
compiler's function-statement store attribution is a separate next checkpoint;
the closure's actual end-line attribution must survive that correction.
No soft flag or reference edit was used. Full unchanged errors.lua/T memerr.lua,
remaining source/T/shared/platform obligations and final-head acceptance stay
open. The independently measured cold string.find output refusal remains
distinct from the selected warmed scalar cases.
