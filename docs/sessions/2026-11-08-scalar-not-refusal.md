# Scalar logical negation under allocator refusal

Date: 2026-11-08, Asia/Tokyo. Component checkpoint within the continuing full
remaining-suite delivery. Source base 4e0f0fb; no full-file acceptance claim.

The unchanged T memerr.lua campaign reached checkerr's `not stat` expression
after a genuine protected table-allocation refusal. GDB identified a fresh
Values.Vector allocation in Canonical.Step's unary request at line 1213.
Logical negation has no handler and needs no helper activation. Pinned Lua
lvm.c:1618-1625 writes its boolean result directly from the operand's truth.

The canonical NOT word now performs that scalar write. Arithmetic negation,
bitwise negation and length keep their existing distinct paths. No parser,
opcode number, C API surface, allocator policy or reference source changes.
Six separately named AUnit cases cover false, nil, zero, empty string, a table
with a hostile length handler and a function. Each constructs the operand
before refusal and runs NOT on a parameter, so constant folding cannot hide
the word. Growth remains disabled until the opcode has returned its value.
The test helper restores controls and verifies physical ownership on teardown.

All six default/upstream-test static root, tests and C consumer builds pass
under the centrally granted exclusive lease with inspected clean diagnostics.
Tools: Windows x86-64, Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.1. Ada 2022
warning/style checks and runtime checks remain enabled. All six new cases pass
in both local AUnit suites. The full integrated suite is 2,088/2,094 in each:
six existing I/O argument-error cases fail the vector borrow invariant after
registry diagnostic continuation integration. That is not a passing suite.
The parent owns the corresponding scalar operand-copy correction; the borrow
check remains enabled, and this checkpoint does not modify those I/O paths.

The unchanged tests/lua/primitive_not_refusal.lua fixture passes native T and
Ada T. Native and Ada dumps also execute on the opposite VM, so all four
producer/VM combinations match raw stdout SHA256
043EA1F78873DE93CEB60BCC3BAC9A786E85C1658F8D31D7E0475B4976A605DD.
The prior Ada artifact fails this fixture at line 5 with "not enough memory";
the native fixture succeeds. Dumps use each interpreter's actual loadfile,
string.dump and binary file output, independently of any reference VM linkage
in the Ada implementation. No native luac executable is supplied in this local
oracle tree; these actual interpreter dumps provide the producer evidence.

Unchanged soft memerr.lua still fails through checkerr at line 7. Its next
observed refusal is now Strings.Run.Apply_Text.Apply_Pattern at line 331,
appending plain string.find's numeric results to a fresh vector. The scalar
NOT allocation is gone; further permanent-refusal library behavior remains
open. The fixture and upstream source were not reduced, edited or skipped.
Logs and dump artifacts remain under reports/not-*.

Continue the assigned shared borrowed Lua CI/custom C hook repair and the
remaining source/T/allocator matrices. The final PR, automatic GitHub review,
review fixes and authorized merge remain part of the full ongoing task.
