# Host base C closing slots

Date: 2026-11-08, Asia/Tokyo. Base: integrated `62c9f3c`. This is a component
checkpoint in the authorized remaining-suite delivery, not final acceptance.

Idle host C stacks now acquire a real reserved base activation when a truthful
slot is marked to close. The activation owns the existing scalar window,
ordinary root calls retain it, and state close consumes it through the shared
iterative closing driver. It has no fabricated function pointer, public debug
level or native depth charge. Its reserved record survives ordinary retirement
outside the shrinkable frame cache and is physically freed with its context.

Typed predecessor links are reserved and physically shrunk atomically with
the scalar/cell arenas. C registration writes only actual indices, requiring
no allocator request and no redundant upvalue cell. Normal C return, error
recovery, settop, closeslot and state close find the same links. Lua lexical
closing cells remain independently owned. [ADR 0026](../decisions/0026-base-c-closing-ownership.md)
records the choice and the rejected allocating alternatives.

Lua-created coroutines also prepare their C surface while construction may
allocate. The first Ada-host borrowed C entry prepares preexisting threads;
thread conversion queries borrow the stable surface. The focused refusal
case verifies pointer/status identity, not the separate initial function-stack
or resume/reset obligations.

Strict local Windows/default/static root, C consumer and nested test builds
pass with Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (banner
26.0.0, 2026-04-15-gpr2). Required warning/style/runtime checks remain enabled.
All 1,695 AUnit cases pass, zero failures/errors, including thirteen separately
named wrappers executing the identical actual public C fixture.

`base_closing_api_contract.c` passes thirteen cases against Ada default/static
and separate pinned default and T C libraries. All stdout files have SHA-256
`eac790195b5e08b0ea01f379eefc783e705a5feb7144f6ba20eb950abc0fb7ab`.
Cases cover direct host settop/closeslot, reverse order, actual scalar value
replacement, first/grown/callback registration under persistent refusal with
zero provider calls, nil/false registration, previously unexposed Lua-created
thread queries under refusal, collection of the actual host prefix while a
handler runs, a live base slot at state close, retained C return results and
arbitrary error-object identity during C error closing. Both native
configurations execute every case. All owning states finish with zero counted
blocks and bytes.

The first allocation strategy passed the focused cases but failed the retained
`Iterator_Call_Refusal` AUnit test: reserving a C frame's close vector could
prevent the restoration callback itself from entering under refusal. The
stack-reserved links fix the implementation; that existing assertion was not
changed. A subsequent run exposed an omitted normal C-return close-head
condition. The final normal-return/error cases cover that path explicitly.

Twelve retained C consumers pass: foreign, debug, external string, reader/dump,
builtin, arithmetic/comparison, conversion, value, auxiliary, formatting,
collector and IO. Ignored logs are under `reports/base-closing/`, including
`root-build-3.log`, `consumer-build-3.log`, `tests-build-3.log`, `aunit-3.log`,
the final `*-3.log` consumer records and both `native-*.log` files. The
core-image script registers the new same-source oracle, stdout comparison and
source hashes. Its syntax parses; the full pipeline was not run here.

No reference tree or revision changed. Thread reset/self-close, initial fresh
coroutine function slots, logical unwinding/prefix retirement, public buffers,
integrated Ada T/shared/platform execution and complete suite acceptance
remain open. The uncommitted thread-reset fixture is not part of this passing
checkpoint and is not counted as Ada evidence.
