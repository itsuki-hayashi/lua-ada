# ADR 0003: Lua IEEE Values and Optional Validity Checks

Date: 2026-11-05. Status: accepted narrow compatibility exception.

## Evidence and decision

The separately named numeric overflow test reproduced Constraint_Error when
copying valid Lua infinity under Alire's generated -gnatVa. GNAT's optional
floating validity check classifies IEEE infinity and NaN as invalid. Lua permits
both, including overflow to infinity and arithmetic-generated NaN.

Append -gnatVF in first-party library/consumer GPRs to disable only that optional
classification. Retain -gnat2022 -gnatwa -gnatwe -gnatv -gnaty, range/array/
overflow/access/discriminant checks, assertions in validation, and remaining
profile validity checks. No warning suppression or global check removal is used.

This exception implements the language's valid value set; it does not hide
uninitialized data or permit unchecked foreign representations. Infinity is
constructed from a known IEEE bit pattern in one isolated conversion. Numeric
grammar is validated before conversion and boundary tests exercise the result.

## Alternatives and consequences

Rejecting infinity would violate Lua. Disabling all validity/runtime checks is
unnecessary. A tagged representation of every exceptional float would duplicate
IEEE arithmetic throughout the runtime without improving compatibility.

Review this exception if numeric representation or compiler changes. Keep
numeric subtype/range validation at explicit interfaces, especially table keys.

Source: [GNAT validity checks](https://gcc.gnu.org/onlinedocs/gnat_ugn/Validity-Checking.html).
