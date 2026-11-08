# String-table feature review

Date: 2026-11-08, Asia/Tokyo. Source-only review; delivery continues.

Root independently inspected the author's three exact querystr candidates,
the original generated API workload, the pinned native query/resize routines,
the manual's collection/weak-string/allocator contracts, and Ada's actual
interning, index replacement, unlinking and existing identity tests. The
[feature decision](../../tests/conformance/targets/remaining-upstream-compatibility/reviews/api-string-table-geometry.independent-feature-review.json)
permits replacing private size/population observations with actual Ada safety
counterparts. It installs no exclusion or adapted source and grants no runtime
or coverage acceptance.

The native bucket capacity and intern population are observable through its
private test module but carry no public compatibility promise. The surrounding
fresh-state workload remains required: minimal libraries, a thousand dynamic
strings, recursion and stack observations, allocator-disabled collection,
remote result delivery and explicit state closure. A Lua weak table holding
strings cannot establish intern-index reclamation: strings are not removed
from weak tables by the language contract.

Actual replacement allocation refusal, preservation of old chains and live
roots, retry, dead-header detachment and balanced shutdown need focused
counterpart evidence. Ada does not request a string-index shrink during full
collection. Its growth-only refusal control cannot establish execution of C's
refused-shrink path, nor does that private resize strategy require emulation.

The binding audit checked 22 available file identities. Three references to
the engine body have changed file hashes; their exact relevant spans occur
uniquely and unchanged at new offsets. Four historical native report files
are unavailable in this checkout and were not verified or treated as evidence.
The decision records these limits. Any exact source review must bind current
implementation files and actual new observations; historical approval does
not transfer automatically.
