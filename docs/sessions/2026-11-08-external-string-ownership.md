# External string ownership and ordinary short identity

Date: 2026-11-08, Asia/Tokyo. Scope: the next public C boundary checkpoint in
the approved remaining-suite delivery. Base: integrated main `557b8c0`, after
the callable builtin checkpoint. This is component evidence, not full M3,
all-T, native-module, platform matrix, or PR acceptance.

## Implementation

[ADR 0021](../decisions/0021-external-string-ownership.md) records the external
payload and guarded release design. `lua_pushexternalstring` preserves the
original bytes/address for every length, owns the actual callback/userdata,
and calls it once with original length plus one and new size zero. Borrowed
buffers have no release callback. Header-refusal cleanup remains C-owned and
observes the original stack top before the memory error is raised.

An intrusive pending queue and active LIFO release chain retain existing
provider-owned headers. Collection executes no foreign callback. The C
portal catches nonlocal transfers above completed Ada steps, and nested Lua
work uses the same iterative driver. Actual returning frames/results remain
owned until callbacks finish. Registered close packets retain globals/code
until the pre-disposal drain; host quota abort still permits physical cleanup.

Ordinary short strings now share a weak per-world identity index, with
transactional growth, unlink-before-free, unswept-white revival and a
no-allocation transient root for reused strings. New short external table
keys normalize separately; long external keys remain original buffers.
Public string `lua_topointer`/`%p` identify the real header rather than the
byte buffer/serial. `package.searchpath` loses its unused package capture so
its public zero-upvalue identity matches the pinned C function.

Two retained fixture setups changed without weakening their assertions.
The byte-hash case still requires two separate equal embedded-NUL objects,
so its common payload is now forty-three bytes (ordinary short values are
intentionally interned). The provider-reclamation case still allocates and
reclaims 200 tables plus 200 actual string headers, using distinct payload
contents rather than 200 aliases of one interned short string. New focused
identity cases independently verify the ordinary short-string behavior.

## Commands, results and recovery

Tools: Alire 2.1.1, GNAT 16.1.0, GPRbuild package 26.0.1 (banner 26.0.0,
2026-04-15-gpr2), Windows x86-64. Isolated C oracle builds used GCC 13.2.0
MinGW-W64 x86_64-ucrt-posix-seh. No machine pin, generated configuration,
reference source or reference revision changed.

Serialized builds:

```text
alr -n build --validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default
alr exec -- gprbuild -P c_api/consumer.gpr -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
alr -n -C tests build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
```

All strict builds pass with the required Ada warning/style/runtime checks.
Final execution of `tests/bin/static/test_runner.exe` passes all 1,557 cases,
zero assertion failures and zero unexpected errors. Eight new named cases
cover 40/41-byte identity, embedded NUL, weak index reclamation, incremental
sweep revival, operation roots, growth, actual C callback work-budget failure,
and disposal after an earlier host abort. The two C-host cases close with
zero managed live blocks and exactly one actual external free.

The same C99 `external_string_contract.c` source passes eighteen named cases
against Ada default/static and isolated pinned default C. Their raw stdout
SHA-256 is `a7c0efa822c5b989216fef905c3b56f1d4d9554a7391f090092946ebba843ca3`.
It covers ordinary identities and refusal, empty/short/long/embedded-zero
external buffers, borrowing, key normalization/retention/update, weak values,
repeated header refusal/recovery, exact free arguments and pre-error stack
top, state closure, Lua reentry, nested collection, actual interrupted caller,
Lua closure collection and close-time reentry. Counted providers close with
zero bytes and blocks. External C payloads are independently freed once.

Native instrumented C passes its first thirteen ownership cases, then a
full-mode run aborts at its lock assertion on the first deallocator
`lua_getglobal` (`ltests.h` lock counter, `lapi.c:701`). The explicit
`--ownership-only` mode prints five skipped reentry cases. That mode matches
the same Ada default executable byte-for-byte with stdout SHA-256
`701ed9104ceb8bf8ec7b4a78b4677fd81accdee7e3a0ac04603d94fab4246122`.
This is not an Ada instrumented build or passing native-T reentry claim.

Retained C bootstrap, GC, IO/OS, foreign, reader/writer, twenty-case debug
and fifteen-case builtin consumers all pass against the final local image.
`check-core-image.ps1` now registers the external consumer, identical native
source, arguments, separate matched/skipped counts and stdout comparison;
PowerShell parsing passes. Its complete build/platform pipeline was not run.

Earlier executions are retained in ignored `reports/external-strings/`:
initial native payload tests caught an incorrect assumption equating
`lua_topointer` with payload bytes before implementation claims; first Ada
execution passed fourteen C cases then exposed missing real external-portal
origin recognition for nested Lua calls. The first AUnit run had only the
two old short-identity fixture assumptions above. A later 1,555-case run and
seventeen-case C run passed before the final two host cases and eighteenth
closure-lifetime witness. Final logs are `runtime-build-3.log`,
`consumer-build-3.log`, `tests-build-3.log`, `aunit-3.log`,
`ada-external-3.log`, `native-default-3.log`, `ada-ownership-3.log` and
`native-upstream-test-2.log`. GDB exception traces confirmed the nested
boundary origin fault; those exploratory failures are not passing evidence.

## Remaining work

Unchanged `strings.lua` advances through the short-identity `%p` assertions
and stops at assertion 256 (formatted `__name` text). It is not a file pass.
Integrated Ada default/T, shared libraries, all OS contexts and complete
unchanged suite/native-module protocols remain pending. In particular the
platform loader must keep module code loaded through all external release
callbacks, then release OS handles after physical world objects. Ordinary
owner allocator reentry is not enabled by this external-string portal.
