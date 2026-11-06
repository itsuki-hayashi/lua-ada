/* Build unchanged fixture sources with real public API imports. Module entry
 * points are exported independently of Lua's own DLL export declarations. */
#ifndef CONFORMANCE_MODULE_EXPORTS_H
#define CONFORMANCE_MODULE_EXPORTS_H
#include "../../../references/lua/lprefix.h"
#include "../../../references/lua/luaconf.h"
#if defined(_WIN32)
#undef LUA_API
#define LUA_API extern
#undef LUAMOD_API
#define LUAMOD_API __declspec(dllexport)
#endif
#endif
