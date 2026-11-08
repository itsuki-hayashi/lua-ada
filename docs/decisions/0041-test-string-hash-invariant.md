# ADR 0041: Test-only cached string-hash invariant

Status: implemented component with focused strict validation; whole-target
acceptance and current source-review bindings remain separate.

The only two direct T.hash calls in the pinned test suite are in attrib.lua:343.
They compare a normal string with the real C module's external string. The mixed
block 335-350 also checks byte equality, table-key lookup/update, next identity
and duplicate external strings at lengths 0/10/39/40/41/1000. Its original bytes
and assertions remain unchanged. Missing T.hash stopped instrumented Ada before
those subsequent assertions.

Pinned ltests.c:1078-1095 has two distinct modes. With no second argument it
requires a string, ensures a cached long-string hash, and returns a signed C-int
hash. With a second table argument it reports the physical C hash-node main
position. There is no suite use of that second mode and no asserted numeric hash
literal. Root and the remaining-suite reviewer independently accepted a narrow
Ada string invariant, preserving the actual storage implementation rather than
cloning C's hash algorithm, width or table geometry.

Test adapter operation 40 reads the real Object.String_Hash used by Tables.Hash.
Owned and external string constructors already initialize that cached 64-bit
field. The inspection leaf reads it without scanning payload bytes, allocating,
collecting, or changing a budget/provider control. The actual C argument window
roots its string through inspection. The existing generic C inspection transport
publishes the integer only after Ada returns; no new C or runtime code is added.
Normal portal/result publication retains its existing allocation/error behavior.

The full 64-bit bit pattern is reversibly rendered as signed Integer_Value by a
same-size unchecked conversion. High-bit values remain negative integers with
every bit preserved. This is explicitly an Ada invariant counterpart, not a
promise of unchanged native signed-32-bit numerical representation. The adapter
requires exactly one actual string and returns exactly one integer. It rejects
numeric coercion and extra arguments. It does not implement or advertise the
physical table-position overload. Installation uses the existing operation/world
captures in the main-state adapter, not the independently created-state module.
No production interface or runtime dependency changes.

Two separately named private probes retain a 97-byte noninterned long string as
an actual argument. After callee lookup and Start, each replaces only its cached
field with a sentinel, invokes the actual installed helper, and restores the
field before result inspection, key lookup, Finish and physical teardown. The
exception path restores before Cancel. The string is never a key or intern-chain
member. Positive and high-bit patterns prove cached-field reading, full-width
transport and one-result cardinality; recomputation, constants and truncation
cannot satisfy them. No corrupt hash survives cleanup.

Six named public boundary cases plus binary-content and invalid-type cases run
the same mandatory-T Lua fixture in native and Ada. They retain owned strings,
real T.externstr copies and T.externKstr borrows through collection, actual
table-key reads/writes, next and duplicate payloads. The caller uses borrowed
source strings after collection. An Ada-only extra-argument case records the
narrower supported contract, and a default-absence negative proves the fixture
is not silently accepted without T.

Both complete AUnit suites pass 2,612 cases, including 12 new cases. All four
strict runtime/test builds and four instrumented compiler/VM roles pass; fixture
stdout matches native at e8da16262495dd936c80cf8e82dc6b850457f849e13f8871a75a42ee1ed0f91d.
A fresh approved-path attrib native/Ada T pair completes its actual dump/load
entry and single-result-27 protocol with matching stdout and zero selected
provider blocks/bytes. The path source approval is unchanged; no source
exclusion, upstream assertion change or full-target acceptance is installed.
Changing adapter code requires explicit renewed exact reviews of dependent
verifier/API/locals mappings before claiming current source authority.
