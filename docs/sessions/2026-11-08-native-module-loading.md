# Native module loading checkpoint

Date: 2026-11-08, Asia/Tokyo. Branch:
`codex/m3-remaining-upstream-compatibility`. This is an intermediate checkpoint
of the authorized complete delivery, not its stopping condition.

## Implementation

The owned Ada loader implements `package.loadlib`, native and root-module
searchers, pinned symbol fallback, OS error stages, `package.cpath`, versioned
environment precedence, first-double-separator expansion and Windows
executable-directory substitution. The CLI sets the actual `LUA_NOENV`
registry marker and configures paths before initialization. Bounded sessions
keep their existing environment policy. Three additional builtin trampolines
use the real C callback boundary.

Provider-owned loader records are constructed before OS acquisition, retained
through state cleanup and released in reverse opening order. The allocator's
code image is held through final cache-record release and the storage owner's
final cleanup by a controlled lease. See
[ADR 0025](../decisions/0025-native-module-lifetimes.md). No reference source,
submodule pin, strict Ada switch or runtime check changed.

## Observations

Local Windows default validation/static builds use Alire 2.1.1, native GNAT
16.1.0 and GPRbuild package 26.0.1 (executable 26.0.0). Root, CLI, nested
tests and C consumers compile with their strict flags. All 1,691 AUnit cases
pass, with no assertion failures or unexpected errors. Nine new separately
named package cases cover empty path templates, invalid public path fields,
OS-open failure results, exact accumulated searcher messages, C-string
boundaries and alias/method/custom-type diagnostics.

All fourteen current C consumers pass. The newly integrated 27-case indexing
and type consumer has the same output as native default and instrumented C:
`e92aee4ca3502371274c0ff4fe70f07a29d70a40703bb39344b4ee6631156ef8`.
These are local component observations, not new global API classifications.

The eight-case `tests/lua/native_package_contract.lua` also matches both
native configurations and Ada, with stdout SHA-256
`202a60f5b0eec437ca2620985087f2fa97a09c71ca8dd4721accf87aa23d7b59`.
Its source-linked name test distinguishes the C-string cache/search key from
the original counted name passed to the chosen loader.

All five unchanged upstream fixture sources build against an import library
generated from the actual static CLI's exports and basename. A direct smoke
checks calls into that host, inter-library exports, native/root searchers and
external-string construction. Disposal completes without abnormal exit.

The unchanged original `attrib.lua` fails at assertion 154 on both native C
and Ada under Windows: the expected literal uses forward slashes while the
actual selected path uses the native separator. A disposable diagnostic copy
correcting those expectations completes unreduced on both runtimes, with
identical stdout SHA-256:
`400ca700d8110c892dbe04ca180b90ccb0b15f7d6a73d3020149ed1ea6b3add7`.
Both have empty stderr and exit zero, including native modules and external
strings. This copy has no approved transformation manifest and is not
accepted conformance evidence. The mixed template separator at assertion 211
requires a distinct correction; blindly replacing every slash is incorrect.

Local raw observations are under ignored `reports/remaining-native-module-*`,
`reports/remaining-index-type-Ada.log` and
`reports/remaining-native-attrib*-diagnostic.*`. These observed binaries include
the uncommitted implementation during development; they do not certify an
immutable final revision or any complete acceptance context.

A bounded read-only Claude Sonnet 5.5 review inspected loader/storage source.
Its concrete findings led to extending the allocator-code lease through
owner finalization, using POSIX `RTLD_NOLOAD`, exporting static POSIX host
symbols, correcting C-string and argument diagnostics, and documenting native
code capabilities in the embedding guide. The review ran no tests and grants
no acceptance authority. Its raw record is
`reports/remaining-native-module-sonnet-review.json`. POSIX execution and
explicit module-owned allocator witnesses remain required.

## Outstanding work

Finish independently reviewed Windows transformations and same-image fixture
production with immutable receipts. Add explicit unload/provider lifetime and
allocation-failure witnesses. Validate shared, instrumented and POSIX images,
metamethods on public package/registry fields, environment/CLI children and the
final matrix. The remaining public auxiliary
surface, relevant T drivers, source obligations, aggregate/stress execution,
full acceptance, GitHub review and authorized merge remain unfinished.

## Subsequent lifetime-driver checkpoint

The separately named `native_module_contract.c` now executes nine public C
cases against local Ada default/static, native C default and native C T.
All three outputs match SHA-256
`cf8431b2792ef0a65b0ae1b8c0349538ad9ef6c74029b0e4b4db571e356fc979`.
Each case uses a fresh provider-backed state and verifies zero blocks/bytes
and actual OS module absence after close. The cases exercise open/symbol
failure stages, real fixture calls, both inter-library dependencies, root and
hyphen searchers, retained native calls from a state-close finalizer, a
registry-held external string and exactly-once explicit external release.
The external header belongs to the unchanged fixture, not private Lua data.

The first-party fixture builder uses actual PE exports/imports and generates
an import library bound to the driver's final basename. Its default Ada and
native-T runs capture source, compiler, module alias, dependency and owner
identities. The independent nine-case linkage regression also passes,
including real function/data pointer identity, rejection of a renamed host
with old imports and successful regeneration for its new basename. Those
small C image checks are infrastructure tests, not Lua conformance.

The integrated module/base-C-closing/retirement/prefix source builds strictly
and passes 1,714 AUnit cases and fifteen existing C consumers. These are local
development observations; the runtime also contains uncommitted auxiliary
buffer work whose behavior is not certified by this run. Raw driver logs are
`reports/remaining-native-module-consumer-{Ada,C-default,C-upstream-test}.log`;
the fixture receipts are `reports/remaining-native-module-fixture-receipt.json`
and `reports/remaining-native-module-T-fixture-receipt.json`. A Haiku draft was
corrected against the actual fixture sources before compilation/execution.
Its original unsupported fixture assumptions are not passing evidence.

Ada T/shared/POSIX, a module-owned allocator, allocation-failure sweeps,
immutable final-head replay and independent acceptance remain unfinished.
