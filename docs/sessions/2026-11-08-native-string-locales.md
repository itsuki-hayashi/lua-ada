# Native string locales, 2026-11-08

After the table diagnostic correction, original strings reached its native
Portuguese collation assertion. os.setlocale already queried/set the actual
native category, but execution comparisons and default sorting still used
byte order; pattern classes and case conversion still used fixed ASCII rules.
The pinned manual and lvm.c/string-library source require the current native
collation and byte classification behavior. Existing platform locale glue
already exposes these libc operations; no dependency or C interpreter code
was added.

The private string helper borrows rooted, NUL-terminated payloads. It charges
both lengths separately before entering native collation, avoiding summed
integer overflow and input-sized temporary copies. Equal native prefixes
advance independently through embedded-NUL segments; exhausting one complete
byte string settles the order. No allocation, collection safe point or Lua
callback occurs while borrowing those addresses. Empty strings use an actual
local terminator. Raw byte equality and storage/index comparisons stay intact.

The execution and sorting paths share this helper. Non-strict string order is
the complement of reverse strict collation order, preserving different byte
strings with equal native weights. A measured Windows Portuguese example is
`ab` and `a` followed by byte173 and `b`: equality remains false, while both
non-strict comparisons succeed. Numeric/NaN comparisons retain their policy.

Recognized pattern classes and lower/upper conversion use the existing
unsigned-byte ctype bridge. Pattern syntax, inversion, unknown classes and
the NUL class stay in Ada; lexical scanning remains independent of locale.
The public fixture restores each process locale category even after failure.
Optional Portuguese categories emit explicit availability observations; hosts
without those categories do not acquire non-C behavior coverage from a name.

Validation:

- Eight strict validation/static builds pass, followed by2,570/2,570 AUnit
  cases in each configuration. An initial test build caught an80-column line;
  formatting was corrected. The first execution's six new bodies succeeded
  but the inherited empty-output test helper rejected their deliberate
  observations; a dedicated exact output/availability checker corrected that
  test integration. Failed logs remain diagnostics, not passing evidence.
- Both native modes find `ptb` for collation and ctype and pass all six focused
  cases. All eight compiler/VM roles match stdout hash
  `e05037a88a0e89754e180f68c10103c04f4bc6cc2eed34cd5b43e8ac2b395f66`,
  with empty stderr.
- Original default strings completes its actual file wrapper/zero-return
  protocol in C and Ada, with identical stdout hash
  `8e7db5b0d2a85a6e88221762c4765bee7cb58f66036f8e3c74427201c3acbff2`
  and empty stderr. Both report the same native unavailable hex-format
  modifiers and expected T omissions; those omissions are not instrumented
  coverage. No reduced-suite flags or source adaptations were enabled.
- Original instrumented C strings completes. Ada now reaches534, missing
  externKstr; the retained external-string block remains unaccepted.
- Fresh no-argument C campaigns pass all26 default and27 instrumented
  consumers with exit0 and empty stderr. The argument-driven native module
  campaign remains outside that command set.

The combined images also include the eight materialized-vararg test cases.
Their independent resource eligibility and exact source decisions remain
separate. Local raw captures are below reports/exact-equivalent-review.
Final immutable26-context execution, aggregate/heavy, global reconciliation,
review certificate, PR and merge remain pending.
