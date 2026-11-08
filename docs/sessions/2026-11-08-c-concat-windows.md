# Public C concatenation windows (2026-11-08)

This component follows the transferred metamethod argument ownership
checkpoint. It repairs actual C `lua_concat` operand slots; it does not close
the remaining upstream, relevant T, shared/platform or final-head gates.

## Behavior and ownership

The previous C preparation copied every operand into a new argument packet,
popped the real C slots and called a private helper with those copies. Lua
handlers therefore could not inspect or replace a not-yet-consumed operand
through the original C caller, and consumed copies remained extra GC roots.

`Foreign.Prepare_Concatenation` now folds primitive suffix pairs directly in
the original scalar interval. A handler continuation captures only its first
absolute slot and remaining count. Its own temporary callable window retires
before the handler runs. After each handler, the result replaces the real
left slot, the public C top shrinks and the next pair is read afresh. The
existing request-packet transfer then removes private argument copies once
the actual Lua/C handler owns its inputs. C glue drives the zero-argument
continuation and publishes its result over the consumed interval; it contains
no interpreter operation or recursive Ada executor entry.

Primitive folds charge the existing bounded driver and preserve string-byte
limits. Ordinary empty short-string joins reuse the adjacent string object
without a heap growth request. External empty strings deliberately follow
the copy path, as pinned `lvm.c`'s `isemptystr` excludes external strings.
Zero operands append an empty string; one operand preserves its type/object.

Pinned sources are `lapi.c:lua_concat`, `lvm.c:luaV_concat` and `isemptystr`,
and `lstring.c:luaS_newextlstr` at unchanged Lua pin
`7579fc9d7ed90240487251dfb69168f8e64e9294`.

## Verification

GNAT 16.1.0 strict default and upstream-test static runtime, nested tests and
public C consumer builds passed with all required flags and runtime checks.
Both configurations passed all **1,979 AUnit cases**, including eighteen
independently named public C concat cases and three separately named bounded
primitive-loop/result-extent/handler abort-and-recovery cases.

The identical eighteen-case C99 source passes Ada default, Ada T, native
default and native T. It covers original caller identity, future operand
mutation, per-fold public local bounds, preserved prefixes, overwritten and
consumed weak operands, clearing current pair roots inside its handler,
primitive suffix publication, numeric conversion, zero/one operand behavior,
both ordinary empty-string zero-growth refusal shortcuts, both external
empty-string copy directions, zero-result handlers becoming nil, unchanged
numeric metamethod arguments, error object identity, recovery and the real
non-yieldable C barrier. Each case owns a fresh counted-provider state and
checks complete post-close block/byte balance.

Twenty-two retained public C consumers pass in each Ada configuration; the
native-module consumer remains a separately configured image fixture and
was not run bare. The thirty-six retained four-way compiler/runtime cases
pass. Both eighty-case operation fixtures, both thirty-case argument
fixtures and the seven-case metamethod-root fixture pass all four default
compiler/runtime paths with equal stdout and empty stderr.

Unchanged db.lua again passes through loadfile in a disposable original-byte
test tree, with empty stderr and stdout SHA256
`61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`.

A tool-free one-turn supplied-diff Claude Haiku review found no
high-confidence regression (reported cost USD 0.01158615). Its conditional
zero-result concern was resolved against the existing nil-on-empty `First`
helper and an independently native-proven new test. The real top setter
clears vacated slots, New_Native copies its captures, and host abort tests
exercise retirement-before-error. The review did not execute tests and is
not GitHub/final approval.

## Grouped primitive followup

A separately native-proven real-provider case established that pairwise
materialization was also a public storage problem. It supplies 4,096 already
existing string slots, then permits thirty-two further growth requests.
Native default/T succeed; the original Ada pairwise path fails with the
actual `not enough memory` error after the first eighteen cases pass. This
is a bounded construction allowance, not an assertion of native pool order,
capacity or exact allocation counts.

Primitive runs now convert original scalar operands from right to left and
publish each number conversion immediately, matching `luaV_concat`. A managed
builder collects the whole convertible suffix and publishes one result.
Immutable borrowed byte views avoid input-sized Ada String temporaries; the
original actual slots own all operand roots throughout emergency collection
and result allocation. Ordinary empty-string shortcuts still require no
growth. The builder uses the existing one-emergency-collection retry policy,
and both operand scans and actual copied bytes charge the owning driver.

The new growth-bound case passes Ada default/T. A separate actual one-shot
provider refusal succeeds after retry in all four native/Ada configurations,
and another named case checks NUL-bearing runs with numeric conversion and
an untouched prefix. A fourth new bounded case proves byte-copy work itself
can stop a two-operand concat and preserve host recovery/complete cleanup.

All **1,983 AUnit cases** pass in each local Ada configuration. Strict
default/T runtime, tests and C builds pass with no policy/flag relaxation.
All twenty-one identical public concat C cases pass native default/T and
Ada default/T, and all twenty-two retained public C consumers pass in each
Ada configuration. The borrowed Lua CI gap below remains independently open.

## Remaining boundaries

An independent same-C-source external deallocator probe now demonstrates a
broader borrowed Lua CI gap. Automatic GC during a Lua allocation invokes
the deallocator with a real interrupted Lua frame. Native default observes
top four, appends three operands, concatenates while inspecting/mutating the
actual temporary slots, and restores its original top. Current Ada observes
top zero and errors. This is a required public stack-view followup, related
to the separately measured custom C hook scalar-view gap; it is not eligible
for a private-internals exclusion. No passing borrowed-Lua-CI claim is made.
Native T's lock rejects external allocator API reentry, as recorded by the
existing external-string fixture's explicit instrumentation skip.

The registry `_LOADED` fallback callback continuation, remaining source/T
files, locals.lua progress output policy, full shared/platform matrices and
immutable final-head acceptance remain open. Reference bytes and pins are
unchanged; `git diff --check` passes.
