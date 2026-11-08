# Batch Command Line

The CLI uses the same Sessions and Syntax interfaces as Ada consumers.
The current library surface is listed in [capabilities](capabilities.md);
[status](status.md) owns platform evidence. This is a Lua subset, not a complete
replacement for every C Lua command-line option.

```text
lua_ada [--check] [-e stat | -l [g=]mod | -W | -E | -v | -i]...
        [--] [script | -] [arguments...]
lua_ada --help | --version
```

Options follow `lua.c` `collectargs`: `-e`/`-l` take an operand that exists and
does not begin with `-`; other malformed options print the C-style
"unrecognized option"/"needs argument" usage on stderr and fail. `-e`, `-l`
and `-W` are separate actions run in command-line order in one session before
an optional script. A file path executes that file; `-` reads stdin, except
after `--`, where it is a file name. Trailing values become script arguments,
`--` ends option parsing, and execution supplies `arg`. `-v` prints the native
banner (`Lua 5.5.1  Copyright (C) 1994-2026 Lua.org, PUC-Rio`); `-i` implies
it. `--version` remains the project banner and is a separate option.

Startup order mirrors `pmain`: `arg`, package-path environment, `LUA_INIT_5_5`
(else `LUA_INIT`; `@file` is `dofile` semantics, otherwise a chunk named
`=LUA_INIT_5_5`/`=LUA_INIT`), the warning default, then the ordered
actions, then the script. `-E` skips the environment variables.
`LUA_PATH_5_5`/`LUA_PATH` and the `CPATH` pair are applied by the CLI host to
`package.path`/`package.cpath` before user code, with the first `;;` replaced
by the default. The CLI uses the internal host package operation, which sets
the actual registry `LUA_NOENV` field and configures paths through the shared
native-module loader. `-E` sets that field to true; ordinary startup clears it.
`-l` runs `g = require(mod)` through the global `require` as a small internal
chunk, which is one extra Lua frame during `require` (lua.c uses a C call).
`-W` delivers `@on` through the actual warning mechanism, independently of
the replaceable `warn` global. Initialization runs with the initial enabled
handler; the interpreter turns warnings off before processing the actions.

With no script and no `-e`/`-v`/`-i`, redirected stdin is executed as the
program (chunk name `=stdin`) and a terminal enters the REPL after the banner.
`-i` enters the REPL after the script. The REPL is a host loop, not a Lua
bootstrap loop: each entry is tried as `return <line>;` and otherwise as a
statement, continuing with the `>> ` prompt while the shared checker reports
unfinished input through its structured completeness result. Results are
printed by resolving the actual current
global `print` after the chunk returns, in a second sequential drive with the
results held in a traced root (`Lua.Sessions.Execute_Display`); a failing
`print` is reported as `error calling 'print' (...)` and does not end the loop.
Statement and display errors leave the REPL running. Before each read, the
host resolves the current `_PROMPT` or `_PROMPT2` through the actual global
environment. Nil selects `> ` or `>> `; other values use auxiliary string
conversion, including `__tostring`, independently of the public `tostring`
global. The converted string remains rooted until its C-string prefix is
written and flushed. Prompt lookup/conversion failure is a fatal raw
diagnostic, and `os.exit` preserves its typed exit code/close request. The
[CLI-only prompt transport](decisions/0039-cli-prompt-transport.md) retains the
actual anonymous C callback frame without a Lua shim. Readline, SIGINT/hook
interruption and tracebacks in REPL errors remain deferred.

`--check` validates each requested chunk without executing it, creating globals,
or loading modules. It accepts the same files, snippets, explicit stdin, `--`,
and trailing argument structure. A successful check emits no stdout unless help
or version was requested. Stop at the first failed chunk. A valid construct may
check successfully without being executed. Goto, labels and closing declarations
now execute through the lifecycle runtime. See [frontend checking](frontend.md).

File loading preserves bytes and handles the file preamble, including BOM
and initial interpreter line. Stdin is read through the shared native `stdin`
stream in untranslated binary mode (`lua_ada_stream_set_binary`), so NUL, CR and
Ctrl-Z bytes survive and a precompiled chunk can be piped; line-end handling is
left to the Lua frontend.
Raw `-e` snippets are not file loading. Runtime
`loadfile`/`dofile` use the shared file handling; raw `load` source is distinct.

Normal execution selects Process_Streams output delivery. Runtime stdout bytes
are written immediately through native stdio, including embedded NUL/high
bytes; each print flushes its completed line. Earlier Ada help/version output
is flushed before this switch, and captured result output is not replayed.
Output already produced before a failure remains visible. Diagnostics go to
stderr and failures return a failing process status. Script files now accept
native Lua 5.5.1 binary chunks for the matching host configuration, including
the shared BOM/interpreter-line handling. Runtime load/loadfile mode filters
select text or binary input, and string.dump serializes actual prototypes.
CLI --check remains text-only. Package loading includes binary Lua modules,
native searchers and `package.loadlib`; native handles remain owned through
state cleanup. Host-specific module and loader validation is recorded in
[status](status.md) and does not establish ecosystem-module acceptance.
Readline and signal handling remain deferred. The CLI host applies the path
environment variables described above through the shared package operation.

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
