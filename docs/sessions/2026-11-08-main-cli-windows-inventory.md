# Windows main.lua CLI inventory

Date: 2026-11-08, Asia/Tokyo. Read-only author proposal at
`d3a3fd721b58f0a575d242962edb768ecddee9af`; independent review is pending.
The preserved checkpoint is refs/codex/checkpoints/runtime-gaps/verybig-d3a3fd7.

The [author inventory](../../tests/conformance/targets/remaining-upstream-compatibility/main-cli-windows.inventory.author-proposal.json)
partitions all 600 lines of the pinned main.lua into 47 byte-bound blocks and
indexes all 112 literal Title definitions in
[the CLI harness](../../scripts/check-cli.ps1). Every relation is to separate
authored input. No relation grants coverage of an original assertion or grants
source, adaptation, native-applicability or runtime authority. No new Lua
execution, transformed source, source mapping, exclusion, build or policy
installation is included. This is a plan for M3-11 and M3-12, not acceptance.

The primary hash is
`844d13f96bdbf03a554b8b466fdf21aeac2bcddb907ad2b971814c994898d457`
at reference pin `7579fc9d7ed90240487251dfb69168f8e64e9294`.
The inventory binds 26 reference, implementation, harness and documentation
files. The seven inspected CLI/session/stream source files also match Root
0570ce8 byte for byte at inspection. Root's allocator-observer/host-ceiling
changes are separately owned, uncommitted and outside this packet.

The retained [original baseline](2026-11-08-main-cli-native-baseline.md)
fails every native/Ada default/T role at RUN line 67, from redirected -v at
line 81. Its actual names begin with a backslash and no drive; cmd.exe reports
Access is denied. That dated observation is the only original runtime evidence
used here. It does not establish a later assertion, whole result tuple, module
run or interrupt protocol. The Verybig proposal is separate and its exact
12-byte expression cannot be imported as authority for main.lua.

Static CLI control selection
----------------------------

The full harness has two unconditional clean-default captures, 91 other cases
and 19 prompt cases: 112 definitions. NativeProtocol selects 38 named cases
plus the 19 prompt cases and the two captures, or 59 definitions. PromptProtocol
selects the 19 prompts and those two captures, or 21. These are static selection
counts, not newly executed or passing totals. The dated prompt checkpoint owns
the reported 112/112 product results and the failed native T no-close diagnostic.

Every process uses UseShellExecute=false, an explicit ArgumentList, a private
fixture directory, redirected stdin/stdout/stderr and a 30-second timeout.
The harness decodes its captured streams as text. It therefore supplies no true
terminal evidence and does not test cmd.exe parsing, main's os.execute/io.popen
wrappers, raw final-process byte capture, or per-child conformance telemetry.
Its 112 controls also include project-only --check/help/version and independent
resource-policy checks. Those extra controls do not fill missing main assertions.
The JSON lists every exact case title and line, including unmatched controls.

Complete source-block map
-------------------------

Cnnn below abbreviates CLI-nnn in the author inventory. A dash means no one
of the 112 controls checks that block directly. Every row remains pending
original-source execution; related controls can have narrower inputs or
expectations. The JSON preserves the exact differences, classifications, byte
offsets, lengths, hashes and reciprocal control edges.

| Main lines | Source block             | Related authored controls                |
| ---------- | ------------------------ | ---------------------------------------- |
| 1-17       | preconditions            | -                                        |
| 18-21      | temporary paths          | -                                        |
| 22-30      | executable identity      | C019                                     |
| 31-78      | helpers                  | -                                        |
| 79-85      | version                  | C052                                     |
| 86-102     | stdin files              | C010, C011, C017                         |
| 103-129    | bom                      | C021, C027, C028                         |
| 130-133    | dash option              | C017, C018                               |
| 134-173    | path init environment    | C064, C067, C068, C069, C077             |
| 174-199    | ignore environment       | C001, C002, C070, C078                   |
| 200-215    | readline library         | -                                        |
| 216-237    | path expansion           | C001, C071, C072, C073, C074             |
| 238-249    | library order            | C054, C055, C056, C058                   |
| 250-255    | versioned native module  | C054, C055                               |
| 256-268    | argument table           | C018, C019, C020                         |
| 269-273    | argument library         | C019, C054                               |
| 274-278    | mutable argument table   | -                                        |
| 279-282    | repl print error         | C090, C091                               |
| 283-286    | debug console            | -                                        |
| 287-296    | local warnings           | C088, C082                               |
| 297-320    | warning fragments        | C059, C060, C061, C062, C063, C065, C066 |
| 321-330    | finalizer warnings       | C008, C009, C007                         |
| 331-362    | reentrant finalization   | C007, C008                               |
| 363-367    | many arguments           | C018                                     |
| 368-370    | attached actions         | C014, C015, C016, C056                   |
| 371-380    | empty prompts expression | C096, C082, C083, C084                   |
| 381-384    | long string repl         | C096, C084                               |
| 385-389    | repl eof                 | C086, C089                               |
| 390-397    | custom prompt            | C094                                     |
| 398-407    | default prompt           | C082                                     |
| 408-422    | converted prompt         | C101                                     |
| 423-437    | error message handler    | C029                                     |
| 438-457    | broken lines             | C083, C084, C096                         |
| 458-465    | preambles                | C026, C027                               |
| 466-470    | open file shutdown       | -                                        |
| 471-476    | banner terminator        | C052, C093                               |
| 477-489    | exit status              | C003, C004, C006, C007, C092             |
| 490-503    | main closing             | C007                                     |
| 504-508    | temporary cleanup        | -                                        |
| 509-520    | invalid options          | C031, C032, C033, C034, C079, C028       |
| 521-524    | t startup refusal        | -                                        |
| 525-536    | t warning store          | -                                        |
| 537-547    | warning errors           | -                                        |
| 548-552    | progress                 | -                                        |
| 553-579    | protected interrupt      | -                                        |
| 580-599    | native loop interrupt    | -                                        |
| 600-600    | completion               | -                                        |

Source findings and implementation priorities
---------------------------------------------

1. Review temporary paths and the two distinct quoting layers first. Main
   lines 18-20 create three actual temporary names; lines 64-76 interpolate shell
   commands. Lines240 and260 also put prog/progname into quoted Lua literals
   without %q. Windows backslashes can become invalid escapes, even after
   rooted paths are made relative. A native counterpart must prove absent
   disposable filenames, actual calls and children, argv containing spaces and
   backslashes, original success/failure values, exact streams and cleanup.
   No exact replacement has been authored or approved by this inventory.
2. Measure and then repair the actual mutable-arg obligation. Pinned lua.c
   lines 251-274 reads the current global arg, checks its table type, obtains
   length through luaL_len and pushes raw integer elements before calling the
   already selected script. Current Lua_CLI lines 776-784 instead passes
   Arguments_After into Sessions.Execute, which makes strings from host argv.
   This does not implement main lines 274-277. A private child/driver operation
   should preserve actual Lua values and callback/root/error behavior; no Lua
   shim, stringification or new public values API is proposed. This source
   finding has no new runtime observation yet.
3. Batch and REPL message handling need their own native-paired component.
   C lua.c lines 142-170 runs __tostring on nonstring errors through a real C
   message-handler activation and appends a traceback on its fallback path.
   Current CLI Report only formats Sessions.Failure_Image text with source
   and line. Main lines 423-435 checks both actual ancestry/currentline and a
   type fallback. Generic runtime-error and fatal prompt-error controls do
   not establish these assertions. Preserve actual error identity, C ancestry,
   string/NUL rules, REPL recovery and the native program-name distinction.
4. debug.debug is a real missing public library function, not a Unix shell
   exemption. Library_Openers lines 122-126 does not export it. ldblib.c
   lines 423-434 reads commands, reports errors, resumes at cont and uses the
   source =(debug command). Manual lines 9156-9167 specifies the interactive
   behavior. Implement only after native command/error/stdio observations
   and an explicit continuation plan; no recursive executor or wrapper that
   substitutes the product REPL.
5. Preserve T startup refusal and warning storage. Main lines 521-535 must
   execute under actual T. Native ltests.c reads MEMLIMIT on its first
   allocator call, so MEMLIMIT=100 tests state-construction refusal. No
   MEMLIMIT handling exists in the inspected Ada paths, and the test Configure
   hook runs after Session construction. The parent's host hard-ceiling
   correction is a different obligation. A post-creation T.alloccount cannot
   establish native constructor behavior or failed-construction cleanup.
6. Fill the remaining focused loader/module/warning/lifecycle controls, then
   replay the actual reviewed source. The inventory identifies all BOM cases,
   six separator patterns, multi-library caching, lib2-v2 -l, finalizer errors,
   reentrant state close, open-file flushing, EOF continuation, long/broken
   input, invalid options and both warning-error assertions. The actual native
   module image must match its executing host; .so is a fixture convention,
   not proof that a PE image with that extension is intrinsically unloadable.
7. Review optional-readline applicability independently before a Windows
   source equivalent. Main lines 200-213 guards only on release, but lua.c
   lines 459-544 has three different paths: linked readline, dynamically loaded
   readline, or stdio fallback. The warning occurs only in the dynamic path
   requiring LUA_USE_DLOPEN and LUA_READLINELIB. The current Windows GPR and
   luaconf.h select DLL support and stdio fallback. Linux selects the dynamic
   path; macOS selects linked readline. The release check alone does not
   establish a positive warning on every platform. Preserve warning/fallback
   and -E semantics where native uses the facility. No eligibility or
   omission is installed, and whole-file _port would erase real obligations.
8. Signals and terminal behavior remain real gates. Actual terminal detection
   is implemented through _isatty/isatty and selects banner/REPL versus batch
   stdin. Its true-terminal behavior has no evidence in the always-redirected
   112 controls. Readline/history is a separate unimplemented facility. No
   production SIGINT bridge exists. Native lua.c sets a hook on the first INT,
   restores the default handler and raises interrupted! at the next Lua hook.
   Main's first child must print 12, catch the real interrupt and print 42; its
   second must enter the actual expensive string search and need at least two
   successful signals before pipe closure. Windows counterpart design must
   preserve real targeted console/process-group delivery, PID acknowledgement,
   shell/pipe/wait results, deadlines and cleanup. A taskkill, short timeout,
   fabricated kill count, catchable Lua error or replacement search is not
   equivalent. Native positive behavior must precede any applicability claim.

Two source/document traps remain explicit. The empty-environment child at
lines 187-190 assigns its output to local out but compares the earlier output
variable. Preserve those assertions rather than silently credit a stronger
empty-environment equality. Additional meaningful first-party controls can be
added separately. Also docs/cli.md still says registry LUA_NOENV and native
modules are deferred. The actual package operation in Machine lines 4672-4683
sets the real registry value and calls Native_Modules.Configure_Paths. Do not
repeat those stale implementation-gap claims; the extra Lua -l helper frame
remains real at Lua_CLI lines 592-601. An existing implementation is not evidence
that main's particular native module or environment assertion ran.

Counterpart ordering and review boundary
----------------------------------------

The JSON supplies nine bounded priorities, each with source-block identities
and a required positive native gate. First review path/literal handling and
small explicit argv/environment/stdin controls. The actual mutable-arg,
message-handler, debug console and T constructor gaps then have independent
native observations and narrow runtime design checkpoints. Preserve every
remaining warning/lifecycle/module assertion while reviewing transport. Treat
optional readline, true terminal input and both real signals separately; they
are not a wholesale main exemption. The final protocol still requires the
original or independently approved exact whole source, the final OK, zero
returned values, real matching children/modules, both interrupt outcomes, and
clean closure in every required role. Old source authority cannot silently
cover a newly authored transport or product implementation.

Validation and limits
---------------------

[The source validator](../../scripts/test-main-cli-inventory.ps1) parses the
PowerShell AST without invoking the harness. It checks all 26 source identities,
all 112 actual Titles/locations and selections, reciprocal edges, all 47 hashes
and a gap-free byte partition through main line 600. Fifteen negative controls
reject changed source, counts, authority, selection and graph edges. These
checks provide source-index integrity only. They are not Lua conformance or
independent feature review. No Alire/GPR, new Lua process, adapted main source,
policy installation, reference mutation or original test skip occurred.
