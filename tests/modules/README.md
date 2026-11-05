# Real-World Module Test Fixtures

These eight third-party submodules are source inputs for future feature-parity
testing between pinned C Lua 5.5.1 and Lua Ada. They are kept separately from
the development references in [references/](../../references/README.md).
Do not use their implementation as a development/design reference or add them
to production source paths or runtime dependencies.

**Current state: checkout and documentation only.** No module has been built,
installed, loaded, or tested in this setup. No parity runner or CI job has been
added. M1 capabilities and its historical validation evidence are unchanged.

The maintainer selected these projects for expected C Lua 5.5 compatibility
on Windows, macOS, and Linux. That is the selection basis; this repository has
not independently exercised the pinned snapshots on those platforms.
For every module, C-oracle execution and Lua Ada parity are **not run** on all
three target operating systems.

## Source inventory and immutable pins

Selection date: 2026-11-06, Asia/Tokyo. Each pin is the upstream default-branch
(`master`) HEAD inspected on that date, rather than a claimed release tag.
The parent Git repository records a full commit gitlink; checkouts are detached.
There is no moving branch setting or automatic remote update policy.

| Fixture                         | Upstream                                                                    | Pinned commit                              |
| ------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------ |
| [LPeg](lpeg/)                   | [roberto-ieru/LPeg](https://github.com/roberto-ieru/LPeg)                   | `089112f883540c4434e9e8e96de50a75f2b15f7e` |
| [Say](say/)                     | [lunarmodules/say](https://github.com/lunarmodules/say)                     | `06484f676e170e822a4b3ff936f8ab15b7541178` |
| [Penlight](penlight/)           | [lunarmodules/Penlight](https://github.com/lunarmodules/Penlight)           | `7f3351f226c2f643aaa1d3afa8d7293dd8a1d985` |
| [LuaSocket](luasocket/)         | [lunarmodules/luasocket](https://github.com/lunarmodules/luasocket)         | `35187983315e3a9bb920e73ca94d19ffe17ba385` |
| [Busted](busted/)               | [lunarmodules/busted](https://github.com/lunarmodules/busted)               | `22f8089f461a563fb9553ab56f926c6805850833` |
| [LuaFileSystem](luafilesystem/) | [lunarmodules/luafilesystem](https://github.com/lunarmodules/luafilesystem) | `146ab458e821cd7617892099fe8e6e399b46185c` |
| [LuaSQL](luasql/)               | [lunarmodules/luasql](https://github.com/lunarmodules/luasql)               | `491fea76b9d9ee613fcd7de6b8a1c902e3668d11` |
| [luacheck](luacheck/)           | [lunarmodules/luacheck](https://github.com/lunarmodules/luacheck)           | `2f764bdcabe8b7c19deadf0e9bb2adc19df1a4c5` |

## Intended future coverage and prerequisites

These are planning notes from the checked-out READMEs and current development
rockspecs, not an installed dependency lock or a module-support claim.

| Fixture       | Intended consumer coverage                        | Future setup notes                                                             |
| ------------- | ------------------------------------------------- | ------------------------------------------------------------------------------ |
| LPeg          | Patterns, captures, matching, native-module ABI   | C extension; matching Lua headers/library and native compiler                  |
| Say           | String lookup, namespaces, localization           | Lua implementation; its upstream tests use Busted                              |
| Penlight      | Collections, utilities, paths, filesystem helpers | Lua implementation; rockspec requires native LuaFileSystem                     |
| LuaSocket     | Socket APIs, networking, protocol helpers         | C components plus Lua modules; controlled network fixtures                     |
| Busted        | Real-world Lua test-runner behavior               | Lua implementation; dependency tree includes native modules                    |
| LuaFileSystem | Paths, metadata, directory operations             | C extension; temporary filesystem fixtures and OS-specific expectations        |
| LuaSQL        | Driver loading, connections, queries, cursors     | C extensions; select/pin DB client libraries, drivers, and services separately |
| luacheck      | Lua parsing/linting, CLI behavior, diagnostics    | Lua implementation; rockspec requires argparse and native LuaFileSystem        |

Busted's current [rockspec](busted/busted-scm-1.rockspec) lists lua_cliargs,
luasystem, dkjson, Say, luassert, lua-term, Penlight, and mediator_lua. These
eight checkouts do not provision that dependency closure. Penlight's
[rockspec](penlight/penlight-dev-1.rockspec) and luacheck's
[rockspec](luacheck/luacheck-dev-1.rockspec) also show why a Lua implementation
does not imply an entirely Lua-only runtime/test environment. No additional
dependencies are installed or added as submodules in this change.

Future comparisons must record each module's commit, separately resolved
dependencies, OS/architecture, Lua numeric/ABI configuration, compiler/linker,
library kind, and any network/database setup. Preserve upstream tests and
expected behavior. Record C-oracle and Ada results separately, including
blocked or deferred coverage. A checkout, successful build, or oracle-only run
does not establish Ada module parity. See [compatibility](../../docs/compatibility.md)
and the future MOD-001 gate in the [backlog](../../docs/backlog.md).

## Checkout and updates

From the repository root, populate only these fixtures with:

```text
git submodule update --init --recursive -- tests/modules
git submodule status -- tests/modules
```

A full `git clone --recurse-submodules` also includes them. Ordinary Ada builds
do not use these sources. Existing GPR source directories and test drivers stay
explicit; tests/lua contains the separately authored differential scripts.

Update one fixture deliberately:

1. Inspect parent and submodule status; preserve local changes.
2. Fetch the intended upstream commit or release, review its changes and
   dependency/license impact, then check it out detached.
3. Update this inventory's full SHA and selection rationale, stage the gitlink
   with its documentation, and add a dated session record.
4. Keep prior execution evidence tied to its original snapshot. New pins have
   no inherited passing result.

Do not use `git submodule update --remote` for normal setup. Do not edit upstream
trees or assertions to make Lua Ada appear compatible. When later authorized,
build/install and run suites in disposable work areas outside these checkouts;
generated files must not dirty the pinned sources. No fixture integration,
dependency installation, or execution is part of the present setup.

## Upstream notices

Preserve the original notices within each checkout. Entry points are
[LPeg's license](lpeg/lpeg.html#license), [Say](say/LICENSE),
[Penlight](penlight/LICENSE.md), [LuaSocket](luasocket/LICENSE),
[Busted](busted/LICENSE), [LuaFileSystem](luafilesystem/LICENSE),
[LuaSQL](luasql/doc/us/license.html), and [luacheck](luacheck/LICENSE).
Vendored components and future dependency packages retain their own notices.
These checkouts do not change the first-party MIT license.
