# Public value and auxiliary checkpoint

Date: 2026-11-08, Asia/Tokyo.

Continue the authorized remaining-upstream implementation from the integrated
debug, external-string, comparison and fixed-scratch checkpoints through
bc715d3. The owning decision is [ADR 0023](../decisions/0023-public-value-auxiliary-operations.md).
Three core operations and 28 auxiliary exports execute through the real Ada
runtime. The reference interpreter remains a separately linked oracle.

## Implementation and observations

Length and concatenation use the existing iterative operation continuations.
The first concatenation fixture found a real vector borrow spanning frame
retirement; copying its scalar result before completion fixes that ownership
error. Every consumed operand is pinned before stack replacement.

A 20,000-value binary64 comparison exposed four decimal differences: three
seventeen-digit halfway values rounded away instead of to even, plus one
fifteen-digit subnormal readback. Shared exact formatting/parsing in a fixed
arena fixes those differences and avoids requesting Lua allocator storage.
The first instrumented C fixture also exposed an unacceptable test index:
its absent slot is now explicitly reserved with lua_checkstack before use.

A bounded Claude Haiku 5.5 sidekick drafted the auxiliary composition file and
consumer in an isolated worktree. The primary agent inspected them, compiled
the same consumer against native C, corrected two missing method-test setups,
added charged long-prefix/default scans, and verified actual Ada execution.
The two drafting calls cost $0.24305629 and $0.22983754; their JSON
records remain ignored review inputs, not acceptance. A separate bounded
Sonnet 5.5 formatter review cost $0.2472524 and found no blocking scoped defect;
its conditional initialization, budget-model and invalid-input notes were
checked and clarified. No independent whole-target approval is claimed.

A subsequent read-only Sonnet 5.5 auxiliary review cost $0.2576807 and found
no high-confidence actionable defect in the 28 composition functions. It did
not inspect the underlying Ada implementations or the full consumer. Its
zero-charge question was checked against the actual Ada charge operation;
the two bounded-scan witnesses also confirm that failed charges never return
to continue their loops. This scoped review supplies no acceptance authority.

## Validation and limits

Windows x86-64, Alire 2.1.1, native GNAT 16.1.0 and GPRbuild package 26.0.1
(executable 26.0.0), default/validation/static. Required strict flags and
runtime checks remain enabled. Build logs are ignored under reports/.

```text
alr -n build --validation -- -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=false
alr exec -- gprbuild -P c_api/consumer.gpr -p -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=true
alr -n build --validation --profiles=lua_ada=validation -- -XLUA_ADA_CONFIGURATION=default -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=true
alr exec -- bin/static/test_runner.exe
```

The final two commands run from tests/. The six scalar regressions initially
pass within an integrated 1,662-case run. After adding the two auxiliary
bounded-scan cases, a fresh strict nested build and run pass all 1,664 AUnit
cases, with no assertion failures or unexpected errors. Both new cases verify
the host abort, a subsequent recovery chunk and zero live managed blocks
after finalization.

All eleven current C consumer executables complete successfully with empty
stderr. The seven-case value consumer matches both native configurations
byte-for-byte (SHA-256 4dbc7c89b753fb099e84244673ae1ec5234cd507a85b0e59b3c389e01cfd9758),
including binary64 fingerprint 90eb8de147d180eb. The 76-case auxiliary consumer
also matches both (SHA-256 d15187b4cebdaa250adf72f132c03fa955212e890f87b92cbb3e70c13ad5fd91).
The consumers close their counted states with zero live bytes/blocks.

These observations bind a dirty component tree. All-platform/shared/T Ada
execution, native fixture linkage, complete public exports, relevant T drivers,
aggregate/heavy execution, final-head reconciliation, PR review and merge
remain open. No reference/module revision, upstream test or frozen historical
certificate was changed. Completion with reviewed adaptations/exclusions must
still be reported separately from unchanged original assertion execution.
