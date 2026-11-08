/* Real C callers used by the bounded Ada-session AUnit cases.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include <stdarg.h>
#include <string.h>

static const char *format(lua_State *L, const char *text, ...) {
    const char *result;
    va_list arguments;
    va_start(arguments, text);
    result = lua_pushvfstring(L, text, arguments);
    va_end(arguments);
    return result;
}

static int work(lua_State *L) {
    char text[8193];
    memset(text, 'w', sizeof text - 1);
    text[sizeof text - 1] = '\0';
    (void)format(L, "%s", text);
    return 1;
}

static int extent(lua_State *L) {
    char text[129];
    memset(text, 's', sizeof text - 1);
    text[sizeof text - 1] = '\0';
    (void)lua_pushfstring(L, "%s", text);
    return 1;
}

static int option_prefix(lua_State *L) {
    char text[8193];
    const char *options[] = {text, NULL};
    memset(text, 'o', sizeof text - 1);
    text[sizeof text - 1] = '\0';
    /* The absent argument selects a borrowed C default. Only the runtime's
     * option comparison scans it, so its work cannot be charged by Lua
     * source construction or a preceding string library operation. */
    return luaL_checkoption(L, 1, text, options);
}

static int default_length(lua_State *L) {
    char text[8193];
    size_t length;
    memset(text, 'd', sizeof text - 1);
    text[sizeof text - 1] = '\0';
    (void)luaL_optlstring(L, 1, text, &length);
    lua_pushinteger(L, (lua_Integer)length);
    return 1;
}

lua_CFunction lua_ada_test_formatter(int choice) {
    switch (choice) {
    case 1: return work;
    case 2: return extent;
    case 3: return option_prefix;
    default: return default_length;
    }
}
