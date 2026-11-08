# Runtime numeric locale checkpoint

Date: 2026-11-08, Asia/Tokyo. Remaining upstream implementation continues.

The runtime now supplies the actual native decimal-point byte to the shared
exact number parser. Base-zero string conversion accepts that point and the
ordinary dot; explicit-base integer conversion remains unchanged. The source
lexer and public Ada number parser retain their dot-only default. The consumed
point travels into exact rational rounding without a transformed input copy.
The pinned C alternate-dot retry's 200-byte limit remains observable under a
non-dot locale, even though the Ada parser needs no retry buffer.

Eight separately named AUnit regressions cover comma decimals, dot fallback,
hexadecimal midpoint rounding, mixed/repeated point rejection, explicit bases,
default parser isolation, and long alternate-dot refusal. Temporary limb
ownership is checked after conversions. A capped Claude Haiku 5.5 draft was
reviewed and corrected by the primary contributor; the final native-separator
and retry-limit decisions follow pinned lobject.c l_str2d/l_str2dloc and the
existing locale bridge, not invented locale availability.

Strict Windows validation/static root and nested test builds pass with
Alire 2.1.1 and GNAT 16.1.0. Commands: alr -n build --validation with
-XLUA_ADA_LIBRARY_TYPE=static at root; the nested tests additionally use
--profiles=lua_ada=validation and -XLUA_ADA_PREBUILT=true. The actual runner
passes 1,418 cases, zero failed assertions and zero unexpected errors. Captures:
reports/remaining-locales-build.log, remaining-locales-tests-build.log and
remaining-locales-aunit.log. An initial declaration/body default mismatch was
corrected before these successful runs; strict switches remain enabled.

This component worktree predates the shared streaming frontend and later debug
checkpoints. Its test count is component evidence, not integrated final-head
evidence. Full unchanged literals.lua, relevant instrumented paths, remaining
files, native modules, matrix reconciliation, PR review and merge remain open.
