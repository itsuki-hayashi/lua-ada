# Literal auxiliary substitution checkpoint

Date: 2026-11-08, Asia/Tokyo. This is a component of the approved remaining
upstream delivery, not full-target completion.

`luaL_addgsub` and `luaL_gsub` now compose the actual owned public buffer API.
The facade retains only scalar offsets into caller-owned C strings. Literal
leftmost, nonoverlapping matching, verbatim replacement and stack-result
ownership follow pinned lauxlib.c. No input-sized temporary or independent
pattern engine is introduced. All growing bytes belong to the selected Ada
storage owner and its existing closing/resource fallback.

Foreign scans and actual byte comparisons charge the shared execution budget.
A repeated-prefix input cannot hide unlimited comparisons behind one outer
search charge. The pinned helper does not progress for an empty pattern; the
Ada bounded policy still stops that loop, including an empty replacement.
No native empty-pattern termination or passing upstream obligation is claimed.

A bounded Haiku task drafted sixteen public C cases, inspected and corrected
by the primary author. The refusal flag now becomes active inside the actual
callback, so an outer protected-call metadata allocation cannot masquerade as
substitution work. Persistent refusal requires the native `LUA_ERRMEM` class,
not an allowed ordinary runtime-error alternative. The draft's scratch C DLL
run was not reused as acceptance evidence. Fresh same-host pinned default/T
images were linked and run by the primary agent.

The sixteen cases cover literal syntax, overlap, replacement rescanning,
shrink/grow/delete, no match, empty subject, prefix/suffix, counted Lua bytes
viewed through C-string termination, existing-buffer append, 60,004-byte
output, callbacks, protected errors and actual refusal followed by recovery.
Each uses a fresh counted state and requires balanced close. Three separately
named AUnit cases exercise empty-pattern quota/recovery, actual repeated
prefix comparison charging, and immediate physical cleanup of a promoted
buffer after abort with no intervening Lua operation.

Strict Windows validation/static runtime, tests and C consumers built serially
with Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (executable26.0.0).
An initial two-line Ada width failure was corrected; that failed build is not
called passing. All 1,858 combined AUnit cases pass. The sixteen C cases pass
against Ada default and native default/T with identical stdout SHA256
`7ad674f126a7fecb84c9739dde2cfc00ee546d66a703f3160f5e771f8c004da1`.

Raw logs: `reports/remaining-substitution-{default,tests,consumer}-build.log`,
`remaining-substitution-AUnit.log` and
`remaining-substitution-{Ada-default,C-default,C-T}.log`. Sidekick record:
`reports/remaining-substitution-haiku-draft.json` (source authoring, no
acceptance authority). T Ada/shared/POSIX, final-head immutable matrices,
source reconciliation and independent review remain pending. The remaining
public auxiliary file and traceback functions still require implementation.
No exclusion, equivalent or passing global ledger resolution is installed.
