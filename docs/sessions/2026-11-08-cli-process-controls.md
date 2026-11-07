# CLI process controls checkpoint

Date: 2026-11-08, Asia/Tokyo. Remaining compatibility delivery continues.

The CLI parses ordered -e/-l/-W actions, native -v/-i behavior, -E,
versioned initialization and path variables, implicit redirected stdin and
interactive input. Shared native stdio preserves source bytes instead of
Windows text-mode Ctrl-Z truncation. The REPL uses the owned frontend's actual
Incomplete_Input result, with sequential chunk/display drives and traced
return packets. Resolving the current print includes __index. Warning controls
use the actual handler independently of the replaceable warn global. Typed
exit remains a returned host transfer, with disposal before process exit.

Lua.Sessions adds only Execute_Display and Set_Warnings_Enabled for these idle
host operations. Returned Lua objects remain private. The display phases share
the instruction budget and output policy; failure cleanup releases frames and
roots. Six focused AUnit cases exercise result arity, retained values through
collection, environment lookup, error recovery, bounded printer execution and
host warning controls after removal of warn. The embedding and CLI guides own
the public contracts and remaining limits.

A capped Sonnet 5.5 draft was independently inspected by the primary
contributor. Corrections include Ada specs/style, actual LF bytes in generated
chunks, allocator-refusal cleanup, ordinary print lookup, typed completeness
and direct warning controls. Comparing the process protocol against native C
caught a mistaken primary-agent warning-order change: pinned runargs turns
warnings off after LUA_INIT. The final sequence and two exact stderr cases
retain that behavior. No warning suppression or build-policy relaxation was
introduced.

Strict Windows validation/static root, tests and CLI builds pass with
Alire 2.1.1 and GNAT 16.1.0. Root uses alr -n build --validation and
-XLUA_ADA_LIBRARY_TYPE=static; nested builds add
--profiles=lua_ada=validation and -XLUA_ADA_PREBUILT=true. The actual AUnit
runner passes 1,422 cases, zero failed assertions and zero unexpected errors.
scripts/check-cli.ps1 passes 86 isolated Ada processes. Its separately
selected -NativeProtocol passes all 32 corresponding protocols against the
pinned separately built C executable, including interactive stderr recovery.
Captures are reports/remaining-cli-warning-build.log,
remaining-cli-aunit-build.log, remaining-cli-options-build.log,
remaining-cli-aunit.log, remaining-cli-process.log and
remaining-cli-native-process.log. Earlier failed compiles/protocols were
corrected before these final runs and are not counted as passes.

This component worktree includes demand-driven input but predates later debug
and compiler checkpoints. These counts are component evidence. Dynamic prompts,
readline/signals, native loading, registry LUA_NOENV semantics, eliminating the
extra require helper frame and full main.lua remain open. Full-target matrix,
allocation-failure campaigns, PR review and merge are still required.
