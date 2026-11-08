# ADR 0044: Native CLI readline transport

Status: implemented locally; Unix execution and final-context acceptance pending.

The pinned lua.c:452-542 selects optional dynamic readline on Linux, linked
system readline on macOS and a 512-byte fgets fallback on Windows. Using an
unbounded fallback everywhere changes observable prompt counts and omits line
editing, history and the Linux environment/warning behavior. Keep the same
platform selection in CLI-only native transport. The production runtime SAL
and Ada embedding API gain no dependency or public interface.

Linux uses dlopen with RTLD_NOW/RTLD_LOCAL and LUA_READLINELIB, defaulting to
libreadline.so. -E ignores that environment override. Missing libraries or a
missing readline symbol emit the original three warning fragments through
the actual Lua warning API and guarded C portal, then use stdio fallback.
macOS links the system readline API as the pinned oracle does. Windows uses
fgets directly. Do not replace an installed backend with fallback to simplify
captured-output expectations; readline implementations have different pipe
echo/prompt behavior and require same-host C observations.

The optional host dependency supplies native line editing and history.
Alternatives considered are retaining only stdio, implementing an editor in
Ada, or vendoring another editor. Stdio remains the fallback; the other choices
would add a second editor or a mandatory implementation dependency without
matching the pinned CLI selection. No library source is vendored. GNU Readline
uses GPL version 3 or later, as stated in its
[source license](https://gnu.googlesource.com/binutils-gdb/+/master/readline/readline/readline.h).
The supplied host library's license applies; an environment-selected compatible
library or system SDK implementation must retain its own license information.
This decision records the dependency, not a license for redistributing it.
Ordinary runtime-library builds do not need readline headers or libraries.
CLI/test builds use native dlopen on Linux and system readline headers/linking
on macOS; Windows requires neither.

Apple's [libedit header](https://github.com/apple-oss-distributions/libedit/blob/main/src/editline/readline.h)
declares add_history with an integer return, while GNU's API returns void.
The linked macOS branch calls that declared function through a void wrapper
that discards the result, never an incompatible function-pointer cast. Four
strict compile-only cases cover both signatures and product/test branches
using explicitly synthetic declarations; actual SDK builds remain separate.

Ada retains prompt lookup/conversion and its real anonymous C caller. The
converted Lua string stays rooted through synchronous native input; its
existing NUL-terminated payload is borrowed without an input-sized stack copy.
The native backend owns returned input until the Ada child copies its C-string
prefix, removes one final LF and releases it exactly once, even on a host
copying exception. The fallback owns one fixed 512-byte buffer and fgets
retains native text-mode behavior. Explicit whole-stdin loading keeps its
separate binary-safe path. Readline's own editor/history allocations follow
the host library's allocator, as in C Lua; they are not fabricated managed
allocator observations.

Save complete nonempty commands once, after expression/statement selection and
multiline assembly. A synchronous history call borrows a selected-owner,
NUL-terminated temporary buffer; refusal returns normal session memory failure
and never publishes an invalid pointer. No history backend means no temporary
allocation. The readline handle remains loaded through the final history/read
call and process termination. These CLI-only operations are serialized, like
the native readline API, and do not promise concurrent use across sessions.

Three separately named AUnit cases use a test-crate-only C observer to verify
empty history does not allocate/call, actual C-prefix borrowing, and actual
selected-provider refusal followed by healthy history and Lua execution.
The observer hook is absent from product CLI and runtime SAL builds. Paired
process regressions retain exact stdin/stdout/stderr and frozen executable/
library identities for ordinary input, EOF, fallback boundaries, NUL, CRLF,
invalid UTF-8, multiline and library environment/warning selection. These pipe
observations do not establish TTY behavior or final matrix acceptance.
