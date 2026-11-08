# Expected readline warning in the instrumented native CLI

Date: 2026-11-08. Change proposer: Codex /root/validation_delivery.
Independent feature reviewer: Codex /root. Implementation is not installed by
this review. Runtime acceptance, coverage and source-adaptation authority are
false; no exclusion or original upstream assertion is resolved here.

Root independently read the downloaded Linux instrumented report from run
42478332696, job 128724613029. Its SHA256 is
83865a956eccdc31c9ff2becb9ef52810bee2c9718ad5e488ac4b802a3b5092c;
the verified archive is
f3e356e494d31cea030ee924264b6db97e820079238938dc5746bb1cc8fd4998.
The missing-library-warnings-on native process exits 1 after its banner.
Its stderr explicitly says Unexpected warning in test mode and aborting;
SHA256 c0f21fe0dba199a6e78cd112304c817a62305f2c786a9f0a291e59e09ceba3ea.
Ada exits zero and emits the expected library warning, stderr SHA256
89613778f8b16045ea2cbdcbcc4bae4a861e357337ebe296b43c62420e3a1067.
These failed original captures remain unchanged and unaccepted.

Pinned ltests.c:86-154 explains the difference. Its default private test mode
aborts an enabled warning that does not begin with #; the explicit @allow
control selects printing of expected warnings. This is separate from the
public warning API and the CLI's correct missing-library warning. The native
readline initializer itself emits that warning through three lua_warning calls.
The test intentionally requests it with an invalid library and -W.

Approve only this proposed counterpart setup: for configuration upstream-test,
platform linux, case missing-library-warnings-on, prepend exactly
`if T then warn('@allow')end;` to the existing setup in both role invocations.
All other cases/configurations retain their existing setup. Keep -W, the exact
invalid library name, input print(71), native backend selection and exact raw
stdout/stderr comparison. T remains present and enabled; its allocator and
other safety checks remain active. The ordinary auxiliary warning handler is
not replaced, and unexpected warnings in every other case keep their original
test policy. No warning may be filtered, normalized away or inferred from OK.

Bind the final counterpart to the exact configuration, platform, source and
case contracts. Replay must select the recorded target platform, not the OS
running the receiver. The prefix is a reviewed test configuration, not a repair
of the old failed row. Require fresh native/Ada observations and retain the
unchanged failure as baseline evidence. This review does not authorize any
other @allow insertion, implementation change, source transformation, policy
exclusion or final-context acceptance.
