/* First-party C fixtures for Ada-session -> C -> Lua callback boundaries.
 * These are test consumers, never production interpreter implementation. */
#include "lua.h"
#include "lauxlib.h"
#include <assert.h>
#include <string.h>

static int escaped_body;
static int entered_body;
static int warning_count;
static char warning_bytes[128];
static int warning_nested;

static int add(lua_State *L) {
    assert(lua_gettop(L) == 2);
    lua_pushinteger(L, lua_tointeger(L, 1) + lua_tointeger(L, 2));
    return 1;
}
static int invoke_lua(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_pushinteger(L, 20); lua_pushinteger(L, 22);
    lua_call(L, 2, 1);
    return 1;
}
static int exact_error(lua_State *L) {
    lua_pushvalue(L, 1);
    return lua_error(L);
}
static int protected_quota(lua_State *L) {
    entered_body++;
    lua_pushvalue(L, 1);
    (void)lua_pcall(L, 0, 0, 0);
    /* A bounded host abort must abandon this body, rather than becoming a
     * catchable LUA_ERR* or killing the Ada process that owns the session. */
    escaped_body++;
    return 0;
}
static void warning(void *data, const char *message, int to_continue) {
    lua_State *L = (lua_State *)data;
    size_t old = strlen(warning_bytes), count = strlen(message);
    assert(old + count + 2 < sizeof warning_bytes);
    memcpy(warning_bytes + old, message, count);
    warning_bytes[old + count] = to_continue ? '+' : '|';
    warning_bytes[old + count + 1] = '\0';
    warning_count++;
    if (!warning_nested) {
        warning_nested = 1;
        assert(luaL_loadstring(L, "warn('inner')") == LUA_OK);
        lua_call(L, 0, 0);
        assert(strcmp(message, "outer") == 0);
    }
}
static int install_warning(lua_State *L) {
    warning_count = warning_nested = 0;
    warning_bytes[0] = '\0';
    lua_setwarnf(L, warning, L);
    return 0;
}
static int check_warning(lua_State *L) {
    assert(warning_count == 3);
    assert(strcmp(warning_bytes, "outer+inner|last|") == 0);
    lua_setwarnf(L, NULL, NULL);
    return 0;
}
static char warning_error_key;
static void error_warning(void *data, const char *message, int to_continue) {
    lua_State *L = (lua_State *)data;
    (void)message; (void)to_continue;
    lua_rawgetp(L, LUA_REGISTRYINDEX, &warning_error_key);
    lua_error(L);
}
static int install_error_warning(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &warning_error_key);
    lua_setwarnf(L, error_warning, L);
    return 0;
}
lua_CFunction lua_ada_test_borrowed_callback(int choice) {
    switch (choice) {
    case 0: return add;
    case 1: return invoke_lua;
    case 2: return exact_error;
    case 3: escaped_body = entered_body = 0; return protected_quota;
    case 4: return install_warning;
    case 5: return check_warning;
    case 6: return install_error_warning;
    default: assert(0); return NULL;
    }
}
int lua_ada_test_borrowed_escaped_body(void) { return escaped_body; }
int lua_ada_test_borrowed_entered_body(void) { return entered_body; }
