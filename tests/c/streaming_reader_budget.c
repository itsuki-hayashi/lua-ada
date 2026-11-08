/* Test-only real C readers for bounded Ada-host policy regressions.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"

struct reader_state { int phase; };

static const char *large_reader(lua_State *L, void *data, size_t *size) {
    struct reader_state *reader = (struct reader_state *)data;
    static const char spaces[8192] = {' '};
    (void)L;
    if (reader->phase++ == 0) {
        *size = sizeof spaces;
        return spaces;
    }
    *size = 0;
    return NULL;
}

static const char *reentrant_reader(lua_State *L, void *data, size_t *size) {
    struct reader_state *reader = (struct reader_state *)data;
    if (reader->phase++ == 0) {
        int status = luaL_loadstring(L, "for i=1,500 do end");
        if (status != LUA_OK) lua_error(L);
        status = lua_pcall(L, 0, 0, 0);
        if (status != LUA_OK) lua_error(L);
        *size = 8;
        return "return 1";
    }
    *size = 0;
    return NULL;
}

static const char *error_reader(lua_State *L, void *data, size_t *size) {
    (void)data;
    (void)size;
    lua_newtable(L);
    lua_pushinteger(L, 99);
    lua_setfield(L, -2, "code");
    lua_error(L);
    return NULL;
}

static int load_large(lua_State *L) {
    struct reader_state reader = {0};
    int status = lua_load(L, large_reader, &reader, "=large-reader", "t");
    if (status != LUA_OK) return lua_error(L);
    return 1;
}

static int load_reentrant(lua_State *L) {
    struct reader_state reader = {0};
    int status = lua_load(L, reentrant_reader, &reader, "=nested-reader", "t");
    if (status != LUA_OK) return lua_error(L);
    return 1;
}

static int load_error(lua_State *L) {
    int status = lua_load(L, error_reader, NULL, "=error-reader", "t");
    if (status != LUA_OK) return lua_error(L);
    return 1;
}

lua_CFunction lua_ada_test_streaming_reader(int which) {
    switch (which) {
        case 1: return load_large;
        case 2: return load_reentrant;
        case 3: return load_error;
        default: return NULL;
    }
}
