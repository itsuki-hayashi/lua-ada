# Public Lua Header Contract

These four installable public headers are unchanged byte copies from pinned
Lua commit 7579fc9d7ed90240487251dfb69168f8e64e9294. They describe the C interface
being implemented, not the Ada interpreter's private representation. No C
interpreter source is included in the production library.

manifest.json records each original path and SHA-256. Verify all four files
against both that manifest and the pinned reference checkout before accepting
an ABI result. The original copyright/license notice remains in lua.h; see the
[license copy](../../../docs/licenses/lua.md). Header updates require a deliberate
reference/API review and regenerated hash evidence, never incidental editing.

Production C builds include these local headers, so reference-only directories
are not production include paths. Tests may compile clients against these and
against the pinned originals to verify interchangeable public declarations.
The default/instrumented configuration distinction still applies: including an
internal ltests.h is not supported by simply copying C private layouts.
