/* Test-only public C API drivers. See conformance_adapter.sources.md. */
#ifndef LUA_ADA_CONFORMANCE_API_H
#define LUA_ADA_CONFORMANCE_API_H

#include "lua.h"

lua_CFunction lua_ada_test_api_callback(int operation);

#endif
