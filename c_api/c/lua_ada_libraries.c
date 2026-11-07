/* Standard-library initialization and auxiliary module publication.
 * These are C ABI/OS glue only: actual library implementations and Lua
 * execution remain in the owning Ada runtime. The public stack algorithms
 * follow pinned Lua 5.5.1 lauxlib.c:1000-1047 and linit.c:27-70.
 * Copyright (C) 1994-2026 Lua.org, PUC-Rio. See lua.h for the MIT notice.
 */
#include "lua_ada_runtime_configuration.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lua_ada_boundary.h"
#include <stddef.h>
#include <string.h>

/* The selector belongs to this first-party boundary, not to the public Lua
 * headers. Each constructor returns its actual Ada module on the C stack;
 * luaL_requiref below independently owns publication and registry caching. */
static int open_module(lua_State *L, int kind) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    memset(&input, 0, sizeof input);
    memset(&output, 0, sizeof output);
    input.operation = ADA_OPEN_STANDARD_MODULE;
    input.index = kind;
    lua_ada_debug_dispatch(L, &input, &output);
    return (int)output.integer_data;
}

int luaopen_base(lua_State *L) { return open_module(L, 0); }
int luaopen_package(lua_State *L) { return open_module(L, 1); }
int luaopen_coroutine(lua_State *L) { return open_module(L, 2); }
int luaopen_debug(lua_State *L) { return open_module(L, 3); }
int luaopen_math(lua_State *L) { return open_module(L, 4); }
int luaopen_string(lua_State *L) { return open_module(L, 5); }
int luaopen_table(lua_State *L) { return open_module(L, 6); }
int luaopen_utf8(lua_State *L) { return open_module(L, 7); }

int luaL_getsubtable(lua_State *L, int index, const char *name) {
    if (lua_getfield(L, index, name) == LUA_TTABLE) return 1;
    lua_pop(L, 1);
    index = lua_absindex(L, index);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_setfield(L, index, name);
    return 0;
}

void luaL_requiref(lua_State *L, const char *name, lua_CFunction opener,
                  int global) {
    /* Keep the registry-owned loaded table on the public stack throughout
     * the opener call. A real protected-call guard owns every possible C
     * error transfer; no saved C frame becomes an Ada continuation. */
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
    lua_getfield(L, -1, name);
    if (!lua_toboolean(L, -1)) {
        lua_pop(L, 1);
        lua_pushcfunction(L, opener);
        lua_pushstring(L, name);
        lua_call(L, 1, 1);
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, name);
    }
    lua_remove(L, -2);
    if (global) {
        lua_pushvalue(L, -1);
        lua_setglobal(L, name);
    }
}

void luaL_openselectedlibs(lua_State *L, int load, int preload) {
    static const struct {
        const char *name;
        lua_CFunction opener;
    } libraries[] = {
        {"_G", luaopen_base}, {"package", luaopen_package},
        {"coroutine", luaopen_coroutine}, {"debug", luaopen_debug},
        {"io", luaopen_io}, {"math", luaopen_math}, {"os", luaopen_os},
        {"string", luaopen_string}, {"table", luaopen_table},
        {"utf8", luaopen_utf8}
    };
    unsigned mask = 1;
    size_t i;
    /* Opening wins over preloading for the same bit. Keep the original
     * ordering because base/package publication is visible to later openers
     * and a preloaded opener must be the real exported C function pointer. */
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    for (i = 0; i < sizeof(libraries) / sizeof(libraries[0]); ++i) {
        if ((unsigned)load & mask) {
            luaL_requiref(L, libraries[i].name, libraries[i].opener, 1);
            lua_pop(L, 1);
        } else if ((unsigned)preload & mask) {
            lua_pushcfunction(L, libraries[i].opener);
            lua_setfield(L, -2, libraries[i].name);
        }
        mask <<= 1;
    }
    lua_pop(L, 1);
}
