# Selected debug-line baselines (2026-11-08)

The Ada-produced direct string-argument fixture exposed an actual native T
debug-reader assertion. The unchanged source and native-produced chunk ran;
the Ada-produced T chunk aborted in ldebug.c:getbaseline at line 70. The
smaller dedicated debug fixture reproduces that old-writer failure too.

Pinned Lua revision `7579fc9d7ed90240487251dfb69168f8e64e9294` defines the
ordinary MAXIWTHABS as 128 in ldebug.h and overrides it to 3 in ltests.h.
Getbaseline estimates its initial absolute-record index from the actual PC
divided by that interval. Its estimate must be a lower bound. A writer that
spaces its records farther apart can violate that invariant even though an
unrestricted scan could recover the source line. The Ada writer previously
used 128 in both configurations.

The private selected runtime configuration now supplies the absolute-line
interval to the existing canonical writer: 128 ordinarily and 3 in T. Actual
line values, large-delta handling and per-prototype PC origins remain the
same. Lcode's savelineinfo uses a post-increment counter and resets it to one
after a marker, giving subsequent periodic gaps equal to MAXIWTHABS. The Ada
writer retains its existing fixed checkpoints from PC zero. Extra markers
for large deltas make the reader's estimate smaller; identical private marker
placement is unnecessary. No debug events, source behavior or native checks
are suppressed. Reference trees and pins remain unchanged.

Six separately named AUnit cases exercise an empty root, every PC around
multiple interval boundaries on one long physical line, large source gaps,
child prototypes, actual binary encode/decode and stripping. They run the
native reader's estimate/correction rule against each real generated graph
and compare its reconstructed source line with an independent complete scan.
Stripped graphs have neither relative nor absolute line records.

The seven-case Lua fixture additionally observes actual currentline, nested
functions, error source prefixes and line hooks, and executes empty/stripped
chunks. Both native configurations pass the original source. The old Ada T
chunk fails native T with the retained ldebug.c assertion; after the fix all
four C/Ada producer/VM paths pass separately in each matching configuration,
with identical stdout and empty stderr. The prior three string fixtures now
also pass all four paths in both configurations, closing the specific T
writer limitation recorded by the preceding string checkpoint. Both retained
36-case four-way campaigns pass too.

All six static runtime/tests/C-consumer strict builds passed first try,
serially under the root's exclusive build lease, with GNAT 16.1.0, Ada 2022
and all required warning/style/runtime-check policies. Both configurations
pass **2,157 AUnit cases**, including the six new cases and the retained
provider fault sweep. All twenty-six ordinary standalone C consumers pass in
both configurations, with the separate private T buffer caller also passing.
Configured native-module images were not rerun in this checkpoint. Unchanged
db.lua through loadfile passes the fresh default conformance runner with empty
stderr and stdout SHA256
`61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`.

A tool-free one-turn supplied-source Claude Haiku review found no
high-confidence defect in the interval/lower-bound change (reported cost
USD 0.00258995). It did not inspect the new test bodies or execute tests and
is not GitHub/final approval.

The fresh unchanged T memerr.lua campaign still stops at line 7 with
`not enough memory`; selected warmed scalar refusal cases do not certify the
full file. Unchanged errors.lua next needs table.sort callback argument
naming. Borrowed Lua CI windows/hooks, remaining source/T obligations,
shared/platform campaigns and immutable final-head acceptance remain open.
