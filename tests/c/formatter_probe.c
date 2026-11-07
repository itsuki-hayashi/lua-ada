/* Real C callers used by the bounded Ada-session AUnit cases.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
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

lua_CFunction lua_ada_test_formatter(int choice) {
    return choice == 1 ? work : extent;
}
