# API Documentation

Use GNATdoc's `--style=gnat` (trailing) convention and public API scope by
default. Keep declaration documentation adjacent, at the same indentation,
without an intervening blank line. Packages have additional attachment rules;
see the [GNATdoc annotations guide](https://docs.adacore.com/gnatdoc-docs/users_guide/_build/html/annotations.html).

Declaration convention:

```ada
function Count (Text : String) return Natural;
--  Count the bytes in Text.
--  @param Text Byte sequence to inspect.
--  @return Number of bytes in Text.
```

Document parameters, returns, raised exceptions, record fields, enumeration
literals, and generic formals with the applicable `@param`, `@return`,
`@exception`, `@field`, `@enum`, and `@formal` tags. Describe ownership,
invalidated handles, callback lifetimes, contracts, and concurrency rules.
Use internal comments for invariants and Markdown for architecture/rationale.

## Planned generation workflow

Public runtime declarations now include `Lua.Sessions` and numeric/lexical
helpers. The [embedding guide](embedding.md) explains ownership and errors.
GNATdoc remains an optional developer installation; rendered output has not
been generated or verified in M1. When the tool is installed:

1. Build it through Alire with the same environment used for documentation.
2. Run GNATdoc through `alr exec`, passing explicit style, scope, and warnings.
3. Capture logs under ignored `reports/`; generate HTML under ignored
   `docs/generated/` and keep authored Markdown tracked.
4. Check diagnostics for undocumented changed entities and errors. Verify the
   output directory and `index.html`, then inspect rendered declarations/tags.
   A zero exit code alone is not documentation coverage.

Planned generation command (tool availability and rendered output unverified):

```text
alr exec -- gnatdoc -P lua_ada.gpr --backend=html --style=gnat --generate=public --warnings -O docs/generated/api
```

Private/body documentation can be generated deliberately for internal reviews;
do not change the public default silently. Locate installed tools explicitly
rather than guessing a vendor installation's environment.
