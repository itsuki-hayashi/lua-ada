# ADR 0045: CLI interrupt lease and safe VM delivery

Status: core implemented and locally exercised with a temporary Docall helper;
the persistent CLI host integration and Unix execution remain pending.

The pinned lua.c:70-87 installs an interrupt hook on the fixed globalL context
and resets SIGINT to its default disposition before requesting the hook. Its
docall region at lines 161-172 starts after successful loading and, for a
selected script, after pushargs. A second signal can therefore terminate a
native operation which has not returned to a Lua hook point. Hooks are disabled
inside active hooks and finalizers. The Ada executor must preserve those
boundaries without an asynchronous callback into Ada or a nonlocal C transfer
across an Ada frame.

The private CLI-only C controller owns the process disposition. Its handler
resets that disposition first, then assigns a pending scalar and restores errno.
The scalar is a C11 atomic int, with a compile-time requirement that int atomics
are always lock-free. There are no Lua calls, VM pointers, allocations, I/O or
longjmp operations in the handler. Synchronous arm/consume/restore operations
are the complete controller protocol. Other C translation units retain C99.
Windows uses the CRT signal disposition; POSIX uses sigaction with no
SA_RESTART and retains the complete preceding action for restoration. An
unsupported atomic representation fails the build rather than silently using
a lock or unsafe signal path.

An explicit controlled Lua.CLI_Interrupts.Lease installs the controller only
around an actual CLI Docall execution. Generic sessions, coroutine drivers,
compilation, prompt input, display print and script argument lookup do not arm
it. The lease records one fixed context and two nonowning world fields. Scalar
publication after successful installation cannot allocate; a signal in that
interval only sets the controller's pending scalar. The lease ends before
Apply_Exit can release the world, on ordinary return, Lua/host failure and typed
os.exit. The previous host disposition is restored, including its POSIX action,
so an embedding test/host does not retain CLI policy after its execution scope.
Installation/reset/restoration failure is an explicit host Program_Error.

The iterative executor consumes the request before an actual Lua word and at
an eligible public return after result publication. The latter matters for
pcall(real_C_raise_callback): the interruption must occur before that pcall
finishes. Private continuation, collector and C-hook transports do not add
hook points. A different current coroutine, active hook or suppressed finalizer
cannot consume the request. Native library loops are intentionally unpolled;
the second signal follows the OS default rather than adding a second polling
interpreter or changing library algorithms.

Delivery removes current hook controls, as native lstop does, then enters the
existing Language_Error/Recover path with 'interrupted!'. The old registry Lua
hook callback is retained, matching lua_sethook(NULL). Source attribution uses
the real immediate public caller, matching the hook's luaL_where(level=1), and
borrows the retained prototype name through bounded Short_Source formatting.
Actual return values are already rooted before delivery. Existing closing,
protected-call, host quota, error-handler and coroutine policies remain the
authoritative execution mechanisms.

Alternatives rejected are calling Ada/Lua from the asynchronous handler,
installing signal policy in every Driver.Start, polling all native loops,
injecting an artificial Lua error from a C signal handler and changing private
hook masks asynchronously. Each either breaks ownership/ABI safety or changes
native docall/second-interrupt behavior. No runtime library or public embedding
API dependency is added; only the CLI and nested test crate link the C leaf.

Local Windows tests use actual raise(SIGINT) and an isolated-console OS broker,
not synthetic pending injection. See the dated
[component record](../sessions/2026-11-08-cli-interrupts.md). Core publication
alone is dormant: a separately owned actual Docall site must hold the lease.
The temporary per-Docall C transport has known extra C hook events and is not
the final persistent host-main integration. No upstream main source mapping,
native T abrupt-teardown waiver or complete cross-platform CLI claim follows.
