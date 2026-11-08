/* Actual C ABI callbacks for Lua reader lifetime regressions. MIT license. */
#include "lua.h"
#include "lauxlib.h"

int lua_ada_test_reader_self_close(lua_State *state) {
    lua_closethread(state, state);
    return luaL_error(state, "self-closed reader C body resumed");
}

int lua_ada_test_reader_direct_load(lua_State *state) {
    lua_CFunction loader;
    lua_getglobal(state, "load");
    loader = lua_tocfunction(state, -1);
    lua_pop(state, 1);
    return loader(state);
}
