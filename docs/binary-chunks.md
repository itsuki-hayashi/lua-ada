# Canonical Programs and Binary Chunks

Lua.Prototypes and Lua.Chunks are private, compiler-independent implementation
units. The canonical ownership model and native Lua 5.5.1 codec are implemented;
runtime migration is being integrated and verified under M3. No new public Ada
object handles are exposed. Standalone compiler/codec evidence below does not
establish the runtime migration's acceptance.

The Ada scheduler also executes real canonical words through explicit runtime
continuations. Twenty-five focused canonical runtime cases pass at the recorded
788-case checkpoint, including callbacks, collection, coroutines and closing.
The normal CLI still uses the existing backend pending migration regressions.
These runtime checks are separate from the C-executed compiler campaign below;
neither checkpoint establishes unchanged full-suite execution or final platform
acceptance.

## Ownership and format

A limited controlled Program owns a flat registry of stable prototype nodes,
canonical instruction words, constants, ordered captures, child references and
debug metadata. Byte strings are interned in managed storage; zero is null,
distinct from an interned empty string. All persistent and temporary codec
storage uses the supplied Lua.Storage owner. Close releases every registered
node once, including unattached or cyclic partial construction. Borrowed nodes
and string views must not outlive their program or storage owner.

The codec follows pinned native Lua 5.5.1 headers, integer zigzag/MSB varints,
binary64 bits, instruction alignment, string reuse and debug arrays. It checks
numeric widths and native byte order rather than converting an incompatible
host profile silently. Limits cover input bytes, depth, nodes, instructions,
constants, strings/string bytes and debug entries. Decode reports controlled
format, resource or memory failure and discards partial ownership. Trailing
bytes remain unread; Consumed identifies the end of the decoded chunk.

Encode validates ownership, graph shape, metadata and operand/pair bounds.
Strip omits source names and debug arrays. It retains executable capture
descriptors. [ADR 0012](decisions/0012-canonical-program-ownership.md) records
the alternatives and eventual runtime lifetime requirements.

## Standalone verification

Build the nested tests crate and the separate C oracle before running:

```powershell
alr -C tests build --validation --profiles=lua_ada=validation
pwsh -File scripts/check-chunk-codec.ps1 `
  -Probe tests/bin/static/lua-chunk_probe.exe `
  -ReferenceInterpreter build/conformance/default/bin/lua.exe `
  -Configuration default
pwsh -File scripts/check-chunk-codec.ps1 `
  -Probe tests/bin/static/lua-chunk_probe.exe `
  -ReferenceInterpreter build/conformance/upstream-test/bin/lua.exe `
  -Configuration upstream-test
```

Use the corresponding executable suffix and library runtime directory on each
host. The runner does no Alire builds and can run after a serialized build.
It verifies the pinned reference tree and measured C configuration, records
source/executable hashes, and uses disposable process directories. Each process
has a 60-second timeout and must exit successfully with empty stderr.

The current corpus produces sixteen C chunks across full/stripped forms,
requires byte-exact Ada roundtrips, tests eight additional stripped crossloads,
and lets C execute an independently Ada-built LOADK/RETURN1 chunk. C executes
both sides of the semantic comparison; Ada only decodes/encodes these files.
Results live under ignored reports/chunk-codec directories with raw captures.
Twenty-seven named AUnit cases independently cover the codec, cleanup and
allocation-free program transfer. Move preserves node/string identities while
retokening ownership to the destination; the source becomes empty and reusable.

## Canonical code generation

Private Lua.Canonical_Compiler lowers the successful shared frontend directly
into canonical prototypes. Its lexical maps, jump/loop work lists, constants,
debug records and output use the supplied allocator owner. It borrows frontend
byte strings synchronously and retains no frontend handles. Fixed encoding
limits remain distinct from explicitly configured lowering quotas.

Lowering covers expressions and result adjustment, lexical captures, globals
and _ENV, calls/tail calls, constructors, loops, labels/gotos and closing scopes.
Arithmetic words carry real adjacent metamethod fallbacks. Named varargs use
materialized tables; numeric controls use Lua 5.5's three-slot layout. Last
compile-time const declarations can omit a stack cell. Instruction selection
and optimization choices do not promise the C compiler's exact instruction
streams. Debug PCs and capture descriptors describe the actual emitted words.

After building tests, run scripts/check-canonical-compiler.ps1 with the same
Probe/ReferenceInterpreter/Configuration arguments above, choosing
lua-canonical_compiler_probe as the probe executable. Its 36 named cases compile
source through Ada, let C load and execute the emitted chunks, and compare raw
stdout with C-compiled source in separate C processes. Eighteen focused AUnit
cases cover lowering contracts, semantic limits, host quotas and allocation
transactions. Reports identify this as Ada code generation with C execution;
that compiler-only mode is not evidence of Ada VM execution.

Pass RuntimeProbe with lua-canonical_runtime_probe to require four-way output
agreement: C source execution, C execution of the Ada chunk, Ada execution of
the Ada chunk, and Ada execution of an unchanged C string.dump chunk. All 36
cases passed in the local default/validation/static configuration at the
816-case retained-test checkpoint. The corpus includes closing/error paths,
coroutines, weak collection, environment mutation, fixed/open varargs, binary
strings and extended constructors. reports/m3-canonical-four-way-default.log
and its disposable JSON/process records contain the evidence. Instrumented Ada
and other OS/profile/link contexts still need their own measured runs.

These are standalone codec checks. They do not establish runtime load/dump
support, canonical instruction execution, a whole-file db.lua pass, or complete
upstream conformance. Final M3 evidence still requires the integrated backend,
unchanged upstream files, and every declared platform configuration.
