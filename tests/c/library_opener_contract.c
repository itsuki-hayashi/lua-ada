/* Direct public constructors must expose actual functional module tables.
 * Each numbered case runs in a fresh bare state and is also linked unchanged
 * into the separately built pinned C oracle consumer.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stddef.h>
#include <string.h>

static lua_CFunction selected_opener;
static int opened_results, opened_delta;

static int open_checked(lua_State *L) {
    int before = lua_gettop(L);
    int results = selected_opener(L);
    opened_results = results;
    opened_delta = lua_gettop(L) - before;
    return results;
}

static int push_export(lua_State *L, const char *name) {
    lua_getfield(L, 1, name);
    if (lua_type(L, -1) != LUA_TFUNCTION) return 1;
    /* The caller supplies arguments after this helper returns. This initial
     * check observes the actual public function type, not a field name list. */
    return 0;
}

int lua_ada_test_library_opener_contract(int which) {
    static const char *const names[] = {"debug", "string", "table", "utf8"};
    lua_State *L;
    int result = 0;
    size_t length;
    const char *bytes;
    if (which < 1 || which > 4) return 100;
    L = luaL_newstate();
    if (L == NULL) return 101;
    selected_opener = which == 1 ? luaopen_debug :
        which == 2 ? luaopen_string : which == 3 ? luaopen_table : luaopen_utf8;
    opened_results = opened_delta = -1;
    lua_pushcfunction(L, open_checked);
    if (lua_pcall(L, 0, 1, 0) != LUA_OK || !lua_istable(L, 1) ||
        opened_results != 1 || opened_delta != 1) { result = 102; goto done; }
    lua_getglobal(L, names[which - 1]);
    if (!lua_isnil(L, -1)) { result = 103; goto done; }
    lua_pop(L, 1);
    switch (which) {
    case 1:
        /* A returned debug.getregistry must expose this actual state's real
         * registry table even though no base/debug globals have been opened. */
        if (push_export(L, "getregistry")) { result = 11; break; }
        if (lua_pcall(L, 0, 1, 0) != LUA_OK) { result = 12; break; }
        lua_pushvalue(L, LUA_REGISTRYINDEX);
        if (!lua_rawequal(L, -1, -2)) result = 13;
        break;
    case 2:
        /* A byte-string operation retains embedded zeros, and the newly
         * installed string metatable indexes this exact returned module. */
        if (push_export(L, "sub")) { result = 21; break; }
        lua_pushlstring(L, "a\0bc", 4);
        lua_pushinteger(L, 2);
        lua_pushinteger(L, 3);
        if (lua_pcall(L, 3, 1, 0) != LUA_OK) { result = 22; break; }
        bytes = lua_tolstring(L, -1, &length);
        if (bytes == NULL || length != 2 || memcmp(bytes, "\0b", 2) != 0) {
            result = 23;
            break;
        }
        if (!lua_getmetatable(L, -1)) { result = 24; break; }
        lua_getfield(L, -1, "__index");
        if (!lua_rawequal(L, 1, -1)) result = 25;
        break;
    case 3:
        /* Packing through the returned actual function preserves a nil hole
         * and its explicit n field instead of returning a canned table. */
        if (push_export(L, "pack")) { result = 31; break; }
        lua_pushinteger(L, 17);
        lua_pushnil(L);
        lua_pushinteger(L, 19);
        if (lua_pcall(L, 3, 1, 0) != LUA_OK || !lua_istable(L, -1)) {
            result = 32;
            break;
        }
        lua_getfield(L, -1, "n");
        if (lua_tointeger(L, -1) != 3) { result = 33; break; }
        lua_pop(L, 1);
        lua_rawgeti(L, -1, 1);
        if (lua_tointeger(L, -1) != 17) { result = 34; break; }
        lua_pop(L, 1);
        lua_rawgeti(L, -1, 2);
        if (!lua_isnil(L, -1)) { result = 35; break; }
        lua_pop(L, 1);
        lua_rawgeti(L, -1, 3);
        if (lua_tointeger(L, -1) != 19) result = 36;
        break;
    case 4:
        /* UTF8 decoding uses the actual returned module and consumes the
         * supplied multibyte string; no string or base module is preopened. */
        if (push_export(L, "codepoint")) { result = 41; break; }
        lua_pushlstring(L, "\xc3\xa9", 2);
        if (lua_pcall(L, 1, 1, 0) != LUA_OK ||
            lua_tointeger(L, -1) != 233) result = 42;
        break;
    }
done:
    lua_close(L);
    return result;
}
