# Warning Delivery

Warnings use stderr independently of captured or process stdout. The Lua
`warn` function validates every argument before emitting any fragment, accepts
numeric string conversion and returns no results. Messages follow C-string
termination: embedded NUL ends the current fragment.

The pinned Lua 5.5.1 auxiliary constructor installs its enabled warning handler.
Ada sessions and the CLI follow that default. A bare C `lua_newstate` has no
warning handler. These are distinct states; `lua_setwarnf` with a null callback
removes the handler.

The default handler understands final `@on` and `@off` control messages and
ignores unknown final controls. A continued fragment is ordinary text, including
an `@off` spelling. Enabled messages begin with `Lua warning: `; the last
fragment ends the message with a newline. Custom callbacks receive control
spellings literally and receive their original continuation indicator.

## Ownership and callback boundary

The private `Engine.Emit_Warning` overloads accept either an owned Lua string or
a borrowed, NUL-terminated byte view with an optional owning Lua value. Static
fragments need no owner. No message copy or warning-event allocation is required.

A deferred custom warning occupies an embedded event in its actual origin
frame. That event retains the owning Lua value, callback/data snapshot and
previous event. Nested callbacks preserve their outer message roots. An opaque
activation address and request serial identify each acknowledgment. Frame
retirement releases an abandoned event in reverse order.

The C pump invokes the real `lua_WarnFunction` only after the Ada scheduler
returns. It borrows the current real frame's public stack view without adding
a logical debug frame. Its stack writes remain traced. Reentrant API calls use
the same iterative driver; callback errors return through the C-owned guard.
Public `lua_warning` borrows its caller's C string and snapshots callback data
into the returned action, then invokes the callback from its C wrapper. The
caller retains that string through nested warnings, so this path allocates no
Lua storage.

## Checkpoint evidence

The Windows validation/static checkpoint passes 1,067 AUnit cases, including
eight focused warning cases and three native-stack ownership cases. The actual
C consumer passes 39 cases, including custom control/fragment delivery, nested
warning reentry with Lua API use, a protected warning-callback error and recovery,
and delivery while the allocator refuses all growth without any allocator call.
Those four public C cases pass independently against pinned C Lua.

A separate real C consumer compares constructor/control stderr bytes against
the pinned C DLL: enabled auxiliary construction produces the same 64 bytes on
this host and bare construction produces zero bytes. Reports are
`reports/m3-warning-tests1.log`, `reports/m3-warning-c-consumer1.log` and the
`warning-default`/`warning-bare` C/Ada stderr captures. Other platforms and final
M3 acceptance require their own evidence. This checkpoint does not establish
yieldable C continuations or complete C API conformance.

The later borrowed-driver checkpoint passes 1,085 AUnit cases and retains all
39 C cases. Two actual mixed-language tests now drive deferred warnings from
ordinary Ada execution: one warning callback runs nested Lua `warn` code while
the outer borrowed message remains intact; another throws a registry-rooted
table which Lua `pcall` receives with exact identity. See
[the callback boundary decision](decisions/0013-c-owned-call-boundary.md) for
the driver borrow and uncatchable host-abort behavior.
