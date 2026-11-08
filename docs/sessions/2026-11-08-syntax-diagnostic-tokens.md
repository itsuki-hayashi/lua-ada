# Source-linked syntax diagnostics

Date: 2026-11-08, Asia/Tokyo. Remaining delivery remains in progress.

The shared owned parser now reports actual token context for syntax errors:
fixed token spellings, original numeral text, decoded quoted/long-string
tokens including delimiters, and pinned control-byte notation. Diagnostic
construction uses the compilation owner's byte buffer and borrowed text views;
it neither rereads a callback nor creates a second grammar. Embedded NUL ends
the diagnostic token as C txtToken does, while the actual token remains binary
safe. Structured Incomplete_Input remains distinct from diagnostic wording.

Binding/attribute/goto semantic failures omit near-token text like
luaK_semerror. Goto and duplicate-label messages retain the original source
line; saved statement sites precede token advancement. Invalid break is checked
before consuming its actual token. Default string-load syntax errors use the
shared bounded chunk identifier, while reader loads retain =(load). Lua load
names truncate at their C-string NUL without truncating counted source bytes.

Canonical fixed return count now checks B=count+1 before field packing:
254 values compile/execute, while 255 produce the semantic too-many-returns
diagnostic. This preserves the actual encoding boundary rather than reporting
an internal Ada field error. Valid-source checking remains separate from
canonical encoding limits.

Sixteen separately named AUnit cases and tests/lua/syntax_diagnostic_tokens.lua
cover these behaviors. The Lua witness passes against actual Ada and both
pinned default/instrumented C executables with identical output. Strict Windows
validation/static root and tests builds pass with Alire 2.1.1 and GNAT 16.1.0.
Root uses alr -n build --validation with -XLUA_ADA_LIBRARY_TYPE=static after
the GPR separator; nested tests add --profiles=lua_ada=validation and
-XLUA_ADA_PREBUILT=true. The full runner passes 1,534 cases, zero failed
assertions and zero unexpected errors. Captures: reports/remaining-syntax-
diagnostic-{build,tests-build,aunit,native,native-instrumented,ada}.log.
Initial strict compilation caught a shadowed Varargs enum literal and a dynamic
discriminant aggregate; both causes were corrected without relaxing checks.

Unchanged calls.lua now reaches OK in a direct unreduced default Ada process;
its T-only constant-storage block remains unexercised there, and fresh
source-bound return/dump/load/matrix evidence is still required. Unchanged
errors.lua advances past parser/goto assertions to its ordinary runtime
diagnostics. Its next observed mismatch is table bitwise arithmetic reporting
an arithmetic error instead of the bitwise error class. No whole errors.lua,
instrumented-file, full target, PR or merge acceptance is claimed here.
