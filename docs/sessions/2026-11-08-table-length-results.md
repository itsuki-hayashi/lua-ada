# Table length conversion and ordering

Date: 2026-11-08, Asia/Tokyo. Component checkpoint, full delivery continues.

Unchanged sort.lua reached its helper assertion because an invalid __len result
reported an ordinary integer-argument error. The table continuation now retains
the exact luaL_len diagnostic, including fractional and nonnumeric results,
while accepting numeric strings through the same integer conversion.

Native execution of the new focused witness also exposed an existing incorrect
assumption: pinned Lua 5.5 tunpack obtains aux_getn before checking optional
bounds, even with an explicit end or an empty range. The old lazy-length path
and its contradictory Table_Unpack_Explicit_End regression were corrected.
The function identity is retained; its label now describes length ordering.
The replacement checks successful explicit traversal, empty ranges, receiver
validation, invalid-bound ordering and default bounds. This is a compatibility
repair supported by unchanged ltablib.c, not an exclusion of an upstream
assertion. Historical acceptance artifacts remain unchanged.

Four newly named AUnit cases protect invalid/fractional length results,
numeric-string coercion and length-before-bound ordering. The source fixture
tests/lua/table_length_results.lua runs against both actual Ada and pinned C,
with identical output: table length results OK. An initial draft incorrectly
expected the old bypass; native execution rejected it before final validation.

Strict Windows validation/static root and tests builds pass using Alire 2.1.1
and GNAT 16.1.0, retaining all warning/style switches and runtime checks.
Root command: alr -n build --validation -XLUA_ADA_LIBRARY_TYPE=static through
the normal GPR argument separator. Nested tests add
--profiles=lua_ada=validation and -XLUA_ADA_PREBUILT=true. The actual AUnit
runner passes 1,507 cases, zero failed assertions and zero unexpected errors.
Captures are reports/remaining-table-length-build.log,
remaining-table-length-tests-build.log, remaining-table-length-aunit.log,
remaining-table-length-native.log and remaining-table-length-ada.log.

Unchanged sort.lua also completes its unreduced 50,000-element workloads and
reaches OK in a direct Ada diagnostic run, with no soft flag. Its timing and
comparison counts need the reviewed semantic protocol and fresh runner/matrix
evidence; this local completion is not full-target acceptance. Instrumented
private capacity assertions remain subject to individual review.

Before this repair, exact-head d418a5488efa7085e8ed2dd56b34b8a309ff2cd4
passed fresh default Windows validation/static C/Ada literals.lua runner
observations. Both report passed, empty stderr, identical stdout SHA256
22db3798e44518fc7fe4e77b9f9c66b116e2d612ba61960eda59bbe0c19d855a,
2 GiB managed ceilings and balanced cleanup. Reports are
reports/remaining-literals-ada-default.json and
reports/remaining-literals-c-default.json. Their source profile confirms
absence of reduced-suite flags. They are observations on that revision, not
final-head/global certificates; later runtime changes require fresh evidence.
