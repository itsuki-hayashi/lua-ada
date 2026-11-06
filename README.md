# Lua Ada

Lua Ada aims to reimplement current Lua in idiomatic Ada 2022, with compatible
language behavior, a drop-in public C API/ABI, and a safer native Ada embedding
interface. The initial compatibility baseline is **Lua 5.5.1**.

**Current capability:** reusable static/shared Ada sessions and a batch CLI
execute the accepted [M1 Lua subset](docs/milestones/m1.md). M2b implementation
adds core metamethods, strings/patterns/packing, UTF-8, common table/math helpers,
and text/module loading; its full platform matrix has passed. See the
[export inventory](docs/capabilities.md) and [status](docs/status.md) for exact
scope and evidence. Complete Lua compatibility, C exports, native modules, and
LuaRocks remain later milestones. **M1 is complete**, with its
[validated platform matrix](docs/validation.md).

Syntax checking uses the shared Lua 5.5.1 frontend through Lua.Syntax.Check or
CLI --check. It accepts valid deferred syntax without executing it. See the
[frontend guide](docs/frontend.md) for limits and compatibility boundaries.
**M2a is complete**, with [three-platform evidence](docs/validation-m2a.md).
[M2b](docs/milestones/m2b.md) targets three unchanged upstream execution files:
tpack.lua, utf8.lua, and bitwise.lua. bwcoercion.lua is their helper, not a fourth
suite. All three pass on Windows, Linux, and macOS; the
[M2b validation record](docs/validation-m2b.md) documents exact evidence and
does not establish full standard-suite conformance.

[M3](docs/milestones/m3.md) is the active complete-upstream-coverage milestone.
It combines remaining runtime/libraries, canonical bytecode execution and the
public C API/ABI through staged PRs. Its first gate establishes an explicit
[conformance inventory and harness](tests/conformance/README.md). Full M3
coverage remains in progress; reviewed C-internal/native-platform equivalents
will be reported separately from unchanged test execution. Production behavior
is unchanged by this foundation work.

## Checkout and build

Install [Alire](https://alire.ada.dev/) and use the latest stable native GNAT
available through Alire. Run these commands from a PowerShell or POSIX shell:

```text
git clone --recurse-submodules https://github.com/itsuki-hayashi/lua-ada.git
cd lua-ada
alr build --development
alr -C cli build
alr -C cli exec -- bin/static/lua_ada --help
```

For an existing checkout, run `git submodule update --init --recursive`.
Run scripts with `alr -C cli exec -- bin/static/lua_ada script.lua`, snippets
with `-e 'print(6 * 7)'`, or explicit stdin with `-`. Repeated snippets share one
session. No input displays usage. Select an explicit binary path when multiple
library kinds exist; Alire cannot infer one. See [embedding](docs/embedding.md)
and the [batch CLI guide](docs/cli.md).

## Repository map

| Location          | Responsibility                                   |
| ----------------- | ------------------------------------------------ |
| `src/`            | Reusable Ada library sources                     |
| `alire.toml`      | Metadata and profile-wide runtime checks         |
| `lua_ada.gpr`     | Build entry point and mandatory compiler flags   |
| `docs/`           | Development and project management               |
| `tests/`          | Focused AUnit and differential Lua fixtures      |
| `tests/modules/`  | Pinned consumer modules for future parity tests  |
| `cli/`            | Separate batch CLI crate                         |
| `scripts/`        | Build/test and differential drivers              |
| `experiments/`    | Isolated reference and C ABI fixtures            |
| `references/`     | Pinned reference-only submodules                 |
| `config/`, `obj/` | Generated local configuration and build products |

Start with [agent instructions](AGENTS.md), [architecture](ARCHITECTURE.md),
[goals](docs/goals.md), and the [documentation index](docs/README.md).
See [contributing](CONTRIBUTING.md) for the development workflow.

Windows, Linux, and macOS are target platforms. Support claims require evidence
for each platform and ABI configuration. Historical M1 static/shared acceptance passed all
three profiles on Windows x86-64, Linux x86-64, and macOS ARM64; see
[exact configurations and evidence](docs/validation.md).

## License

First-party work uses the [MIT license](LICENSE). Reference submodules retain
their own licenses and copyright notices; they are not runtime dependencies.
Canonical opcode definitions preserve the [Lua notice](docs/licenses/lua.md).
The [consumer module fixtures](tests/modules/README.md) likewise retain their
upstream notices and serve only as future test inputs.
