# Fixed numeric scratch checkpoint

Date: 2026-11-08, Asia/Tokyo. Base: integrated `6e166ea`. This reusable
checkpoint precedes public numeric C operations that must not grow a refusing
Lua allocator. [ADR 0024](../decisions/0024-fixed-numeric-scratch.md) owns the
capacity/lifetime rationale.

`Lua.Storage.Fixed_Arenas` binds a fixed local 131,072-byte provider once to
an ordinary owner. Absolute-address alignment, copy-on-growth, transactional
refusal and real controlled-object release reuse the existing storage path.
Freed regions remain counted in the cumulative cursor until scope exit.
`Number_Parsing.Read_Without_Allocation` invokes unchanged shared grammar and
exact arithmetic using that local arena/owner. The existing 1,100-digit
prefix/sticky bound prevents input-sized rational storage.

Tools: Alire 2.1.1, GNAT 16.1.0, GPRbuild package 26.0.1 (banner 26.0.0,
2026-04-15-gpr2), Windows x86-64. Serialized commands:

```text
alr -n build --validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default
alr -n -C tests build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_PREBUILT=true
tests/bin/static/test_runner.exe
```

All strict builds pass with required warnings/style/runtime checks. All 1,640
AUnit cases pass, zero assertion failures and unexpected errors. Seven new
named cases cover cumulative refusal, byte-preserving resize/release, a
midpoint with a remote nonzero tail beyond three thousand zeros, 1,100 kept
decimal/hexadecimal digits near subnormal limits, ten-thousand-digit
mantissa/exponent cancellation, and shared locale/integer/signed-zero rules.
Each large rational case has zero live owner blocks after parsing. GDB at
the completed arithmetic measures cumulative use of 15,886 decimal and
13,366 hexadecimal provider bytes, including replaced buffers/alignment.
The complete suite also passes under that diagnostic run.

Ignored `reports/fixed-numeric/` retains `runtime-build-2.log`,
`tests-build-3.log`, `aunit-1.log` and `arena-measurements.log`. Earlier compile
attempts found a nonstatic alignment attribute in a rep clause (replaced
with absolute-address alignment) and test-only selectors/type visibility;
those failures are not passing evidence. No compiler pin, generated config,
reference source or revision changed.

This checkpoint does not wire public C conversions yet. Actual C refusal
contracts and the parent's exact 15/17-digit formatter need separate tests.
Existing allocating frontend/runtime parser callers remain unchanged.
Integrated Ada T/shared/platform and final full-suite acceptance remain open.
