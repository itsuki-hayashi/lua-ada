# Lua Ada

Lua Ada aims to reimplement current Lua in idiomatic Ada 2022, with compatible
language behavior, a drop-in public C API/ABI, and a safer native Ada embedding
interface. The initial compatibility baseline is **Lua 5.5.1**.

**Current capability:** static/shared libraries, tested lexical analysis and
integer primitives, a development CLI, and test/reference infrastructure.
It cannot execute Lua scripts or load LuaRocks modules yet. M1 is in progress.
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
The CLI supports help/version and rejects execution requests. Select an explicit
binary path when multiple library kinds exist; Alire cannot infer one.

## Repository map

| Location          | Responsibility                                   |
| ----------------- | ------------------------------------------------ |
| `src/`            | Reusable Ada library sources                     |
| `alire.toml`      | Metadata and profile-wide runtime checks         |
| `lua_ada.gpr`     | Build entry point and mandatory compiler flags   |
| `docs/`           | Development and project management               |
| `tests/`          | Test strategy and future test layout             |
| `cli/`            | Separate development CLI crate                   |
| `scripts/`        | Build/test and differential drivers              |
| `experiments/`    | Isolated reference and C ABI fixtures            |
| `references/`     | Pinned reference-only submodules                 |
| `config/`, `obj/` | Generated local configuration and build products |

Start with [agent instructions](AGENTS.md), [architecture](ARCHITECTURE.md),
[goals](docs/goals.md), and the [documentation index](docs/README.md).
See [contributing](CONTRIBUTING.md) for the development workflow.

Windows, Linux, and macOS are target platforms. Support claims require evidence
for each platform and ABI configuration. Static/shared consumers pass on Windows;
Linux/macOS CI awaits execution.

## License

First-party work uses the [MIT license](LICENSE). Reference submodules retain
their own licenses and copyright notices; they are not runtime dependencies.
