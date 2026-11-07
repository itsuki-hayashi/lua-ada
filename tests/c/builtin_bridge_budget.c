/* Actual direct standard-library C pointer invoked by a bounded Ada host.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"

static int forward_pairs(lua_State *L) {
    lua_CFunction function;
    lua_getglobal(L, "pairs");
    function = lua_tocfunction(L, -1);
    lua_pop(L, 1);
    if (function == NULL) {
        lua_pushliteral(L, "pairs has no callable C identity");
        return lua_error(L);
    }
    return function(L);
}

lua_CFunction lua_ada_test_builtin_bridge(void) { return forward_pairs; }
