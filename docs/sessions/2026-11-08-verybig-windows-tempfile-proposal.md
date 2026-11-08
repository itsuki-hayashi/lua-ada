# Windows verybig tempfile proposal (2026-11-08)

This bounded author checkpoint follows Root's unchanged native default/T
verybig.lua observations, which both fail at original142's io.output(file)
with Permission denied for a current-drive rooted CRT temporary name. The
[original author manifest](../../tests/conformance/targets/remaining-upstream-compatibility/verybig-windows-tempfile.author-proposal.json)
is pending native-platform-equivalent source review. It grants no adaptation,
coverage, whole-file result or native-applicability authority.

Original source SHA256 is
2B6D30C69CBE6974068881108EAE297BDEDD275B429BE8EC614BF5F8EE89707E,
3,724 bytes. The actual expression is original141's os.tmpname(): byte3491,
length12, SHA256
5877A423400935AF8288A4A9D58C43BA23153277ED30FDD2F7448FF190911E7A.
Only that expression is proposed as '.'..os.tmpname(), 17 bytes. The in-memory
3,729-byte preview has SHA256
D973C7A66FD1F4D50EC48C7D2BC49AD2BF8AA3E0DF9CADF7033C52F1E3CE00DC.
It was never emitted or executed. Prefix0/3491 and suffix3503/221 stay byte
identical. The [source author packet](../../tests/conformance/targets/remaining-upstream-compatibility/verybig-windows-tempfile.source.author-proposal.json)
binds those hashes, the counterpart, and exact pinned native source spans.

The pinned non-POSIX loslib.c macro delegates to C tmpnam; os_tmpname returns
its buffer bytes without path rebasing. The selected Windows oracles actually
return rooted names such as backslash-s26bo-dot. This is measured host/image
behavior, not a claim for every Windows CRT. The proposed dot prefix retains
one real os.tmpname call and every leaf byte while selecting a disposable CWD
file. It adds no _port/_soft flag, skip, exclusion, replacement name generator,
assertion removal or output normalization. Every 50,000-entry generator,
original RK/large-program assertion, dofile, remove and return remains unchanged.
The original writes text and has no explicit binary load/dump call; the new
focused counterpart's binary check is additional evidence, not an original
verybig assertion. Full-scale and all-context evidence remains pending.

The [ordinary Lua counterpart](../../tests/conformance/platform/windows-verybig-tempfile.lua)
checks the actual rooted native shape before constructing the dot-prefixed
path. It never opens or removes the raw rooted name. Its read-before-write
requires ENOENT2, so an existing or unreadable local file is not overwritten.
It retains io.output/io.write/io.close, checks exact native CRLF file bytes and
ordinary text-mode reads, loads text with loadfile and dofile, dumps/loads a
binary control, removes the file and confirms absence. The external native
wrapper also asserts its return10. Fresh unique fixture directories retain
only the counterpart source afterward. Initial native execution caught the
counterpart's incorrect LF-only binary-read expectation; the final counterpart
checks native Windows CRLF bytes directly, without rewriting observations.

observe-verybig-windows-native.ps1 copies the selected executable and DLL into
separate frozen default/T directories, verifies each hash before and after
execution, sanitizes ambient Lua controls through the existing runner, and
records exact arguments/environment/raw output and PID/run-bound telemetry.
No native rebuild, Alire or GPR command is run. Existing GPR/C source hashes
are recorded as inputs, not invented actual compile-command receipts. Actual
configuration commands identify C Lua5.5.1, correct default/T adapter presence,
64-bit integers/numbers/pointers and the requested 2,147,483,648-byte ceiling.
The native configuration command creates no state and returns before its
telemetry epilogue; no missing probe sidecar is fabricated.

Fresh unmodified baseline processes each exit1 at verybig.lua142 with rooted
filename Permission denied, before the 50k generated workload. Both raw stdout
hashes are 1A4BD1FEDD99D8D64B87BFE912F5E832D1F1FAA69839B2E90733D9EE01D5BDE5;
the raw stderr/path differences are retained. Actual counterpart processes
both exit0 with empty stderr and exact eight-label raw stdout SHA256
CAA61AE082C361317D4CB6BCD42C6DAFC43DECEA729255487C82120B036D08D2.
Every real Lua workload's sidecar matches its run/PID/configuration/2-GiB limit
and finishes with zero outstanding bytes/blocks. The negative original file
results are diagnostic observations, never passing source coverage.

The [native author observation](../../tests/conformance/targets/remaining-upstream-compatibility/verybig-windows.native.author-observation.json)
binds frozen artifact/configuration/source/script hashes and all raw records.
Ignored captures are
reports/verybig-windows/1de31af7c47549c999b93d7a8e513345. Earlier incomplete
attempts remain diagnostic only. No native-platform-applicability approval or
actual equivalent approval is authored. Native evidence alone does not permit
full transformed emission or execution before independent exact review.

Twenty-four source/rejection checks pass: pinned expression/platform/source,
whole untouched prefix/suffix, real tmpname retention, no widened/second edit,
no flags/authority/evidence, current native/counterpart bindings and pending
review rejection through the actual equivalent resolver. That resolver builds
only in-memory bytes and rejects the absent independent approval. The source
self-test does not launch Lua or write transformed whole-file bytes.

The worktree started clean at7b700a5, retained it under
refs/codex/checkpoints/runtime-gaps/schema4-7b700a5 and resynced to Root4c8fb6c.
Only new verybig proposal/counterpart/scripts/session files are owned here.
Root's heavy allocator units and Suite's adapter work are untouched. Independent
source review, later native applicability review, fresh whole-file/binary and
profile/context matrix observations remain required before any acceptance.

Final checks validate 42 source/raw/frozen content identities, both new
PowerShell parsers, the24 source/rejection cases and the new session link/UTF-8/
LF rules. Git whitespace checks pass. No Alire/GPR, Ada runtime build, transformed
whole-file run or full documentation campaign is claimed by this checkpoint.
