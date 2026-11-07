# Public value identity checkpoint

Date: 2026-11-08, Asia/Tokyo. This continues the complete authorized delivery;
implementation, full acceptance, PR review and merge are not yet complete.

The C pointer API and Lua default rendering now share actual stable identity.
Named default descriptions use raw C-prefix names and managed output. Long
strings and string-valued __tostring results retain their original identity.
Native pointer formatting uses a bounded literal-width specification, including
the measured MinGW difference from star widths. Ada-only thread identities
remain unchanged when the first actual C callback arrives. See
[ADR 0031](../decisions/0031-public-value-identities.md).

A Haiku C draft was inspected and corrected: a private string-header/data
pointer inequality was removed, real native-width comparisons were added,
and assertion disabling is rejected. Eight same-source C cases pass native
default/T and Ada default/T. They check all relevant public identity kinds,
raw names, callbacks, C closures, coroutine lifecycle, widths and native NULL
spelling. Output SHA256 is
`fa41bd3e30177202ca0e5ad45c55265b578b2195e0629374b0090e17fea13e7c`.
Twenty-three Lua cases pass all four images, output SHA256
`9f33aae1617de2001d0d7aa0e7cb31d0f472c08be650009cb2d9e75750edc25b`.

Thirty-five separately named new AUnit cases comprise those Lua/C cases plus
late C borrowing, long-name quota, short-prefix/huge-suffix work, and actual
first-surface refusal. The weak-thread case is among the twenty-three Lua
cases. The refusal case steps the already-compiled Lua function to its real
tostring activation, refuses actual growth there, and requires the inner
Lua pcall false/memory-error pair, followed by retry and zero live blocks.
The outer Start_Foreign success prefix is checked separately. An initial
test-only wrong enum name and missing outer result prefix were corrected;
those failed observations are not passing tests.

Both Windows validation/static configurations pass all 1,993 combined AUnit
cases. Strict runtime/tests/C/CLI builds ran serially with retained checks,
Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (executable 26.0.0).
Twenty-two standalone C consumers pass in each Ada configuration; the native
module lifetime driver requires separate fixtures and was not run bare.
Typed integer/string/boolean stdin assertions were strengthened, and the
sixteen actual binary/text producer-consumer children still pass.

A bounded independent Sonnet review inspected ownership, rendering, surface
teardown, roots and the C leaf. It found no confirmed defect, raised active
stack/refusal risks and did not read all specs, pinned sources or tests.
The first-borrow, weak and refusal cases address the actual risks; the primary
author also checked pinned lapi.c:492-504 for public collectable identities.
Raw sidekick records: `reports/remaining-pointer-haiku-draft.json` and
`remaining-pointer-sonnet-review.json`. They confer no acceptance authority.

Logs: `reports/remaining-pointer-{default,tests,consumer,cli,T,T-tests,T-consumer,T-cli}-build.log`,
`remaining-pointer-{AUnit,T-AUnit}.log`,
`remaining-pointer-{C-default,C-T,Ada-Lua,Ada-T-Lua}.log`,
`remaining-pointer-*-consumer.log` and `remaining-pointer-retained-*.log`.
The initial missing-DLL native launch and stale CLI executable were diagnostic
failures, corrected before fresh runs. Raw pointer-format probe evidence is
`reports/pointer_printf_probe.c` and its executables.

Fresh unchanged errors.lua execution under the configured 2 GiB provider now
passes named tostring and next fails the `(io.write or print){}` message:
actual `string expected, got table`, expected a message naming io.write.
The original source remains unchanged; a diagnostic hook reads its locals.
Reports `remaining-errors-pointer` and `remaining-errors-pointer-hook` retain
the actual failure, not conformance acceptance. Shared/POSIX/final matrices,
remaining drivers, traceback and global ledgers/certificate stay open.
