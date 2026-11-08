# Linear Lua readers and closing declaration lines (2026-11-08)

Unchanged errors.lua reached a multiple-closing local declaration followed by
LF. Ada used the scanned EOF line; pinned Lua uses the last consumed name or
attribute token. The shared declaration check now selects Last_Line, matching
lparser.c:localstat and lcode.c:luaK_semerror without changing ordinary syntax
diagnostics or incomplete-input classification. Ten syntax/public-coordinate
checks and three runtime controls cover trailing LF, blanks, comments, CRLF,
semicolons, split names/attributes, an incomplete attribute, once-only closing,
attribute override and a reader's actual semantic-error stopping point.

That reader regression exposed eager draining in base.load. Native stops
after a completed semantic failure before requesting another callback; Ada
previously read a deliberately erroring later piece. The mandatory regression
was retained throughout the repair. An actual shared-parser pending-prefix
prototype fixed correctness without inventing EOF, but its measured quadratic
cost rejected it for production. Its 8,009-byte one-byte assignment stream
took 22.492 seconds; 16,009 bytes took 99.375 seconds. Native took roughly
8 and 9 milliseconds respectively. The prototype's helper, input extension
and build-list entry were removed; no such reparsing path remains.

[ADR 0036](../decisions/0036-linear-lua-readers.md) records the implemented
linear portal. The actual base.load activation retains its identity and
requests the existing guarded public lua_load path after Native_Step returns.
The C shim transports callbacks/status only. Ada owns options, source/codec
selection, reader result checking, numeric coercion, environment and results.
The shared frontend/decoder consumes the stream once. A directly invoked saved
builtin publishes its working prefix into the real C caller and borrows those
actual scalar cells, retaining its own genuine guard/token. Obsolete argument
packets retire before callback collection. Normal completion roots results
before releasing that lease; error/host-abort/reset paths preserve their
existing typed acknowledgement and cleanup protocol.

Forty-five separately named AUnit cases are added: thirteen closing-declaration
cases, eleven pending-input boundaries, seventeen portal behaviors and four
host-policy/lifetime checks. The forty-one Lua witnesses pass native default
and T configurations. They cover names/numerals/escapes/long delimiters and
comments split across pieces, real delimiter demand, reader error identity,
binary exact-end/trailing bytes, early mode rejection, load identity, mutable
reader/environment cells, retired weak roots including extra arguments,
numeric option cells, rejected yields, nil-error fallback, actual return-hook
result/tuple edits, one public call, nested loads and inherited handlers.
The four Ada policy cases exercise real source-work, callback-work and source
extent host aborts, same-host recovery, balanced guard/depth/view teardown and
zero selected live blocks after finalization.

Both configurations pass **2,312 AUnit cases**. The public builtin C fixture
preserves its original twenty-four cases and adds five separately named
saved-load cases: direct host entry without a public CI, original C owner and
environment, mutable reader/weak root, protected error/recovery, and replaced
extra-argument root. All twenty-nine pass in Ada and separately built native
Lua in both configurations, with identical stdout SHA-256
`fa2f13c574a55ee1893c0142c43d962ddff9998f0a0b79b4ab27adcfbcf7effc`.
All twenty-six ordinary standalone C consumer executables pass in each
configuration, with the additional private T buffer consumer passing too.
Configured native-module fixture images were not rerun in this component.

All three new Lua fixtures match all four C/Ada producer/VM roles separately
in default and T, with equal stdout and empty stderr. Both retained 36-case
canonical compiler/runtime campaigns pass. The new portal first exposed that
the canonical runtime probe's manual loop never serviced a real C request.
The host loop now uses the same driver and production borrowed callback,
warning and release pump between Steps, and cancels an unfinished exceptional
borrow. It retains every producer/VM check and does not replace execution
with a source approximation or suppress hook events.

Final one-byte stream measurements use the actual conformance launcher, a
900-second process bound and its existing 2-GiB selected-provider ceiling.
The successful assignment streams contain 8,009, 64,009 and 256,009 source
bytes; callbacks count those bytes plus one genuine EOF. The final default
run took approximately 0.310, 0.897 and 3.823 seconds; T took 0.597, 1.095
and 4.285 seconds. A 1,000,009-byte whitespace stream completed in 12.601
seconds by default and 13.023 seconds in T. Those elapsed values include
process startup and concurrent immutable checks; they establish bounded
practical scaling for these inputs, not a general performance guarantee.

All six final static runtime/tests/C strict verification commands passed
serially with GNAT 16.1.0, Ada 2022, warnings/style as errors and runtime
checks retained. An earlier six-command window briefly overlapped another
worktree's test build; its build claims were discarded and all six commands
were replayed under an exclusive lease. The canonical probe repair compiled
and linked in both replayed test builds; other current targets correctly
reported reuse where no input changed. The final execution evidence above
comes from those serially verified images.

A supplied-diff, tool-free one-turn Claude Haiku review cost USD 0.00516945.
Its three claims were checked against full source and rejected: Stage0 already
copies a supplied name before the reader branch; inactive stack-view restoration
is explicitly harmless; and Push advances the inclusive live top before the
two failure slots are written. That review supplies no test or GitHub approval.

Reference sources and their pin remain unchanged. This checkpoint does not
separately establish reader-injected permanent refusal or self-close for the
new Lua portal flag. Retained public C reader/reset cases pass, but they do
not substitute for those new entry-path witnesses. Continue them as a bounded
follow-up, including result-capacity preflight before callbacks if native
observations require allocation-free completion under refusal.
This checkpoint also does not
certify full errors.lua, T memerr.lua, the remaining upstream files, platform
matrix or immutable final-head acceptance. Continue the original source/T
delivery from fresh bounded file diagnostics after integration.
