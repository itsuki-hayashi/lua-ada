# Function definition store sites (2026-11-08)

Unchanged errors.lua reached a failed function a.x.y definition: the final
store through nil x reported the function's closing line 3 instead of line 1.
The retained old executable fails the same native-paired fixture. Ordinary
function assignment and closure construction have different source phases;
changing every closure or assignment to its opening line would be incorrect.

Pinned Lua revision `7579fc9d7ed90240487251dfb69168f8e64e9294`,
lparser.c:funcstat resolves the target before the body, emits the closure,
stores the result and applies luaK_fixline to that final store. The canonical
Assignment path already resolves its targets before the child. A direct
Function_Expression child identifies a function statement; ordinary assignment
uses an expression list. Only the defining store's line changes to the
opening function keyword. Closure/end-line instructions and ordinary anonymous
function assignment retain their existing attribution and real execution.
No hook event or instruction is suppressed or synthesized.

The related explicit-global path needs two distinct preserved sites.
Globalfunc fixes the store/check to GLOBAL's line, while supplying the current
opening-parenthesis line to body for the child prototype's linedefined.
The parser now records the global Assignment's original opening site and
passes the actual current site to Function_Body. The compiler selects that
global opening site for its defining store. A split native witness gives
store line 1, child linedefined 4 and lastlinedefined 6; both remain distinct.
No parse signature, grammar or vararg/flags visitor changed.

Twelve separately named AUnit cases and primary/direct-code Lua fixtures
cover failed field/method/empty definitions, a split function keyword/target,
ordinary assignment and early-target contrasts, actual field/global/local
hook-event sequences, explicit-global store and prototype metadata and the
ordinary-function metadata control. Both fixtures pass all four fresh C/Ada
producer/VM paths separately in default and T configurations, with matched
stdout and empty stderr. Both retained 36-case four-way campaigns also pass.

All six static runtime/tests/C-consumer strict builds passed first try,
serially under the root's exclusive build lease, with GNAT 16.1.0, Ada 2022
and every required warning/style/runtime-check policy retained. Both
configurations pass **2,212 AUnit cases**, including the twelve new cases and
retained provider/return-window regressions. All twenty-six ordinary standalone
C consumers pass in both configurations; the separate private T buffer caller
passes too. Configured native-module images were not rerun in this component.
Unchanged default db.lua through loadfile passes with empty stderr and stdout
SHA256 `61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`.

Fresh unchanged default errors.lua through the 2-GiB conformance runner in a
disposable original-byte test tree now passes every runtime lineerror case,
including explicit global function and the negative absolute-base estimate.
It next fails the syntax line check at line 523: duplicate ::L1:: declarations
on lines 1 and 2 with a trailing newline report the semantic error on line 3,
while native expects line 2. A diagnostic-only wrapper identifies that state;
the original source and pins remain untouched, with no soft flag. That parser
error boundary is the next separate checkpoint. Full errors.lua/T memerr.lua,
remaining source/T/shared/platform obligations and final-head acceptance stay
open.
