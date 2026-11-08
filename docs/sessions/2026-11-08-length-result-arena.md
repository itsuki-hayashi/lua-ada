# Reuse the owned length result

Date: 2026-11-08, Asia/Tokyo. Narrow shared-runtime correction; the separately
implemented CLI argument feature exposed the existing failure.

The native-paired warmed M0 callback returned its integer normally, but Ada
attempted a fresh 223-byte provider growth in Native_Step.Return_Native's
single-result vector. The preserved first-refusal backtrace is
reports/cli-argument-refusal-gdb.log. It reaches the Stage1 unary length
continuation through actual C luaL_len. The inner Native_Results already owns
and roots the handler result. Creating an unrelated vector is unnecessary.

Only the completed @unary length branch changes: copy its first value into an
allocation-free scalar, charge normalization, reserve before clearing the old
publication, and normalize the same rooted packet to exactly one value or nil.
Complete_Packet receives the owned alias already supported by the runtime.
The enclosing @length continuation forwards that exact packet. Equality,
other unary operators and generic Return_Native retain their previous paths.
The original error/host-abort classifications and shared budget remain intact.
This follows the existing [owned result decision](../decisions/0037-reusable-c-call-metadata.md).

Four separately named AUnit cases cover extra-result truncation, no-result nil,
error identity plus recovery, and actual M0 left armed until the Lua caller gets
its value. The [ordinary fixture](../../tests/lua/length_result_semantics.lua)
passes unchanged under native default and T; the
[mandatory T fixture](../../tests/lua/length_result_refusal.lua) passes under
actual native T. Seven native processes finish with empty stderr and balanced
measured owners. A T-absent default run is not credited for the M0 body. M0 is
an actual zero-growth limit, not a demand to record a refused growth after the
correction succeeds. Both direct # and the C-backed CLI luaL_len path pass it.

All six strict runtime/tests/CLI default/T builds pass with Alire 2.1.1 and
GNAT 16.1.0, retaining Ada 2022 warning/style/check policies. All 2,644 AUnit
cases pass in each configuration in the combined draft, including four new
core cases and 28 separately delivered CLI argument cases. This count belongs
to that combined source artifact; no core-only 2,644-case revision is claimed.
Both fresh C-consumer projects relink cleanly against the new static runtime;
all 26 ordinary default contracts and 27 instrumented contracts pass without
flags and with empty stderr. The argument-driven native-module campaign is not
rerun by this checkpoint. Both full product CLI suites pass 112 controls.

Current CLI process evidence additionally satisfies the original 21 argument
controls in all six frozen images and the eight lifecycle controls in their
explicit ordinary/T roles. Those measurements are delivered by the CLI
checkpoint, not original upstream main.lua coverage. Raw native direct-length
captures are reports/length-result-native-eaf3390661064322882dafbacf3b0ccf;
combined build/test/C captures are
reports/cli-argument-build-2d4294d243404cc7b49ce7abcef1948c. Initial failed
compiles and the pre-fix M0 assertion remain distinct from the corrected runs.

No reference, source mapping, exclusion, semantic assertion, private count,
allocator limit, generic scalar helper or C ABI layout is changed. The full
upstream matrix, renewed source bindings and independent integration review
remain required. A focused fixed continuation does not establish those gates.
