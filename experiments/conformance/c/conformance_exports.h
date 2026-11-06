/* ltests.h declares its shared Memcontrol object using LUA_API. On Windows
 * upstream's dllexport spelling omits extern, which creates tentative data
 * definitions in every translation unit with modern GCC -fno-common.
 * Preserve the headers and ABI, but give these declarations explicit external
 * linkage in this oracle-only forced include. The initialized definition still
 * belongs solely to unchanged ltests.c. Do not weaken -fno-common globally. */
#ifndef CONFORMANCE_EXPORTS_H
#define CONFORMANCE_EXPORTS_H
#include "../../../references/lua/lprefix.h"
#include "../../../references/lua/luaconf.h"
#if defined(_WIN32) && defined(LUA_BUILD_AS_DLL)
#undef LUA_API
#if defined(CONFORMANCE_LIBRARY_EXPORTS)
#define LUA_API extern __declspec(dllexport)
#else
#define LUA_API extern __declspec(dllimport)
#endif
#endif
#endif
