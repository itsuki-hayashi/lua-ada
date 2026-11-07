# Argument registry continuations (2026-11-08)

This component implements the measured registry callback obligation retained
by the earlier library argument diagnostic checkpoint. It follows the
existing [native continuation decision](../decisions/0007-native-libraries.md)
and preserves the [real C guard transfer](../decisions/0027-protected-error-closing.md).
It does not
certify the remaining source/T/shared/platform/final-head gates.

## Actual operation and ownership

Pinned `lauxlib.c`'s `luaL_argerror` uses `pushglobalfuncname` when debug call
metadata has no name. That helper performs ordinary registry `_LOADED`
getfield, including a registry `__index` function or table forwarding chain.
The previous synchronous Ada formatter read that field raw, omitting the
callback and reporting `?` even when C Lua executed it and found math.sin.

The failing activation now owns the original argument index and copied
diagnostic bytes before raising a private typed scheduler request. The
existing driver schedules `@argument.error`, which delegates to its normal
`@get` continuation. No executor or Lua callback runs recursively inside the
formatter. The returned module graph is searched raw to the pinned depth of
two; a callback that also rewrites the registry does not change which actual
getfield result is searched. Known debug call names bypass this lookup.

The lookup phase owns its precise non-yieldable charge: synchronous auxiliary
argument checking may reenter Lua but cannot suspend through a live C body.
Ordinary callback errors replace the pending argument error with the same
error object; host policy still aborts through the original owning driver.
The retained parent frame and its managed detail buffer outlive callbacks,
then reset on normal physical frame retirement/reuse. The typed request is
neither a Lua failure value nor an abandoned Ada activation.

`luaL_typeerror` first publishes any raw string `__name` and its formatted
detail in the actual C scalar window. Name fallback then publishes the
actual target function and getfield key. A completed lookup replaces that
key with its real result. Lua debug inspection therefore observes ordinary
operation values in the original CI; direct representation argerrors do not
invent the type-error detail temporary.

Two independently measured extra ownership defects were required to make
those callback observations correct:

* A native tail call preserves its real Lua caller until the C return. After
  the new callee owns its argument window, the old Lua call request packets
  now retire. Its visible scalar locals, cells and lexical captures remain.
  Keeping the old request rooted retained an operand even after every real
  caller/callee slot was cleared. `Native_Captures` in this path is the call
  request's callee value, not the Lua closure's lexical capture cells.
* A directly called saved builtin pointer has an original public C owner
  and a hidden working phase. On definitive argument failure, the working
  scalar prefix transfers to that original owner before diagnostic lookup.
  Reservation precedes an ascending downward copy; explicit ordering and
  linkage checks protect overlap. The moved rows become the owner's real
  prefix, and only the remaining private source tail retires. The original
  C function slot, close links, cells and live guard remain. The failed
  operation never resumes. All original C slots transfer, including extras
  beyond the builtin's semantic arity; taking a maximum with an obsolete top
  would wrongly resurrect values intentionally removed by the operation.

Copied hidden inputs/captures retire before callbacks can replace actual
locals/upvalues and collect old sole edges. Real closure/upvalue cells stay
owned through the actual callee. These changes move actual execution roots;
they do not synthesize a debug view or suppress hooks.

Pinned evidence is unchanged Lua revision
`7579fc9d7ed90240487251dfb69168f8e64e9294`, especially `lauxlib.c`'s
`luaL_typeerror`, `luaL_argerror`, `pushglobalfuncname` and `findfield`, and
`ldo.c`'s native tail-call lifetime.

## Verification

The fifteen same-source Lua witnesses pass native default and T. They cover
callback count and identity, plain/named C temporaries and bounds, nested
errors, table forwarding, returned nil/non-table/module values, registry
mutation, NUL-rendered names, original third argument indices, direct
representation errors, collection after actual slot mutation, known-name
bypass and rejection of yield. Each is separately named in AUnit; a separate
bounded callback case proves host stop and subsequent session recovery.

The real C builtin consumer preserves its original nineteen cases and adds
five native default/T paired protocols. Their identical shared test header
also runs in fresh counted-provider AUnit states. Saved builtin pointers
preserve their original C CI and actual temporaries, release a C-created
argument after its sole slot is cleared, propagate arbitrary callback errors
without executing later C body code, release a replaced actual C closure
upvalue and preserve extra live C temporaries beyond sin's consumed argument.

The frozen source passes all **2,039 AUnit cases** in each local Ada
configuration, including the fifteen Lua cases, one bounded case and five
actual C bridge cases. The retained public builtin consumer now passes all
twenty-four cases on Ada default/T and native default/T, with complete
counted-provider balance after close. During this component all twenty-three
retained public C consumers passed in each Ada configuration; native-module
images remain a separately configured fixture and were not run bare.

Final default/T static runtime, tests and C builds were replayed serially
under an explicit exclusive build lease, with GNAT 16.1.0, Ada 2022 and every
required warning/style/runtime-check policy retained. No earlier potentially
overlapping build is used as strict-build evidence. The thirty-six retained
four-way compiler/runtime cases pass, as do the new fifteen-case fixture,
both retained thirty-case argument fixtures, both eighty-case operation
fixtures and the seven-case metamethod-root fixture on all four default
compiler/runtime paths with matched stdout and empty stderr.

Unchanged db.lua passes again through loadfile in the disposable original-byte
test tree, with empty stderr and stdout SHA256
`61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`.

Two tool-free one-turn supplied-source Claude Haiku reviews reported no
high-confidence regression (combined reported cost USD 0.0122592). Conditional
questions were checked against inclusive stack indices, actual hidden phase
ownership, the real current C owner, canonical call request captures, nil/
non-table guards and existing charge retirement. The direct C cases and
extra-prefix witness exercise the important invariants independently. These
reviews did not execute tests and are not GitHub/final approval.

## Remaining boundaries

The separately measured borrowed Lua CI scalar view remains assigned to the
hook/window component. This checkpoint addresses ordinary real native C
owners; it does not claim that every callback borrowing an interrupted Lua
frame has passed. Remaining errors.lua diagnostics, unchanged relevant T
api.lua/memerr.lua and every other outstanding full-source obligation still
require their accepted execution/equivalent evidence. Shared/platform and
immutable final-head acceptance remain open. Reference trees and pins are
unchanged.
