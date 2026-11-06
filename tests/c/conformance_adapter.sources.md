# Test adapter source manifest

Status: implementation in progress; independent semantic review pending.

The source is pinned Lua 5.5.1 commit
`7579fc9d7ed90240487251dfb69168f8e64e9294`, under `references/lua`.
The upstream files remain unchanged. This driver is linked only into test
executables and calls the actual Ada implementation's public C exports.
Pinned `ltests.c` SHA-256:
`62a7015b036d366addd131e4f046f38557d66b8f48aae120e8aad992f3d90199`.

| Driver | Pinned source | Changes |
| --- | --- | --- |
| `userdata` | `ltests.c:1279`, `newuserdata` | Explicit public argument checks instead of auxiliary macros; actual `lua_newuserdatauv`; zero payload bytes. |
| `test_warning` | `ltests.c:85`, `warnf` | Per-state registry-owned userdata replaces static state; public raw global access replaces private locking/auxiliary calls; same controls, fragment bound, unconsumed `_WARN` rejection and unexpected-warning abort. |
| `inspect` | Original Ada adapter boundary | Returns scalars from private Ada inspection before C API publication; no foreign nonlocal jump crosses the Ada inspection call. |
| `nonblock` | `ltests.c:2154`, `nonblock` | Validate real public stream payload/metatable with exported APIs; use actual POSIX descriptor flags; report native errors. Absent on Windows, matching the pinned driver's platform guard. |

Collector color, age, phase, allocation statistics, parameter codec and physical
storage controls use real Ada state. They do not emulate C private layouts.
`T.checkmemory` inspects the real registry, collector lists, heap/code edges,
live activation windows, finalizer queues and allocator headers/accounting.
Its implementation and negative tests still require independent review of the
invariant mapping. `T.nonblock` requires POSIX execution evidence and Windows
counterpart coverage; its absence on Windows does not resolve the guarded
obligation. This manifest does not close those obligations.
`T.ada_emergency_tables` is an explicitly named Ada
counterpart for the C-specific 200-byte emergency allowance, with measured
table storage and actual allocation refusal/recovery. Its source mapping is
pending review in `tests/conformance/equivalents/gc-ada-instrumented.json`.

Upstream license notice (also retained in the pinned public `lua.h`):

Copyright (C) 1994-2026 Lua.org, PUC-Rio.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
