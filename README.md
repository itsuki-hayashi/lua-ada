# Lua Ada

Lua Ada aims to reimplement current Lua in idiomatic Ada 2022, with compatible
language behavior, a drop-in public C API/ABI, and a safer native Ada embedding
interface. The initial compatibility baseline is **Lua 5.5.1**.

**Current capability:** reusable static/shared Ada sessions and a batch CLI
execute the documented [M1 Lua subset](docs/milestones/m1.md), including closures,
tables, tracing collection, and a small base library. Complete Lua compatibility,
C exports, and LuaRocks remain later milestones. **M1 is complete**; see the
[validated platform matrix](docs/validation.md).
See [status](docs/status.md) for actual verification evidence.

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
library kinds exist; Alire cannot infer one. See [embedding](docs/embedding.md).

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
for each platform and ABI configuration. Static/shared acceptance passed all
three profiles on Windows x86-64, Linux x86-64, and macOS ARM64; see
[exact configurations and evidence](docs/validation.md).

## License

First-party work uses the [MIT license](LICENSE). Reference submodules retain
their own licenses and copyright notices; they are not runtime dependencies.
The [consumer module fixtures](tests/modules/README.md) likewise retain their
upstream notices and serve only as future test inputs.
