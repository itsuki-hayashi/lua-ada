# ADR 0029: Owned file input before public compilation

- Date: 2026-11-08, Asia/Tokyo.
- Status: implemented component; complete target acceptance remains pending.
- Scope: public auxiliary file loading and the shared Lua file/stdin loaders.

## Context

The remaining public file loader needs actual libc filename, errno, stdio and
text/binary behavior. A C stack-local FILE reader would need its own guarded
ownership for every error, host abort and execution transfer. The Ada frontend
already accepts owned or borrowed input and must remain the one parser.
Source-sized temporary storage must use the session's selected allocator.

## Decision

Use a small private File_Inputs component for native stream mechanics and
selected-owner source buffers. A fixed 4096-byte transfer block retains no
input between iterations. The source buffer owns all retained bytes. Close
the owned FILE on every normal or exceptional exit before parsing/decoding;
stdin is borrowed and remains open. Actual C callbacks continue to use the
existing independent guarded reader-based public load implementation.

Open files in native text mode, detect the prepared binary signature, then
reopen binary files in rb. Capture native open/reopen errors immediately.
For read failure, use the pinned final-close errno policy. Share the existing
pure preamble preparation and the same compiler/decoder with Lua loadfile,
dofile, Lua-module loading and the C auxiliary entry. C source-name ownership
is a real stack slot removed after the result, as in pinned lauxlib.c.

Actual stream bytes read charge the bounded session work budget, including a
binary reread that physically occurs. Whole-file source extent is checked
before parsing: a bounded extent failure can therefore precede a syntax
error in that file. These remain uncatchable host limits. Lua-compatible
allocation refusal remains a catchable memory error with owned cleanup.

## Alternatives and compatibility limits

A streaming file reader would reduce whole-file retention but adds native
resource ownership across parser/error continuations. This can be considered
with measured need; the current buffered design retains selected-provider
accounting and contains no second grammar or reference interpreter code.

The public fixed-buffer B mode of lua_load requires the entire first reader
piece and storage surviving everything created from it (pinned manual.of,
the lua_load entry). A diagnostic experiment loading a file with B and then
executing it violated that storage contract and crashed native C after its
stack-local reader went away. The raw failed observation is retained, never
counted as passing coverage. Reproducing those temporary pointer identities
or that crash is not an implementation requirement. Valid persistent-buffer
coverage remains in the public loadbuffer/reader campaigns; no public header
entry, source anchor or ledger obligation is excluded by this decision.

## Verification implications

Require identical-source C cases for file/text/binary behavior, source/debug
metadata, caller stack, native error classes/messages, and each measured
allocation-growth refusal followed by healthy retry and balanced close.
Named binary-safe stdin subprocesses retain raw byte inputs/outputs and child
identities, including bidirectional C/Ada dumps. Check bounded extent/work
abort and immediate disposal without an intervening Lua operation.

A bounded independent Sonnet source review found lone-CR interpreter-line
exposure in the shared preamble. The fix ignores that CR through LF, retains
the existing terminal CRLF pair policy, and adds native and pure Ada cases.
The review ran no tests and grants no full-target acceptance authority.
