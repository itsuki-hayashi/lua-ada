# Native Windows main transport proposal

Date: 2026-11-08, Asia/Tokyo. Author-only work based on
`2d956c25db0fc77dd096ebbae35a2ed3cedba6fb`. Independent source and native
applicability review are pending. This checkpoint changes no production unit,
reference, policy, source mapping or source exclusion. No adapted main.lua was
emitted or run, and no Alire/GPR command was needed.

The [author packet](../../tests/conformance/targets/remaining-upstream-compatibility/main-windows-transport.author-proposal.json)
adds measured transport design to the older
[complete source inventory](2026-11-08-main-cli-windows-inventory.md). It binds
eight actual files and eleven exact original byte ranges. The original main
hash remains
`844d13f96bdbf03a554b8b466fdf21aeac2bcddb907ad2b971814c994898d457`.
The packet cannot approve a source change or credit an original assertion.
The older inventory's dated CLI/implementation bindings remain historical;
this proposal does not renew them.

The [new Lua counterpart](../../tests/conformance/platform/windows-main-cli-transport.lua)
runs real native Lua children through os.execute and io.popen. The
[observer](../../scripts/observe-windows-main-transport.ps1) copies the actual
selected native executable/DLL to a private directory named runtime image,
retains before/after hashes, and runs from another disposable directory. A
space-bearing executable path is an actual test input. The controlled names
exclude shell expansions and metacharacters; the helper is not a universal
Windows quoting function or a Unix shell emulator.

Thirteen authored controls completed in both native configurations:

1. Three actual tmpname calls produce distinct mapped CWD leaves, absent before
   use. No raw drive-root path is opened or written by this counterpart.
2. Actual -v redirection contains the native version.
3. Empty redirected stdin exits with empty output.
4. Multi-line redirected stdin with explicit `- --` prints both values.
5. A real Windows type pipe passes those same bytes to explicit stdin.
6. Unescaped Windows paths fail as Lua literals, while %q preserves their bytes.
7. A real selected script checks negative arg indices, positive arguments and
   typed script varargs after the exact `"-e " --` option sequence.
8. Native SET changes a Lua child's package path without a POSIX env command.
9. Actual -l requires a generated module and the script reads its exact global
   name using a Lua %q literal.
10. Actual stdout/stderr redirection retains both streams' contents.
11. A real failed Lua child returns nil, exit, 1 and its error fragment.
12. Actual io.popen reads the frozen child's configuration and closes cleanly.
13. All owned temporary files are removed; only the frozen fixture remains.

Raw positive campaign:
`reports/windows-main-transport/5fb6ad511b4243098084cbf66b4ec61c`.
Both outer processes exit zero with empty stderr and identical raw stdout
SHA-256 `9af55ff4bcb82db9ef045a9a6357fbaf1b6ccf75c739727e7461abeab780d8db`.
Each configuration has ten real Lua-state sidecars, including its parent and
ordinary children. All twenty carry the actual run/configuration, 2 GiB ceiling,
zero refusals and zero outstanding bytes/blocks. The configuration-only child
creates no Lua state; no sidecar is invented for it. These are native authored
counterpart results, with no new Ada runtime result or whole-main result.

Concrete failed attempts
-----------------------

The packet preserves three failed diagnostic campaigns and does not relabel
them as passing. d09cbc00d0ae46c0a7613a846b95749b passed four controls before
an incorrectly nested quote pair after the type pipe failed. c5712fcb89374fbca1b6c53528974b4d
passed seven before the same extra outer quote pair failed after SET &&.
2059500950144d09818b3782e5da4307 passed eight before native require rejected
the generated module name `.\name.`. Native loadlib.c searchpath replaces dots
in module names with directory separators. Merely prefixing the original
root-relative tmpname with a dot therefore cannot repair main's later -l use.

The successful counterpart quotes a standalone executable with an additional
outer pair, and directly quotes the executable after type-pipe or SET prefixes.
It uses the actual tmpname result, removes its initial root separator and maps
its dots to underscores; it asserts permitted characters, distinct names and
absence before writes. That is a candidate for three main temporary-name
expressions, not the already reviewed Verybig expression and not an installed
main transformation. Generated Lua needs its own escaping: main 240 can express
the global key with `_G[%q]`, and main 260 can express the executable comparison
with `%q`. The actual values and assertions must remain unchanged.

Recommended bounded next work
-----------------------------

First independently review these native results and the three temporary-name
expressions at main 18-20. Then author exact Windows command forms for each
affected source call, retaining actual os.execute/io.popen, child status,
stdin/stdout/stderr and arguments. Keep the generic RUN/NoRun assertion purposes.
Do not parse arbitrary Unix command strings into a replacement language or
replace real Lua children with a forwarding stub. The standalone/pipe/SET quote
distinction requires native positives for every added form. Literal paths and
the module-name substitution are different layers; neither is solved by shell
quoting alone. Original unmodified bytes must stay byte-identical outside any
later independently approved exact spans.

Next measure the remaining environment values, -E, six path separator patterns,
library order/aliases/native module, binary/BOM stdin and real multi-line REPL
input. Native SET of one path is not an empty-environment implementation.
Main 187-190 stores the new child output in local out but compares prior output;
retain that weak original assertion and add any stronger control separately.
Windows echo does not certify the original multi-line shell input. Use actual
native input-byte evidence before choosing exact TYPE/redirection counterparts.

SIGINT and true terminal behavior remain gates. Microsoft documents that
CTRL_C_EVENT cannot target a nonzero process group; group zero broadcasts to
processes sharing the sender's console. A newly created separate console is
available as an isolation boundary. A future test-only broker therefore needs
its own console and actual child identity/pipe lifecycle before sending the
event. This is a design requirement, not an implemented broker or a passing
native interrupt probe. See [GenerateConsoleCtrlEvent](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent)
and [Creation of a Console](https://learn.microsoft.com/en-us/windows/console/creation-of-a-console).
CTRL+BREAK maps to SIGBREAK rather than the requested SIGINT, so a convenient
group-targeted break does not establish main's Ctrl-C semantics. See
[Microsoft's signal distinction](https://learn.microsoft.com/en-us/windows/console/ctrl-c-and-ctrl-break-signals).

The first original interrupt must run the protected loop, print 12, catch a real
interrupt and print 42. The second must enter the original expensive native
string search, receive at least two successful real interrupts, and close its
pipe with the required result. A timeout, TerminateProcess, replacement Lua error
or fabricated count establishes neither outcome. No signal was sent here.
All present streams are redirected, so no true-terminal or readline/history
positive is claimed. Optional-readline native applicability and the actual T
constructor refusal also remain separate pending obligations. No _port, _soft,
whole-block skip or public assertion exclusion is proposed.

Verification and handoff
------------------------

The native observer ran with PowerShell 7.6.9 and the existing separately built
native executable/DLL pairs. It bounds each outer process to 30 seconds and
1 MiB per captured stream, inspects every completion flag and raw output, checks
frozen-image hashes and all actual sidecars, and requires owned-file cleanup.
No native source/build provenance beyond the measured artifact hashes is
invented. The actual config child supplies the reported configuration/ceiling.

[The source guard](../../scripts/test-windows-main-transport.ps1) passes 128
positive integrity checks and fourteen rejection controls. It checks original
byte anchors, all eight source bindings, exact thirteen-case output, both
native images/configurations, raw evidence hashes, all twenty sidecars and
the three retained failures. It rejects authority, mapping, omission, stale
source, altered output, invented review and relabelled diagnostic mutations.
It executes no Lua and is not an independent review or conformance pass.
Root owns the current strict combined builds and final whole-source authority.
