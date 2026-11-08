# Public-boundary integration and argument borrow lifetime

Date: 2026-11-08, Asia/Tokyo.

The shared traceback, argument registry continuation, public panic/provider,
scalar NOT, I/O argument and SDK consumer checkpoints were integrated in the
major remaining-suite branch. Reference and module revisions remain unchanged.

## Integration correction

Six I/O regressions exposed a checked borrow interaction. Passing an indexed
Native_Arguments element directly to the argument diagnostic kept its vector
reference guard alive. The diagnostic correctly transferred the failed
builtin's actual scalar window to its C owner and retired the obsolete
packet, which attempted mutation while that element remained borrowed.

Write_Arguments now copies the scalar through its existing Arg query before
testing its kind or calling the diagnostic. The real frame/window continues
to root the value. This needs no allocation, preserves partial writes, and
ends the element borrow before a legal ownership transition. The vector
borrow check remains enabled. The separately named existing I/O cases failed
before this correction and pass afterwards; no expectation was relaxed.

## Validation

All eight serialized Windows validation/static builds passed: root, nested
tests, C consumers and CLI in default and upstream-test configurations.
Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.0 retained strict Ada switches and
runtime checks. Each local configuration passed all 2,094 AUnit cases,
including the 513-position refusal sweep and new NOT, registry and traceback
regressions. No unexpected errors or assertions failed.

All twenty-six ordinary standalone C consumers passed in both configurations.
The instrumented reset consumer used its named `--without-warning-reentry`
configuration; its explicitly omitted native-lock-sensitive operation retains
its separate policy and does not acquire fake passing evidence. An initial
batch command supplied that fixture argument incorrectly; the direct corrected
invocation passed. The separate instrumented private-buffer receiver passed
all seventeen actual operations and reported LUAL_BUFFERSIZE 23, structure
size 64 and header extraspace 16. Ordinary and opt-in SDK macro receivers
also passed their actual 47 and 53 Windows operations in each configuration.

The native-module C consumer requires fixture arguments and was not rerun in
this integration check. Its previous component evidence remains separately
scoped. Local logs are under `reports/combined-public-boundary`; they are
component observations, not immutable final-head acceptance artifacts.

## Remaining obligations

Continue the unchanged errors.lua string-method diagnostic and actual
string.find refusal path, borrowed Lua CI/custom C hooks, traceback registry
metamethod continuation, remaining source records, helpers/aggregate/heavy,
native fixtures, final 26-context matrix and independent reconciliation.
Public-header routes and macro audits remain proposals. No full original file,
whole target, exclusion approval, final review or merge is claimed here.
