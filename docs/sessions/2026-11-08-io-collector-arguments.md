# I/O and collector argument diagnostics

Date: 2026-11-08, Asia/Tokyo.

## Changes and scope

Invalid write operands and the first collectgarbage option now use the
existing shared argument diagnostic before string conversion. The diagnostic
retains the actual activation, caller origin, method adjustment, raw named
type and source prefix. Write validation remains sequential: bytes accepted
before an invalid later operand remain written. Numeric string coercion and
the absent/nil collector default retain their existing behavior.

Six separately named I/O cases cover an unknown call origin, a direct call,
first and later method arguments, a raw named type containing NUL, and an
empty argument list. Four collector cases cover unknown/direct origins,
boolean and raw named types, and integer-zero default results. The method
fixture places `write` in the first constant slot so both pinned compiler
configurations emit the same method-call form. This first-party witness
does not adapt any upstream test or exclude an optimizer assertion.

## Validation

On Windows with Alire 2.1.1, native GNAT 16.1.0 and GPRbuild 26.0.0, all
eight serialized validation/static builds passed: root library, nested tests,
C consumers and CLI, each in default and upstream-test configurations.
Strict Ada switches and runtime checks remain enabled. Each configuration
passed all 2,028 AUnit cases, including the ten separately registered cases.

Both first-party Lua fixtures passed unchanged in four separate processes:
native default, native instrumented, Ada default and Ada instrumented. The
native interpreter remains a separately linked oracle. Logs are under
`reports/io-collector-arguments` in this checkout and are diagnostic component
evidence, without final target acceptance authority.

Unchanged errors.lua was replayed with the bounded conformance runner and a
diagnostic hook that reports its first failed expected message. It now gets
past the write and collector type checks and fails `aaa:sub()`: the actual
message lacks the required `bad self` form. This file is still failing.

## Remaining work

Complete the string-method diagnostic and remaining original errors.lua
assertions, public traceback, retained T behavior, the full final-head
platform matrix, independent reconciliation, automatic PR review and merge.
No adaptation, exclusion or full-suite pass is claimed by this checkpoint.
