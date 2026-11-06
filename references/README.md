# Reference Projects

These submodules are read-only implementation/API references, not dependencies.
Keep their sources outside production GPR source paths and preserve their licenses.

The [consumer modules](../tests/modules/README.md) live separately under
tests/modules/ as future parity fixtures. They are not development references.

| Project | Revision                                       | Purpose                    |
| ------- | ---------------------------------------------- | -------------------------- |
| Lua     | `v5.5.1`                                       | Semantics, C API, tests    |
| ada-lua | `7c5c03413a35a3b0e57903a633b0b5243e0d5e7f`     | Ada embedding design input |

Lua's pinned commit is `7579fc9d7ed90240487251dfb69168f8e64e9294`.
Origins are [lua/lua](https://github.com/lua/lua) and
[Nikokrock/ada-lua](https://github.com/Nikokrock/ada-lua).

## Checkout

```text
git -c core.autocrlf=false submodule update --init --recursive -- references/lua references/ada-lua
git submodule status -- references/lua references/ada-lua
```

A submodule is intentionally detached at its recorded commit. Do not use
`git submodule update --remote` as a routine setup command.

Materialize the pinned bytes with automatic newline conversion disabled,
including on Windows. The conformance inventory hashes original LF source
bytes; a CRLF-converted checkout is not that byte baseline even if Git reports
it clean. Parent attributes do not govern submodule files. CI sets this Git
policy before recursive checkout. For an existing converted checkout, preserve
any local changes and obtain a fresh reference checkout with this policy;
do not rewrite reference sources or regenerate the ledger to hide hash drift.

## Deliberate update

1. Check parent/submodule status and preserve local changes.
2. Verify the intended upstream release or snapshot and inspect its changes.
3. Fetch in the relevant submodule and check out the explicit tag/commit detached.
4. Record the full resolved SHA, baseline changes, licenses, and test impact.
5. Update compatibility documents, evidence, and a decision/session as needed.
6. Stage the changed gitlink with the associated documentation for review.

Do not claim compatibility with an updated baseline until its acceptance checks
run. Build C Lua separately as an oracle; never substitute it for the Ada core.
