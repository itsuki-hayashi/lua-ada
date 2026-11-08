# Exact Nextvar and Sort source proposal

Author: Codex /root/remaining_suite, 2026-11-08. Pending independent review.
The [data packet](nextvar-sort-exact-source.author-proposal.json) is a proposal,
not a manifest accepted by the reviewed-source selector. It installs no policy,
exclusion, source approval, transformation or execution authority. The two
proposed results were reconstructed and hashed only in memory; neither was
written as a Lua file or executed.

The proposal has six disjoint changes, bound to the unchanged pinned source:

* Nextvar bytes 823/104, lines 38-42: replace only the private geometry body
  inside check(t, na, nh). Keep the signature, T-absent guard and closing end.
  The actual Ada checker must return nonnegative integer rows/live counts,
  with rows >= live and live equal to real iteration. All 29 original calls
  and their complete argument bytes/evaluations remain unchanged, including
  every mp2 expression. Neither expected C size is interpreted as Ada capacity.
* Nextvar bytes 4022/220, lines 183-188: separately propose a source-only
  exclusion of the positive 2/3 allocation allowance control. Native
  alloccount limits nonzero size-changing allocator requests; these literals
  are upper allowances, not assertions that exactly two/three occurred.
  Generated source/load, the warm call, observed constructor, original no-arg
  alloccount reset, GC stop/restart, length and original check remain. This
  private control is not reported as a passing Ada invariant.
* Nextvar bytes 4331/26, line 193: retain that original check call as an exact
  prefix and add public checks for sa+sh entries, every array value and every
  generated hash value. The [implemented constructor companion](nextvar-storage.author-observation.json)
  and real selected-provider refusal/retry cases support review of this
  retention; the newly proposed whole-file code itself has not run.
* Nextvar bytes 5023/437, lines 232-245: replace physical-rehash termination
  with 1,024 real fresh-key insert/deletes, a before-value map, bidirectional
  retention checks, actual storage walks and periodic real collections.
  Preserve both original callers. These two tables are ordinary, nonweak and
  hold only the original integer/string keys and primitive values; the
  snapshot retains bindings already strongly owned by them. The name stays
  forcerehash to preserve callers, without promising a physical rehash.
* Sort bytes 658/27, line 29: replace only the predicate with a real storage
  walk and live count 40 after the original forty writes. Retain assert,
  not-T short-circuit, N=10000, allocation, writes, length/content and the
  unchanged memdiff > N*4 assertion.
* Sort bytes 867/41, line 36: replace only the predicate with a real storage
  walk and zero live entries in the newly created empty table. Retain the
  original memdiff > 1024*12 assertion, argument/overflow checks and every
  later comparator/callback/iteration/move/unpack/sort assertion.

The original mixed T block at Nextvar lines 144-322 is not excluded. The
separate 100,000-cycle public churn and all unused printTable bytes remain
unchanged. The original coverage files retain all 197 Nextvar and 46 Sort
anchors and statuses; the proposal links affected anchors without accepting
or deleting them. Indexed querytab in the uncalled diagnostic printer receives
no fabricated implementation or passing runtime credit.

The dated feature packet has one corrected inventory error: its second
forcerehash caller span points to line 300, the following comment. The actual
callers are lines 258 and 299. This proposal binds those real call bytes and
preserves the earlier packet as dated evidence.

In-memory output identities are Nextvar 23,231 bytes / SHA256
0ff9cc83ffabfbb84b6ffbdf305fcbf206e322647aa52ed54c6b8419d18daf55,
and Sort 9,664 bytes / SHA256
6add6792ad930be118af2b6c0098b2e20b4e754b90e9e72b2141be511de873dc.
The packet independently hashes every unchanged segment and maps each original
check call to identical bytes in that preview. The identities provide review
targets, not authority to emit or run them.

Current V4 eligibility is closed to its single reviewed Memerr resource row;
it does not admit this Nextvar conditional and two allowance calls. The target
reviewed-source selector also has no Nextvar/Sort case. Those are explicit
policy gaps, not permission to create a general registry or schema. A bounded
eligibility/retention decision and a separately reviewed exact selector would
be needed before installing the private-count candidate or emitting a source.

Independent feature and exact reviews must bind the actual current runtime,
checker, C transport, constructor faults and public companions. The packet
uses the frozen 5496d0e source snapshot and its dated 2,629-case/eight-role
component evidence; later Root debug-console or CLI changes cannot inherit
that authority by rehashing. Review the new before-map code, GC/root lifetime
and full-source cost as proposed code, rather than pretending it is identical
to the already executed companion. Fresh original native baselines, approved
Ada-T whole-file/binary protocols under 900 seconds / 2 GiB, applicability and
final context/aggregate/ledger reconciliation remain separate requirements.
