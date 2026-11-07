# Shared owned traceback rendering

Date: 2026-11-08, Asia/Tokyo.

## Implementation

The public luaL_traceback export and Lua debug.traceback share a renderer in
the existing private Inspection package. It uses actual logical frames,
borrowed call identities, source lines and tail markers. The C wrapper only
measures a borrowed message with shared-budget charges and dispatches the
operation. It creates no intermediate Lua message or input-sized unmanaged
text copy. No foreign transfer crosses an active Ada frame.

The destination provider owns growing text and matched module-name builders.
Two metered walks count and render frames without stack-sized snapshots.
Filtering of retained error owners charges each comparison. Numeric message
conversion is bounded, C prefixes stop at NUL, and source display scans only
the prefix that can contribute to the bounded identifier. The source context
is borrowed without resuming it, including for an independent destination.
See [ADR 0033](../decisions/0033-shared-traceback-rendering.md).

## Validation and review

Windows validation/static builds passed for the root library, nested tests,
C consumers and CLI in both default and upstream-test configurations. All
strict Ada flags and runtime checks remain enabled. Tool versions were
Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.0. The changed test consumer was
rebuilt in both configurations after adding the final level-cast assertion.

Each local configuration passed all 2,052 AUnit cases. Twenty-two separately
named C cases ran unchanged against native default/T and Ada default/T.
They cover exact messages and nested-frame text, level selection, intact
stack prefixes, inactive/suspended/closed threads, an independent output
state, shared Lua rendering, real allocator refusal and healthy retry,
numeric/NUL/nonstring Lua messages, integer narrowing, deep shortening and
its boundary, and hook origins. Every counted state closes with zero live
provider bytes and blocks. The four stdout files have identical SHA-256:
`fffbae23a240858cea54a024070015f7dc33424f9b7aacd3154e69e6017a23c9`.

Two additional AUnit cases prepare a retained message before reducing host
limits. Actual renderer scanning/copying exhausts the instruction limit or
result string ceiling; Lua pcall cannot turn the host stop into success, and
the same session executes a healthy subsequent chunk.

A focused Sonnet code review identified unmetered filtering and stack-sized
frame snapshots, both removed before final validation. It also identified
the missing Lua-to-C integer cast, now covered by the native-paired cases.
Its possible hook-PC underflow is ruled out by the frame's Positive PC type
and exercised hook case. The review did not run tests or grant conformance
approval. Raw local logs are under `reports/shared-traceback`.

The earlier first-party Debug_Traceback_Level_Range case expected a fabricated
range error for math.maxinteger. The pinned wrapper casts that integer to
C int and returns a message with no frames. The case retains its name and
now requires the native result, also independently checked by the identical
C witness. This corrects a first-party regression expectation; it does not
exclude or alter an accepted upstream assertion.

## Limits and next steps

The synchronous module-name lookup does not yet implement a registry
`_LOADED` metamethod continuation. Its public callback behavior remains a
retained requirement. Integrate the separately tested registry and panic
work, continue unchanged errors.lua and all remaining primary/helper/fixture
campaigns, and collect the final same-head platform matrix and certificate.
No full debug, C-surface, file-level or whole-target acceptance is claimed.
No original source, reference revision, adaptation or exclusion changed.
