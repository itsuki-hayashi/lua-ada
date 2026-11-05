# Reference Projects

These submodules are read-only implementation/API references, not dependencies.
Keep their sources outside production GPR source paths and preserve their licenses.

| Project | Revision                                       | Purpose                    |
| ------- | ---------------------------------------------- | -------------------------- |
| Lua     | `v5.5.1`                                       | Semantics, C API, tests    |
| ada-lua | `7c5c03413a35a3b0e57903a633b0b5243e0d5e7f`     | Ada embedding design input |

Lua's pinned commit is `7579fc9d7ed90240487251dfb69168f8e64e9294`.
Origins are [lua/lua](https://github.com/lua/lua) and
[Nikokrock/ada-lua](https://github.com/Nikokrock/ada-lua).

## Checkout

```text
git submodule update --init --recursive
git submodule status
```

A submodule is intentionally detached at its recorded commit. Do not use
`git submodule update --remote` as a routine setup command.

## Deliberate update

1. Check parent/submodule status and preserve local changes.
2. Verify the intended upstream release or snapshot and inspect its changes.
3. Fetch in the relevant submodule and check out the explicit tag/commit detached.
4. Record the full resolved SHA, baseline changes, licenses, and test impact.
5. Update compatibility documents, evidence, and a decision/session as needed.
6. Stage the changed gitlink with the associated documentation for review.

Do not claim compatibility with an updated baseline until its acceptance checks
run. Build C Lua separately as an oracle; never substitute it for the Ada core.
