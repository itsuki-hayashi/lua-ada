# Public auxiliary allocator and seed checkpoint

Date: 2026-11-08, Asia/Tokyo. This continues the approved remaining-upstream
implementation. Full-target acceptance, review and merge remain pending.

The C ABI now exports `luaL_alloc` and `luaL_makeseed`. The first is essential
standard allocation glue: it ignores userdata/old size, delegates to the host
realloc/free pair, and preserves the old block on refusal. It contains no
interpreter logic or reference interpreter object. Seed generation folds host
address/time/clock representations; exact seeds are implementation dependent.
It neither reads a Lua state nor allocates through its provider.

`luaL_newstate` now selects that actual public allocator, NULL userdata and a
public seed. Ada-owned sessions retain their existing bounded provider policy.
The auxiliary C constructor installs its default panic handler only after
successful state publication. It avoids number-to-string allocation while
reporting a panic. A returning or absent panic handler terminates without an
extra invented diagnostic; the explicit host-abort policy remains separate.

The inspected Haiku consumer draft became thirteen separately registered
AUnit cases sharing the actual C source with native default and T processes.
It measures grow/shrink prefixes, numeric alignment, real SIZE_MAX refusal,
allocator function identity, inert seed generation and balanced state close.
Two additional named subprocess modes call the installed default panic
function directly and compare its exact string/nonstring diagnostics. They do
not claim to exercise an abort or foreign nonlocal transfer.

On Windows, native DLL consumers require `LUA_BUILD_AS_DLL` for a function
address witness to identify the imported function instead of its link thunk.
Ordinary Ada static consumers retain plain declarations; shared consumers and
C bridges select DLL imports. Public SDK headers remain unchanged.

Local Windows validation/static observations use Alire 2.1.1, GNAT 16.1.0 and
GPRbuild package 26.0.1 (executable 26.0.0), with the retained strict flags and
runtime checks. Runtime, tests and C consumers built serially. An initial
project-name error and missing private test subprogram specifications were
corrected before the successful builds; neither failed build is called passing.
All 1,822 AUnit cases passed, including thirteen new allocator cases. Eighteen
standalone retained C consumers passed. The thirteen-case output matches
native default and native T byte-for-byte, SHA256
`a7d5eba930acbaab2ceecdb2103741d2fb8968c6ab89b772e8292b23bfd31335`.
Both panic-mode diagnostics also match those native images exactly.

Logs are `reports/remaining-allocator-{default,tests,consumer}-build.log`,
`remaining-allocator-AUnit.log`, `remaining-allocator-Ada-default.log`,
`remaining-aux-allocator-C-{default,upstream-test}.log`,
`remaining-allocator-{Ada,C-default,C-upstream-test}-panic-{string,number}.log`
and `remaining-allocator-retained-*.log`. These are component observations,
not immutable final-head matrix evidence or an independent certificate.
Instrumented Ada, shared and POSIX replay, fault campaigns and full auxiliary
file/traceback/substitution completion remain outstanding. No source exclusion
or passing global ledger resolution is authorized by this checkpoint.
