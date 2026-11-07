# Compiled declaration probe author design

This is an unapproved source proposal for the remaining target. It installs no
compiled cases, changes no global API classifications and supplies no execution
or coverage authority. The companion JSON binds every original API declaration
and both public-header trees. Its mechanical categories are a review queue.

The first pass contains 228 declaration candidates (18 type anchors and 210
object macro anchors), 157 callable/data entries and 88 function-like macro
anchors. Existing named routes remain visible. All callable public macros
retain a behavioral obligation. In particular, lua_register, lua_insert,
lua_replace, luaL_newlib, luaL_argcheck, luaL_opt, the buffer macros, the legacy
comparison/length aliases and the luaconf numeric/string conversion helpers
cannot acquire coverage from their expansion merely compiling. Token helpers
such as LUAI_TOSTR and l_floatatt need an explicit semantic decision; their
function-like spelling alone neither proves runtime behavior nor grants a
declaration-only exception.

Three probe families are proposed:

| Family | Observations and assertions | Runtime boundary |
| --- | --- | --- |
| Public constants and tokens | Version/signature bytes, statuses, tags, operation numbers, GC/hook selectors, library names and masks, reference sentinels, header guards and stringification | Constants may use compiled evidence. Operations selected by those constants keep actual C/Ada behavioral cases. |
| Callback and aggregate ABI | Scalar widths/signedness/alignment, callback prototype compatibility, sizeof/alignment/offsetof for lua_Debug, luaL_Reg, luaL_Buffer and luaL_Stream; opaque lua_State pointer compatibility | Header agreement complements the existing actual debug, callback, allocator, stream and buffer cases. It does not prove Ada record representation or callback execution by itself. |
| Configuration and definition origin | Selected integer/float types and promotion formats, extra space, ID/buffer sizes, maximum alignment, paths/separators, export/language tokens and active conditional directive origins | Alternative numeric ABIs, C++/DLL modes and compatibility switches require explicit applicability review or actual supplemental probes. A macro name being present cannot identify its selected source branch. |

For each of the 26 contexts, use the exact selected compiler and real native
platform/configuration flags. Compile the same source twice: once against the
first-party public SDK, once against the pinned C headers. Capture compiler
identity, exact arguments, every included header hash, output executable,
execution arguments and complete stdout/stderr. Compare the complete measured
tuple/fingerprint on the same host, and retain independently reviewed fixed
assertions for stable public constants. Pointer/long-double alignment and
platform strings must be measured rather than copied from Windows observations.
No reference library is linked into the Ada implementation by a header probe.

Definition selection needs more than evaluating the lexical inventory's guard
strings. Continued preprocessor directives and chains of elif/else require the
complete original source, and a default definition can later be undefined and
replaced. LUA_KCONTEXT is the concrete example: luaconf.h first defines it as
ptrdiff_t, then may replace it with intptr_t. The proposed native preprocessing
capture must preserve original definition origins and final active definitions,
including undef/redefinition events. The two LUA_USE_POSIX branches and the
float/integer format alternatives likewise need distinct original anchors.
An unconditional earlier definition that is later replaced is not an invented
conditional omission: the source review must account for both its preprocessing
effect and the final effective ABI.

The original C library build, ordinary SDK consumer and unchanged native
fixture compiler have distinct export/include flags. Keep those modes explicit.
In particular, Windows reference internals use LUA_BUILD_AS_DLL and an export
header, while module fixtures use the reviewed forced dllimport header. Do not
claim their LUA_API definitions are interchangeable observations. The T profile
also includes the pinned ltests.h through LUA_USER_H; capture its transitive
inputs without substituting private C layouts for Ada runtime behavior.

The current compiled-witness protocol accepts a source-bound C probe, exact
compile/execution arguments and one independently reviewed output line. Before
installing these families, it needs an explicit SDK/native pairing contract
and a measured tuple protocol (or separate small probes with reviewed exact
lines) that checks both counterpart processes. Source-origin applicability
must bind actual native compiler captures and original directive spans. A
successful compile or a fixed completion marker alone cannot close the queue.

Independent review must decide every one of the 473 semantic classifications,
preserve the original 159 routes and 100 C/94 AUnit predecessor protocols, and
bind all 26 future context routes. Fresh compiled observations and the complete
source/global ledgers remain mandatory for final target acceptance. The author
generator does not populate that final schema or bypass its existing guards.
