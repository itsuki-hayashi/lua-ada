# M2b: Core Libraries and First Upstream Execution Passes

Accepted: 2026-11-06, Asia/Tokyo. Status: **in progress**.
Baseline: merged M2a at master commit 8c001ad.

## Target

Deliver a broader reusable scripting runtime and pass three unchanged Lua
5.5.1 primary test files: tpack.lua, utf8.lua, and bitwise.lua. The latter
loads unchanged bwcoercion.lua as a dependency; it is not a fourth suite.

The reference remains commit 7579fc9d7ed90240487251dfb69168f8e64e9294,
default contextual global declarations, int64, binary64, and ASCII classes.
No selected upstream source or consumer module fixture may be edited.

## Deliverables

- Core metatable dispatch: index/newindex/call, arithmetic/bitwise/unary,
  length/concatenation/comparison, tostring/pairs, metatable protection, and
  applicable type names. Raw functions bypass these handlers.
- Per-session string metatables with standard arithmetic conversion handlers;
  primitive bitwise string rejection remains until user Lua handlers install
  coercion, as the unchanged bwcoercion module does.
- Resumable native continuations and traced native closures, supporting Lua
  callbacks without recursive VM invocation or restarted execution budgets.
- All string library functions except dump; complete Lua patterns, replacement
  callbacks/tables, format conversion, and binary pack/unpack/packsize.
- Full UTF-8 library, including Lua 5.5 offset result pairs and lax extended
  encodings.
- Table concat/insert/remove/move/pack/unpack and the selected math subset:
  abs/ceil/floor/fmod/max/min/modf/tointeger/type/ult, huge/pi/integer limits.
- getmetatable/setmetatable/xpcall and text load/loadfile/dofile/require.
- Lua-only package loading with real preload and file searchers, loaded and
  preload registries, searchpath/config, and mutable local package.path.

The default local path is ./?.lua;./?/init.lua. Native loading, installed-prefix
paths, and environment-based package initialization remain later work.
Coroutines, userdata, weak/finalized objects, closing, goto/labels execution,
debug facilities, binary chunks, table.sort/create, remaining math, canonical
opcode execution, full C ABI, and LuaRocks are not M2b claims.

## Gates and work identifiers

- M2B-FND-001: scope, disposable upstream runner, native C layout evidence,
  and the unchanged 349-case baseline; depends ACCEPT-002.
- M2B-VM-001: native continuation frames/closures, roots, errors, tail calls,
  recovery, and unified work charging; depends M2B-FND-001.
- M2B-META-001: pinned core metamethod behavior and string handlers;
  depends M2B-VM-001.
- M2B-STR-001: string/pattern/format helpers and callbacks;
  depends M2B-VM-001 and M2B-META-001.
- M2B-BIN-001: portable packing and UTF-8 helpers; depends M2B-FND-001.
- M2B-LOAD-001: text loading, environments, package state/searchers;
  depends M2B-VM-001 and M2B-META-001.
- M2B-LIB-001: table/math helpers and default registration/reset;
  depends M2B-META-001 and M2B-LOAD-001.
- M2B-ACCEPT-001: all delivered features, focused tests, three unchanged files,
  complete platform matrix, evidence, and open PR; depends every item above.

Each item remains open until its actual evidence is recorded. Helper source
existence, a built test program, or a generated harness is not a passing gate.

## Provisional local evidence

The integration owner's Windows development/static run recorded 439/439 AUnit
cases passing in reports/m2b-aunit.log. The disposable driver subsequently
recorded all three primary files passing in reports/m2b-upstream.log with
the unchanged 1,000,000-instruction profile and 120-second timeout.
These are work-in-progress results, not final-revision acceptance: additional
table-event tests and native-loop accounting were added afterwards. Required
final checks and platform jobs must be rerun before closing any gate.

## Test protocol

scripts/check-upstream.ps1 copies all four selected sources into a new ignored
disposable directory for each primary file and verifies SHA-256 equality.
Independent C and Ada processes run each file with the same working directory
and package.path. No _soft/_port/_U/_nomsg flags are set, and T must be absent.
Ambient LUA_INIT/path settings are removed from child environments only.

Require successful exit, empty stderr, byte-identical same-host stdout, and
the file's final OK/ok marker. Preserve raw output and copied sources under
reports/upstream for failed-case diagnosis. A 120-second wall timeout,
resource exhaustion, or process failure fails acceptance rather than skipping
the file. The harness never invokes all.lua or a consumer-module suite.

Use the normal 1,000,000-instruction budget first. A measured instruction-only
exhaustion may justify the explicit 20,000,000-instruction runner profile;
record it per file, do not silently retry, and preserve product defaults.

The dedicated upstream_runner uses only the public Session API. It owns one
universe per process and accepts an explicit bounded budget. Bind it with -Wb
for Lua byte output, consistent with the CLI's existing policy.

## Portability and safety acceptance

Verify native packing sizes/alignment against the isolated C99 host probe,
including long double in LUAI_MAXALIGN. Windows long need not have Unix long's
size. Virtual packsize calculations do not allocate; semantic integer/format
overflow must remain a catchable Lua error before allocation quota checks.

Run meaningful separately named AUnit cases, API/CLI consumers, and existing
regressions in all Windows/Linux/macOS x development/validation/release x
static/shared configurations. Each must execute the three primary files.
Static-validation on each OS adds layout/differential campaigns and existing
ABI probes; Windows additionally retains static-PIC acceptance.

Keep strict warning/style switches and runtime checks. Explain continuations,
ownership transitions, pattern state, format validation, and compatibility
choices in code. Optional GNATdoc rendering, GNATtest generation, fuzzing, or
proof must not be reported as performed unless their results were inspected.

The milestone closes only when every gate has evidence on the final PR
revision. Three file passes are not complete Lua-suite or runtime conformance.
