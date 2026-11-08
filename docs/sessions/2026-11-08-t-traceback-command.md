# Public T traceback command

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

The first-party runC driver now recognizes the pinned traceback command and
delegates directly to luaL_traceback on the addressed real state. Existing
message-token and dynamic-number parsing remain shared. No frame rendering,
private C layout, interpreter operation or result fabrication is added to C.
The source manifest now inventories 97 implemented command names; that count
is an implementation inventory, not whole-file conformance evidence.

Three separately named AUnit and Lua witnesses cover a quoted message and
actual testC frame, a dynamic stack-supplied out-of-range level, and a
suspended addressed coroutine whose continuation still resumes correctly.
All three pass with original native T. The identical first-party C driver
also compiles with strict GCC 13.2.0 flags and passes the three witnesses
against both separately built native configurations.

On isolated base 1b5ef46, all four final serialized default/T tests/C refreshes
pass using Alire 2.1.1 and GNAT 16.1.0 with required warning, style and runtime
checks. Both configurations pass all 2,301 AUnit cases, including the three
new cases, and both existing 22-case public traceback C consumers pass.
The default ordinary runner keeps T absent; default adapter behavior here
is exercised by its explicitly installed AUnit fixture. The instrumented
runner executes all three Lua witnesses. No T-absent skip is credited as a
passing command witness.

Each witness also passes all four native/Ada producer/VM roles under the
instrumented configuration, with empty stderr and matching raw stdout:

| Witness          | SHA256                                                           |
| ---------------- | ---------------------------------------------------------------- |
| Current command  | B0C78DAF0543041A8BDCD6D9B918B2228A8C1F5151CD745C4B01C73E551D8A46 |
| Dynamic level    | EEC1807AB3338D2B3647AD6D3F7AC7CFF4AADBD35E6DFD9F23B067F33D8D5901 |
| Suspended thread | 3BD150DF13504358EEAF32B0DAAE4DDA3949BCC73350802AA7035691C1AEEE81 |

This checkpoint changes the thin test driver and its regression coverage.
It does not change production runtime code, reference sources or their pins,
and does not certify all of api.lua or memerr.lua. The latter still exposes
fresh call-record and return-packet allocations under the original zero-growth
entry condition. Reusable metadata capacity and actual scalar return delivery
are the next owned runtime obligations; no limit, warmup or assertion is weakened.

Changed-document UTF-8/LF, link/table checks and git diff whitespace checks pass.
The full documentation check is blocked by the isolated checkout's missing
tests/modules/busted/busted-scm-1.rockspec fixture; it is not reported passing.
