# Canonical frame storage reduction

Date: 2026-11-08, Asia/Tokyo. Author: Codex /root, from 5599014.

[ADR 0047](../decisions/0047-canonical-frame-footprint.md) records the exact
two-field removal and its limits. The source search covers src, tests, c_api,
cli and experiments. The removed vectors had no execution/collector reader
or writer; their actual scalar/cell counterparts stay in the context. Native
warning/hook/release events and private packet migration storage are retained.

A bounded read-only Claude Haiku 5.5 audit used $0.01371905 of a $0.10 ceiling.
It correctly directed attention to live frame cost, but did not measure sizes.
Its larger side-record suggestion was not implemented: eagerly allocating it
would preserve the footprint, and lazy native-event allocation would require
separate refusal/ownership proof. This audit supplies no approval authority.

An ignored strict private child measured the actual Frame/Value/vector/lease
representations and retained a real 1,003-frame suspended coroutine. Frame
size falls 1,304 to 1,232 bytes, retained raw storage 2,176,302 to 2,103,870,
with 3,497 blocks in both observations and zero final bytes. The exploratory
probe executable was rebuilt in place; it is diagnostic, not an immutable
acceptance artifact. Its final log is reports/frame-storage-probe/after.stdout.

All eight strict local runtime, C consumer, CLI and test builds pass; full
AUnit default/T each pass 2,665 cases. All 26 default and 27 T no-argument C
consumers pass. Their fresh raw record is
reports/exact-equivalent-review/table-error-consumers-f0893cb29ee04f56b26b395dbcbe12f7.
The actual eight build logs are under
reports/exact-equivalent-review/table-error-build-b10899579f53433eabc982298648c34c.

Fresh frozen-image unchanged coroutine source observations are under
reports/exact-equivalent-review/remaining-originals-46b94275c84e4143ad31dc984eb5aa75.
All four native/Ada default/T processes exit zero with empty stderr and final
OK. Measured sidecars enforce 2 GiB and report zero bytes/blocks; Ada reports
complete shutdown/no accounting fault. Ada default peak is 1,896,476,423,
compared with the prior frozen-image 1,968,500,975 under
reports/exact-equivalent-review/remaining-originals-3bbc22df50124dcabea9a7f692bd135c.
T peak is 130,237,089 versus 135,157,641. Default's two original T omissions
receive no instrumented credit; T executes the retained coroutine API paths.
The initial attempt to use the remaining-file completion wrapper was rejected
because coroutine belongs to the accepted set; those failed wrapper captures
remain diagnostic. Fresh runs execute the original file directly.

No new passing ledger resolution, source approval or final-head matrix is
asserted. Runtime-dependent source reviews must bind the resulting layout and
current implementation, and the macOS resident watchdog remains pending.
