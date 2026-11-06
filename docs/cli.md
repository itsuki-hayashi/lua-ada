# Batch Command Line

The CLI uses the same Sessions and Syntax interfaces as Ada consumers.
The current library surface is listed in [capabilities](capabilities.md);
[status](status.md) owns platform evidence. This is a Lua subset, not a complete
replacement for every C Lua command-line option.

```text
lua_ada [--check] [-e code]... [--] [script | -] [arguments...]
lua_ada --help | --version
```

Repeated `-e` snippets are separate chunks in the same session, evaluated in
command-line order before an optional script. A file path executes that file;
`-` explicitly reads stdin. Trailing values become script arguments under the
existing option rules, and `--` ends option parsing. Execution supplies `arg`.
With no execution input, display usage; an interactive REPL remains deferred.

`--check` validates each requested chunk without executing it, creating globals,
or loading modules. It accepts the same files, snippets, explicit stdin, `--`,
and trailing argument structure. A successful check emits no stdout unless help
or version was requested. Stop at the first failed chunk. A valid construct may
check successfully without being executed. Goto, labels and closing declarations
now execute through the lifecycle runtime. See [frontend checking](frontend.md).

File/stdin loading preserves bytes and handles the file preamble, including BOM
and initial interpreter line. Raw `-e` snippets are not file loading. Runtime
`loadfile`/`dofile` use the shared file handling; raw `load` source is distinct.

Output already produced before a failure remains visible. Diagnostics go to
stderr and failures return a failing process status. Binary chunks, native
modules, a REPL, and the complete C Lua flag surface remain deferred. Library
text loading and Lua-only require are M2b features; their local default path is
`./?.lua;./?/init.lua` and does not read Lua path environment variables.

The dedicated upstream test runner is separate from the product CLI. Its
explicit test instruction profile does not alter CLI defaults or establish a
new user-facing resource-limit option.

Normal execution selects Lua_Compatible before installing arguments or loading
source. Project instruction, source, heap, output and call quotas are removed;
checked representations, frontend nesting and Lua semantic stack/native-depth
checks remain. File/stdin, -e, load readers and runtime file loading use the same
policy. CLI --check passes policy-derived limits explicitly; the standalone
Lua.Syntax.Check API retains its bounded defaults. This policy name describes
limits, not complete Lua or C ABI compatibility. See
[execution policy](embedding.md) and [lifecycle acceptance](milestones/m3-language-lifecycle.md).
