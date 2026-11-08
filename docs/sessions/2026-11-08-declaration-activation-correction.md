# Declaration activation correction

Date: 2026-11-08, Asia/Tokyo. Correction to the preceding compiler-context
checkpoint; full delivery continues.

Independent peer review found two additional native counterexamples to the
early New_Name check: 201 literal compile-time constants remain valid, and a
malformed initializer for 201 names must report its syntax error first. Pinned
localstat parses the initializer before adjustlocalvars checks register demand;
a folded final const can occupy no local register. The earlier upstream
errors.lua observation remains valid, but that eager check was too broad.

The check now runs after a completed ordinary declaration's initializer, and
after parameter-list parsing before the closing parenthesis. It uses a safe
lower bound on definite register demand. Possible constant storage remains
the existing canonical Fold/Bind decision, rather than a second evaluator in
the frontend. Recursive local functions still activate before their body.
The initializer list is borrowed from the actual owned node updated by Child,
instead of the stale earlier Item snapshot. No source-sized vector copy is
introduced. Bounded/checking policy remains unchanged.

Four separately named regressions add many folded constants, a folded const
after 200 ordinary locals, a nonconstant const that still exceeds the actual
register limit, and initializer syntax precedence. All fourteen context cases
pass native in both configurations; both Ada configurations pass all 2,398
AUnit cases. The public context fixture passes all eight native/Ada compiler
and VM combinations. Six serialized strict tests/C/CLI builds pass using
Alire 2.1.1 and GNAT 16.1.0 with the required flags and runtime checks.
All twenty-six default and twenty-seven instrumented standalone C executables
also pass; the complete 163-file documentation check passes.

Fresh unchanged errors.lua again completes in all four native/Ada default/T
processes. Logs are under reports/compiler-limit-contexts and
reports/combined-reader-failure/errors-be8041e2b7a74590b6b194a1a97857c0.
No reduced-suite flag or source adaptation is used for that file. Final-head
matrix, source-ledger and independent acceptance remain pending.
