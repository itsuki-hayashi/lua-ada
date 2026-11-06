# Runtime Build Configurations

The source-selected private Lua.Runtime_Configuration package distinguishes
ordinary Lua 5.5.1 behavior from the pinned upstream test build. These constants
are independent of Alire's development/validation/release profiles and the
static/static-PIC/shared library modes. A build profile never weakens compiler
warnings, style rules or ordinary runtime checks.

| Setting                   | default   | upstream-test |
| ------------------------- | --------- | ------------- |
| Contextual global keyword | true      | false         |
| Compatibility math names  | false     | true          |
| Actual 32-bit RNG path    | false     | true          |
| Lua semantic stack slots  | 1,000,000 | 68,000        |
| Native call-depth limit   | 200       | 180           |

These values follow pinned luaconf.h, llimits.h and ltests.h. The RNG selection
chooses real split-word arithmetic; it is not a report-only flag. Math names
are selected when each world initializes. The shared scanner/parser use the
selected global-keyword mode, including independent syntax checking.

## Build selection and artifacts

The default remains unchanged. Select the other configuration explicitly:

```powershell
alr -C tests build --validation --profiles=lua_ada=validation -- `
  -XLUA_ADA_CONFIGURATION=upstream-test
alr -C cli build --validation --profiles=lua_ada=validation -- `
  -XLUA_ADA_CONFIGURATION=upstream-test
```

runtime_configuration.gpr selects one first-party specification from
src/configurations. Generated Alire configuration is never edited. The default
object/library/executable paths remain unchanged. Instrumented artifacts add
upstream-test as a subdirectory: for example,
tests/bin/upstream-test/static/test_runner and
lib/upstream-test/validation/static. CLI and C-facade artifacts use the same
separation. Select the matching library directory when executing shared builds.

scripts/check-runtime-configuration.ps1 takes Configuration and the built
lua-configuration_probe executable. It verifies selected limits, actual math
registration/RNG selection and reserved-global parsing. Raw output and JSON
live under reports/runtime-configuration. This narrow witness is distinct from
the complete conformance launcher's measured configuration/T-adapter handshake.

## Boundaries

The configuration package does not install T, reproduce private C layouts,
provide lock-state extra space or certify allocator/ABI behavior. Those remain
separately implemented and verified adapter obligations. C test-only extra-space
layout belongs to the foreign-state implementation. Matching selected constants
alone never makes the upstream instrumented configuration accepted.

The root Lua_Ada project builds one configured standalone library named lua.
Ada and C consumers import that same image; the legacy C-facade project only
forwards its build. The [one-core decision](decisions/0014-one-core-library.md)
owns this distinction: artifact separation between configurations must not create
two interpreter images within a consumer. The permanent core-image checks use
the selected production library and verify actual state, pool, allocator and
elaboration identity. Each configuration/platform still needs its own evidence.
