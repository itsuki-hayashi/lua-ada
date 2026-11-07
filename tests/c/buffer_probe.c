/* Actual public buffer calls within bounded Ada-session callbacks.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include <string.h>

static int work(lua_State *L) {
    char text[8193];
    luaL_Buffer B;
    memset(text, 'w', sizeof text - 1);
    text[sizeof text - 1] = '\0';
    luaL_buffinit(L, &B);
    luaL_addstring(&B, text);
    luaL_pushresult(&B);
    return 1;
}

static int extent(lua_State *L) {
    char text[128];
    luaL_Buffer B;
    memset(text, 's', sizeof text);
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, text, sizeof text);
    luaL_pushresult(&B);
    return 1;
}

static int heap_abort(lua_State *L) {
    char text[8192];
    luaL_Buffer B;
    memset(text, 'h', sizeof text);
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, text, 2048);
    /* The buffer already owns dynamic bytes when this larger request hits
     * the host string policy. Physical cleanup must work without more Lua. */
    luaL_addlstring(&B, text, sizeof text);
    luaL_pushresult(&B);
    return 1;
}

static int near_limit(lua_State *L) {
    char text[1024];
    luaL_Buffer B;
    memset(text, 'b', sizeof text);
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, text, sizeof text);
    luaL_addlstring(&B, text, 200);
    luaL_pushresult(&B);
    return 1;
}

lua_CFunction lua_ada_test_buffer_budget(int choice) {
    switch (choice) {
    case 1: return work;
    case 2: return extent;
    case 3: return heap_abort;
    default: return near_limit;
    }
}
