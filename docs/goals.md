# Project Goals

Serve Lua application developers, C embedders, native module authors, and Ada
developers needing a safer idiomatic interface.

## Long-term success

- Implement current Lua semantics, starting from pinned Lua 5.5.1.
- Pass applicable unchanged upstream language/public API tests, with reviewed
  Ada equivalents for assertions coupled to C internals.
- Provide a drop-in public C API/ABI on explicitly validated configurations,
  including existing clients and compatible LuaRocks native modules.
- Offer owned Ada sessions, rooted references, typed operations, and predictable
  errors that improve on stack-only bindings.
- Support static/shared libraries and compatible command-line behavior.
- Use maintainable Ada 2022, strict diagnostics, runtime safety, extensive AUnit
  and compatibility tests, and maintained API/design documentation.
- Prefer standard Ada libraries; justify and isolate essential C/OS glue.

## Foundation boundary

This milestone establishes layout, compiler policy, reference revisions,
documentation, and follow-up management. It implements no language feature and
does not establish compatibility. See [status](status.md).

Do not mechanically translate C or hide a C interpreter backend. Idiomatic Ada
does not require universal inheritance. Internal layouts may differ except
where observable public ABI behavior imposes constraints.

Reference updates are deliberate changes. Verify newer stable Lua and compiler
releases, record the date and versions, and refresh evidence before changing
the accepted baseline. Do not track moving branches as compatibility oracles.
