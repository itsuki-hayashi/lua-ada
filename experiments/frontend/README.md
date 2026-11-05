# Frontend and Opcode Oracles

These test-only adapters inspect unchanged pinned Lua 5.5.1. Production
projects do not import them. C error unwinding stays inside the oracle process.

Build from the root Alire environment:

```powershell
alr exec -- gprbuild -P experiments/frontend/frontend_oracle.gpr
alr exec -- gprbuild -P experiments/frontend/opcode_oracle.gpr
```

frontend_oracle takes lex or parse followed by a source filename. Parse only
compiles source through luaL_loadbufferx; it never executes it.
Lex reports token IDs, scanner lines, hex byte payloads, decimal int64 values,
and binary64 bits. A lexical failure preserves preceding token records.

For bounded byte campaigns, batch takes a text file containing one hex-encoded
source per line. It creates an independent protected Lua state for every case
and emits END delimiters. lexer_probe --batch consumes the same format.
An empty line represents empty source. The C adapter bounds batch lines to
4,095 source bytes; file mode bounds source to 1,000,000 bytes.

opcode_oracle reports the pinned baseline, all 85 name/metadata entries, and
4,096 deterministic instruction words with decoded fields/top predicates.
The Ada lua-opcode_probe uses the same ASCII report protocol.
These executable names have the platform's usual executable suffix.

All reports are test protocols, not public embedding interfaces or binary
chunk readers. Upstream copyright notices remain intact. No ecosystem fixture
is used as an implementation reference.
