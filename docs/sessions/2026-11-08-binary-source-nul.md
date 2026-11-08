# Counted binary source names and C-prefix display

Date: 2026-11-08, Asia/Tokyo.

A bounded Haiku review of the argument renderer identified a possible source
NUL display difference. Ordinary load names already undergo C-prefix handling,
so the suggested direct load case does not reproduce it. An actual binary
chunk with a patched counted source string does: native C preserves the full
getinfo source bytes but displays only `a`, while the previous Ada implementation
displayed `a`, NUL and `b` in both short_src and an argument-error source prefix.

The shared bounded Short_Source helper now applies C-prefix termination after
rendering the chunk identifier. This order matters: a long file name selects
its final 56 bytes before C-string consumption. Truncating the original source
first would incorrectly display its prefix instead of the native file tail.
The full counted source field remains unchanged. No chunk byte-format or
reference-source change is involved.

Four Lua bodies pass unchanged on native default/T and Ada default/T: literal,
file, snippet, and a long file with an early NUL. Each patches an actual dump,
reloads it, checks full and printable debug metadata, then executes a real
argument error with an exact expected source prefix. All four stdout SHA-256
values are `c91e00dc4c9511fc0ee469bfba151edd0ba88479af43132d962d4602837c484c`.
Four separately named AUnit cases reuse these bodies.

After integrating the selected line-baseline checkpoint, all eight serialized
Windows validation/static root, tests, C-consumer and CLI builds passed in
default and upstream-test configurations. Both configurations passed all
2,161 AUnit cases. The debug, load/dump and traceback standalone C consumers
also passed in each configuration. Strict switches and runtime checks remain
enabled; tools were Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.0. Local logs
are under `reports/binary-source-nul`, with component scope only.

The review also noted that noncanonical legacy source formatting still has an
ordinary String conversion and recommended an explicit size contract on the
argument formatter's private Append_Bytes helper. These remain audit items;
no whole storage/debug/binary acceptance is inferred from this correction.
Continue the sort and cold-refusal failures, borrowed C/hook views, traceback
callbacks, final context failure-text ownership and full final-head matrix.
