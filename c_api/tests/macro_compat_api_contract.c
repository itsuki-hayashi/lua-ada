/* Explicit SDK client opt-ins, not a different Lua runtime configuration.
 * MIT; see ../../LICENSE. The shared source emits and verifies these flags;
 * neither inactive ordinary aliases nor nil/false branches become passes
 * merely because the other receiver compiled them. */
#ifndef LUA_COMPAT_APIINTCASTS
#define LUA_COMPAT_APIINTCASTS
#endif
#ifndef LUA_FAILISFALSE
#define LUA_FAILISFALSE
#endif
#include "macro_api_contract.c"
