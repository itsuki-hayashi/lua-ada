# Nextvar and sort private table-geometry candidates

Author: Codex /root/remaining_suite, 2026-11-08. Pending independent feature
review. The [data packet](nextvar-sort-table-geometry.author-proposal.json) binds
the pinned source bytes, eight direct querytab lines, 29 check callsites and
existing counterpart files. It supplies no replacement source, exclusion,
execution receipt, approval or conformance status change.

The most important boundary is nextvar's forcerehash loop. It terminates when
the private C array/hash shape changes. Actual Ada member-row/live-entry counts
can stay constant during legitimate row reuse, so substituting those values
for querytab would create a nonterminating test. Its two callsites need a
separate reviewed bounded churn/storage-safety counterpart. Preserve real
insertions/deletions and all surrounding live-value assertions. The existing
outside-T 100,000-cycle churn and 2,047-entry count remain unchanged.

The proposed feature groups are deliberately separate:

* sort.lua:29 and 36 assert exact C table.create array/hash allocation geometry.
  Preserve both adjacent collectgarbage-count thresholds, GC, writes, length,
  value, argument and overflow assertions. Only those two geometry expressions
  are candidates for a reviewed actual-storage invariant. All sorting,
  comparator, callback, move and unpack behavior remains unchanged.
* nextvar.lua:36-43 checks private array/hash sizes at 29 callsites. A reviewed
  equivalent could inspect actual Ada storage and compare live count with real
  iteration, while preserving each original call and expected-argument
  evaluation. In particular, keep the evaluated mp2 math.log/ceil/power
  assertions; they also test ordinary math behavior.
* nextvar.lua:179-193 mixes constructor source generation/load/calls, GC and
  public length with private C allocation counts of two or three blocks. Those
  counts assume header/array/hash allocations and require their own feature
  decision. Preserve actual construction, warm call, GC transitions, length and
  values. Existing reservation/insertion tests do not automatically replace a
  real constructor provider-refusal/retry witness.
* nextvar.lua:232-245 is the physical-rehash loop described above. Do not skip
  the whole T block, fake geometry or merely rename an unrelated counter. The
  exact bounded stress operation and retention checks are still unresolved.
* nextvar.lua:16-26 is an unused local diagnostic printer with indexed raw
  querytab access. There is no callsite. Preserve its bytes and record that it
  was not executed, rather than inventing an indexed C-layout facade.

The existing read-only adapter proves heap membership/tags before dereference,
safe array/hash/free chains and actual Tables.Find consistency. It accepts
indexed nil-valued tombstones and revived live free-listed rows, returning
retained member rows and nonnil values. Its 22 focused cases plus three public
weak/live/reuse witnesses supply useful safety evidence. Actual dense/hash
reservation refusal and partial-reserve retry also exist. Those facts do not
establish C capacity geometry, original constructor allocation counts or this
whole-source execution.

Before authorizing an equivalent, measure actual inspector cost across the
529 generated constructors and repeatedly growing tables under the real
900-second/2-GiB campaign. Allocation-free bounded walks can still be expensive,
especially heap-membership checks. Do not waive checks or silently weaken
retention if the straightforward equivalent scales poorly. Runtime/source
counterpart drift requires fresh independent exact binding review.
