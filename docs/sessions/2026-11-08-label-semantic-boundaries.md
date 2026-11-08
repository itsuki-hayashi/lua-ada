# Label semantic boundaries (2026-11-08)

Unchanged errors.lua reached adjacent duplicate labels on lines 1 and 2 with a
trailing newline. Ada attributed the error to EOF line 3. Pinned native Lua
uses line 2 and cites an already-defined label on line 2, not line 1.

Pinned revision `7579fc9d7ed90240487251dfb69168f8e64e9294` explains both
parts: lparser.c:labelstat finishes following labels/semicolons before checking
the current label, and lcode.c:luaK_semerror uses the last consumed token line.
Consequently a later malformed adjacent label fails before an earlier repeat
check. With a split label, the error uses the closing delimiter line while
the cited definition still uses the label's opening line. A consumed trailing
semicolon can also supply the error line. Merely forcing the opener or EOF
line would lose these distinctions.

The existing shared Block loop now defers checks through a complete no-op
run. It reuses the actual source-order Labels metadata and a scalar run-start
index. A reverse check sees completed earlier runs and already-defined later
run entries, ignoring earlier pending entries. It adds no parser recursion,
second grammar or independent label table. Existing function/block visibility,
goto targets, active bindings and terminal-label handling remain authoritative.
The shared error formatter accepts an explicit semantic line; ordinary syntax
errors retain their scanned token's final line and existing continuation
classification. Only the completed repeat check selects Last_Line here.

The prior first-party adjacent-label diagnostic asserted the native-contradicted
message ending in line 1. Its expected message is corrected to native's line
2, with a comment recording the reverse definition order. Reference tests and
pins remain untouched; no assertion is removed or bypassed.

Nineteen separately named AUnit cases and the Lua fixture cover trailing LF,
blank/comment/CRLF boundaries, split delimiters, semicolons, triple runs,
separated/nested definitions, unconsumed lookahead, malformed later-label
precedence, ordinary EOF expectations, backward gotos, disjoint/function
scopes, terminal runs and an actual reader's callback order. Invalid cases
check complete loader diagnostics and public Syntax.Check coordinates; the
shared parser's incomplete-input flag is checked independently. A direct-code
companion emits the valid label/goto controls through each actual producer.
Both fixtures match all four C/Ada producer/VM paths separately in default
and T configurations, with equal stdout and empty stderr. Both retained
36-case four-way campaigns also pass.

Both configurations pass **2,263 AUnit cases**, including the nineteen new
cases, corrected old expectation and retained provider/return-window tests.
All twenty-six ordinary standalone C consumers pass in each configuration;
the separate private T buffer caller passes too. Configured native-module
images were not rerun in this component. All six static runtime/tests/C
strict builds pass serially under the root's exclusive build lease, with
GNAT 16.1.0, Ada 2022 and all warning/style/runtime-check policies retained.
The first test compile correctly rejected a private-child import from a
non-Lua test unit; placing that unit under Lua resolved it and the strict
build was rerun. Production parser code compiled first try.

A tool-free one-turn supplied-source Claude Haiku review found no
high-confidence defect (reported cost USD 0.00418855). Its conditional index
question was checked against the actual 1-based Labels vector. That review
did not compile or execute tests and is not GitHub/final approval.

Fresh unchanged default errors.lua through the 2-GiB conformance runner in a
disposable original-byte tree now passes the duplicate-label and undeclared
global syntax checks. The next measured failure is local <close> a, b followed
by LF: native expects line 1, Ada reports line 2 for the multiple-closing
declaration. The original source remains unchanged and no soft flag is set.
This is the next separate semantic-token boundary. Full errors.lua/T memerr.lua,
remaining source/T/shared/platform obligations and final-head acceptance remain
open.
