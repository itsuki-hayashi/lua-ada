# Table errors and missing iteration arguments, 2026-11-08

Fresh isolated original-file observations exposed two ordinary public error
gaps. Strings failed its concat error check for the largest integer index;
nextvar failed its missing pairs receiver check. Diagnostic-only disposable
copies printed expected/actual errors and caller lines. Pinned sources were
unchanged, and those diagnostic copies provide no conformance passes.

Core and resumed table concatenation now distinguish an invalid table element
from an invalid separator. Elements report the actual signed Lua integer
index, including either64-bit endpoint and zero, with the offending value's
type. Separator errors use auxiliary argument2 diagnostics. Missing pairs and
ipairs receivers use the existing argument1 formatter. Explicit nil ipairs
still returns its iterator/state/zero tuple.

The new public Lua fixture and seven separately registered AUnit cases cover
these boundaries and a collecting proxy index callback. An initial author
probe attempted to yield inside native table.concat; C Lua correctly rejected
that crossing. The final proxy case collects and returns a false element; it
makes no claim that this C operation is yieldable.

Validation on the combined root runtime, including the marked-closing fix:

- All eight strict validation/static builds pass: runtime, consumers, CLI and
  nested tests, default and upstream-test. Flags and runtime checks remain.
- Both complete local AUnit runs pass2,556/2,556, with zero failed assertions
  and unexpected errors; their expected named finalizer warning is inspected.
- Both native producers and both Ada producers feed both VMs in each mode:
  all eight binary roles pass with empty stderr and identical stdout hash
  `ea8aa598b30e67c992cbf4b4f62c024355e180c2118e9035605bfa94ba9ed9e8`.
- All26 default and27 instrumented no-argument C consumers exit0 with empty
  stderr. The separately argument-driven native module consumer is excluded
  from this command set, not called passing by this observation.
- Original default nextvar completes its real wrapper/zero-return protocol
  in both C and Ada. Original strings now reaches its locale collation
  assertion at442; it does not pass the whole file.

Other fresh pre-correction observations found original literals completing in
all four roles, sort completing its default pair, and cstack completing all
four entry/return protocols with real tracegc progress dots. Instrumented sort
and nextvar stop at missing private querytab. Those are dated component
observations, without final-target acceptance or a reviewed stderr contract
for cstack. No private source exclusion was added by this correction.

Raw build, AUnit, binary, consumer and original-file captures remain below
`reports/exact-equivalent-review/`. Their executable/source identities remain
component evidence from source-frozen local images. Complete current-head
immutable matrix, aggregate/heavy, review certificate, PR and merge are pending.
