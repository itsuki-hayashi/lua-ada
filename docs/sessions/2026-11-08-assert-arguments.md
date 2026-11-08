# Assert argument presence

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.

The base assert function now distinguishes an absent argument from explicit
nil before testing truth. Missing arguments use the existing auxiliary
argument formatter, including actual call-origin names and the collecting
registry lookup continuation. Explicit nil keeps assertion-failure behavior;
successful calls preserve the entire result tuple, including trailing nils.

Five separately named AUnit cases and the public Lua fixture cover absence,
a direct alias, a collecting registry callback, explicit nil and successful
tuple preservation. The Lua fixture passes against both separately built
native configurations and all eight native/Ada compiler/VM combinations.
Both local configurations pass all 2,359 AUnit cases. Six serialized strict
tests/C/CLI builds pass with Alire 2.1.1 and GNAT 16.1.0, retaining warning,
style and runtime checks. Raw logs are under reports/assert-arguments.

Fresh unchanged errors.lua runs now pass the missing-assert check at line675.
Both Ada configurations subsequently stop at the syntax-nesting limit during
the generated compilation-limit tests; native completes both runs. That
catchability/diagnostic gap remains required work. These observations do not
close errors.lua, any source ledger parent or the final acceptance matrix.
