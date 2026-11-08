# Heavy allocator ceilings and observation, 2026-11-08

The first new Heavy campaign requested 64 MiB but exposed a test-launcher defect.
Ada Configure always installed 2 GiB, and Finish always printed that literal.
Both Ada processes therefore exceeded 64 MiB before catching memory failure.
Their exit 0/OK/clean shutdown cannot establish the requested Heavy operation.
The original reports and raw captures remain immutable dated diagnostics.

Configure now accepts only the two canonical decimal contract limits, defaults
to 2 GiB when absent, rejects unsupported spellings, and sets the actual owner
ceiling before attaching the observer. The shared provider snapshots that cap
independently of reversible T.totalmem controls. Finish prints its stored
Host_Limit after disposal, without reading an expired owner. Production Ada
session policies and the runtime library are unchanged.

The native T observer had a related measurement gap: its backing malloc
counter missed real NULL returns from the original debug allocator's earlier
count/byte controls. A function-like macro renames only the original allocator
definition into a private body. Bare public debug_realloc pointer uses still
refer to the wrapper, including the pinned T startup identity assertion. The
wrapper forwards every argument and returns the original result unchanged;
it counts only positive-size NULL results. The narrower backing counter stays
separate. No reference source or revision was edited, and no reference code
enters the Ada implementation.

Validation and corrected evidence:

- Both strict test-crate builds pass against the previously verified runtime,
  and both full AUnit suites pass 2,600/2,600 after the test changes.
- Thirteen actual process checks pass in each configuration: three measured
  configuration/sidecar selections, eight invalid spellings, real protected
  allocation refusal with recovery at 64 MiB, and the same 80 MiB string request
  succeeding under 2 GiB. Instrumented refusal follows T.totalmem(0), proving
  that resetting its test limit does not remove the host ceiling.
- An independent review found that the first sidecar reader omitted PID/run
  pairing. The new reader binds exact PID filename/body, fresh run ID,
  configuration, raw bytes/hash, typed counters, actual cap and clean 0/0.
  Twenty-two synthetic non-execution guards cover stale/missing/duplicate
  identities, changed hashes, invalid types, over-cap peaks and bad cleanup.
- Both native oracle builds pass. Seven strict C observer cases verify real
  allocator identity/T startup, fail-next/count/byte early refusals, unchanged
  old payloads, one backing refusal in both views, successful growth/free,
  recovery and zero ownership at original state closure.
- Fresh frozen unchanged Heavy runs complete in native/Ada default/T at an
  independently measured 64 MiB cap, within 600 seconds, with no reduced flags.
  Every role records two actual managed refusals and zero outstanding blocks
  and bytes. Ada reports provider 0 because Storage.Check_Growth denies the
  real request first; native T reports backing 0 because debug_realloc denies
  it before backing malloc. Neither is renamed a provider/backing refusal.
- Ada raw peaks are 48,509,660 and 48,583,216 bytes. Native preserves its four
  progress markers; Ada reaches refusal before the first million-entry mark.
  Raw sizes/memory/progress remain intact rather than being normalized into
  equal output. All processes print the original OK and return zero values
  through the additional wrapper; final semantic operation review is pending.

Raw observations are below reports/allocator-ceiling,
reports/native-allocator-observer and reports/exact-equivalent-review.
The corrected four-role Heavy capture is heavy-4d4e0ee6cf74425c833106eeeb62f7b2.
These are local component observations, not the final immutable matrix,
source/global/API ledger closure or a conformance certificate. Source-bound
reviews over allocator/launcher/observer files must be renewed explicitly.
