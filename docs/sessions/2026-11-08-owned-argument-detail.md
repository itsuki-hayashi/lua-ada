# Owned type-detail construction and actual raw-name temporaries

Date: 2026-11-08, Asia/Tokyo.

Type_Error now builds its type detail in a selected-owner byte buffer. A raw
string name is borrowed while its C prefix is scanned and copied with shared
budget charges. Text after NUL is neither copied nor scanned. The detail is
published through a borrowed view to the existing argument diagnostic; this
removes the input-sized ordinary String intermediate at this construction
site. Other failure rendering and storage sites still require their audit.

The raw __name field is also left in the actual native caller window whenever
it is nonnil, including a number, false or a table. The pinned luaL_getmetafield
leaves those values even though they cannot provide the type label. The earlier
implementation only preserved strings. Registry callbacks can now inspect the
raw value, detail, callee and lookup key in their actual temporary slots.

Four first-party Lua cases run unchanged on native default/T and Ada default/T.
They inspect numeric, boolean and table raw fields, then a short type name with
NUL followed by 30,000 bytes. All four stdout files have SHA-256
`5f82766b86d657d92c28b2f19b984315df658c7aa2218bb7a254b60cc11200e0`.
The separately named AUnit cases use the same Lua bodies. A fifth AUnit case
prepares a long name before lowering the instruction quota, then requires an
uncatchable host stop during its actual scan and healthy session reuse.

All eight serialized Windows validation/static root, nested-test, C-consumer
and CLI builds passed, in default and upstream-test configurations. Each
configuration passed all 2,099 AUnit cases. Six relevant standalone C consumers
also passed in each configuration: builtin, auxiliary, index/type, foreign,
external-string and traceback. Tool versions remain Alire 2.1.1, GNAT 16.1.0
and GPRbuild 26.0.0 with strict switches and runtime checks enabled. Logs are
under `reports/owned-argument-detail` and remain component evidence.

Continue failure-text and error-renderer allocation ownership, string/self and
refusal behavior, borrowed C views/hooks, traceback callbacks and all unresolved
source/aggregate/platform obligations. This change installs no exclusion,
adaptation, header-classification approval or final acceptance certificate.
